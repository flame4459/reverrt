import Testing
import Foundation
@testable import Revert

@MainActor
struct HazardDirectionTests {
    private func camera(_ direction: Int?) -> Hazard {
        Hazard(id: 1, kind: .speedCamera, lat: 40.7, lon: -73.5, direction: direction)
    }

    @Test func aCameraFacingTheSameWayAsTheRiderIsKept() {
        #expect(!camera(90).facesAway(from: 80))
        #expect(!camera(90).facesAway(from: 120))
    }

    @Test func theOppositeCarriagewayIsIgnored() {
        #expect(camera(270).facesAway(from: 90))
        #expect(camera(0).facesAway(from: 180))
    }

    @Test func unknownDirectionOrBearingNeverSuppressesAnAlert() {
        #expect(!camera(nil).facesAway(from: 90))
        #expect(!camera(90).facesAway(from: nil))
    }

    @Test func oldCachedHazardsDecodeWithoutADirection() throws {
        let legacy = Data(#"{"id":5,"kind":"speedCamera","lat":40.7,"lon":-73.5}"#.utf8)
        let hazard = try JSONDecoder().decode(Hazard.self, from: legacy)
        #expect(hazard.direction == nil)
        #expect(!hazard.facesAway(from: 180))
    }
}
