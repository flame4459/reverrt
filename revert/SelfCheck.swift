#if DEBUG
import Foundation
import CoreLocation

/// Cheap debug-only invariants for the route/alert math. These run at launch
/// while developing; `assert` compiles out of Release.
enum SelfCheck {
    static func run() {
        assert(abs(Units.feet(1) - 3.28084) < 0.0001)
        assert(Units.shortDistanceText(100).contains("ft") || Units.shortDistanceText(100).contains("m"))

        let start = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let end = CLLocationCoordinate2D(latitude: 37.0, longitude: -121.999)
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: start.latitude, lon: start.longitude, road: 1),
                RoutePoint(lat: 37.0, lon: -121.9995, road: 1),
                RoutePoint(lat: end.latitude, lon: end.longitude, road: 2),
                RoutePoint(lat: 37.0001, lon: -121.9985, road: 2),
                RoutePoint(lat: 37.0002, lon: -121.9980, road: 3)
            ],
            roads: [:], twistPerKm: 80, retraced: 0, bearing: 90
        )
        assert(route.steps.count >= 2, "expected turns from road-id changes")

        let match = RouteCorridor.project(
            latitude: 37.0, longitude: -121.9995,
            route: route, near: 0, behind: 0, ahead: 200, maxLateral: 25
        )
        assert(match != nil, "hazard on the route should project")
        if let match {
            assert(match.lateral < 2, "route hazard should have near-zero lateral offset")
            assert(match.along > 20 && match.along < 100, "route hazard should be mid-route")
        }
        print("SelfCheck passed")
    }
}
#endif
