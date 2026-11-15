import Testing
import Foundation
import CoreLocation
@testable import Revert

struct RegionCoverageTests {
    private let center = CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0)

    private func circle(_ latOffsetKm: Double, _ lonOffsetKm: Double, _ radiusKm: Double) -> RegionCoverage.Circle {
        let lat = center.latitude + latOffsetKm / 111.0
        let lon = center.longitude + lonOffsetKm / (111.0 * cos(center.latitude * .pi / 180))
        return RegionCoverage.Circle(latitude: lat, longitude: lon, radiusKm: radiusKm)
    }

    @Test func anAreaCoversItselfCompletely() {
        let fraction = RegionCoverage.fraction(of: center, radiusKm: 10, coveredBy: [circle(0, 0, 12)])
        #expect(fraction > 0.99)
    }

    @Test func disconnectedCoverageIsNotEnough() {
        let fraction = RegionCoverage.fraction(of: center, radiusKm: 10, coveredBy: [circle(0, 0, 5)])
        #expect(fraction < 0.3)
    }

    @Test func overlappingAreasAddUp() {
        // Two 12 km areas, 10 km apart, together hold the 10 km disc between
        // them. Either one alone would have been a cache miss.
        let fraction = RegionCoverage.fraction(of: center, radiusKm: 10,
                                               coveredBy: [circle(0, -5, 12), circle(0, 5, 12)])
        #expect(fraction > 0.95)
    }

    @Test func marginDisqualifiesTheEdge() {
        // A cached disc exactly the size of the request loses its edge to the
        // 300 m margin, which is what keeps truncated ways out of the graph.
        let fraction = RegionCoverage.fraction(of: center, radiusKm: 10, coveredBy: [circle(0, 0, 10)])
        #expect(fraction < 0.99)
        #expect(fraction > 0.8)
    }

    @Test func noAreasMeansNoCoverage() {
        #expect(RegionCoverage.fraction(of: center, radiusKm: 10, coveredBy: []) == 0)
    }

    @Test func containsRequiresTheWholeRequestInside() {
        #expect(RegionCoverage.contains(circle(0, 0, 12), center: center, radiusKm: 10))
        #expect(!RegionCoverage.contains(circle(0, 3, 12), center: center, radiusKm: 10))
        #expect(!RegionCoverage.contains(circle(0, 0, 9), center: center, radiusKm: 10))
    }
}

@MainActor
struct RegionCacheNamingTests {
    @Test func savedAreaNamesRoundTrip() throws {
        let center = CLLocationCoordinate2D(latitude: 40.7241, longitude: -73.6877)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = RoadStore.bulkFileName(center: center, radiusKm: 22, surface: .adventure, at: date)

        let area = try #require(RoadStore.parse(URL(fileURLWithPath: "/tmp/\(name)")))
        #expect(area.radiusKm == 22)
        #expect(area.surface == .adventure)
        #expect(abs(area.center.latitude - center.latitude) < 0.0001)
        #expect(abs(area.center.longitude - center.longitude) < 0.0001)
        #expect(abs(area.fetched.timeIntervalSince1970 - date.timeIntervalSince1970) < 1)
    }

    @Test func legacyFileNamesAreNotMistakenForNewOnes() {
        let legacy = URL(fileURLWithPath: "/tmp/roads_bulk_12_-34.json")
        #expect(RoadStore.parse(legacy) == nil)
    }
}

@MainActor
struct HazardAreaNamingTests {
    @Test func hazardAreaNamesRoundTrip() throws {
        let center = CLLocationCoordinate2D(latitude: 40.7241, longitude: -73.6877)
        let name = HazardAreas.fileName(center: center, radiusKm: 16, at: Date())
        let area = try #require(HazardAreas.parse(URL(fileURLWithPath: "/tmp/\(name)")))
        #expect(area.radiusKm == 16)
        #expect(abs(area.center.latitude - center.latitude) < 0.0001)
        #expect(abs(area.center.longitude - center.longitude) < 0.0001)
    }

    @Test func tileFilesAreNotMistakenForAreas() {
        #expect(HazardAreas.parse(URL(fileURLWithPath: "/tmp/hazards_12_-34.json")) == nil)
    }
}
