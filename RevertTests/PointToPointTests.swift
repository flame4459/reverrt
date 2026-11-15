import Testing
import Foundation
import CoreLocation
@testable import Revert

struct PointToPointTests {
    private func road(id: Int64, highway: String, _ points: [(Double, Double)]) -> Road {
        let coords = points.flatMap { [$0.0, $0.1] }
        let lats = points.map(\.0)
        let lons = points.map(\.1)
        return Road(id: id, highway: highway, name: "Test \(id)",
                    maxspeed: nil, maxspeedForward: nil, maxspeedBackward: nil,
                    surface: nil, oneway: nil, ref: nil, coords: coords,
                    minLat: lats.min()!, maxLat: lats.max()!,
                    minLon: lons.min()!, maxLon: lons.max()!)
    }

    @Test func directFindsAPathAcrossAnL() throws {
        // East along 40.0, then north along -73.99.
        let horizontal = road(id: 1, highway: "residential", [(40.0, -74.0), (40.0, -73.99)])
        let vertical = road(id: 2, highway: "tertiary", [(40.0, -73.99), (40.01, -73.99)])
        let start = CLLocationCoordinate2D(latitude: 40.0002, longitude: -73.9998)
        let end = CLLocationCoordinate2D(latitude: 40.0098, longitude: -73.9902)

        let route = try #require(RouteBuilder.direct(roads: [horizontal, vertical], from: start, to: end))
        #expect(route.kind == .directions)
        #expect(route.points.count > 2)
        #expect(route.length > 1_000)
        #expect((route.expectedTravelTime ?? 0) > 0)
    }

    @Test func directGivesUpWhenNothingIsNear() {
        let horizontal = road(id: 1, highway: "residential", [(40.0, -74.0), (40.0, -73.99)])
        let route = RouteBuilder.direct(roads: [horizontal],
                                        from: CLLocationCoordinate2D(latitude: 41.0, longitude: -73.0),
                                        to: CLLocationCoordinate2D(latitude: 41.1, longitude: -73.1))
        #expect(route == nil)
    }

    @Test func longCorridorIsSplitIntoSlices() {
        let start = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        let end = CLLocationCoordinate2D(latitude: 41.0, longitude: -74.0)   // ~111 km
        let slices = RoadStore.corridorSegments(from: start, to: end)
        #expect(slices.count >= 3)
        #expect(slices.allSatisfy { $0.radiusKm <= 22.0001 })
        #expect(zip(slices, slices.dropFirst()).allSatisfy { $0.center.latitude < $1.center.latitude })
    }

    @Test func shortCorridorIsOneSlice() {
        let start = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        let end = CLLocationCoordinate2D(latitude: 40.01, longitude: -74.0)  // ~1.1 km
        #expect(RoadStore.corridorSegments(from: start, to: end).count == 1)
    }

    @Test func corridorContainsBothEnds() {
        let start = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        let end = CLLocationCoordinate2D(latitude: 40.05, longitude: -73.95)
        let shape = RoadStore.corridor(from: start, to: end)
        let center = CLLocation(latitude: shape.center.latitude, longitude: shape.center.longitude)
        #expect(center.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) <= shape.radiusKm * 1_000)
        #expect(center.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) <= shape.radiusKm * 1_000)
    }
}
