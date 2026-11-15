import Testing
import Foundation
@testable import Revert

struct CorridorChunkTests {
    private func route(latitudeSpan: Double, points: Int = 60) -> PlannedRoute {
        let pts = (0..<points).map { index in
            RoutePoint(lat: 40.0 + latitudeSpan * Double(index) / Double(points - 1),
                       lon: -74.0, road: 0)
        }
        return PlannedRoute(points: pts, roads: [:], twistPerKm: 0, retraced: 0, bearing: 0)
    }

    @Test func shortRouteIsOneChunk() {
        #expect(RouteHazardLoader.chunkBoxes(route(latitudeSpan: 0.01)).count == 1)
    }

    @Test func longRouteIsSplitButBounded() {
        let boxes = RouteHazardLoader.chunkBoxes(route(latitudeSpan: 1.0))
        #expect(boxes.count > 1)
        #expect(boxes.count <= 12)
    }

    @Test func chunksCoverTheRoute() {
        let boxes = RouteHazardLoader.chunkBoxes(route(latitudeSpan: 0.4))
        // Every point on the route falls inside at least one chunk.
        let pts = (0...40).map { 40.0 + 0.4 * Double($0) / 40.0 }
        for latitude in pts {
            #expect(boxes.contains { latitude >= $0.south && latitude <= $0.north })
        }
    }
}
