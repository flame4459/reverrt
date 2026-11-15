import Foundation
import CoreLocation

/// Hazard data saved as whole areas instead of 5.5 km tiles.
///
/// The tile store predates the area cache and still backs riding, but a single
/// Overpass request for one bounding box replaces roughly a hundred tile
/// requests in an offline download. Areas are also what the alert engine reads
/// while riding, so one download serves both.
nonisolated enum HazardAreas {
    /// Hazards move more than roads do: new lights appear, roadworks close
    /// crossings. A week is the compromise between freshness and a phone that
    /// re-downloads a county every time it is opened.
    static let cacheDays = 7.0
    static let coverageThreshold = 0.9
    private static let maxFiles = 24

    struct Area: Sendable {
        let url: URL
        let center: CLLocationCoordinate2D
        let radiusKm: Double
        let fetched: Date
    }

    private struct Cache: Codable, Sendable {
        let centerLatitude: Double
        let centerLongitude: Double
        let radiusKm: Double
        let fetched: Date
        let hazards: [Hazard]
    }

    /// Decoded areas are kept because the alert engine asks for hazards on
    /// every GPS fix; decoding a megabyte of JSON per fix would be absurd.
    nonisolated(unsafe) private static var memory: [URL: (fetched: Date, hazards: [Hazard])] = [:]
    private static let lock = NSLock()

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bulk_hazards", isDirectory: true)
    }

    // MARK: Naming

    static func fileName(center: CLLocationCoordinate2D,
                         radiusKm: Double,
                         at date: Date) -> String {
        let lat = Int((center.latitude * 10_000).rounded())
        let lon = Int((center.longitude * 10_000).rounded())
        let radius = Int((radiusKm * 10).rounded())
        return "hazards_area_\(lat)_\(lon)_\(radius)_\(Int(date.timeIntervalSince1970)).json"
    }

    static func parse(_ url: URL) -> Area? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        guard parts.count >= 5, parts[0] == "hazards", parts[1] == "area",
              let lat = Int(parts[2]), let lon = Int(parts[3]),
              let radius = Int(parts[4]), radius > 0 else { return nil }
        let epoch = parts.count >= 6 ? Int(parts[5]) : nil
        return Area(
            url: url,
            center: CLLocationCoordinate2D(latitude: Double(lat) / 10_000, longitude: Double(lon) / 10_000),
            radiusKm: Double(radius) / 10,
            fetched: epoch.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast
        )
    }

    // MARK: Lookup

    static func areas(near center: CLLocationCoordinate2D, radiusKm: Double) -> [Area] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        let request = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap(parse)
            .filter { area in
                let areaCenter = CLLocation(latitude: area.center.latitude, longitude: area.center.longitude)
                return areaCenter.distance(from: request) <= (area.radiusKm + radiusKm) * 1_000
            }
            .sorted { $0.fetched > $1.fetched }
    }

    static func needsDownload(center: CLLocationCoordinate2D, radiusKm: Double) -> Bool {
        let areas = areas(near: center, radiusKm: radiusKm)
        guard !areas.isEmpty else { return true }
        let circles = areas.map {
            RegionCoverage.Circle(latitude: $0.center.latitude, longitude: $0.center.longitude, radiusKm: $0.radiusKm)
        }
        return RegionCoverage.fraction(of: center, radiusKm: radiusKm, coveredBy: circles) < coverageThreshold
    }

    static func items(near coordinate: CLLocationCoordinate2D) -> [Hazard] {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var seen = Set<Int64>()
        var found: [Hazard] = []
        for area in areas(near: coordinate, radiusKm: 0) {
            guard Date().timeIntervalSince(area.fetched) < cacheDays * 86_400 else { continue }
            let areaCenter = CLLocation(latitude: area.center.latitude, longitude: area.center.longitude)
            guard point.distance(from: areaCenter) <= area.radiusKm * 1_000 else { continue }
            for hazard in cachedHazards(of: area) where seen.insert(hazard.id).inserted {
                found.append(hazard)
            }
        }
        return found
    }

    private static func cachedHazards(of area: Area) -> [Hazard] {
        let cached: [Hazard]? = lock.withLock {
            memory[area.url].map(\.hazards)
        }
        if let cached { return cached }
        guard let data = try? Data(contentsOf: area.url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return [] }
        lock.withLock { memory[area.url] = (cache.fetched, cache.hazards) }
        return cache.hazards
    }

    // MARK: Download

    /// One request for the whole area. Returns what was saved.
    @discardableResult
    static func download(center: CLLocationCoordinate2D,
                         radiusKm: Double,
                         timeout: TimeInterval = 45) async throws -> [Hazard] {
        let queryRadius = min(max(radiusKm + 1.0, 4.5), 30)
        let latitudeDelta = queryRadius / 111.0
        let longitudeDelta = queryRadius / (111.0 * max(cos(center.latitude * .pi / 180), 0.2))
        let started = Date()
        let hazards = try await HazardStore.fetchArea(
            south: center.latitude - latitudeDelta,
            west: center.longitude - longitudeDelta,
            north: center.latitude + latitudeDelta,
            east: center.longitude + longitudeDelta,
            timeout: timeout
        )
        RevertDiagnostics.log("hazards.area \(Int(Date().timeIntervalSince(started) * 1_000))ms"
                              + " count=\(hazards.count) radius=\(Int(queryRadius))km")

        // An empty answer is more likely a server hiccup than a hazard-free
        // district. Saving it would silence the area for a week.
        guard !hazards.isEmpty else { return [] }

        let cache = Cache(centerLatitude: center.latitude,
                          centerLongitude: center.longitude,
                          radiusKm: queryRadius,
                          fetched: Date(),
                          hazards: hazards)
        let url = directory.appendingPathComponent(fileName(center: center, radiusKm: queryRadius, at: cache.fetched))
        let dir = directory
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
        lock.withLock { memory[url] = (cache.fetched, hazards) }
        prune()
        return hazards
    }

    // MARK: Housekeeping

    private static func prune() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              urls.count > maxFiles else { return }
        let parsable = urls.compactMap { url -> (URL, Date)? in
            parse(url).map { ($0.url, $0.fetched) }
        }.sorted { $0.1 < $1.1 }
        for (url, _) in parsable.prefix(parsable.count - maxFiles) {
            try? FileManager.default.removeItem(at: url)
            lock.withLock { memory[url] = nil }
        }
    }

    static func diskBytes() -> Int64 {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return urls.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
        lock.withLock { memory.removeAll() }
    }
}
