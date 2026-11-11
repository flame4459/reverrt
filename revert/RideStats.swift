import Foundation
import CoreLocation

/// One definition of how a recorded track turns into ride numbers.
///
/// The live recorder and the crash-recovery journal used to apply different
/// rules: the recorder counted every plausible fix, while the journal threw
/// away any segment of 30 m or more. On the highway at 1 Hz that is every
/// segment, so a recovered ride came back with almost no distance. Both paths
/// now call this, which also makes the numbers reproducible in tests.
nonisolated struct RideStats: Sendable, Equatable {
    var distanceMeters: Double = 0
    var maxSpeedMps: Double = 0
    var elevationGainMeters: Double = 0
    var maxLeanAngleDegrees: Double = 0
    var movingSeconds: Double = 0
    var stoppedSeconds: Double = 0

    /// A speed at or below this counts as stopped, matching the cockpit's
    /// "moving" readout.
    static let stoppedSpeedMps: Double = 1.5
    /// Fixes further apart than this are treated as a signal gap, not riding.
    static let maximumFixGap: TimeInterval = 15
    /// A segment longer than this is only accepted when the fix itself shows
    /// plausible movement; see `segmentMeters`.
    static let jumpDistanceMeters: Double = 30
    /// Anything implying faster than this is a multipath jump, not a vehicle.
    static let impossibleSpeedMps: Double = 60
    /// Vertical change smaller than this is GPS barometer noise.
    static let elevationThreshold: Double = 3

    static func compute(points: [RidePoint]) -> RideStats {
        var stats = RideStats()
        var altitudeRef: Double?

        for index in points.indices {
            let point = points[index]
            stats.maxSpeedMps = max(stats.maxSpeedMps, point.speed)
            stats.maxLeanAngleDegrees = max(stats.maxLeanAngleDegrees, abs(point.lean ?? 0))

            if index > 0 {
                let previous = points[index - 1]
                if let meters = segmentMeters(from: previous.coordinate, at: previous.time,
                                              to: point.coordinate, at: point.time,
                                              nextSpeed: point.speed) {
                    stats.distanceMeters += meters
                    let gap = point.time.timeIntervalSince(previous.time)
                    if point.speed > stoppedSpeedMps {
                        stats.movingSeconds += gap
                    } else {
                        stats.stoppedSeconds += gap
                    }
                }
            }

            stats.elevationGainMeters += elevationGain(altitude: point.alt, reference: &altitudeRef)
        }
        return stats
    }

    /// Distance this pair of fixes contributes, or nil when the pair must be
    /// ignored (signal gap, stopped drift, multipath jump).
    ///
    /// A long segment is legitimate: at 70 mph a 1 Hz GPS delivers a 31 m
    /// step. So a long segment is only rejected when the fix reports that the
    /// bike was essentially stationary, or when covering that distance would
    /// imply an impossible speed.
    static func segmentMeters(from previous: CLLocationCoordinate2D, at previousTime: Date,
                              to next: CLLocationCoordinate2D, at nextTime: Date,
                              nextSpeed: Double) -> Double? {
        let gap = nextTime.timeIntervalSince(previousTime)
        guard gap > 0, gap < maximumFixGap else { return nil }
        let delta = RoadGraph.flat(previous.latitude, previous.longitude,
                                  next.latitude, next.longitude).dist
        guard delta.isFinite, delta >= 0 else { return nil }
        let impliedSpeed = delta / gap
        if delta > jumpDistanceMeters, nextSpeed < 1 || impliedSpeed > impossibleSpeedMps {
            return nil
        }
        return delta
    }

    /// Climb to add for this altitude, updating the reference with the same
    /// 3 m hysteresis the cockpit uses.
    static func elevationGain(altitude: Double, reference: inout Double?) -> Double {
        guard altitude != 0 else { return 0 }
        guard let previous = reference else {
            reference = altitude
            return 0
        }
        let difference = altitude - previous
        if difference >= elevationThreshold {
            reference = altitude
            return difference
        }
        if difference <= -elevationThreshold {
            reference = altitude
        }
        return 0
    }
}
