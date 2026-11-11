import Foundation
import CoreLocation

struct FuelStation: Identifiable, Hashable, Codable, Sendable {
    let id: Int64
    let name: String?
    let brand: String?
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var displayName: String { name ?? brand ?? "Fuel station" }
}

struct FuelSuggestion: Identifiable {
    var id: Int64 { station.id }
    let station: FuelStation
    let distanceAlong: Double      // meters from route start
    let detourMeters: Double
}

struct FuelPlan {
    let rangeKm: Double
    let usableKm: Double
    let routeKm: Double
    let stopsNeeded: Int
    let suggestions: [FuelSuggestion]
    let stationsFound: Int

    var needsFuelStop: Bool { stopsNeeded > 0 }
}

/// Finds fuel stations from OpenStreetMap and places them along a route at
/// usable tank-range intervals. No account, no routing backend: the station is
/// simply injected as a waypoint and the existing waypoint planner does the
/// pit-stop routing.
nonisolated enum FuelService {
    private final class CacheBox {
        let stations: [FuelStation]
        init(_ stations: [FuelStation]) { self.stations = stations }
    }

    nonisolated(unsafe) private static let cache = NSCache<NSString, CacheBox>()
    nonisolated private static let endpoints = [

        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter"
    ]

    nonisolated private struct DiskCache: Codable {
        let fetched: Date
        let stations: [FuelStation]
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FuelCache", isDirectory: true)
    }

    static func diskBytes() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func clearDiskCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private static func diskURL(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return cacheDirectory.appendingPathComponent("\(safe).json")
    }

    static func stations(along route: PlannedRoute, corridorKm: Double = 6) async -> [FuelStation] {
        guard !route.points.isEmpty else { return [] }
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for point in route.points {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        let padLat = corridorKm / 111.0
        let padLon = corridorKm / (111.0 * max(cos((minLat + maxLat) / 2 * .pi / 180), 0.2))
        let key = String(format: "%.3f,%.3f,%.3f,%.3f", minLat - padLat, maxLat + padLat,
                         minLon - padLon, maxLon + padLon) as NSString
        if let cached = cache.object(forKey: key) { return cached.stations }
        if let data = try? Data(contentsOf: diskURL(key as String)),
           let disk = try? JSONDecoder().decode(DiskCache.self, from: data),
           Date().timeIntervalSince(disk.fetched) < 90 * 86_400 {
            cache.setObject(CacheBox(disk.stations), forKey: key)
            return disk.stations
        }

        let bbox = "(\(minLat - padLat),\(minLon - padLon),\(maxLat + padLat),\(maxLon + padLon))"
        let query = """
        [out:json][timeout:25];
        nwr["amenity"="fuel"]\(bbox);
        out center;
        """
        for endpoint in endpoints {
            if let stations = try? await fetch(query: query, endpoint: endpoint) {
                cache.setObject(CacheBox(stations), forKey: key)
                writeDiskCache(key as String, stations)
                return stations
            }
        }
        return []
    }

    static func plan(route: PlannedRoute,
                     rangeKm: Double,
                     tankFraction: Double,
                     stations: [FuelStation]) -> FuelPlan {
        let routeKm = route.length / 1_000
        // Never round a nearly empty tank up to a comfortable 40 km: that
        // overstates range exactly when the rider needs a stop most.
        let usableKm = max(rangeKm * min(max(tankFraction, 0.1), 1), 1)
        guard routeKm > usableKm else {
            return FuelPlan(rangeKm: rangeKm, usableKm: usableKm, routeKm: routeKm,
                            stopsNeeded: 0, suggestions: [], stationsFound: stations.count)
        }
        let stopsNeeded = max(Int(ceil(routeKm / usableKm)) - 1, 1)

        // Project each station onto the nearest route vertex.
        var located: [FuelSuggestion] = []
        for station in stations {
            var bestDistance = Double.infinity
            var bestAlong = 0.0
            let stride = max(1, route.points.count / 900)
            for index in Swift.stride(from: 0, to: route.points.count, by: stride) {
                let point = route.points[index]
                let distance = RoadGraph.flat(point.lat, point.lon, station.lat, station.lon).dist
                if distance < bestDistance {
                    bestDistance = distance
                    bestAlong = route.cumulative[index]
                }
            }
            guard bestDistance <= 5_000 else { continue }
            located.append(FuelSuggestion(station: station, distanceAlong: bestAlong,
                                          detourMeters: bestDistance))
        }

        var picked: [FuelSuggestion] = []
        for stopIndex in 1...stopsNeeded {
            let target = usableKm * Double(stopIndex) * 1_000
            let candidates = located
                .filter { suggestion in
                    suggestion.distanceAlong > (picked.last?.distanceAlong ?? 0) + usableKm * 1_000 * 0.4
                }
                .sorted { abs($0.distanceAlong - target) < abs($1.distanceAlong - target) }
            if let best = candidates.first {
                picked.append(best)
            }
        }

        return FuelPlan(rangeKm: rangeKm, usableKm: usableKm, routeKm: routeKm,
                        stopsNeeded: stopsNeeded, suggestions: picked,
                        stationsFound: stations.count)
    }

    private static func writeDiskCache(_ key: String, _ stations: [FuelStation]) {
        let url = diskURL(key)
        let dir = cacheDirectory
        let payload = DiskCache(fetched: Date(), stations: stations)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(payload) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func fetch(query: String, endpoint: String) async throws -> [FuelStation] {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("RevertApp/0.1 (personal open-source project)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = "data=\(encoded)".data(using: .utf8)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.elements.compactMap { element in
            guard let lat = element.lat ?? element.center?.lat,
                  let lon = element.lon ?? element.center?.lon else { return nil }
            return FuelStation(id: element.id,
                               name: element.tags?["name"],
                               brand: element.tags?["brand"],
                               lat: lat, lon: lon)
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
