import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct CameraEngineTests {
    /// 300 m north, then 300 m east: a single 90° corner.
    private func cornerRoute() -> PlannedRoute {
        var points: [RoutePoint] = []
        for index in 0...30 {
            points.append(RoutePoint(lat: 40.0 + Double(index) * 0.0001, lon: -73.0, road: 0))
        }
        let top = points.last!
        for index in 1...30 {
            points.append(RoutePoint(lat: top.lat, lon: -73.0 + Double(index) * 0.00013, road: 0))
        }
        return PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                            retraced: 0, bearing: 0, kind: .directions)
    }

    private func straightRoute() -> PlannedRoute {
        let points = (0...60).map { index in
            RoutePoint(lat: 40.0 + Double(index) * 0.0001, lon: -73.0, road: 0)
        }
        return PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                            retraced: 0, bearing: 0, kind: .directions)
    }

    @Test func curvatureFindsTheBendAndIgnoresTheStraight() {
        let straight = RideCameraEngine.curvatureDegreesPerMetre(route: straightRoute(), progress: 100)
        #expect(straight < 0.05)
        // The corner sits ~333 m in; sample across it.
        let bend = RideCameraEngine.curvatureDegreesPerMetre(route: cornerRoute(), progress: 300)
        #expect(bend > 0.5, "expected a corner, got \(bend)")
    }

    @Test func headingSlewDoesNotDependOnFrameRate() {
        let route = cornerRoute()
        var sixty = RideCameraEngine()
        var oneTwenty = RideCameraEngine()
        let start: TimeInterval = 100
        _ = sixty.update(route: route, rawProgress: 250, speed: 10, maneuverMeters: 0,
                         fallbackHeading: 0, timestamp: start)
        _ = oneTwenty.update(route: route, rawProgress: 250, speed: 0, maneuverMeters: 0,
                             fallbackHeading: 0, timestamp: start)

        for step in 1...60 {
            _ = sixty.update(route: route, rawProgress: 250, speed: 0, maneuverMeters: 0,
                             fallbackHeading: 0, timestamp: start + Double(step) / 60)
        }
        for step in 1...120 {
            _ = oneTwenty.update(route: route, rawProgress: 250, speed: 0, maneuverMeters: 0,
                                 fallbackHeading: 0, timestamp: start + Double(step) / 120)
        }
        let a = try? #require(sixty.frame?.heading)
        let b = try? #require(oneTwenty.frame?.heading)
        #expect(abs((a ?? 0) - (b ?? 0)) < 3, "60 Hz \(a ?? 0) vs 120 Hz \(b ?? 0)")
    }

    @Test func springSettlesOnTheTarget() {
        let route = straightRoute()
        var engine = RideCameraEngine()
        for step in 0...300 {
            _ = engine.update(route: route, rawProgress: 0, speed: 0, maneuverMeters: 0,
                              fallbackHeading: 0, timestamp: 100 + Double(step) / 60)
        }
        guard let target = RouteGeometry.coordinate(at: 0, route: route) else {
            Issue.record("route has no start coordinate")
            return
        }
        #expect(abs((engine.frame?.latitude ?? 0) - target.latitude) < 0.0002)
        #expect(abs((engine.frame?.longitude ?? 0) - target.longitude) < 0.0002)
    }
}
