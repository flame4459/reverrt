import Testing
import Foundation
import CoreLocation
@testable import Revert

struct RegionPrepTests {
    private let center = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)

    @Test func smallRegionIsOneCell() {
        let cells = RegionPrep.cells(center: center, radiusKm: 16)
        #expect(cells.count == 1)
        #expect(cells[0].radiusKm == 16)
    }

    @Test func bigRegionIsAGridOfRequestSizedCells() {
        let cells = RegionPrep.cells(center: center, radiusKm: 32)
        #expect(cells.count >= 9)
        #expect(cells.allSatisfy { $0.radiusKm <= RegionPrep.maxCellRadiusKm })
        let lats = cells.map(\.center.latitude)
        // The grid must reach the far edge of the requested region (~+/-32 km).
        #expect((lats.max()! - lats.min()!) > 0.4)
        #expect((lats.max()! - lats.min()!) < 0.7)
    }

    @Test func neighbouringCellsOverlap() {
        let cells = RegionPrep.cells(center: center, radiusKm: 32)
        // No cell may be more than two radii from its nearest neighbour, or a
        // hole would open between two downloads.
        for (index, cell) in cells.enumerated() {
            let here = CLLocation(latitude: cell.center.latitude, longitude: cell.center.longitude)
            let nearest = cells.enumerated()
                .filter { $0.offset != index }
                .map { here.distance(from: CLLocation(latitude: $0.element.center.latitude,
                                                     longitude: $0.element.center.longitude)) }
                .min() ?? .infinity
            #expect(nearest <= RegionPrep.maxCellRadiusKm * 2 * 1_000)
        }
    }
}
