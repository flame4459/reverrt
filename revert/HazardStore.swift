import Foundation

/// Stop signs, lights, cameras, rail crossings, schools and roundabouts from OpenStreetMap.
enum HazardStore {
    nonisolated static let shared = TileStore<Hazard>(folder: "hazards_v3", pause: 0.35, idOf: { $0.id }) { x, y in
        try await HazardStore.fetch(x: x, y: y)
    }

    nonisolated private static let endpoints = [
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter"
    ]

    nonisolated private static func fetch(x: Int, y: Int) async throws -> [Hazard] {
        let s = Double(y) * tileDeg, w = Double(x) * tileDeg
        let n = s + tileDeg, e = w + tileDeg
        let bbox = "(\(s),\(w),\(n),\(e))"
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
        var lastError: Error = URLError(.cannotConnectToHost)
        for endpoint in endpoints {
            do {
                return try await fetch(query: query, endpoint: endpoint)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    nonisolated private static func fetch(query: String, endpoint: String) async throws -> [Hazard] {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("RevertApp/0.1 (personal open-source project)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        req.httpBody = "data=\(encoded)".data(using: .utf8)
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.elements.compactMap { el in
            guard let tags = el.tags, let kind = kind(for: tags) else { return nil }
            guard let lat = el.lat ?? el.center?.lat, let lon = el.lon ?? el.center?.lon else { return nil }
            let uid: Int64 = el.type == "node" ? el.id : (el.type == "way" ? -el.id : -(el.id + 1_000_000_000_000))
            return Hazard(id: uid, kind: kind, lat: lat, lon: lon)
        }
    }

    nonisolated static func kind(for tags: [String: String]) -> HazardKind? {
        if tags["highway"] == "stop" { return .stop }
        if tags["highway"] == "traffic_signals" { return .signal }
        if tags["highway"] == "speed_camera" { return .speedCamera }
        if tags["railway"] == "level_crossing" { return .railCrossing }
        if tags["amenity"] == "school" { return .school }
        if tags["junction"] == "roundabout" || tags["highway"] == "mini_roundabout" { return .roundabout }
        switch tags["enforcement"] {
        case "traffic_signals", "red_light": return .redLightCamera
        case "maxspeed", "average_speed", "speed": return .speedCamera
        default: return nil
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
