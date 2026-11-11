import Foundation
import SwiftData
import CoreLocation

nonisolated struct RidePoint: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var alt: Double
    var speed: Double   // m/s
    var time: Date
    /// Signed lean angle in degrees (+ right, - left). Optional so tracks
    /// recorded before lean logging still decode.
    var lean: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

@Model
final class Ride {
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double
    var maxSpeedMps: Double
    var elevationGainMeters: Double
    var durationSeconds: Double
    @Attribute(.externalStorage) var pointsData: Data

    // Rich ride data. Defaults keep existing stores compatible.
    var maxLeanAngleDegrees: Double = 0
    var bikeName: String?
    var bikeID: UUID?
    var routeName: String?
    var movingSeconds: Double = 0
    var stoppedSeconds: Double = 0
    var savedRouteID: UUID?

    /// Decoding the whole track on every access is expensive, so keep the
    /// result for the lifetime of this model object.
    @Transient private var cachedPoints: [RidePoint]?

    init(startDate: Date, endDate: Date, distanceMeters: Double, maxSpeedMps: Double,
         elevationGainMeters: Double, durationSeconds: Double, points: [RidePoint],
         maxLeanAngleDegrees: Double = 0, bikeName: String? = nil, bikeID: UUID? = nil,
         routeName: String? = nil,
         movingSeconds: Double = 0, stoppedSeconds: Double = 0, savedRouteID: UUID? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.maxSpeedMps = maxSpeedMps
        self.elevationGainMeters = elevationGainMeters
        self.durationSeconds = durationSeconds
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.maxLeanAngleDegrees = maxLeanAngleDegrees
        self.bikeName = bikeName
        self.bikeID = bikeID
        self.routeName = routeName
        self.movingSeconds = movingSeconds
        self.stoppedSeconds = stoppedSeconds
        self.savedRouteID = savedRouteID
    }

    var points: [RidePoint] {
        if let cachedPoints { return cachedPoints }
        let decoded = (try? JSONDecoder().decode([RidePoint].self, from: pointsData)) ?? []
        cachedPoints = decoded
        return decoded
    }

    var averageSpeedMps: Double {
        durationSeconds > 0 ? distanceMeters / durationSeconds : 0
    }

    var movingTimeSeconds: Double {
        movingSeconds > 0 ? movingSeconds : durationSeconds
    }

    var stoppedTimeSeconds: Double {
        max(stoppedSeconds, 0)
    }

    var bikeDisplayName: String {
        guard let bikeName = bikeName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bikeName.isEmpty else { return "Unassigned bike" }
        return bikeName
    }
}

/// Formatting helpers are pure maths over `UserDefaults`, so they are used
/// from the off-main-actor route planner as well as the UI. Opting the whole
/// namespace out of the project's default main-actor isolation keeps e.g.
/// `distanceText` callable from `RouteBuilder`.
nonisolated enum Units {
    static let metricKey = "units.metric"

    static var isMetric: Bool {
        UserDefaults.standard.bool(forKey: metricKey)
    }

    static func setMetric(_ metric: Bool) {
        UserDefaults.standard.set(metric, forKey: metricKey)
    }

    // MARK: Raw conversions (kept for existing/internal callers)
    static func mph(_ mps: Double) -> Double { mps * 2.23694 }
    static func miles(_ meters: Double) -> Double { meters / 1609.344 }
    static func feet(_ meters: Double) -> Double { meters * 3.28084 }
    static func kilometers(_ meters: Double) -> Double { meters / 1_000 }

    // MARK: Display values
    static var speedUnit: String { isMetric ? "km/h" : "mph" }
    static var speedUnitUppercase: String { isMetric ? "KM/H" : "MPH" }
    static var distanceUnit: String { isMetric ? "km" : "mi" }
    static var elevationUnit: String { isMetric ? "m" : "ft" }

    static func speedValue(_ mps: Double) -> Double {
        isMetric ? mps * 3.6 : mph(mps)
    }

    static func speedValueFromMph(_ value: Double) -> Double {
        isMetric ? value * 1.60934 : value
    }

    static func speedText(_ mps: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f %@", speedValue(mps), speedUnit)
    }

    static func speedTextFromMph(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f %@", speedValueFromMph(value), speedUnit)
    }

    static func distanceValue(_ meters: Double) -> Double {
        isMetric ? kilometers(meters) : miles(meters)
    }

    static func distanceText(_ meters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", distanceValue(meters), distanceUnit)
    }

    static func distanceTextFromMiles(_ miles: Double, decimals: Int = 0) -> String {
        isMetric
            ? String(format: "%.\(decimals)f km", miles * 1.60934)
            : String(format: "%.\(decimals)f mi", miles)
    }

    static func elevationValue(_ meters: Double) -> Double {
        isMetric ? meters : feet(meters)
    }

    static func elevationText(_ meters: Double) -> String {
        "\(Int(elevationValue(meters).rounded())) \(elevationUnit)"
    }

    /// Short, glanceable distance for banners: feet/meters when close, then miles/km.
    static func shortDistanceText(_ meters: Double) -> String {
        if isMetric {
            if meters < 1_000 {
                let rounded = max(Int((meters / 10).rounded()) * 10, 10)
                return "\(rounded) m"
            }
            return String(format: "%.1f km", meters / 1_000)
        }
        let feet = feet(meters)
        if feet < 1_000 {
            return "\(max(Int((feet / 50).rounded()) * 50, 50)) ft"
        }
        return String(format: "%.1f mi", miles(meters))
    }

    /// Distance for a device approach: short and precise, never "half a mile"
    /// when the rider needs to know how far the stop sign is.
    static func spokenApproachDistance(_ meters: Double) -> String {
        if isMetric {
            if meters < 1_000 {
                return "\(max(Int((meters / 25).rounded()) * 25, 25)) meters"
            }
            return String(format: "%.1f kilometers", meters / 1_000)
        }
        let feet = feet(meters)
        if feet < 1_000 {
            return "\(max(Int((feet / 50).rounded()) * 50, 50)) feet"
        }
        return String(format: "%.1f miles", miles(meters))
    }

    /// Spoken distance with natural phrasing for the active unit system.
    static func spokenDistance(_ meters: Double) -> String {
        if isMetric {
            if meters < 100 { return "\(max(Int((meters / 10).rounded()) * 10, 10)) meters" }
            if meters < 1_000 { return "\(max(Int((meters / 100).rounded()) * 100, 100)) meters" }
            let km = meters / 1_000
            if km < 1.3 { return "one kilometer" }
            return "\(Int(km.rounded())) kilometers"
        }
        let ft = feet(meters)
        if ft < 1_000 { return "\(max(Int((ft / 100).rounded()), 1) * 100) feet" }
        let mi = miles(meters)
        if mi < 0.7 { return "half a mile" }
        if mi < 1.3 { return "one mile" }
        return "\(Int(mi.rounded())) miles"
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func durationText(_ seconds: Double) -> String {
        Duration.seconds(max(seconds, 0))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
