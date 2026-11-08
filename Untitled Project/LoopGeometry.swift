import CoreLocation
import Foundation
import MapKit

/// Geometry checks that keep generated loops lap-able.
///
/// A loop should be a circuit, not a circuit with an out-and-back tail. The
/// common failure is a waypoint that MapKit snaps to the end of a driveway or
/// cul-de-sac: the route rides in, turns around at the head, and rides back
/// out. That is invisible in a distance or twistiness score (a 150 m spur on a
/// 40 km loop is 0.4%), so it needs its own detector.
nonisolated enum LoopGeometry {
    private struct Cell: Hashable {
        let latitude: Int
        let longitude: Int
    }

    private struct Visit {
        let latitude: Double
        let longitude: Double
        let heading: Double
        let alongMeters: Double
    }

    struct Analysis: Sendable, Equatable {
        let totalMeters: Double
        let repeatedMeters: Double
        let reversalMeters: Double
        let longestSpurMeters: Double

        static let empty = Analysis(totalMeters: 0, repeatedMeters: 0, reversalMeters: 0, longestSpurMeters: 0)

        var repeatedFraction: Double { totalMeters > 0 ? repeatedMeters / totalMeters : 0 }
        var reversalFraction: Double { totalMeters > 0 ? reversalMeters / totalMeters : 0 }
    }

    /// Resampling at 8 m catches short cul-de-sacs without making a 40 km loop
    /// expensive. Cells are 10 m so a real hairpin (two legs tens of metres
    /// apart) is not mistaken for a retrace of the same lane.
    static let sampleIntervalMeters = 8.0
    static let cellSizeMeters = 10.0
    /// Two samples within this distance are riding the same piece of tarmac.
    static let proximityMeters = 7.0
    /// Ignore only the immediately preceding sample: it is the same pass.
    /// Anything 12 m or more back along the route is a genuine second visit.
    static let minimumSeparationMeters = 12.0

    /// Hard limits used when accepting a loop. A little overlap is fine at a
    /// crossing or a one-way pair; riding back down the road you just used is
    /// not.
    static let maximumSpurMeters = 20.0
    static let maximumReversalMeters = 30.0
    static let maximumRepeatedFraction = 0.06

    /// How strict the lap check is.
    ///
    /// Engines try `.standard` first: no spur, no riding back down the road you
    /// just used. That is the right answer when the road network offers a clean
    /// circuit. Plenty of real starts do not — a subdivision with one road out,
    /// a valley with a single pass road — and the old binary check rejected
    /// every loop there, including the one the rider would happily ride.
    /// `.relaxed` still forbids a real out-and-back tail; it only tolerates a
    /// shared connector or a short repeated approach. Engines only fall back to
    /// it when nothing passes the standard check, so a clean loop always wins.
    struct Limits: Sendable, Equatable {
        let maximumSpurMeters: Double
        let maximumReversalMeters: Double
        let maximumRepeatedFraction: Double

        static let standard = Limits(
            maximumSpurMeters: LoopGeometry.maximumSpurMeters,
            maximumReversalMeters: LoopGeometry.maximumReversalMeters,
            maximumRepeatedFraction: LoopGeometry.maximumRepeatedFraction
        )
        static let relaxed = Limits(
            maximumSpurMeters: 60,
            maximumReversalMeters: 90,
            maximumRepeatedFraction: 0.14
        )
        /// Last resort. A quarter of the loop may reuse a road. Anything above
        /// this is an out-and-back with extra steps, not a lap.
        static let loose = Limits(
            maximumSpurMeters: 120,
            maximumReversalMeters: 200,
            maximumRepeatedFraction: 0.22
        )
        /// Used only when every normal loop check rejects the candidates. The
        /// result is still a rideable circuit, but it may share a connector or
        /// carry a short spur, so the planner labels it as the best available.
        static let bestEffort = Limits(
            maximumSpurMeters: 1_200,
            maximumReversalMeters: 1_200,
            maximumRepeatedFraction: 0.55
        )
    }

    static func isLapable(_ analysis: Analysis, limits: Limits = .standard) -> Bool {
        analysis.longestSpurMeters <= limits.maximumSpurMeters
            && analysis.reversalMeters <= limits.maximumReversalMeters
            && analysis.repeatedFraction <= limits.maximumRepeatedFraction
    }

    /// Measures how much of the polyline reuses a cell it has already visited,
    /// and how much of that reuse is in the opposite direction (a U-turn).
    ///
    /// `ignoreStartMeters` / `ignoreEndMeters` forgive the rider's own street:
    /// someone living at the end of a cul-de-sac has to ride out and back to
    /// reach the circuit, but the circuit itself should still be clean.
    static func analyze(
        _ coordinates: [CLLocationCoordinate2D],
        ignoreStartMeters: Double = 0,
        ignoreEndMeters: Double = 0
    ) -> Analysis {
        guard coordinates.count > 2 else { return .empty }
        let sampled = resample(coordinates, every: sampleIntervalMeters)
        guard sampled.count > 2 else { return .empty }

        var cumulative = [Double](repeating: 0, count: sampled.count)
        for index in 1..<sampled.count {
            cumulative[index] = cumulative[index - 1] + distance(sampled[index - 1], sampled[index])
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return .empty }

        var grid: [Cell: [Visit]] = [:]
        grid.reserveCapacity(sampled.count / 2)

        var repeated = 0.0
        var reversal = 0.0
        var currentRun = 0.0
        var longestRun = 0.0

        for index in 1..<sampled.count {
            let segmentLength = cumulative[index] - cumulative[index - 1]
            guard segmentLength > 0 else { continue }
            let along = cumulative[index]
            if along < ignoreStartMeters || total - along < ignoreEndMeters { continue }

            let start = sampled[index - 1]
            let end = sampled[index]
            let leg = RoadGraph.flat(start.latitude, start.longitude, end.latitude, end.longitude)
            let cell = cellFor(end)

            var isRepeat = false
            var isReversal = false
            // Compare against points on roads that pass within a lane width.
            // Looking at a 3×3 neighbourhood (rather than a single cell) keeps
            // this stable when the outbound and inbound samples are offset by
            // a few metres.
            search: for latitudeDelta in -1...1 {
                for longitudeDelta in -1...1 {
                    let neighbour = Cell(
                        latitude: cell.latitude + latitudeDelta,
                        longitude: cell.longitude + longitudeDelta
                    )
                    guard let visits = grid[neighbour] else { continue }
                    for visit in visits {
                        // Ignore the previous few samples: they are the same
                        // pass, not a second visit to the same place.
                        guard along - visit.alongMeters >= minimumSeparationMeters else { continue }
                        let separation = RoadGraph.flat(
                            end.latitude, end.longitude,
                            visit.latitude, visit.longitude
                        ).dist
                        guard separation <= proximityMeters else { continue }
                        isRepeat = true
                        if abs(normalized(leg.heading - visit.heading)) >= 150 {
                            isReversal = true
                            break search
                        }
                    }
                }
            }

            if isRepeat { repeated += segmentLength }
            if isReversal {
                reversal += segmentLength
                currentRun += segmentLength
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }

            var visits = grid[cell] ?? []
            visits.append(Visit(
                latitude: end.latitude,
                longitude: end.longitude,
                heading: leg.heading,
                alongMeters: along
            ))
            // A busy junction can revisit the same cell many times. Keeping a
            // handful of passes is enough to detect a reversal.
            if visits.count > 8 { visits.removeFirst() }
            grid[cell] = visits
        }

        return Analysis(
            totalMeters: total,
            repeatedMeters: repeated,
            reversalMeters: reversal,
            longestSpurMeters: longestRun
        )
    }

    /// MapKit sometimes says "turn around" rather than "U-turn".
    static func containsUTurn(_ routes: [MKRoute]) -> Bool {
        for route in routes {
            for step in route.steps {
                let text = step.instructions.lowercased()
                if text.contains("u-turn") || text.contains("u turn")
                    || text.contains("uturn") || text.contains("turn around") {
                    return true
                }
            }
        }
        return false
    }

    private static func cellFor(_ coordinate: CLLocationCoordinate2D) -> Cell {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        return Cell(
            latitude: Int(floor(coordinate.latitude * latitudeScale / cellSizeMeters)),
            longitude: Int(floor(coordinate.longitude * longitudeScale / cellSizeMeters))
        )
    }

    private static func resample(
        _ coordinates: [CLLocationCoordinate2D],
        every interval: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var output = [coordinates[0]]
        var remaining = interval
        var previous = coordinates[0]

        for current in coordinates.dropFirst() {
            var start = previous
            var segmentRemaining = distance(start, current)

            while segmentRemaining >= remaining {
                let fraction = remaining / max(segmentRemaining, 0.001)
                let point = interpolate(start, current, fraction: fraction)
                output.append(point)
                start = point
                segmentRemaining -= remaining
                remaining = interval
            }

            remaining -= segmentRemaining
            previous = current
        }

        if let last = output.last, distance(last, coordinates.last!) > interval * 0.5 {
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
        _ start: CLLocationCoordinate2D,
        _ end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )
    }

    private static func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
