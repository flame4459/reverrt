import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct NavigationJoinTests {
    private func route(kind: RouteKind, count: Int = 400) -> PlannedRoute {
        let points = (0..<count).map { index in
            RoutePoint(lat: 40.0 + Double(index) * 0.00005, lon: -73.0, road: 0)
        }
        return PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                            retraced: 0, bearing: 0, kind: kind)
    }

    @Test func pointToPointJoinsAwayFromTheStart() {
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route(kind: .directions), roads: [])
        // ~200 m along the line. The old 75 m gate to the route's first point
        // refused this, so guidance never advanced and the first turn was
        // announced for the rest of the ride.
        nav.handle(CLLocation(latitude: 40.0 + 0.002, longitude: -73.0))
        #expect(nav.joined)
    }

    @Test func aLoopIsApproachedNotJoinedMidRoute() {
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route(kind: .loop), roads: [])
        // 600 m along the loop, well past the start line. Joining here was what
        // skipped the approach to the start and started the clock mid-lap.
        nav.handle(CLLocation(latitude: 40.0 + 0.006, longitude: -73.0))
        #expect(!nav.joined)
    }

    @Test func loopJoinsAtItsStartLine() {
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route(kind: .loop), roads: [])
        nav.handle(CLLocation(latitude: 40.0 + 0.0002, longitude: -73.0))
        #expect(nav.joined)
    }

    @Test func loopRefusesAFixNowhereNearIt() {
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route(kind: .loop), roads: [])
        // Three kilometres beside the loop: not a join, just a rider who has
        // not reached it yet.
        nav.handle(CLLocation(latitude: 40.03, longitude: -73.03))
        #expect(!nav.joined)
    }
}
