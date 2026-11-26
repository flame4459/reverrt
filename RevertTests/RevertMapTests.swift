import Testing
import Foundation
import CoreLocation
@testable import Revert

/// The unified map's camera math and scene contract. Rendering itself is
/// verified on the simulator; these protect the parts that can regress silently.
@MainActor
struct RevertMapTests {

    @Test func overviewCameraIsCentredAndFitsTheRoute() {
        let near = [CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
                    CLLocationCoordinate2D(latitude: 40.1, longitude: -73.9)]
        let position = RevertMapFit.fit(near, viewport: CGSize(width: 402, height: 800))!
        #expect(abs(position.latitude - 40.05) < 0.0005)
        #expect(abs(position.longitude - (-73.95)) < 0.0005)
        #expect((5...17).contains(position.zoom))

        let far = [CLLocationCoordinate2D(latitude: 30, longitude: -120),
                   CLLocationCoordinate2D(latitude: 45, longitude: -70)]
        #expect(RevertMapFit.fit(far, viewport: CGSize(width: 402, height: 800))!.zoom < position.zoom,
                "a larger route must zoom out")
    }

    @Test func overviewCameraHandlesASinglePoint() {
        let position = RevertMapFit.fit([CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)],
                                        viewport: CGSize(width: 402, height: 800))!
        #expect(position.latitude == 51.5)
        #expect(position.longitude == -0.1)
    }

    @Test func cockpitSceneKeepsItsOverlays() {
        let scene = RevertMapScene.cockpit(
            route: nil,
            progress: 0.4,
            puck: CLLocationCoordinate2D(latitude: 40, longitude: -74),
            approach: [CLLocationCoordinate2D(latitude: 40, longitude: -74)],
            track: [],
            ghost: nil,
            hazards: [CLLocationCoordinate2D(latitude: 40.01, longitude: -74.01)]
        )
        #expect(scene.camera == .follow)
        #expect(scene.showsRouteProgress)
        #expect(scene.approach.count == 1)
        #expect(scene.hazards.count == 1)
    }

    @Test func previewSceneDrawsOneLineAndFitsTheRoute() {
        let route = PlannedRoute(
            points: [RoutePoint(lat: 40, lon: -74, road: 0),
                     RoutePoint(lat: 40.01, lon: -74.01, road: 0)],
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 0, kind: .directions)
        let scene = RevertMapScene.overview(route)
        #expect(scene.camera == .overview)
        #expect(!scene.showsRouteProgress)
        #expect(scene.route?.points.count == 2)
    }
}
