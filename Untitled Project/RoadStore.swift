import Foundation
import CoreLocation

nonisolated struct Road: Codable, Sendable {
    let id: Int64
    let highway: String
    let name: String?
    let maxspeed: String?
    let maxspeedForward: String?
    let maxspeedBackward: String?
    let surface: String?
    let oneway: String?
    let ref: String?
    let coords: [Double]          // lat, lon, lat, lon, ...
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    var count: Int { coords.count / 2 }
    func lat(_ i: Int) -> Double { coords[2 * i] }
    func lon(_ i: Int) -> Double { coords[2 * i + 1] }
}

/// Road geometry and tags from OpenStreetMap.
enum RoadStore {
    // Paved planning deliberately fetches a lean set: residential alone
    // doubled the payload in dense suburbs (Nassau County) and the response
    // stopped arriving inside the planning budget. Primary arterials are few
    // enough to keep, and without them a start pin on a city arterial looked
    // like it was "not near a mapped road" even though it was in the middle
    // of a street. Residential remains in the ADV set and the dense retry.
    nonisolated private static let roadClasses = "secondary|tertiary|unclassified|primary"
    nonisolated private static let adventureRoadClasses = "secondary|tertiary|unclassified|track|path|residential|primary"
    // Road geometry is stable enough to keep for three months. Reusing it is
    // what makes repeat route planning feel instant.
    nonisolated private static let bulkCacheDays = 90.0
    nonisolated private static let overpassEndpoints = [
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter"
    ]

    nonisolated static let shared = TileStore<Road>(folder: "roads_v4", pause: 0.35, idOf: { $0.id }) { x, y in
        try await RoadStore.fetchTile(x: x, y: y, classes: roadClasses)
    }

    /// Separate cache for dual-sport data so paved planning stays lean.
    nonisolated static let advShared = TileStore<Road>(folder: "roads_adv_v5", pause: 0.35, idOf: { $0.id }) { x, y in
        try await RoadStore.fetchTile(x: x, y: y, classes: adventureRoadClasses)
    }

    nonisolated static func store(for surface: LoopSurface) -> TileStore<Road> {
        surface == .paved ? shared : advShared
    }

    nonisolated static func roadClasses(for surface: LoopSurface) -> String {
        surface == .paved ? roadClasses : adventureRoadClasses
    }

    nonisolated private struct BulkCache: Codable, Sendable {
        let centerLatitude: Double
        let centerLongitude: Double
        let fetched: Date
        let radiusKm: Double?
        let surface: LoopSurface?
        let roads: [Road]
    }

    nonisolated private static var bulkCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("bulk_roads", isDirectory: true)
    }

    nonisolated private static var legacyBulkCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("roads_bulk_local_v2.json")
    }

    nonisolated private static func bulkCacheURL(for center: CLLocationCoordinate2D, surface: LoopSurface = .paved) -> URL {
        let tileX = Int(floor(center.longitude / tileDeg))
        let tileY = Int(floor(center.latitude / tileDeg))
        let suffix = surface == .paved ? "" : "_\(surface.rawValue)"
        return bulkCacheDirectory.appendingPathComponent("roads_bulk_\(tileX)_\(tileY)\(suffix).json")
    }

    /// Returns the locally cached bulk area when it fully covers the requested planning area.
    nonisolated static func cachedArea(center: CLLocationCoordinate2D, radiusKm: Double,
                                       surface: LoopSurface = .paved) -> [Road]? {
        let dir = bulkCacheDirectory
        let requestedCenter = CLLocation(latitude: center.latitude, longitude: center.longitude)

        if let fileURLs = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                // A cache file whose tile is far outside the requested area can
                // never cover it. Skip it without decoding multi-megabyte JSON.
                guard Self.isNearbyBulkFile(fileURL, center: center) else { continue }
                guard let data = try? Data(contentsOf: fileURL),
                      let cache = try? JSONDecoder().decode(BulkCache.self, from: data),
                      (cache.surface ?? .paved) == surface,
                      Date().timeIntervalSince(cache.fetched) < bulkCacheDays * 86_400 else {
                    continue
                }

                let cachedCenter = CLLocation(latitude: cache.centerLatitude, longitude: cache.centerLongitude)
                guard let cachedRadiusKm = cache.radiusKm else { continue }
                let availableMeters = cachedRadiusKm * 1_000 - radiusKm * 1_000
                guard availableMeters >= 0,
                      requestedCenter.distance(from: cachedCenter) <= availableMeters else { continue }

                return roads(cache.roads, intersecting: center, radiusKm: radiusKm, surface: surface)
            }
        }

        if let data = try? Data(contentsOf: legacyBulkCacheURL),
           let cache = try? JSONDecoder().decode(BulkCache.self, from: data),
           Date().timeIntervalSince(cache.fetched) < bulkCacheDays * 86_400 {
            let cachedCenter = CLLocation(latitude: cache.centerLatitude, longitude: cache.centerLongitude)
            if let cachedRadiusKm = cache.radiusKm {
                let availableMeters = cachedRadiusKm * 1_000 - radiusKm * 1_000
                if availableMeters >= 0, requestedCenter.distance(from: cachedCenter) <= availableMeters {
                    return roads(cache.roads, intersecting: center, radiusKm: radiusKm, surface: surface)
                }
            }
        }

        return nil
    }

    nonisolated private static let errorLock = NSLock()
    nonisolated(unsafe) private static var _lastErrorDescription: String?

    /// Human-readable reason for the last failed download, for the planner's
    /// error message.
    static var lastErrorDescription: String? {
        errorLock.withLock { _lastErrorDescription }
    }

    nonisolated private static let inflightLock = NSLock()
    nonisolated(unsafe) private static var inflightDownloads: [String: Task<[Road], Error>] = [:]

    /// Uses the bulk cache first, then the same tile cache used by Offline data.
    /// Pass `cached` when the caller already decoded the bulk cache to avoid a
    /// second full JSON decode.
    static func area(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        cached: [Road]? = nil,
        surface: LoopSurface = .paved,
        classes: String? = nil
    ) async throws -> [Road] {
        // Cached bulk data and road tiles always hold the lean set; they must
        // not masquerade as the denser connectivity retry.
        if classes == nil {
            if let cached, !cached.isEmpty {
                return roads(cached, intersecting: center, radiusKm: radiusKm, surface: surface)
            }
            // Decode the bulk cache off the main thread; the file can be large.
            let decoded = await Task.detached(priority: .userInitiated) {
                RoadStore.cachedArea(center: center, radiusKm: radiusKm, surface: surface)
            }.value
            if let decoded {
                return decoded
            }

            let store = store(for: surface)
            let coverage = store.coverage(center: center, radiusKm: radiusKm)
            if coverage.missing == 0 {
                let cachedTiles = await store.loadArea(center: center, radiusKm: radiusKm)
                let roads = roads(cachedTiles, intersecting: center, radiusKm: radiusKm, surface: surface)
                if !roads.isEmpty { return roads }
            }
        }

        let downloaded = try await coalescedDownload(
            center: center, radiusKm: radiusKm, surface: surface, classes: classes
        )
        return roads(downloaded, intersecting: center, radiusKm: radiusKm, surface: surface)
    }

    /// One in-flight Overpass request per area. The plan screen prefetches on
    /// appear and on every distance change; without this, tapping Find while a
    /// prefetch was running started a second full download and both missed the
    /// deadline.
    nonisolated private static func coalescedDownload(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        surface: LoopSurface,
        classes: String? = nil
    ) async throws -> [Road] {
        let key = String(format: "%.4f,%.4f,%.2f,%@,%@",
                         center.latitude, center.longitude, radiusKm, surface.rawValue,
                         classes ?? "lean")
        let task: Task<[Road], Error> = inflightLock.withLock {
            if let existing = inflightDownloads[key] { return existing }
            let created = Task {
                defer { inflightLock.withLock { inflightDownloads[key] = nil } }
                return try await downloadWithFallback(
                    center: center, radiusKm: radiusKm, surface: surface, classes: classes
                )
            }
            inflightDownloads[key] = created
            return created
        }
        return try await task.value
    }

    nonisolated private static func downloadWithFallback(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        surface: LoopSurface,
        classes: String? = nil
    ) async throws -> [Road] {
        let fullClasses = classes ?? roadClasses(for: surface)
        do {
            return try await downloadArea(
                center: center, radiusKm: radiusKm, surface: surface,
                classes: fullClasses, timeout: 12
            )
        } catch {
            // A narrower class set is far more likely to arrive in time; skip
            // it when paved planning is already using the lean set.
            let lean = "secondary|tertiary|unclassified"
            if fullClasses != lean {
                if let downloaded = try? await downloadArea(
                    center: center,
                    radiusKm: radiusKm,
                    surface: surface,
                    classes: lean,
                    timeout: 8,
                    writeCache: false
                ) {
                    return downloaded
                }
            }
            // Last resort: whatever tiles are already on disk, even if the
            // area is only partly covered. A partial graph can still build a
            // loop; an empty one cannot.
            let tiles = await store(for: surface).loadArea(center: center, radiusKm: radiusKm)
            if !tiles.isEmpty { return tiles }
            errorLock.withLock { _lastErrorDescription = error.localizedDescription }
            throw error
        }
    }

    /// Downloads and persists the road area needed for route planning.
    static func downloadArea(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        surface: LoopSurface = .paved,
        classes: String? = nil,
        timeout: TimeInterval = 14,
        writeCache: Bool = true
    ) async throws -> [Road] {
        // Route generation never needs the full 50-mile payload. A modest buffer
        // keeps the request reliable while still covering the requested planning area.
        // Keep the buffer small: every extra kilometer makes the Overpass
        // response larger and slows down a rider who only wants a quick loop.
        // Keep a healthy buffer so small changes to the start point reuse the
        // cache instead of re-downloading the whole area.
        let queryRadiusKm = min(max(radiusKm + 1.5, 4.5), 22)
        // A bbox uses Overpass's spatial index directly. `around:` has to
        // evaluate a radius for every candidate way and is noticeably slower
        // on a cold cache.
        let latitudeDelta = queryRadiusKm / 111.0
        let longitudeDelta = queryRadiusKm / (111.0 * max(cos(center.latitude * .pi / 180), 0.2))
        let south = center.latitude - latitudeDelta
        let north = center.latitude + latitudeDelta
        let west = center.longitude - longitudeDelta
        let east = center.longitude + longitudeDelta
        let highwayClasses = classes ?? roadClasses(for: surface)
        let query = """
        [out:json][timeout:18];
        way["highway"~"^\(highwayClasses)$"](\(south),\(west),\(north),\(east));
        out geom qt;
        """

        // Planning has a 30-second ceiling. Do not spend a minute per mirror
        // while the rider is staring at a spinner. Residential roads make the
        // payload bigger, so allow a little more time than the old 12 s but
        // still fail over to the next mirror quickly.
        let roads = try await fetch(query: query, timeout: timeout, maxEndpoints: 3)
        let cache = BulkCache(
            centerLatitude: center.latitude,
            centerLongitude: center.longitude,
            fetched: Date(),
            radiusKm: queryRadiusKm,
            surface: surface,
            roads: roads
        )
        // Encoding a multi-megabyte payload should not block the main thread.
        guard writeCache else { return roads }
        let url = bulkCacheURL(for: center, surface: surface)
        let dir = bulkCacheDirectory
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
        return roads
    }

    nonisolated static func clearBulkCache() {
        try? FileManager.default.removeItem(at: bulkCacheDirectory)
        try? FileManager.default.removeItem(at: legacyBulkCacheURL)
    }

    nonisolated static func bulkDiskBytes() -> Int64 {
        var total: Int64 = 0
        if let urls = try? FileManager.default.contentsOfDirectory(at: bulkCacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in urls {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        if let legacy = try? legacyBulkCacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            total += Int64(legacy)
        }
        return total
    }

    nonisolated private static func isNearbyBulkFile(_ url: URL, center: CLLocationCoordinate2D) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "_")
        guard parts.count >= 4, parts[0] == "roads", parts[1] == "bulk",
              let x = Int(parts[2]), let y = Int(parts[3]) else { return true }
        let tileLat = (Double(y) + 0.5) * tileDeg
        let tileLon = (Double(x) + 0.5) * tileDeg
        return RoadGraph.flat(center.latitude, center.longitude, tileLat, tileLon).dist < 35_000
    }

    nonisolated static func roads(_ roads: [Road], intersecting center: CLLocationCoordinate2D, radiusKm: Double,
                                  surface: LoopSurface = .paved) -> [Road] {
        let latitudeDelta = radiusKm / 111.0
        let longitudeDelta = radiusKm / (111.0 * max(cos(center.latitude * .pi / 180), 0.2))
        let minLat = center.latitude - latitudeDelta
        let maxLat = center.latitude + latitudeDelta
        let minLon = center.longitude - longitudeDelta
        let maxLon = center.longitude + longitudeDelta

        return roads.filter {
            $0.maxLat >= minLat && $0.minLat <= maxLat &&
            $0.maxLon >= minLon && $0.minLon <= maxLon &&
            (surface.includesUnpaved || !$0.isUnpaved)
        }
    }

    private static func fetchTile(x: Int, y: Int, classes: String) async throws -> [Road] {
        let south = Double(y) * tileDeg
        let west = Double(x) * tileDeg
        let north = south + tileDeg
        let east = west + tileDeg
        let query = """
        [out:json][timeout:60];
        way["highway"~"^\(classes)$"](\(south),\(west),\(north),\(east));
        out geom;
        """
        return try await fetch(query: query, timeout: 60)
    }

    nonisolated private static func fetch(
        query: String,
        timeout: TimeInterval,
        maxEndpoints: Int = 3
    ) async throws -> [Road] {
        var lastError: Error = URLError(.cannotConnectToHost)
        // One deadline for the whole mirror loop. The old code allowed the
        // full timeout on *each* endpoint, so a slow Overpass could burn 28
        // seconds and the 27-second planning ceiling fired before the lean
        // fallback was ever tried.
        let deadline = Date().addingTimeInterval(timeout)
        let endpoints = Array(overpassEndpoints.prefix(maxEndpoints))
        // Give each mirror a fair slice of the budget. Previously a single
        // unreachable mirror could consume the whole timeout and the healthy
        // mirrors were never tried, which is what produced NSURLError -1001.
        let slice = timeout / Double(max(endpoints.count, 1))
        for endpoint in endpoints {
            let remaining = min(slice, deadline.timeIntervalSinceNow)
            guard remaining > 1 else { break }
            do {
                return try await withDownloadDeadline(seconds: remaining) {
                    try await fetch(query: query, timeout: remaining, endpoint: endpoint)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Hard wall-clock limit for one request. `request.timeoutInterval` is an
    /// idle timeout; a slowly streaming multi-megabyte response can outlive it.
    nonisolated private static func withDownloadDeadline<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0.2) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else { throw URLError(.timedOut) }
            group.cancelAll()
            return result
        }
    }

    nonisolated private static func fetch(
        query: String,
        timeout: TimeInterval,
        endpoint: String
    ) async throws -> [Road] {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("RiderApp/0.1 (personal open-source project)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = "data=\(encoded)".data(using: .utf8)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decodeRoads(data)
    }

    nonisolated private static func decodeRoads(_ data: Data) throws -> [Road] {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.elements.compactMap { element in
            guard element.type == "way", let geometry = element.geometry, geometry.count >= 2 else { return nil }
            var coordinates: [Double] = []
            coordinates.reserveCapacity(geometry.count * 2)
            var minLat = Double.greatestFiniteMagnitude
            var maxLat = -Double.greatestFiniteMagnitude
            var minLon = Double.greatestFiniteMagnitude
            var maxLon = -Double.greatestFiniteMagnitude
            for point in geometry {
                coordinates.append(point.lat)
                coordinates.append(point.lon)
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLon = min(minLon, point.lon)
                maxLon = max(maxLon, point.lon)
            }
            return Road(
                id: element.id,
                highway: element.tags?["highway"] ?? "",
                name: element.tags?["name"],
                maxspeed: element.tags?["maxspeed"],
                maxspeedForward: element.tags?["maxspeed:forward"],
                maxspeedBackward: element.tags?["maxspeed:backward"],
                surface: element.tags?["surface"],
                oneway: element.tags?["oneway"] ?? (element.tags?["junction"] == "roundabout" ? "yes" : nil),
                ref: element.tags?["ref"],
                coords: coordinates,
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon
            )
        }
    }

    nonisolated private struct Response: Decodable {
        struct Pt: Decodable {
            let lat: Double
            let lon: Double
        }

        struct Element: Decodable {
            let type: String
            let id: Int64
            let tags: [String: String]?
            let geometry: [Pt]?
        }

        let elements: [Element]
    }
}

nonisolated extension Road {
    /// Posted limit in mph for the direction of travel.
    ///
    /// OSM is messy here: values can be `50`, `50 mph`, `30 km/h`, `none`,
    /// `signals`, `walk`, or semicolon-separated. A missing unit means km/h.
    func speedLimitMph(forward: Bool) -> Int? {
        let raw = (forward ? maxspeedForward : maxspeedBackward) ?? maxspeed
        guard var text = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        // Use the first value if the tag is a list.
        if let separator = text.firstIndex(where: { $0 == ";" || $0 == "|" }) {
            text = String(text[..<separator]).trimmingCharacters(in: .whitespaces)
        }
        if text.contains("none") || text.contains("signals") || text.contains("variable") {
            return nil
        }
        if text.contains("walk") { return 5 }
        guard let firstNumber = text.firstIndex(where: { $0.isNumber }),
              let value = Double(text[firstNumber...].prefix(while: { $0.isNumber || $0 == "." })),
              value > 0 else { return nil }
        if text.contains("mph") {
            return Int((value / 5).rounded()) * 5
        }
        if text.contains("km/h") || text.contains("kmh") || text.contains("kph") {
            return Int((value * 0.621371 / 5).rounded()) * 5
        }
        // OSM's default unit for maxspeed is km/h.
        return Int((value * 0.621371 / 5).rounded()) * 5
    }

    var isUnpaved: Bool {
        guard let surface = surface?.lowercased() else { return false }

        for token in surface.split(separator: ";") {
            switch token {
            case "unpaved", "gravel", "fine_gravel", "dirt", "ground", "earth", "sand",
                 "mud", "grass", "compacted", "pebblestone", "rock", "woodchips":
                return true
            default:
                continue
            }
        }
        return false
    }

    var surfaceName: String {
        (surface ?? "unpaved").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
