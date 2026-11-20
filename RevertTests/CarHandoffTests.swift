import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct CarHandoffTests {
    private func route() -> CarHandoffRoute {
        let points = (0..<120).map { index in
            RoutePoint(lat: 40.0 + Double(index) * 0.0004, lon: -73.0, road: 0)
        }
        let planned = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                   retraced: 0, bearing: 0, displayName: "Test loop")
        return CarHandoffRoute(route: planned)
    }

    @Test func carAppExportIsTrackOnly() {
        let handoff = route()
        let resampled = CarHandoffExporter.resampled(handoff.points)
        let xml = CarHandoffExporter.makeXML(route: handoff, points: resampled, includeRoute: false)
        #expect(xml.contains("<trk>"))
        #expect(xml.contains("<trkpt"))
        #expect(!xml.contains("<rte>"), "the car app must follow the line, not re-route it")
        #expect(xml.contains("Test loop"))
    }

    @Test func plannerExportHasRouteAndTrack() {
        let handoff = route()
        let resampled = CarHandoffExporter.resampled(handoff.points)
        let xml = CarHandoffExporter.makeXML(route: handoff, points: resampled, includeRoute: true)
        #expect(xml.contains("<rte>"))
        #expect(xml.contains("<rtept"))
        #expect(xml.contains("<trk>"))
    }

    @Test func resamplingKeepsEveryOriginalPointAndBoundsTheCount() {
        let handoff = route()
        let resampled = CarHandoffExporter.resampled(handoff.points)
        #expect(resampled.count >= handoff.points.count)
        #expect(resampled.count <= CarHandoffExporter.maximumPoints)
        #expect(resampled.first?.lat == handoff.points.first?.lat)
        #expect(resampled.last?.lon == handoff.points.last?.lon)
    }

    @Test func sharedFileIsDeclaredAsGPXNotADynamicType() {
        // A dynamic UTI is why the file used to reach the sheet with no GPX
        // handler able to claim it.
        #expect(!CarHandoffShareSheet.typeIdentifier.hasPrefix("dyn."))
        #expect(CarHandoffShareSheet.typeIdentifier == "com.topografix.gpx"
                || CarHandoffShareSheet.typeIdentifier.contains("gpx"))
    }
}

@MainActor
struct CarHandoffXMLTests {
    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var trkpts = 0
        var rte = false
        var times: [String] = []
        var inTime = false
        var buffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if elementName == "trkpt" { trkpts += 1 }
            if elementName == "rte" { rte = true }
            if elementName == "time" { inTime = true; buffer = "" }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inTime { buffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?) {
            if elementName == "time" { inTime = false; times.append(buffer) }
        }
    }

    @Test func trackOnlyExportIsWellFormedGPX() {
        let points = (0..<80).map { index in
            RoutePoint(lat: 40 + Double(index) * 0.0005, lon: -73, road: 0)
        }
        let planned = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                   retraced: 0, bearing: 0, displayName: "Parser loop")
        let route = CarHandoffRoute(route: planned)
        let xml = CarHandoffExporter.makeXML(route: route,
                                             points: CarHandoffExporter.resampled(route.points),
                                             includeRoute: false)
        let delegate = ParserDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        #expect(parser.parse())
        #expect(delegate.trkpts > 0)
        #expect(!delegate.rte)
        #expect(delegate.times.count == delegate.trkpts + 1) // metadata + one per point
        #expect(delegate.times == delegate.times.sorted())
    }

    @Test func carAppLauncherUsesOrganicMaps() {
        #expect(CarAppLauncher.candidateSchemes.contains("om"))
        #expect(CarAppLauncher.appStoreURL.absoluteString.contains("id1567437057"))
    }
}
