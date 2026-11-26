import Testing
import Foundation
import CoreLocation
import MapKit
@testable import Revert

@MainActor
struct RibbonAndMapConfigTests {
    private func route() -> PlannedRoute {
        let points = (0..<200).map { index in
            RoutePoint(lat: 40.0 + Double(index) * 0.0002, lon: -73.0, road: 0)
        }
        return PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                            retraced: 0, bearing: 0, kind: .directions)
    }

    @Test func ribbonSplitsAtTheRiddenDistance() throws {
        let route = route()
        let half = route.length / 2
        let ribbon = RouteRibbon(route: route, progress: half)
        let travelledEnd = try #require(ribbon.travelled.last)
        let remainingStart = try #require(ribbon.remaining.first)
        #expect(abs(travelledEnd.latitude - remainingStart.latitude) < 0.002)
        #expect(!ribbon.remainingSegments.isEmpty)
        #expect(ribbon.travelled.count > 1)
        #expect(ribbon.remaining.count > 1)
    }

    @Test func ribbonHandlesBothEnds() {
        let route = route()
        let before = RouteRibbon(route: route, progress: 0)
        // The start point plus the cut at zero distance.
        #expect(before.travelled.count <= 2)
        #expect(before.remaining.count > 1)

        let after = RouteRibbon(route: route, progress: route.length * 2)
        #expect(after.remaining.last?.latitude == route.points.last?.lat)
    }

    @Test func paceColourIsStableAndClamped() {
        let cold = MapConfig.paceSIMD4(0)
        #expect(abs(cold.x - 0.396) < 0.001)
        #expect(abs(cold.y - 0.953) < 0.001)
        #expect(abs(cold.z - 0.875) < 0.001)
        #expect(MapConfig.paceSIMD4(-5) == cold)
        #expect(MapConfig.paceSIMD4(5) == MapConfig.paceSIMD4(1))
    }
}
