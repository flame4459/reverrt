import Testing
import Foundation
@testable import Revert

struct BulkCacheFormatTests {
    private func road(id: Int64) -> Road {
        let coords = [40.0, -74.0, 40.001, -73.999]
        return Road(id: id, highway: "tertiary", name: "Road \(id)",
                    maxspeed: "25 mph", maxspeedForward: nil, maxspeedBackward: nil,
                    surface: nil, oneway: "yes", ref: nil, coords: coords,
                    minLat: 40.0, maxLat: 40.001, minLon: -74.0, maxLon: -73.999)
    }

    @Test func binaryPlistRoundTripsRoads() throws {
        let roads = (0..<50).map { road(id: Int64($0)) }
        let cache = RoadStore.BulkCache(centerLatitude: 40.7,
                                        centerLongitude: -73.9,
                                        fetched: Date(timeIntervalSince1970: 1_800_000_000),
                                        radiusKm: 22,
                                        surface: .paved,
                                        roads: roads)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(cache)
        let decoded = try PropertyListDecoder().decode(RoadStore.BulkCache.self, from: data)

        #expect(decoded.roads.count == 50)
        #expect(decoded.radiusKm == 22)
        #expect(decoded.surface == .paved)
        #expect(decoded.roads[3].id == 3)
        #expect(decoded.roads[3].coords == roads[3].coords)
        #expect(decoded.roads[3].name == "Road 3")
    }

    @Test func bulkFileDetectionAcceptsBothFormats() {
        #expect(RoadStore.isBulkFile(URL(fileURLWithPath: "/tmp/a.plist")))
        #expect(RoadStore.isBulkFile(URL(fileURLWithPath: "/tmp/a.json")))
        #expect(!RoadStore.isBulkFile(URL(fileURLWithPath: "/tmp/a.txt")))
    }
}
