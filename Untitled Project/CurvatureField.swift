import Foundation
import CoreLocation

/// Radius-based curvature measured along a polyline.
///
/// This is the single definition used by loop scoring, route labels and the
/// live curve engine's advisory speed. Everything here is *measured* geometry,
/// so a "twisty" label can no longer be produced by a score that rewarded
/// straights.
///
/// The old graph implementation averaged heading change over a whole
/// junction-to-junction segment. On a 6 km road with 2 km of bends that
/// diluted the good part into invisibility, and the router could only take or
/// leave the entire road. Measuring short chunks fixes that.
nonisolated enum Curvature {
    struct Stats: Sendable, Equatable {
        var lengthMeters: Double = 0
        /// Total absolute heading change per kilometre.
        var degreesPerKm: Double = 0
        /// Fraction of the length spent with a corner radius under 150 m.
        var cornerShare: Double = 0
        /// Fraction under 70 m (hairpins and sharp turns).
        var tightShare: Double = 0
        /// Fraction between 70 m and 250 m (flowing sweepers).
        var sweeperShare: Double = 0
        var cornersPerKm: Double = 0
        var minRadiusMeters: Double = .infinity
        /// 0...100 riding value. A straight road is 0 by construction.
        var value: Double = 0
        /// Comfortable speed through the tightest part, metres per second.
        var comfortableMps: Double = 30

        static let empty = Stats()
    }

    // MARK: Thresholds
    static let cornerRadiusMeters = 150.0
    static let tightRadiusMeters = 70.0
    static let sweeperRadiusMeters = 250.0
    /// Geometry is sampled every 5 m and the radius is fitted through points
    /// 15 m either side, which is stable on OSM vertices without smoothing away
    /// short hairpins.
    static let sampleSpacingMeters = 5.0
    static let chordMeters = 15.0
    /// Comfortable lateral acceleration used for advisory speeds.
    static let lateralAcceleration = 3.5
    static let maximumComfortableMps = 30.0
    static let minimumComfortableMps = 7.0

    static func measure(_ coordinates: [CLLocationCoordinate2D]) -> Stats {
        guard coordinates.count > 2 else { return .empty }
        let sampled = resample(coordinates, every: sampleSpacingMeters)
        guard sampled.count > 2 * chordSteps + 2 else { return .empty }

        var totalLength = 0.0
        for index in 1..<sampled.count {
            totalLength += distance(sampled[index - 1], sampled[index])
        }
        guard totalLength > 1 else { return .empty }

        let step = sampleSpacingMeters
        let half = chordSteps
        var radii = [Double](repeating: .infinity, count: sampled.count)
        for index in half..<(sampled.count - half) {
            radii[index] = circumradius(
                sampled[index - half],
                sampled[index],
                sampled[index + half]
            )
        }

        var cornerLength = 0.0
        var tightSamples = 0
        var sweeperSamples = 0
        var runs: [(length: Double, minRadius: Double)] = []
        var runStart: Int?
        var runMin = Double.infinity

        for index in half..<(sampled.count - half) {
            let radius = radii[index]
            // Tightness and sweeper flow are categories of their own; a
            // 200 m sweeper is not a corner but it certainly is flow.
            if radius < tightRadiusMeters { tightSamples += 1 }
            if radius >= tightRadiusMeters && radius < sweeperRadiusMeters {
                sweeperSamples += 1
            }
            if radius < cornerRadiusMeters {
                if runStart == nil {
                    runStart = index
                    runMin = radius
                } else {
                    runMin = min(runMin, radius)
                }
            } else if let start = runStart {
                let length = Double(index - start) * step
                // A single noisy sample is not a corner.
                if length >= 3 * step {
                    runs.append((length, runMin))
                    cornerLength += length
                }
                runStart = nil
                runMin = .infinity
            }
        }
        if let start = runStart {
            let length = Double((sampled.count - half) - start) * step
            if length >= 3 * step {
                runs.append((length, runMin))
                cornerLength += length
            }
        }

        let measuredSamples = max(sampled.count - 2 * half, 1)
        let kilometers = totalLength / 1_000
        let cornersPerKm = Double(runs.count) / max(kilometers, 0.05)
        let cornerShare = min(cornerLength / totalLength, 1)
        let tightShare = min(Double(tightSamples) / Double(measuredSamples), 1)
        let sweeperShare = min(Double(sweeperSamples) / Double(measuredSamples), 1)
        let minRadius = runs.map(\.minRadius).min() ?? .infinity

        // Density alone saturates on switchback roads; share alone punishes a
        // single great corner surrounded by a connector. All four terms are
        // required so a straight road cannot score anything at all.
        let densityScore = min(cornersPerKm / 6, 1)
        let shareScore = min(cornerShare / 0.55, 1)
        let tightScore: Double = minRadius.isFinite
            ? clamp((sweeperRadiusMeters - minRadius) / 210, 0, 1)
            : 0
        let sweeperScore = min(sweeperShare / 0.45, 1)
        let value = 100 * (0.30 * densityScore
            + 0.38 * shareScore
            + 0.20 * tightScore
            + 0.12 * sweeperScore)

        return Stats(
            lengthMeters: totalLength,
            degreesPerKm: degreesPerKilometer(sampled, totalLength: totalLength),
            cornerShare: cornerShare,
            tightShare: tightShare,
            sweeperShare: sweeperShare,
            cornersPerKm: cornersPerKm,
            minRadiusMeters: minRadius,
            value: clamp(value, 0, 100),
            comfortableMps: comfortableSpeed(minRadius: minRadius)
        )
    }

    /// Convenience for routes that already carry `RoutePoint`s.
    static func measure(points: [RoutePoint]) -> Stats {
        measure(points.map(\.coordinate))
    }

    static func comfortableSpeed(minRadius: Double) -> Double {
        guard minRadius.isFinite, minRadius > 0 else { return maximumComfortableMps }
        let safe = (lateralAcceleration * max(minRadius, 4)).squareRoot()
        return clamp(safe, minimumComfortableMps, maximumComfortableMps)
    }

    // MARK: Internals
    private static var chordSteps: Int {
        max(1, Int((chordMeters / sampleSpacingMeters).rounded()))
    }

    private static func degreesPerKilometer(
        _ sampled: [CLLocationCoordinate2D],
        totalLength: Double
    ) -> Double {
        guard totalLength > 10 else { return 0 }
        // Heading over 30 m chords keeps GPS/OSM vertex noise from inflating
        // the number, while still capturing a hairpin as one large change.
        let step = max(1, Int((30 / sampleSpacingMeters).rounded()))
        guard sampled.count > step + 1 else { return 0 }
        var previous = bearing(sampled[0], sampled[step])
        var total = 0.0
        var index = step
        while index + step < sampled.count {
            let next = bearing(sampled[index], sampled[index + step])
            // A single 30 m chord cannot turn more than ~60 degrees on a real
            // road; anything above that is a vertex artefact.
            total += min(abs(normalized(next - previous)), 60)
            previous = next
            index += step
        }
        return total / max(totalLength / 1_000, 0.05)
    }

    /// Circumradius of the circle through three points. `infinity` when the
    /// points are effectively collinear.
    private static func circumradius(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        _ c: CLLocationCoordinate2D
    ) -> Double {
        let ab = distance(a, b)
        let bc = distance(b, c)
        let ca = distance(c, a)
        guard ab > 0.01, bc > 0.01, ca > 0.01 else { return .infinity }
        // Project into metres around `a` before taking the cross product.
        // Using 110.54 km for *both* axes overestimated the area by ~24% at
        // mid latitudes and made every corner look tighter than it was.
        let metersPerDegreeLatitude = 110_540.0
        let metersPerDegreeLongitude = 111_320.0 * cos(a.latitude * .pi / 180)
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * metersPerDegreeLongitude
        let by = (b.latitude - a.latitude) * metersPerDegreeLatitude
        let cx = (c.longitude - a.longitude) * metersPerDegreeLongitude
        let cy = (c.latitude - a.latitude) * metersPerDegreeLatitude
        let cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        let area2 = abs(cross)
        guard area2 > 1e-6 else { return .infinity }
        let radius = (ab * bc * ca) / (2 * area2)
        return min(radius, 1_000_000)
    }

    private static func resample(
        _ coordinates: [CLLocationCoordinate2D],
        every step: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var output = [coordinates[0]]
        var travelled = 0.0
        var nextAt = step
        var previous = coordinates[0]
        for current in coordinates.dropFirst() {
            let segment = distance(previous, current)
            if segment <= 0.001 { continue }
            while travelled + segment >= nextAt {
                let fraction = (nextAt - travelled) / segment
                output.append(interpolate(previous, current, fraction: fraction))
                nextAt += step
            }
            travelled += segment
            previous = current
        }
        if let last = output.last, distance(last, coordinates.last!) > step * 0.5 {
            output.append(coordinates.last!)
        }
        return output
    }

    private static func distance(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        RoadGraph.flat(a.latitude, a.longitude, b.latitude, b.longitude).dist
    }

    private static func interpolate(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    private static func bearing(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        RoadGraph.flat(a.latitude, a.longitude, b.latitude, b.longitude).heading
    }

    private static func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
