import Foundation
import CoreLocation

struct ElevationSample: Codable, Hashable, Sendable {
    var distance: Double      // meters from the start
    var elevation: Double     // meters above sea level
}

/// Terrain profile for a planned route.
///
/// This uses the free Open-Meteo elevation endpoint (no account, no personal
/// backend). Results are cached in memory, and failure is silent: the route is
/// still usable, it just has no profile. Recorded rides never call this — their
/// barometric/GPS altitude is already on device.
nonisolated enum ElevationService {
    private final class CacheBox {
        let samples: [ElevationSample]
        init(_ samples: [ElevationSample]) { self.samples = samples }
    }

    nonisolated(unsafe) private static let cache = NSCache<NSString, CacheBox>()

    nonisolated private struct DiskCache: Codable {
        let fetched: Date
        let samples: [ElevationSample]
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ElevationCache", isDirectory: true)
    }

    static func profile(coordinates: [CLLocationCoordinate2D],
                        totalMeters: Double,
                        sampleCount: Int = 36) async -> [ElevationSample] {
        guard coordinates.count > 2, totalMeters > 50 else { return [] }
        let keyString = cacheKey(coordinates)
        let key = keyString as NSString
        if let cached = cache.object(forKey: key) { return cached.samples }
        if let disk = readDiskCache(keyString) {
            cache.setObject(CacheBox(disk), forKey: key)
            return disk
        }

        let sampled = sampleCoordinates(coordinates, count: sampleCount)
        guard sampled.count >= 2 else { return [] }

        guard let elevations = await fetch(sampled) else { return [] }
        guard elevations.count == sampled.count else { return [] }

        var samples: [ElevationSample] = []
        samples.reserveCapacity(elevations.count)
        for (index, elevation) in elevations.enumerated() {
            let distance = totalMeters * Double(index) / Double(max(elevations.count - 1, 1))
            samples.append(ElevationSample(distance: distance, elevation: elevation))
        }
        cache.setObject(CacheBox(samples), forKey: key)
        writeDiskCache(keyString, samples)
        return samples
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

    private static func readDiskCache(_ key: String) -> [ElevationSample]? {
        let url = diskURL(key)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(DiskCache.self, from: data),
              Date().timeIntervalSince(cached.fetched) < 90 * 86_400 else { return nil }
        return cached.samples
    }

    private static func writeDiskCache(_ key: String, _ samples: [ElevationSample]) {
        let url = diskURL(key)
        let dir = cacheDirectory
        let payload = DiskCache(fetched: Date(), samples: samples)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(payload) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Even spacing along the polyline by distance, not by vertex index.
    private static func sampleCoordinates(_ coordinates: [CLLocationCoordinate2D], count: Int) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var cumulative: [Double] = [0]
        for index in 1..<coordinates.count {
            let a = coordinates[index - 1], b = coordinates[index]
            let distance = RoadGraph.flat(a.latitude, a.longitude, b.latitude, b.longitude).dist
            cumulative.append(cumulative[index - 1] + max(distance, 0.001))
        }
        guard let total = cumulative.last, total > 0 else { return [coordinates[0]] }
        var output: [CLLocationCoordinate2D] = []
        var cursor = 0
        for index in 0..<count {
            let target = total * Double(index) / Double(max(count - 1, 1))
            while cursor < cumulative.count - 2, cumulative[cursor + 1] < target { cursor += 1 }
            let span = max(cumulative[cursor + 1] - cumulative[cursor], 0.001)
            let fraction = min(max((target - cumulative[cursor]) / span, 0), 1)
            let a = coordinates[cursor], b = coordinates[cursor + 1]
            output.append(CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                longitude: a.longitude + (b.longitude - a.longitude) * fraction
            ))
        }
        return output
    }

    private static func fetch(_ coordinates: [CLLocationCoordinate2D]) async -> [Double]? {
        let latitudes = coordinates.map { String(format: "%.6f", $0.latitude) }.joined(separator: ",")
        let longitudes = coordinates.map { String(format: "%.6f", $0.longitude) }.joined(separator: ",")
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitudes),
            URLQueryItem(name: "longitude", value: longitudes)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("RiderApp/0.1", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.elevation
        } catch {
            return nil
        }
    }

    private static func cacheKey(_ coordinates: [CLLocationCoordinate2D]) -> String {
        guard let first = coordinates.first, let last = coordinates.last else { return "empty" }
        return String(format: "%.4f,%.4f-%.4f,%.4f-%d",
                      first.latitude, first.longitude, last.latitude, last.longitude, coordinates.count)
    }

    private struct Response: Decodable {
        let elevation: [Double]
    }
}

extension Array where Element == ElevationSample {
    var totalClimb: Double {
        guard count > 1 else { return 0 }
        var climb = 0.0
        for index in 1..<count {
            let delta = self[index].elevation - self[index - 1].elevation
            if delta > 0 { climb += delta }
        }
        return climb
    }

    var totalDescent: Double {
        guard count > 1 else { return 0 }
        var descent = 0.0
        for index in 1..<count {
            let delta = self[index].elevation - self[index - 1].elevation
            if delta < 0 { descent += -delta }
        }
        return descent
    }

    var summit: Double {
        map(\.elevation).max() ?? 0
    }

    var hasMountainPass: Bool {
        count > 4 && totalClimb >= 220 && summit >= 280
    }
}
