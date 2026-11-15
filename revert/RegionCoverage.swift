import Foundation
import CoreLocation

/// Answers "how much of this disc is already saved on the phone?" so the area
/// cache can accumulate across rides instead of being invalidated the moment
/// the rider moves a kilometre and asks for the same radius from a new centre.
nonisolated enum RegionCoverage {
    struct Circle: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let radiusKm: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// Fraction of the requested disc covered by the union of the saved
    /// circles, sampled on a grid. A point within `marginMeters` of a circle's
    /// edge counts as uncovered: ways that straddle the cut can arrive
    /// truncated, which is worse than fetching the area again.
    static func fraction(of center: CLLocationCoordinate2D,
                         radiusKm: Double,
                         coveredBy circles: [Circle],
                         marginMeters: Double = 300,
                         samplesPerAxis: Int = 21) -> Double {
        guard radiusKm > 0, !circles.isEmpty, samplesPerAxis > 1 else { return 0 }
        let step = (radiusKm * 2) / Double(samplesPerAxis - 1)
        var covered = 0
        var total = 0
        for ix in 0..<samplesPerAxis {
            for iy in 0..<samplesPerAxis {
                let east = -radiusKm + Double(ix) * step
                let north = -radiusKm + Double(iy) * step
                guard (east * east + north * north).squareRoot() <= radiusKm else { continue }
                total += 1
                let point = offset(center, eastKm: east, northKm: north)
                if isCovered(point, by: circles, marginMeters: marginMeters) { covered += 1 }
            }
        }
        return total == 0 ? 0 : Double(covered) / Double(total)
    }

    static func isCovered(_ point: CLLocationCoordinate2D,
                          by circles: [Circle],
                          marginMeters: Double = 0) -> Bool {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        return circles.contains { circle in
            let centre = CLLocation(latitude: circle.latitude, longitude: circle.longitude)
            return location.distance(from: centre) <= circle.radiusKm * 1_000 - marginMeters
        }
    }

    /// True when `outer` fully contains the disc described by `center` + `radiusKm`.
    static func contains(_ outer: Circle,
                         center: CLLocationCoordinate2D,
                         radiusKm: Double) -> Bool {
        guard outer.radiusKm > radiusKm else { return false }
        let outerCentre = CLLocation(latitude: outer.latitude, longitude: outer.longitude)
        let inner = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return inner.distance(from: outerCentre) <= outer.radiusKm * 1_000 - radiusKm * 1_000
    }

    private static func offset(_ origin: CLLocationCoordinate2D,
                               eastKm: Double,
                               northKm: Double) -> CLLocationCoordinate2D {
        let dLat = northKm / 111.0
        let dLon = eastKm / (111.0 * max(cos(origin.latitude * .pi / 180), 0.2))
        return CLLocationCoordinate2D(latitude: origin.latitude + dLat,
                                      longitude: origin.longitude + dLon)
    }
}
