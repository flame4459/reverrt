import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct MapExperienceTests {
    private func route() -> PlannedRoute {
        let points = [
            RoutePoint(lat: 37.7000, lon: -122.4000, road: 0),
            RoutePoint(lat: 37.7060, lon: -122.4000, road: 0),
            RoutePoint(lat: 37.7060, lon: -122.3920, road: 0),
            RoutePoint(lat: 37.7120, lon: -122.3920, road: 0)
        ]
        return PlannedRoute(points: points, roads: [:], twistPerKm: 80,
                            retraced: 0, bearing: 0,
                            displayName: "Map test")
    }

    @Test func geometryInterpolatesAlongRoute() {
        let route = route()
        let middle = RouteGeometry.coordinate(at: 500, route: route)
        #expect(middle != nil)
        #expect(middle!.latitude > 37.70 && middle!.latitude < 37.713)
    }

    @Test func matcherSnapsNearAndRejectsFar() {
        let route = route()
        let near = CLLocationCoordinate2D(latitude: 37.7030, longitude: -122.3998)
        let match = RouteMatcher.match(near, route: route)
        #expect(match != nil)
        #expect(match!.lateralMeters < 30)
        let far = CLLocationCoordinate2D(latitude: 37.7500, longitude: -122.3500)
        #expect(RouteMatcher.match(far, route: route) == nil)
    }

    @Test func matcherProgressIsMonotonic() {
        let route = route()
        let first = RouteMatcher.match(CLLocationCoordinate2D(latitude: 37.7010, longitude: -122.4000),
                                       route: route, minimumProgress: 0)
        let backwards = RouteMatcher.match(CLLocationCoordinate2D(latitude: 37.7002, longitude: -122.4000),
                                           route: route, minimumProgress: first?.progress ?? 100)
        #expect(backwards == nil || backwards!.progress >= (first?.progress ?? 0))
    }

    @Test func cameraTargetsLookAheadAndClampsPitch() {
        let route = route()
        var engine = RideCameraEngine()
        let first = engine.update(route: route, rawProgress: 0, speed: 20,
                                  maneuverMeters: 900, fallbackHeading: 0, timestamp: 1)
        let second = engine.update(route: route, rawProgress: 0, speed: 20,
                                   maneuverMeters: 900, fallbackHeading: 0, timestamp: 1.1)
        #expect(first != nil)
        #expect(second != nil)
        #expect(second!.pitch >= 28 && second!.pitch <= 48)
        #expect(second!.distance >= 320 && second!.distance <= 820)
        #expect(second!.latitude != first!.latitude || second!.longitude != first!.longitude)
    }

    @Test func ribbonSplitsAndSimplifies() {
        let route = route()
        let ribbon = RouteRibbon(route: route, progress: route.length * 0.5, tolerance: 1)
        #expect(!ribbon.travelled.isEmpty)
        #expect(!ribbon.remaining.isEmpty)
        #expect(ribbon.travelled.first?.latitude == route.points.first?.lat)
        #expect(ribbon.remaining.last?.latitude == route.points.last?.lat)
    }

    @Test func ribbonPaceSegmentsCoverRemainingRoute() {
        let route = route()
        let ribbon = RouteRibbon(route: route, progress: route.length * 0.3)
        #expect(!ribbon.remainingSegments.isEmpty)
        #expect(ribbon.remainingSegments.allSatisfy { !$0.coordinates.isEmpty })
        #expect(ribbon.remainingSegments.allSatisfy { $0.merit >= 0 && $0.merit <= 1 })
    }

    @Test func simplifyDropsCollinearPoint() {
        let points = [
            CLLocationCoordinate2D(latitude: 37.70, longitude: -122.40),
            CLLocationCoordinate2D(latitude: 37.71, longitude: -122.40),
            CLLocationCoordinate2D(latitude: 37.72, longitude: -122.40)
        ]
        let simplified = RouteRibbon.simplify(points, tolerance: 5)
        #expect(simplified.count == 2)
    }
}
