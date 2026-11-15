import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct AreaRoadsTests {
    private func syntheticRoad(id: Int64, around center: CLLocationCoordinate2D) -> Road {
        let lat = center.latitude, lon = center.longitude
        return Road(id: id, highway: "tertiary", name: "Area Road",
                    maxspeed: "25 mph", maxspeedForward: nil, maxspeedBackward: nil,
                    surface: nil, oneway: nil, ref: nil,
                    coords: [lat, lon - 0.001, lat, lon + 0.001],
                    minLat: lat, maxLat: lat, minLon: lon - 0.001, maxLon: lon + 0.001)
    }

    @Test func savedAreaFeedsTheAlertEngineWithoutNetwork() async throws {
        let center = CLLocationCoordinate2D(latitude: 40.5, longitude: -73.5)
        let roads = [syntheticRoad(id: 900_001, around: center)]
        let cache = RoadStore.BulkCache(centerLatitude: center.latitude,
                                        centerLongitude: center.longitude,
                                        fetched: Date(),
                                        radiusKm: 10,
                                        surface: .paved,
                                        roads: roads)
        let name = RoadStore.bulkFileName(center: center, radiusKm: 10, surface: .paved, at: Date())
        let url = RoadStore.bulkCacheDirectory
            .appendingPathComponent((name as NSString).deletingPathExtension + ".plist")
        try FileManager.default.createDirectory(at: RoadStore.bulkCacheDirectory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(cache).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        // The first call starts a background decode; the second finds it warm.
        _ = RoadStore.areaRoads(near: center)
        var near: [Road] = []
        for _ in 0..<50 where near.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            near = RoadStore.areaRoads(near: center)
        }
        #expect(near.contains { $0.id == 900_001 })
        #expect(RoadStore.items(near: center).contains { $0.id == 900_001 })
    }
}
