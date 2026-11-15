import Foundation
import CoreLocation

/// Prep for a trip: fill the region cache in cells small enough for a single
/// Overpass request each, so a weekend area is one deliberate download instead
/// of fifty incidental ones.
nonisolated enum RegionPrep {
    struct Cell: Sendable {
        let center: CLLocationCoordinate2D
        let radiusKm: Double
    }

    /// One request tops out at 22 km; 20 leaves headroom.
    static let maxCellRadiusKm = 20.0
    /// Centres closer than two cell diameters overlap, so no hole opens
    /// between neighbouring downloads.
    static let stepKm = 32.0

    static func cells(center: CLLocationCoordinate2D, radiusKm: Double) -> [Cell] {
        guard radiusKm > maxCellRadiusKm else {
            return [Cell(center: center, radiusKm: max(radiusKm, 3))]
        }
        let count = max(1, Int(ceil(radiusKm * 2 / stepKm)))
        let step = radiusKm * 2 / Double(count)
        let lonScale = 111.0 * max(cos(center.latitude * .pi / 180), 0.2)
        var cells: [Cell] = []
        for ix in 0...count {
            for iy in 0...count {
                let east = -radiusKm + Double(ix) * step
                let north = -radiusKm + Double(iy) * step
                cells.append(Cell(
                    center: CLLocationCoordinate2D(latitude: center.latitude + north / 111.0,
                                                   longitude: center.longitude + east / lonScale),
                    radiusKm: maxCellRadiusKm
                ))
            }
        }
        return cells
    }
}
