import Testing
import Foundation
@testable import Revert

struct GraphCacheTests {
    private func roads() -> [Road] {
        func road(id: Int64, _ points: [(Double, Double)]) -> Road {
            let coords = points.flatMap { [$0.0, $0.1] }
            let lats = points.map(\.0)
            let lons = points.map(\.1)
            return Road(id: id, highway: "tertiary", name: "Test \(id)",
                        maxspeed: nil, maxspeedForward: nil, maxspeedBackward: nil,
                        surface: nil, oneway: nil, ref: nil, coords: coords,
                        minLat: lats.min()!, maxLat: lats.max()!,
                        minLon: lons.min()!, maxLon: lons.max()!)
        }
        return [road(id: 1, [(40.0, -74.0), (40.0, -73.995), (40.0, -73.99)]),
                road(id: 2, [(40.0, -73.99), (40.005, -73.99), (40.01, -73.99)])]
    }

    @Test func snapshotRestoresNodesEdgesAndRouting() throws {
        let roads = roads()
        let original = RoadGraph(roads: roads)
        let restored = try #require(RoadGraph(snapshot: original.snapshot(), roads: roads))

        #expect(restored.nodeLat == original.nodeLat)
        #expect(restored.nodeLon == original.nodeLon)
        #expect(restored.edges.count == original.edges.count)
        #expect(restored.twin.count == original.twin.count)

        let costs = Array(repeating: 1.0, count: original.edges.count)
        let start = try #require(original.nearestNode(latitude: 40.0, longitude: -73.9998, withinMeters: 500))
        let end = try #require(original.nearestNode(latitude: 40.0098, longitude: -73.9902, withinMeters: 500))
        let originalPath = original.shortestPath(from: start, to: end, costs: costs)
        let restoredPath = restored.shortestPath(from: start, to: end, costs: costs)
        #expect(originalPath != nil)
        #expect(restoredPath == originalPath)
    }

    @Test func snapshotRejectsADifferentRoadSet() {
        let roads = roads()
        let graph = RoadGraph(roads: roads)
        #expect(RoadGraph(snapshot: graph.snapshot(), roads: Array(roads.dropLast())) == nil)
    }

    @Test func roadsHashIsStableAndSensitive() {
        let roads = roads()
        #expect(RoadGraph.roadsHash(roads) == RoadGraph.roadsHash(roads))

        var changed = roads
        changed[0] = Road(id: 1, highway: "tertiary", name: "Test 1",
                          maxspeed: nil, maxspeedForward: nil, maxspeedBackward: nil,
                          surface: nil, oneway: nil, ref: nil,
                          coords: [40.0, -74.0, 40.0, -73.994],
                          minLat: 40.0, maxLat: 40.0, minLon: -74.0, maxLon: -73.994)
        #expect(RoadGraph.roadsHash(changed) != RoadGraph.roadsHash(roads))
    }

    @Test func nearestNodeGivesUpWhenNothingIsClose() {
        let graph = RoadGraph(roads: roads())
        #expect(graph.nearestNode(latitude: 41.5, longitude: -72.0, withinMeters: 500) == nil)
        #expect(graph.nearestNode(latitude: 40.0, longitude: -73.9998, withinMeters: 500) != nil)
    }
}
