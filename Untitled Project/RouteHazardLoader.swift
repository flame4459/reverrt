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

    nonisolated private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RouteHazards", isDirectory: true)
    }

    /// nil means the network request failed; [] means the route genuinely has
    /// no devices and alerts should stay silent.
    static func load(route: PlannedRoute) async -> [Hazard]? {
        let key = routeKey(route)
        if let cached = readCache(key) { return cached }
        guard let bbox = boundingBox(route) else { return [] }
        let query = """
        [out:json][timeout:30];
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
        for endpoint in endpoints {
            if let hazards = try? await fetch(query: query, endpoint: endpoint) {
                let filtered = corridorFilter(hazards, route: route)
                writeCache(key, filtered)
                return filtered
            }
        }
        return nil
    }

    private static func corridorFilter(_ hazards: [Hazard], route: PlannedRoute) -> [Hazard] {
        guard route.points.count > 1 else { return [] }
        return hazards.filter { hazard in
            let lateral: Double
            switch hazard.kind {
            case .school: lateral = 45
            case .roundabout: lateral = 30
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
        return snapshot.hazards
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
        request.setValue("RiderApp/0.1 (personal open-source project)", forHTTPHeaderField: "User-Agent")
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
