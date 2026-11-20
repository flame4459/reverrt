import Foundation
import CoreLocation

/// Loads all traffic devices on a planned route in one Overpass request and
/// caches the corridor-filtered result. This is what keeps alerts from firing
/// for stop signs on a parallel road that happens to be within a tile.
nonisolated enum RouteHazardLoader {
    nonisolated private static let endpoints = [
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter"
    ]

    nonisolated private struct Snapshot: Codable, Sendable {
        let fetched: Date
        let routeKey: String
        let hazards: [Hazard]
    }

    /// What the corridor query produced, and why. The debug export prints the
    /// reason so "failed" can be told apart from "offline", "timeout" or a
    /// route that is simply too big to query.
    nonisolated struct Outcome: Sendable {
        /// nil when every endpoint failed; [] when the route genuinely has no
        /// devices and alerts should stay silent.
        let hazards: [Hazard]?
        let reason: String
    }

    nonisolated private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RouteHazards", isDirectory: true)
    }

    static func load(route: PlannedRoute) async -> Outcome {
        // A 500+ mile route has a continental bounding box; querying all of it
        // would be slow and pointless. The tile cache plus the route-corridor
        // filter in AlertManager still handles devices near the rider.
        if route.length > 300_000 {
            return Outcome(hazards: nil, reason: "skipped:route-too-long")
        }
        let key = routeKey(route)
        if let cached = readCache(key) {
            return Outcome(hazards: cached, reason: "cached")
        }
        let chunks = chunkBoxes(route)
        guard !chunks.isEmpty else {
            return Outcome(hazards: [], reason: "empty-route")
        }

        // One query for a whole route is the request that times out for forty
        // seconds and sometimes six minutes. The same query cut into a handful
        // of small boxes answers in pieces, and a piece that fails does not
        // cost the rest.
        // Chunking helps on a healthy mirror and hurts on a dead one: twelve
        // cells retrying three endpoints each is minutes of waiting. A hard
        // deadline keeps the worst case at half a minute and returns whatever
        // arrived from the cells that did answer.
        let sink = HazardSink()
        let work = Task { await fetchChunks(chunks, into: sink) }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(25))
            if !Task.isCancelled { work.cancel() }
        }
        await work.value
        deadline.cancel()

        let collected = sink.snapshot
        guard collected.success else {
            return Outcome(hazards: nil, reason: "failed:\(collected.reason)")
        }
        let filtered = corridorFilter(collected.hazards, route: route)
        // Only a non-empty answer is worth 30 days in the cache. An empty one
        // is the most likely result to be a server hiccup.
        if !filtered.isEmpty { writeCache(key, filtered) }
        return Outcome(hazards: filtered, reason: "ok chunks=\(chunks.count)")
    }

    /// Thread-safe collection point for chunk results; chunks finish in any
    /// order and some never finish at all.
    private final class HazardSink: @unchecked Sendable {
        private let lock = NSLock()
        private var byID: [Int64: Hazard] = [:]
        private var succeeded = false
        private var failure = "timeout"

        func record(_ result: (hazards: [Hazard]?, reason: String)) {
            lock.withLock {
                if let hazards = result.hazards {
                    succeeded = true
                    for hazard in hazards { byID[hazard.id] = hazard }
                } else {
                    failure = result.reason
                }
            }
        }

        var snapshot: (hazards: [Hazard], success: Bool, reason: String) {
            lock.withLock { (Array(byID.values), succeeded, failure) }
        }
    }

    nonisolated private static func fetchChunks(_ chunks: [Box], into sink: HazardSink) async {
        await withTaskGroup(of: (hazards: [Hazard]?, reason: String).self) { group in
            var next = 0
            var active = 0
            let limit = 3

            func addNext() -> Bool {
                guard next < chunks.count, !Task.isCancelled else { return false }
                let box = chunks[next]
                next += 1
                group.addTask { await fetchChunk(box) }
                return true
            }

            while active < limit && addNext() { active += 1 }
            while active > 0 {
                guard let result = await group.next() else { break }
                active -= 1
                sink.record(result)
                if addNext() { active += 1 }
            }
            group.cancelAll()
        }
    }

    nonisolated struct Box: Sendable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double
    }

    nonisolated static func chunkBoxes(_ route: PlannedRoute) -> [Box] {
        let lats = route.points.map(\.lat)
        let lons = route.points.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        let pad = 0.012
        let south = minLat - pad, north = maxLat + pad
        let west = minLon - pad, east = maxLon + pad

        // ~5 km cells, grown until the grid fits the request budget.
        var cell = 0.05
        var columns = 1
        var rows = 1
        repeat {
            columns = max(1, Int(ceil((east - west) / cell)))
            rows = max(1, Int(ceil((north - south) / cell)))
            if columns * rows <= 12 { break }
            cell *= 1.35
        } while cell < 5

        var boxes: [Box] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let boxSouth = south + Double(row) * (north - south) / Double(rows)
                let boxNorth = south + Double(row + 1) * (north - south) / Double(rows)
                let boxWest = west + Double(column) * (east - west) / Double(columns)
                let boxEast = west + Double(column + 1) * (east - west) / Double(columns)
                boxes.append(Box(south: boxSouth, west: boxWest, north: boxNorth, east: boxEast))
            }
        }
        return boxes
    }

    nonisolated private static func fetchChunk(_ box: Box) async -> (hazards: [Hazard]?, reason: String) {
        let bbox = "(\(box.south),\(box.west),\(box.north),\(box.east))"
        let query = """
        [out:json][timeout:25];
        (
          node["highway"="stop"]\(bbox);
          node["highway"="traffic_signals"]\(bbox);
          node["highway"="speed_camera"]\(bbox);
          node["enforcement"]\(bbox);
          node["railway"="level_crossing"]\(bbox);
          nwr["amenity"="school"]\(bbox);
          nwr["junction"="roundabout"]\(bbox);
          node["highway"="mini_roundabout"]\(bbox);
        );
        out center;
        """
        var lastFailure = "error"
        for endpoint in endpoints {
            do {
                return (try await fetch(query: query, endpoint: endpoint), "ok")
            } catch {
                lastFailure = shortReason(error)
            }
        }
        return (nil, lastFailure)
    }

    /// A few words for the debug export; the full error would swamp the line.
    private static func shortReason(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "error" }
        switch urlError.code {
        case .timedOut: return "timeout"
        case .notConnectedToInternet: return "offline"
        case .networkConnectionLost: return "connection-lost"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "no-dns"
        case .badServerResponse: return "bad-response"
        default: return "url-error-\(urlError.code.rawValue)"
        }
    }

    private static func corridorFilter(_ hazards: [Hazard], route: PlannedRoute) -> [Hazard] {
        guard route.points.count > 1 else { return [] }
        return hazards.filter { hazard in
            let lateral: Double
            switch hazard.kind {
            case .school: lateral = 45
            case .roundabout: lateral = 30
            case .userMark: lateral = 22
            default: lateral = 14
            }
            return RouteCorridor.project(
                latitude: hazard.lat, longitude: hazard.lon,
                route: route, near: 0, behind: 0,
                ahead: route.length, maxLateral: lateral
            ) != nil
        }
    }

    private static func boundingBox(_ route: PlannedRoute) -> String? {
        guard let first = route.points.first else { return nil }
        var minLat = first.lat, maxLat = first.lat
        var minLon = first.lon, maxLon = first.lon
        for point in route.points {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        let pad = 0.012
        return "(\(minLat - pad),\(minLon - pad),\(maxLat + pad),\(maxLon + pad))"
    }

    private static func routeKey(_ route: PlannedRoute) -> String {
        guard let first = route.points.first, let last = route.points.last else { return "empty" }
        // Stable across launches; a route id is not.
        var hash: UInt64 = 14_695_981_039_346_656_037
        func mix(_ value: Double) {
            let bits = UInt64(bitPattern: Int64((value * 1_000_000).rounded()))
            hash ^= bits &+ 0x9E3779B97F4A7C15 &+ (hash << 6) &+ (hash >> 2)
        }
        mix(first.lat); mix(first.lon); mix(last.lat); mix(last.lon)
        mix(Double(route.points.count)); mix(route.length)
        return String(hash, radix: 16)
    }

    private static func cacheURL(_ key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private static func readCache(_ key: String) -> [Hazard]? {
        guard let data = try? Data(contentsOf: cacheURL(key)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince(snapshot.fetched) < 30 * 86_400 else { return nil }
        // A cached "nothing here" is treated as a miss so the next ride asks
        // again instead of silently inheriting the empty answer.
        return snapshot.hazards.isEmpty ? nil : snapshot.hazards
    }

    private static func writeCache(_ key: String, _ hazards: [Hazard]) {
        let url = cacheURL(key)
        let dir = cacheDirectory
        let snapshot = Snapshot(fetched: Date(), routeKey: key, hazards: hazards)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func fetch(query: String, endpoint: String) async throws -> [Hazard] {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("RevertApp/0.1 (personal open-source project)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = "data=\(encoded)".data(using: .utf8)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.elements.compactMap { element in
            guard let tags = element.tags, let kind = HazardStore.kind(for: tags) else { return nil }
            guard let lat = element.lat ?? element.center?.lat,
                  let lon = element.lon ?? element.center?.lon else { return nil }
            let uid: Int64 = element.type == "node" ? element.id
                : (element.type == "way" ? -element.id : -(element.id + 1_000_000_000_000))
            return Hazard(id: uid, kind: kind, lat: lat, lon: lon)
        }
    }

    private struct Response: Decodable {
        struct Center: Decodable { let lat: Double; let lon: Double }
        struct Element: Decodable {
            let type: String
            let id: Int64
            let lat: Double?
            let lon: Double?
            let center: Center?
            let tags: [String: String]?
        }
        let elements: [Element]
    }
}
