import Foundation
import CoreLocation

/// Spatial density of the hazards already cached on device (stop signs,
/// traffic lights, schools, rail crossings). Fusing this into the loop cost is
/// what stops the planner from choosing a light-every-300-metres arterial just
/// because its geometry happens to bend.
nonisolated struct HazardDensity: Sendable {
    struct Counts: Sendable, Equatable {
        var stop = 0
        var signal = 0
        var school = 0
        var rail = 0
        var camera = 0
    }

    private struct Key: Hashable {
        let latitude: Int
        let longitude: Int
    }

    private static let cellDegrees = 0.0025   // roughly 275 m north/south

    private let cells: [Key: Counts]

    init?(_ hazards: [Hazard]) {
        guard !hazards.isEmpty else { return nil }
        var cells: [Key: Counts] = [:]
        cells.reserveCapacity(hazards.count)
        for hazard in hazards {
            let key = Self.key(latitude: hazard.lat, longitude: hazard.lon)
            var counts = cells[key] ?? Counts()
            switch hazard.kind {
            case .stop: counts.stop += 1
            case .signal: counts.signal += 1
            case .school: counts.school += 1
            case .railCrossing: counts.rail += 1
            case .speedCamera, .redLightCamera: counts.camera += 1
            case .roundabout: break
            }
            cells[key] = counts
        }
        self.cells = cells
    }

    func counts(latitude: Double, longitude: Double) -> Counts {
        let centre = Self.key(latitude: latitude, longitude: longitude)
        var total = Counts()
        for latitudeDelta in -1...1 {
            for longitudeDelta in -1...1 {
                let key = Key(
                    latitude: centre.latitude + latitudeDelta,
                    longitude: centre.longitude + longitudeDelta
                )
                guard let counts = cells[key] else { continue }
                total.stop += counts.stop
                total.signal += counts.signal
                total.school += counts.school
                total.rail += counts.rail
                total.camera += counts.camera
            }
        }
        return total
    }

    /// Multiplies the per-metre cost of a chunk. A 3x3 cell window is used so a
    /// hazard just across a cell boundary still counts.
    func costFactor(latitude: Double, longitude: Double, date: Date) -> Double {
        let counts = counts(latitude: latitude, longitude: longitude)
        var factor = 1.0
        factor += Double(counts.signal) * 0.30
        factor += Double(counts.stop) * 0.22
        factor += Double(counts.rail) * 0.12
        factor += Double(counts.camera) * 0.04
        if Self.schoolInSession(date) {
            factor += Double(counts.school) * 0.45
        }
        return min(factor, 2.2)
    }

    /// Estimated seconds lost at standstills on this chunk.
    func delaySeconds(latitude: Double, longitude: Double, date: Date) -> Double {
        let counts = counts(latitude: latitude, longitude: longitude)
        var seconds = Double(counts.signal) * 6 + Double(counts.stop) * 3
        if Self.schoolInSession(date) { seconds += Double(counts.school) * 4 }
        seconds += Double(counts.rail) * 2
        return seconds
    }

    /// Stops and lights encountered, used for the "interruptions" metric.
    func interruptionCount(latitude: Double, longitude: Double, date: Date) -> Int {
        let counts = counts(latitude: latitude, longitude: longitude)
        var count = counts.signal + counts.stop
        if Self.schoolInSession(date) { count += counts.school }
        return count
    }

    static func schoolInSession(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard (2...6).contains(weekday) else { return false }
        return (7...16).contains(calendar.component(.hour, from: date))
    }

    private static func key(latitude: Double, longitude: Double) -> Key {
        Key(
            latitude: Int(floor(latitude / cellDegrees)),
            longitude: Int(floor(longitude / cellDegrees))
        )
    }
}
