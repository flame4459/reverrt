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
    /// OpenStreetMap lane tagging. `lanes` is the count, `turn:lanes` the
    /// left-to-right movements; the directional variants apply when the way is
    /// tagged per direction.
    var lanes: Int? = nil
    var turnLanes: String? = nil
    var turnLanesForward: String? = nil
    var turnLanesBackward: String? = nil

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
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter"
    ]

    nonisolated static let shared = TileStore<Road>(folder: "roads_v4", pause: 0.35, concurrency: 2, idOf: { $0.id }) { x, y in
        try await RoadStore.fetchTile(x: x, y: y, classes: roadClasses)
    }

    /// Separate cache for dual-sport data so paved planning stays lean.
    nonisolated static let advShared = TileStore<Road>(folder: "roads_adv_v5", pause: 0.35, concurrency: 2, idOf: { $0.id }) { x, y in
        try await RoadStore.fetchTile(x: x, y: y, classes: adventureRoadClasses)
    }

    nonisolated static func store(for surface: LoopSurface) -> TileStore<Road> {
        surface == .paved ? shared : advShared
    }

    nonisolated static func roadClasses(for surface: LoopSurface) -> String {
        surface == .paved ? roadClasses : adventureRoadClasses
    }

    nonisolated struct BulkCache: Codable, Sendable {
        let centerLatitude: Double
        let centerLongitude: Double
        let fetched: Date
        let radiusKm: Double?
        let surface: LoopSurface?
        let roads: [Road]
    }

    nonisolated static var bulkCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("bulk_roads", isDirectory: true)
    }

    nonisolated private static var legacyBulkCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("roads_bulk_local_v2.json")
    }

    /// One saved download: where it was centred and how far it reaches.
    nonisolated struct CachedArea: Sendable {
        let url: URL
        let center: CLLocationCoordinate2D
        let radiusKm: Double
        let surface: LoopSurface
        let fetched: Date

        var circle: RegionCoverage.Circle {
            RegionCoverage.Circle(latitude: center.latitude, longitude: center.longitude, radiusKm: radiusKm)
        }
    }

    /// Fractions below this fall back to a network fetch. A little slop is
    /// deliberate: the edges of a saved disc lose their straddling ways, and
    /// re-downloading a whole 20 km area to recover the last 3% is not a trade
    /// a rider waiting for a loop will thank us for.
    nonisolated private static let enoughCoverage = 0.92

    /// How many saved areas to keep. Each one is a few megabytes; the oldest
    /// are dropped so a phone that commutes between regions cannot fill up.
    nonisolated private static let maxBulkFiles = 80

    nonisolated static func bulkFileName(center: CLLocationCoordinate2D,
                                                 radiusKm: Double,
                                                 surface: LoopSurface,
                                                 at date: Date) -> String {
        let tileX = Int(floor(center.longitude / tileDeg))
        let tileY = Int(floor(center.latitude / tileDeg))
        // Centre and radius live in the name so coverage can be decided without
        // decoding a multi-megabyte payload.
        let lat = Int((center.latitude * 10_000).rounded())
        let lon = Int((center.longitude * 10_000).rounded())
        let radius = Int((radiusKm * 10).rounded())
        let suffix = surface == .paved ? "" : "_\(surface.rawValue)"
        return "roads_bulk_\(tileX)_\(tileY)_\(lat)_\(lon)_\(radius)_\(Int(date.timeIntervalSince1970))\(suffix).json"
    }

    nonisolated static func parse(_ url: URL) -> CachedArea? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        // roads_bulk_<tileX>_<tileY>_<latE4>_<lonE4>_<radiusDm>_<epoch>[_surface]
        guard parts.count >= 8, parts[0] == "roads", parts[1] == "bulk",
              let lat = Int(parts[4]), let lon = Int(parts[5]),
              let radius = Int(parts[6]), let epoch = Int(parts[7]) else { return nil }
        let surface = parts.count >= 9 ? (LoopSurface(rawValue: String(parts[8])) ?? .paved) : .paved
        return CachedArea(
            url: url,
            center: CLLocationCoordinate2D(latitude: Double(lat) / 10_000, longitude: Double(lon) / 10_000),
            radiusKm: Double(radius) / 10,
            surface: surface,
            fetched: Date(timeIntervalSince1970: TimeInterval(epoch))
        )
    }

    nonisolated static func isBulkFile(_ url: URL) -> Bool {
        let ext = url.pathExtension
        return ext == "json" || ext == "plist"
    }

    /// Binary plists decode several times faster than the JSON these files
    /// used to be, which is the difference between a cache hit that feels
    /// instant and one that still spins.
    // Decoding an area is 300 ms at best and 2.5 s for a big one, and the
    // planner asks for the same area twice within milliseconds (prefetch and
    // plan). Keeping the last two decodes in memory turns the second ask into
    // a lookup.
    nonisolated(unsafe) private static var bulkMemory: [URL: BulkCache] = [:]
    nonisolated private static let bulkMemoryLock = NSLock()
    nonisolated private static let maxBulkMemory = 2

    nonisolated private static func decode(_ url: URL) -> BulkCache? {
        if let cached = bulkMemoryLock.withLock({ bulkMemory[url] }) { return cached }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let cache: BulkCache? = url.pathExtension == "plist"
            ? try? PropertyListDecoder().decode(BulkCache.self, from: data)
            : try? JSONDecoder().decode(BulkCache.self, from: data)
        if let cache {
            bulkMemoryLock.withLock {
                bulkMemory[url] = cache
                if bulkMemory.count > maxBulkMemory, let oldest = bulkMemory.keys.first {
                    bulkMemory[oldest] = nil
                }
            }
        }
        return cache
    }

    /// Every fresh saved area that could touch the request, newest first.
    nonisolated static func cachedAreas(near center: CLLocationCoordinate2D,
                                        radiusKm: Double,
                                        surface: LoopSurface = .paved) -> [CachedArea] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: bulkCacheDirectory,
                                                                     includingPropertiesForKeys: nil) else {
            return []
        }
        let request = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var areas: [CachedArea] = []
        for url in urls where Self.isBulkFile(url) {
            guard let area = parse(url) else { continue }
            guard area.surface == surface else { continue }
            guard Date().timeIntervalSince(area.fetched) < bulkCacheDays * 86_400 else { continue }
            let areaCenter = CLLocation(latitude: area.center.latitude, longitude: area.center.longitude)
            guard areaCenter.distance(from: request) <= (area.radiusKm + radiusKm) * 1_000 else { continue }
            areas.append(area)
        }
        return areas.sorted { $0.fetched > $1.fetched }
    }

    /// Cheap "do we already have this area?" check: reads the area index and
    /// coverage, never decodes a payload. The planner asks before deciding
    /// whether a patient download is needed.
    nonisolated static func hasCoverage(center: CLLocationCoordinate2D,
                                        radiusKm: Double,
                                        surface: LoopSurface = .paved) -> Bool {
        let areas = cachedAreas(near: center, radiusKm: radiusKm, surface: surface)
        guard !areas.isEmpty else { return false }
        return RegionCoverage.fraction(of: center, radiusKm: radiusKm,
                                       coveredBy: areas.map(\.circle)) >= enoughCoverage
    }

    /// Returns the locally cached bulk area when the union of what is saved
    /// covers the request. Overlapping downloads accumulate: planning 22 km
    /// from one point and then 22 km from a point two kilometres away reads
    /// both files instead of fetching the second area from scratch.
    nonisolated static func cachedArea(center: CLLocationCoordinate2D, radiusKm: Double,
                                       surface: LoopSurface = .paved) -> [Road]? {
        let areas = cachedAreas(near: center, radiusKm: radiusKm, surface: surface)
        guard !areas.isEmpty else { return legacyCachedArea(center: center, radiusKm: radiusKm, surface: surface) }

        let coverage = RegionCoverage.fraction(of: center, radiusKm: radiusKm,
                                               coveredBy: areas.map(\.circle))
        guard coverage >= enoughCoverage else {
            RevertDiagnostics.log("area cache miss coverage=\(String(format: "%.2f", coverage))"
                                  + " areas=\(areas.count) radius=\(Int(radiusKm))km")
            return nil
        }
        RevertDiagnostics.log("area cache hit coverage=\(String(format: "%.2f", coverage))"
                              + " areas=\(areas.count) radius=\(Int(radiusKm))km")

        let decodeStart = Date()
        var seen = Set<Int64>()
        var merged: [Road] = []
        for area in areas {
            guard let cache = decode(area.url), (cache.surface ?? .paved) == surface else { continue }
            for road in cache.roads where seen.insert(road.id).inserted {
                merged.append(road)
            }
        }
        guard !merged.isEmpty else { return nil }
        let decoded = roads(merged, intersecting: center, radiusKm: radiusKm, surface: surface)
        RevertDiagnostics.log("area.cache decode=\(Int(Date().timeIntervalSince(decodeStart) * 1_000))ms"
                              + " roads=\(decoded.count) files=\(areas.count)")
        return decoded
    }

    /// Pre-region-cache files, named only by tile. Read once so a rider who
    /// already has data does not lose it on upgrade.
    nonisolated private static func legacyCachedArea(center: CLLocationCoordinate2D,
                                                    radiusKm: Double,
                                                    surface: LoopSurface) -> [Road]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: bulkCacheDirectory,
                                                                     includingPropertiesForKeys: nil) else {
            return nil
        }
        let request = CLLocation(latitude: center.latitude, longitude: center.longitude)
        for url in urls where Self.isBulkFile(url) && parse(url) == nil {
            guard let cache = decode(url),
                  (cache.surface ?? .paved) == surface,
                  Date().timeIntervalSince(cache.fetched) < bulkCacheDays * 86_400,
                  let cachedRadiusKm = cache.radiusKm else { continue }
            let cachedCenter = CLLocation(latitude: cache.centerLatitude, longitude: cache.centerLongitude)
            let available = cachedRadiusKm * 1_000 - radiusKm * 1_000
            guard available >= 0, request.distance(from: cachedCenter) <= available else { continue }
            return roads(cache.roads, intersecting: center, radiusKm: radiusKm, surface: surface)
        }
        return legacySingleFileArea(center: center, radiusKm: radiusKm, surface: surface)
    }

    nonisolated private static func legacySingleFileArea(center: CLLocationCoordinate2D,
                                                         radiusKm: Double,
                                                         surface: LoopSurface) -> [Road]? {
        guard let cache = decode(legacyBulkCacheURL),
              (cache.surface ?? .paved) == surface,
              Date().timeIntervalSince(cache.fetched) < bulkCacheDays * 86_400,
              let cachedRadiusKm = cache.radiusKm else { return nil }
        let cachedCenter = CLLocation(latitude: cache.centerLatitude, longitude: cache.centerLongitude)
        let available = cachedRadiusKm * 1_000 - radiusKm * 1_000
        let request = CLLocation(latitude: center.latitude, longitude: center.longitude)
        guard available >= 0, request.distance(from: cachedCenter) <= available else { return nil }
        return roads(cache.roads, intersecting: center, radiusKm: radiusKm, surface: surface)
    }

    /// Drops the oldest saved areas once the folder grows past `maxBulkFiles`.
    nonisolated private static func pruneBulkCache() {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: bulkCacheDirectory,
                                                                     includingPropertiesForKeys: keys),
              urls.count > maxBulkFiles else { return }
        let sorted = urls.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast
            return l < r
        }
        for url in sorted.prefix(urls.count - maxBulkFiles) {
            try? FileManager.default.removeItem(at: url)
        }
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
            let roads = try await downloadArea(
                center: center, radiusKm: radiusKm, surface: surface,
                classes: fullClasses, timeout: 30
            )
            guard !roads.isEmpty else { throw URLError(.zeroByteResource) }
            return roads
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
                    timeout: 15,
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
        // An empty answer is a failed request wearing a 200. Never let it
        // become a saved area that counts as coverage for three months.
        guard !roads.isEmpty else { return roads }

        // Encoding a multi-megabyte payload should not block the main thread.
        guard writeCache else { return roads }
        // Do not save a second copy of an area that is already fully saved.
        let alreadySaved = cachedAreas(near: center, radiusKm: queryRadiusKm, surface: surface)
            .contains { RegionCoverage.contains($0.circle, center: center, radiusKm: queryRadiusKm) }
        guard !alreadySaved else { return roads }

        let name = bulkFileName(center: center, radiusKm: queryRadiusKm, surface: surface, at: Date())
        let url = bulkCacheDirectory.appendingPathComponent((name as NSString).deletingPathExtension + ".plist")
        let dir = bulkCacheDirectory
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(cache) {
                try? data.write(to: url, options: .atomic)
            }
            RoadStore.pruneBulkCache()
        }.value
        return roads
    }

    /// The tube of roads a point-to-point route can use: a disc around the
    /// midpoint that contains both ends. Much less data than planning a loop.
    nonisolated static func corridor(from start: CLLocationCoordinate2D,
                                     to end: CLLocationCoordinate2D,
                                     widthKm: Double = 2.0) -> (center: CLLocationCoordinate2D, radiusKm: Double) {
        let a = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let b = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let center = CLLocationCoordinate2D(latitude: (start.latitude + end.latitude) / 2,
                                            longitude: (start.longitude + end.longitude) / 2)
        return (center, min(max(a.distance(from: b) / 2_000 + widthKm, 3.0), 22.0))
    }

    /// A long point-to-point route is several discs, not one. Each disc is
    /// centred on a slice of the line and only as wide as that slice plus the
    /// corridor, so a 200 km trip does not try to fit a 100 km radius into a
    /// request that tops out at 22.
    nonisolated static func corridorSegments(from start: CLLocationCoordinate2D,
                                             to end: CLLocationCoordinate2D,
                                             widthKm: Double = 2.0) -> [(center: CLLocationCoordinate2D, radiusKm: Double)] {
        let a = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let b = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let totalMeters = a.distance(from: b)
        guard totalMeters > 1 else { return [(start, max(widthKm, 3.0))] }
        let maxRadius = 22.0
        // A disc of radius R on a straight slice covers 2 * (R - width) of it.
        let maxLegMeters = max(2 * (maxRadius - widthKm) * 1_000, 4_000)
        let count = max(1, Int(ceil(totalMeters / maxLegMeters)))
        return (0..<count).map { index in
            let t0 = Double(index) / Double(count)
            let t1 = Double(index + 1) / Double(count)
            let first = interpolate(start, end, t0)
            let last = interpolate(start, end, t1)
            let center = interpolate(start, end, (t0 + t1) / 2)
            let legMeters = CLLocation(latitude: first.latitude, longitude: first.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            return (center, min(max(legMeters / 2_000 + widthKm, 3.0), maxRadius))
        }
    }

    nonisolated private static func interpolate(_ a: CLLocationCoordinate2D,
                                                _ b: CLLocationCoordinate2D,
                                                _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    nonisolated private static func merge(_ sets: [[Road]]) -> [Road] {
        var seen = Set<Int64>()
        var merged: [Road] = []
        for set in sets {
            for road in set where seen.insert(road.id).inserted { merged.append(road) }
        }
        return merged
    }

    nonisolated static func cachedCorridor(from start: CLLocationCoordinate2D,
                                           to end: CLLocationCoordinate2D,
                                           widthKm: Double = 2.0,
                                           surface: LoopSurface = .paved) -> [Road]? {
        let slices = corridorSegments(from: start, to: end, widthKm: widthKm)
        var sets: [[Road]] = []
        for slice in slices {
            guard let roads = cachedArea(center: slice.center, radiusKm: slice.radiusKm, surface: surface) else {
                return nil
            }
            sets.append(roads)
        }
        let merged = merge(sets)
        return merged.isEmpty ? nil : merged
    }

    static func downloadCorridor(from start: CLLocationCoordinate2D,
                                 to end: CLLocationCoordinate2D,
                                 widthKm: Double = 2.0,
                                 surface: LoopSurface = .paved,
                                 timeout: TimeInterval = 20) async throws -> [Road] {
        let slices = corridorSegments(from: start, to: end, widthKm: widthKm)
        var sets: [[Road]] = []
        for (index, slice) in slices.enumerated() {
            // A trip can be half warm; only the cold slices cost a request.
            if let cached = cachedArea(center: slice.center, radiusKm: slice.radiusKm, surface: surface) {
                sets.append(cached)
                continue
            }
            do {
                let roads = try await downloadArea(center: slice.center, radiusKm: slice.radiusKm,
                                                   surface: surface, timeout: timeout)
                sets.append(roads)
            } catch {
                // Keep going: a partial corridor can still produce a route,
                // and the region cache keeps whatever did arrive.
                RevertDiagnostics.log("corridor slice \(index + 1)/\(slices.count) failed: \(error.localizedDescription)")
                if sets.isEmpty, index == slices.count - 1 { throw error }
            }
        }
        let merged = merge(sets)
        guard !merged.isEmpty else { throw URLError(.resourceUnavailable) }
        return merged
    }

    // MARK: Route roads

    /// Roads for the route being ridden, so speed limits, curve warnings and
    /// surface alerts work on a directions route that never downloaded an area.
    /// Kept separate from the tile cache because it arrives as one corridor.
    nonisolated(unsafe) private static var routeRoads: [Road] = []
    nonisolated private static let routeRoadsLock = NSLock()

    nonisolated static func setRouteRoads(_ roads: [Road]) {
        routeRoadsLock.withLock { routeRoads = roads }
    }

    nonisolated static func clearRouteRoads() {
        routeRoadsLock.withLock { routeRoads = [] }
    }

    nonisolated static func routeRoads(near coordinate: CLLocationCoordinate2D) -> [Road] {
        let roads = routeRoadsLock.withLock { routeRoads }
        guard !roads.isEmpty else { return [] }
        let lat = 0.02, lon = 0.03
        return roads.filter {
            $0.maxLat >= coordinate.latitude - lat && $0.minLat <= coordinate.latitude + lat &&
            $0.maxLon >= coordinate.longitude - lon && $0.minLon <= coordinate.longitude + lon
        }
    }

    /// Roads from saved areas, decoded once and kept in memory.
    ///
    /// The tile store is the weak link on a busy Overpass: a 5.5 km road tile
    /// is a big `out geom` request and times out, which is why rides logged
    /// `roadItems=0` and no speed limits for twenty minutes. An area that was
    /// downloaded for a loop is already on disk and needs no network at all.
    nonisolated(unsafe) private static var areaMemory: [URL: (fetched: Date, roads: [Road])] = [:]
    nonisolated private static let areaMemoryLock = NSLock()
    nonisolated private static let maxAreaMemory = 2

    nonisolated static func areaRoads(near coordinate: CLLocationCoordinate2D) -> [Road] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: bulkCacheDirectory,
                                                                     includingPropertiesForKeys: nil) else {
            return []
        }
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var roads: [Road] = []
        for url in urls where isBulkFile(url) {
            guard let area = parse(url),
                  Date().timeIntervalSince(area.fetched) < bulkCacheDays * 86_400 else { continue }
            let centre = CLLocation(latitude: area.center.latitude, longitude: area.center.longitude)
            guard point.distance(from: centre) <= area.radiusKm * 1_000 else { continue }
            // Never decode a multi-megabyte area on the caller's thread: the
            // alert engine asks on every GPS fix. Warm it in the background and
            // pick it up on the next fix instead.
            guard let cached = areaMemoryLock.withLock({ areaMemory[url] }), cached.fetched == area.fetched else {
                Task.detached(priority: .utility) { _ = decodedArea(url: url, fetched: area.fetched) }
                continue
            }
            let lat = 0.02, lon = 0.03
            roads.append(contentsOf: cached.roads.filter {
                $0.maxLat >= coordinate.latitude - lat && $0.minLat <= coordinate.latitude + lat &&
                $0.maxLon >= coordinate.longitude - lon && $0.minLon <= coordinate.longitude + lon
            })
        }
        return roads
    }

    nonisolated private static func decodedArea(url: URL, fetched: Date) -> [Road] {
        if let cached = areaMemoryLock.withLock({ areaMemory[url] }), cached.fetched == fetched {
            return cached.roads
        }
        guard let cache = decode(url) else { return [] }
        areaMemoryLock.withLock {
            areaMemory[url] = (fetched, cache.roads)
            while areaMemory.count > maxAreaMemory {
                if let oldest = areaMemory.min(by: { $0.value.fetched < $1.value.fetched })?.key {
                    areaMemory[oldest] = nil
                } else { break }
            }
        }
        return cache.roads
    }

    /// Tiles plus the active route corridor, deduped. The alert engine reads
    /// this so a ride works whether its data came from tiles or a corridor.
    nonisolated static func items(near coordinate: CLLocationCoordinate2D) -> [Road] {
        var seen = Set<Int64>()
        var roads: [Road] = []
        for road in routeRoads(near: coordinate) where seen.insert(road.id).inserted {
            roads.append(road)
        }
        for road in areaRoads(near: coordinate) where seen.insert(road.id).inserted {
            roads.append(road)
        }
        for road in shared.items(near: coordinate) where seen.insert(road.id).inserted {
            roads.append(road)
        }
        return roads
    }

    nonisolated static func clearBulkCache() {
        try? FileManager.default.removeItem(at: bulkCacheDirectory)
        try? FileManager.default.removeItem(at: legacyBulkCacheURL)
        areaMemoryLock.withLock { areaMemory.removeAll() }
        bulkMemoryLock.withLock { bulkMemory.removeAll() }
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
        // A whole 0.05° tile of ways with geometry is the query that never
        // answers on a busy mirror: rides show zero road tiles while the much
        // smaller hazard queries succeed. Two halves halve the payload and are
        // merged; a half that fails still leaves the other one's roads.
        let half = tileDeg / 2
        let south = Double(y) * tileDeg
        let west = Double(x) * tileDeg
        let boxes: [(south: Double, west: Double, north: Double, east: Double)] = [
            (south, west, south + half, west + tileDeg),
            (south + half, west, south + tileDeg, west + tileDeg)
        ]
        var merged: [Road] = []
        var seen = Set<Int64>()
        await withTaskGroup(of: [Road]?.self) { group in
            for box in boxes {
                group.addTask {
                    try? await fetchWays(south: box.south, west: box.west,
                                         north: box.north, east: box.east,
                                         classes: classes, timeout: 45)
                }
            }
            for await roads in group {
                guard let roads else { continue }
                for road in roads where seen.insert(road.id).inserted {
                    merged.append(road)
                }
            }
        }
        guard !merged.isEmpty else { throw URLError(.timedOut) }
        return merged
    }

    nonisolated private static func fetchWays(south: Double, west: Double,
                                              north: Double, east: Double,
                                              classes: String,
                                              timeout: TimeInterval) async throws -> [Road] {
        let query = """
        [out:json][timeout:\(Int(timeout))];
        way["highway"~"^\(classes)$"](\(south),\(west),\(north),\(east));
        out geom qt;
        """
        return try await fetch(query: query, timeout: timeout, parallel: true)
    }

    nonisolated private static func fetch(
        query: String,
        timeout: TimeInterval,
        maxEndpoints: Int = 3,
        parallel: Bool = true
    ) async throws -> [Road] {
        let deadline = Date().addingTimeInterval(timeout)
        let endpoints = orderedEndpoints(limit: maxEndpoints)

        // Overpass answers with data, with a 502 "at capacity" page, or not at
        // all, and which of those happens changes minute to minute. Each
        // mirror therefore keeps its own task and its own place in the queue:
        // a saturated mirror rejects in ~300 ms and is retried with backoff
        // while a queued one is still being served, and the first answer wins.
        guard parallel else {
            // Tile downloads walk the mirrors one at a time; give each its own
            // slice so one dead host cannot eat the whole budget.
            var lastError: Error = URLError(.cannotConnectToHost)
            let slice = max(5, timeout / Double(max(endpoints.count, 1)))
            for endpoint in endpoints {
                let sliceDeadline = Date().addingTimeInterval(slice)
                do {
                    return try await pump(
                        query: query,
                        endpoint: endpoint,
                        deadline: min(sliceDeadline, deadline)
                    )
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }

        return try await withThrowingTaskGroup(of: [Road].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    try await pump(query: query, endpoint: endpoint, deadline: deadline)
                }
            }

            // Collect results rather than `next()`: once every mirror has
            // finished, `next()` returns nil forever, so the old loop kept
            // spinning at 100% CPU instead of reporting the last failure.
            var lastError: Error = URLError(.timedOut)
            while let result = await group.nextResult() {
                switch result {
                case .success(let roads):
                    group.cancelAll()
                    return roads
                case .failure(let error):
                    lastError = error
                }
            }
            throw lastError
        }
    }

    /// One mirror, retried with backoff until the shared deadline. The request
    /// timeout is the remaining budget, so a mirror that is merely queued is
    /// never cut short.
    nonisolated private static func pump(
        query: String,
        endpoint: String,
        deadline: Date
    ) async throws -> [Road] {
        var lastError: Error = URLError(.timedOut)
        var attempt = 0
        while deadline.timeIntervalSinceNow > 2 {
            attempt += 1
            let remaining = max(1, deadline.timeIntervalSinceNow)
            do {
                let roads = try await performFetch(query: query, timeout: remaining, endpoint: endpoint)
                record(endpoint: endpoint, success: true)
                return roads
            } catch {
                record(endpoint: endpoint, success: false)
                // Offline is not a queue: do not burn the whole budget
                // retrying a device with no signal.
                if (error as? URLError)?.code == .notConnectedToInternet {
                    throw error
                }
                lastError = error
                let backoff = min(0.5 * pow(2, Double(attempt - 1)), 4.0)
                let pause = min(backoff, max(deadline.timeIntervalSinceNow - 2, 0))
                guard pause > 0 else { break }
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            }
        }
        throw lastError
    }

    nonisolated private static let healthLock = NSLock()
    nonisolated(unsafe) private static var successes: [String: Date] = [:]
    nonisolated(unsafe) private static var failures: [String: Int] = [:]

    nonisolated private static func record(endpoint: String, success: Bool) {
        healthLock.withLock {
            if success {
                successes[endpoint] = Date()
                failures[endpoint] = 0
            } else {
                failures[endpoint, default: 0] += 1
            }
        }
    }

    /// Most recently successful mirror first, then whichever failed least.
    nonisolated private static func orderedEndpoints(limit: Int) -> [String] {
        healthLock.withLock {
            Array(overpassEndpoints.prefix(limit)).sorted { lhs, rhs in
                let left = successes[lhs] ?? .distantPast
                let right = successes[rhs] ?? .distantPast
                if left != right { return left > right }
                return (failures[lhs] ?? 0) < (failures[rhs] ?? 0)
            }
        }
    }

    nonisolated private static func performFetch(
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
        request.setValue("RevertApp/0.1 (personal open-source project)", forHTTPHeaderField: "User-Agent")
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
        return decoded.elements.compactMap { element -> Road? in
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
            // Kept as locals: one eighteen-argument initialiser inside a
            // compactMap defeated the type checker.
            let tags = element.tags ?? [:]
            let laneCount = tags["lanes"].flatMap(Int.init)
            let turnLanes = tags["turn:lanes"]
            let turnLanesForward = tags["turn:lanes:forward"]
            let turnLanesBackward = tags["turn:lanes:backward"]
            let oneway = tags["oneway"] ?? (tags["junction"] == "roundabout" ? "yes" : nil)
            return Road(
                id: element.id,
                highway: tags["highway"] ?? "",
                name: tags["name"],
                maxspeed: tags["maxspeed"],
                maxspeedForward: tags["maxspeed:forward"],
                maxspeedBackward: tags["maxspeed:backward"],
                surface: tags["surface"],
                oneway: oneway,
                ref: tags["ref"],
                coords: coordinates,
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon,
                lanes: laneCount,
                turnLanes: turnLanes,
                turnLanesForward: turnLanesForward,
                turnLanesBackward: turnLanesBackward
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
