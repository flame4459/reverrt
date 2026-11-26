import Testing
import Foundation
import CoreLocation
@testable import Revert

/// The overview camera must fit all geometry into the real viewport, at any
/// aspect ratio and padding, without NaN or runaway zoom.
@MainActor
struct MapCameraFitTests {

    private let city = [CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00),
                        CLLocationCoordinate2D(latitude: 40.72, longitude: -73.98)]

    @Test func fitsASmallAreaAndCentresIt() throws {
        let fit = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 402, height: 800)))
        #expect(abs(fit.latitude - 40.71) < 0.0001)
        #expect(abs(fit.longitude - (-73.99)) < 0.0001)
        #expect((4...15).contains(fit.zoom))
    }

    @Test func aLargerViewportZoomsInFurther() throws {
        let small = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 300, height: 600)))
        let large = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 600, height: 1_200)))
        #expect(large.zoom > small.zoom)
    }

    @Test func portraitAndLandscapeBothFit() throws {
        let portrait = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 402, height: 874)))
        let landscape = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 874, height: 402)))
        #expect(portrait.zoom.isFinite && landscape.zoom.isFinite)
        #expect((4...15).contains(portrait.zoom))
        #expect((4...15).contains(landscape.zoom))
    }

    @Test func morePaddingZoomsOut() throws {
        let tight = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 402, height: 800), padding: 8))
        let loose = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 402, height: 800), padding: 120))
        #expect(loose.zoom < tight.zoom)
    }

    @Test func largerBoundsZoomOut() throws {
        let near = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 402, height: 800)))
        let far = try #require(RevertMapFit.fit(
            [CLLocationCoordinate2D(latitude: 30, longitude: -120),
             CLLocationCoordinate2D(latitude: 45, longitude: -70)],
            viewport: CGSize(width: 402, height: 800)))
        #expect(far.zoom < near.zoom)
    }

    @Test func identicalPointsUseTheMaximumZoom() throws {
        let point = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.5)
        let fit = try #require(RevertMapFit.fit([point, point],
                                                viewport: CGSize(width: 402, height: 800)))
        #expect(fit.zoom == RevertMapFit.archiveMaxZoom)
        #expect(fit.latitude == 37.5)
        #expect(fit.longitude == -122.5)
    }

    @Test func invalidCoordinatesAreIgnored() throws {
        let fit = try #require(RevertMapFit.fit(
            [CLLocationCoordinate2D(latitude: .nan, longitude: 0),
             CLLocationCoordinate2D(latitude: 200, longitude: 0),
             city[0], city[1]],
            viewport: CGSize(width: 402, height: 800)))
        #expect(abs(fit.latitude - 40.71) < 0.0001)

        #expect(RevertMapFit.fit([CLLocationCoordinate2D(latitude: .nan, longitude: .nan)],
                                viewport: CGSize(width: 402, height: 800)) == nil)
        #expect(RevertMapFit.fit([], viewport: CGSize(width: 402, height: 800)) == nil)
    }

    @Test func tooSmallViewportReturnsNil() {
        #expect(RevertMapFit.fit(city, viewport: CGSize(width: 20, height: 20), padding: 24) == nil)
    }

    @Test func antimeridianRouteIsFramed() throws {
        let crossing = [CLLocationCoordinate2D(latitude: 0, longitude: 179.5),
                        CLLocationCoordinate2D(latitude: 0, longitude: -179.5)]
        let fit = try #require(RevertMapFit.fit(crossing, viewport: CGSize(width: 402, height: 800)))
        // The centre wraps to the date line, not to 0°.
        #expect(abs(abs(fit.longitude) - 180) < 0.001)
        #expect((4...15).contains(fit.zoom))
    }

    @Test func viewportResizeKeepsTheFitValid() throws {
        let small = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 320, height: 568)))
        let large = try #require(RevertMapFit.fit(city, viewport: CGSize(width: 1024, height: 768)))
        #expect(small.zoom.isFinite && large.zoom.isFinite)
        #expect(large.zoom > small.zoom)
    }
}
