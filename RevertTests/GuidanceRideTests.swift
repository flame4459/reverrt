import Testing
import Foundation
import CoreLocation
@testable import Revert

/// Drives `NavigationManager` with synthetic fixes along a known route, in the
/// simulator, the way the route simulator does. This is the layer the field
/// bugs lived in: joining, advancing, and left/right being the road's actual
/// side.
@MainActor
struct GuidanceRideTests {
    /// North 200 m, right turn, east 200 m, left turn, north 200 m.
    private func lRoute(kind: RouteKind = .directions) -> PlannedRoute {
        var points: [RoutePoint] = []
        let latStep = 0.00018      // ~20 m
        let lonStep = 0.000235     // ~20 m at 40°N
        for index in 0...10 {
            points.append(RoutePoint(lat: 40.0 + Double(index) * latStep, lon: -73.0, road: 0))
        }
        let corner = points.last!
        for index in 1...10 {
            points.append(RoutePoint(lat: corner.lat, lon: -73.0 + Double(index) * lonStep, road: 0))
        }
        let second = points.last!
        for index in 1...10 {
            points.append(RoutePoint(lat: second.lat + Double(index) * latStep, lon: second.lon, road: 0))
        }
        return PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                            retraced: 0, bearing: 0, kind: kind)
    }

    private func fix(_ coordinate: CLLocationCoordinate2D, course: Double, speed: Double = 12) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 10,
                   horizontalAccuracy: 4, verticalAccuracy: 4,
                   course: course, speed: speed, timestamp: Date())
    }

    @Test func guidanceAdvancesAndReportsTheRoadsActualSide() {
        let nav = NavigationManager()
        defer { nav.stop() }
        let route = lRoute()
        nav.start(route, roads: [])

        var seen: [NavStep.Turn] = []
        var distances: [Double] = []
        let points = route.points
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let course = RoadGraph.flat(a.lat, a.lon, b.lat, b.lon).heading
            nav.handle(fix(a.coordinate, course: course))
            #expect(nav.joined)
            if let step = nav.step, step.turn != .start, step.turn != .arrive {
                if seen.last != step.turn { seen.append(step.turn) }
                distances.append(nav.stepDistance)
            }
        }

        let stepDump = route.steps.map { "\($0.turn)@\(Int($0.distance))" }.joined(separator: ",")
        // The first turn from north onto east is a right; the second from east
        // onto north is a left. If either is mirrored, this fails.
        #expect(seen.contains(.right), "expected a right turn, saw \(seen); steps=\(stepDump)")
        #expect(seen.contains(.left), "expected a left turn, saw \(seen)")
        // The distance to the upcoming turn has to move, not sit at zero.
        #expect((distances.max() ?? 0) > 40, "turn distance never grew: \(distances.prefix(8))")
        #expect(nav.remaining < route.length * 0.95)
    }

    @Test func cameraHeadingFollowsTheRouteWhileMoving() {
        let nav = NavigationManager()
        defer { nav.stop() }
        let route = lRoute()
        nav.start(route, roads: [])
        let a = route.points[2], b = route.points[3]
        let course = RoadGraph.flat(a.lat, a.lon, b.lat, b.lon).heading
        nav.handle(fix(a.coordinate, course: course))
        let heading = try? #require(nav.cameraPose?.heading)
        #expect(abs((heading ?? 0) - course) < 45)
    }
}
