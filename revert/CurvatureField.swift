import Foundation
import CoreLocation

/// Radius-based curvature measured along a polyline.
///
/// This is the single definition used by loop scoring, route labels and the
/// live curve engine's advisory speed. Everything here is *measured* geometry,
/// so a "twisty" label can no longer be produced by a score that rewarded
/// straights.
///
/// Two things matter for how the number behaves:
///
/// * `fun(radius:)` is a smooth function of log radius. The old score counted
///   only corners under 150 m, so a 151 m corner was worth nothing and a 149 m
///   corner was worth a lot. On Long Island, where most of the good roads are
///   200–400 m sweepers, that produced 0–12 for roads a rider would call
///   twisty.
/// * Radii are computed once per OSM way and then sliced per chunk (see
///   `sampled`/`stats`). Measuring each 220 m chunk in isolation discarded the
///   first and last 15 m of every chunk and split any sweeper that crossed a
///   boundary.
nonisolated enum Curvature {
    nonisolated struct Stats: Sendable, Equatable {
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
        /// 0...100 continuous curvature: the mean of `fun(radius:)` over the
        /// sampled length. Unlike `value` this has no category thresholds, so
        /// it is what the router and the relative scoring use.
        var raw: Double = 0
        /// Length of road whose radius scores at least half of `fun`'s range
        /// (roughly 170 m or tighter). "Twisty kilometres" for a whole route.
        var twistyLengthMeters: Double = 0
        /// Comfortable speed through the tightest part, metres per second.
        var comfortableMps: Double = 30

        var twistyShare: Double {
            lengthMeters > 0 ? min(twistyLengthMeters / lengthMeters, 1) : 0
        }

        static let empty = Stats()
    }

    /// A whole OSM way resampled at `sampleSpacingMeters`, with a fitted radius
    /// at every sample and the distance from the start of the way.
    nonisolated struct Sampled {
        var points: [CLLocationCoordinate2D]
        var arc: [Double]
        var radii: [Double]

        var length: Double { arc.last ?? 0 }
    }

    // MARK: Thresholds
    static let cornerRadiusMeters = 150.0
    static let tightRadiusMeters = 70.0
    static let sweeperRadiusMeters = 250.0
    /// `fun` is 0 at this radius and 1 at `funFullRadiusMeters`.
    static let funZeroRadiusMeters = 450.0
    static let funFullRadiusMeters = 25.0
    /// Geometry is sampled every 5 m and the radius is fitted through points
    /// 15 m either side, which is stable on OSM vertices without smoothing away
    /// short hairpins.
    static let sampleSpacingMeters = 5.0
    static let chordMeters = 15.0
    /// Comfortable lateral acceleration used for advisory speeds.
    static let lateralAcceleration = 3.5
    static let maximumComfortableMps = 30.0
    static let minimumComfortableMps = 7.0

    /// Smooth riding merit of a corner radius: 1 at 25 m, 0 at 450 m.
    ///
    /// Log spacing matches how riders experience the difference: 100 → 150 m is
    /// a real change, 400 → 450 m is not.
    static func fun(radius: Double) -> Double {
        guard radius.isFinite, radius > 0 else { return 0 }
        let denominator = log(funZeroRadiusMeters) - log(funFullRadiusMeters)
        let t = (log(funZeroRadiusMeters) - log(max(radius, funFullRadiusMeters))) / denominator
        return min(max(t, 0), 1)
    }

    // MARK: Measurement

    static func measure(_ coordinates: [CLLocationCoordinate2D]) -> Stats {
        guard let sampled = sampled(coordinates) else { return .empty }
        return stats(sampled, from: 0, to: sampled.length)
    }

    /// Convenience for routes that already carry `RoutePoint`s.
    static func measure(points: [RoutePoint]) -> Stats {
        measure(points.map(\.coordinate))
    }

    /// Resamples a whole way and fits a radius at every interior sample.
    static func sampled(_ coordinates: [CLLocationCoordinate2D]) -> Sampled? {
        guard coordinates.count > 2 else { return nil }
        let points = resample(coordinates, every: sampleSpacingMeters)
        guard points.count > 2 * chordSteps + 2 else { return nil }

        var arc = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            arc[index] = arc[index - 1] + distance(points[index - 1], points[index])
        }
        guard let total = arc.last, total > 1 else { return nil }

        var radii = [Double](repeating: .infinity, count: points.count)
        for index in chordSteps..<(points.count - chordSteps) {
            radii[index] = circumradius(
                points[index - chordSteps],
                points[index],
                points[index + chordSteps]
            )
        }
        return Sampled(points: points, arc: arc, radii: radii)
    }

    /// Stats for the slice of a sampled way between two distances from its start.
    ///
    /// Slicing a whole-way sample is what keeps chunk boundaries from cutting
    /// curves: the radius at a chunk's first sample was fitted using the road on
    /// both sides of the boundary.
    static func stats(_ sample: Sampled, from startMeters: Double, to endMeters: Double) -> Stats {
        guard sample.points.count > 2, sample.length > 1 else { return .empty }
        let start = min(max(startMeters, 0), sample.length)
        let end = min(max(endMeters, start), sample.length)
        guard end - start > 1 else { return .empty }

        var lo = 0
        while lo < sample.arc.count - 1, sample.arc[lo] < start - 0.001 { lo += 1 }
        var hi = lo
        while hi + 1 < sample.arc.count, sample.arc[hi + 1] <= end + 0.001 { hi += 1 }
        guard hi - lo >= 3 else { return .empty }

        let step = sampleSpacingMeters
        var measured = 0.0
        var rawSum = 0.0
        var cornerLength = 0.0
        var tightLength = 0.0
        var sweeperLength = 0.0
        var twistyLength = 0.0
        var runs = 0
        var runStart: Int?
        var runMin = Double.infinity
        var minRadius = Double.infinity

        func closeRun(at index: Int) {
            guard let runStart else { return }
            let runLength = Double(index - runStart) * step
            // A single noisy sample is not a corner.
            if runLength >= 3 * step {
                runs += 1
                cornerLength += runLength
                minRadius = min(minRadius, runMin)
            }
        }

        for index in lo...hi {
            let radius = sample.radii[index]
            let merit = fun(radius: radius)
            measured += step
            rawSum += merit
            if merit >= 0.5 { twistyLength += step }
            if radius < cornerRadiusMeters {
                if runStart == nil {
                    runStart = index
                    runMin = radius
                } else {
                    runMin = min(runMin, radius)
                }
            } else {
                closeRun(at: index)
                runStart = nil
                runMin = .infinity
            }
            if radius < tightRadiusMeters { tightLength += step }
            if radius >= tightRadiusMeters && radius < sweeperRadiusMeters {
                sweeperLength += step
            }
        }
        closeRun(at: hi + 1)

        guard measured > 1 else { return .empty }
        let kilometers = measured / 1_000
        let cornersPerKm = Double(runs) / max(kilometers, 0.05)
        let cornerShare = min(cornerLength / measured, 1)
        let tightShare = min(tightLength / measured, 1)
        let sweeperShare = min(sweeperLength / measured, 1)
        let raw = 100 * rawSum / Double(hi - lo + 1)

        let slice = Array(sample.points[lo...hi])
        // Density saturates on switchback roads; share alone punishes a great
        // corner surrounded by a connector. A straight road still scores 0.
        let densityScore = min(cornersPerKm / 6, 1)
        // Continuous share: a 250 m sweeper is worth something, a 450 m bend is
        // worth almost nothing. Dividing by 0.55 keeps tight mountain roads at
        // the top of the scale they had before the threshold was removed.
        let shareScore = min(raw / 55, 1)
        let tightScore: Double = minRadius.isFinite
            ? clamp((sweeperRadiusMeters - minRadius) / 210, 0, 1)
            : 0
        let sweeperScore = min(sweeperShare / 0.45, 1)
        let value = 100 * (0.30 * densityScore
            + 0.38 * shareScore
            + 0.20 * tightScore
            + 0.12 * sweeperScore)

        return Stats(
            lengthMeters: measured,
            degreesPerKm: degreesPerKilometer(slice, totalLength: measured),
            cornerShare: cornerShare,
            tightShare: tightShare,
            sweeperShare: sweeperShare,
            cornersPerKm: cornersPerKm,
            minRadiusMeters: minRadius,
            value: clamp(value, 0, 100),
            raw: clamp(raw, 0, 100),
            twistyLengthMeters: twistyLength,
            comfortableMps: comfortableSpeed(minRadius: minRadius)
        )
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
