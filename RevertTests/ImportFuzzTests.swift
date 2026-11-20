import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct ImportFuzzTests {
    // MARK: GPX (198)

    @Test func garbageAndTruncatedFilesAreRejected() {
        #expect(GPX.parseTrack(from: Data()) == nil)
        #expect(GPX.parseTrack(from: Data([0x00, 0x01, 0x02])) == nil)
        #expect(GPX.parseTrack(from: Data("<gpx><trk><trkseg>".utf8)) == nil)
        #expect(GPX.parseTrack(from: Data("not xml at all".utf8)) == nil)
    }

    @Test func coordinateBombsAreDropped() {
        let xml = """
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
        <trkpt lat="200.0" lon="999.0"></trkpt>
        <trkpt lat="-91.0" lon="0.0"></trkpt>
        <trkpt lat="40.7" lon="-73.5"></trkpt>
        <trkpt lat="40.7001" lon="-73.5001"></trkpt>
        </trkseg></trk></gpx>
        """
        let track = GPX.parseTrack(from: Data(xml.utf8))
        #expect(track?.points.count == 2)
        #expect(track?.points.allSatisfy { abs($0.lat) <= 90 && abs($0.lon) <= 180 } == true)
    }

    // MARK: Route links (199)

    @Test func linkDecoderRejectsHostilePayloads() {
        #expect(RouteLink.payload(from: URL(string: "https://evil.example/route?d=abc")!) == nil)
        #expect(RouteLink.payload(from: URL(string: "revert://route?d=%%%not-base64%%%")!) == nil)
        #expect(RouteLink.payload(from: URL(string: "revert://route")!) == nil)
        #expect(RouteLink.payload(from: URL(string: "revert://other?d=abc")!) == nil)
    }

    @Test func aValidLinkRoundTrips() throws {
        let points = (0..<40).map { index in
            RoutePoint(lat: 40.7 + Double(index) * 0.0002, lon: -73.5, road: 0)
        }
        let route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0, displayName: "Link test")
        let url = try #require(RouteLink.url(for: route))
        let payload = try #require(RouteLink.payload(from: url))
        let decoded = try #require(RouteLink.route(from: payload))
        #expect(decoded.points.count == route.points.count)
        #expect(abs(decoded.length - route.length) < 1)
        #expect(decoded.displayName == "Link test")
    }
}

@MainActor
struct GPXExportShapeTests {
    @Test func coordinatesAreQuantisedToSixDecimals() {
        let point = RidePoint(lat: 40.123456789, lon: -73.987654321, alt: 12, speed: 10,
                              time: Date(timeIntervalSince1970: 1_700_000_000))
        let xml = GPX.export(points: [point], startDate: point.time)
        #expect(xml.contains("lat=\"40.123457\""))
        #expect(xml.contains("lon=\"-73.987654\""))
        #expect(!xml.contains("40.123456789"))
    }
}

@MainActor
struct CompanionStateTests {
    @Test func offSwitchPersists() {
        let director = CompanionDirector.shared
        let previous = director.state
        defer {
            director.setState(previous)
        }
        director.setState(.off)
        #expect(UserDefaults.standard.string(forKey: "companion.state") == CompanionState.off.rawValue)
        director.setState(.askedOnly)
        #expect(UserDefaults.standard.string(forKey: "companion.state") == CompanionState.askedOnly.rawValue)
    }
}
