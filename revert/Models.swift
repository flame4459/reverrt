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
    /// Circuit laps completed. Point-to-point rides use 1.
    var laps: Int = 1
    /// True for a road-to-road sprint, so summaries and boards can label it
    /// differently from a circuit.
    var isSprint: Bool = false
    /// Opaque, hashed identity of the loop this ride was ridden on. Used to
    /// group rides into a local leaderboard without storing coordinates twice.
    var routeKey: String?
    /// Motorcycle or car. Existing rides migrate as motorcycles.
    var vehicleKindRaw: String = VehicleKind.motorcycle.rawValue

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

    var vehicleKind: VehicleKind {
        get { VehicleKind(rawValue: vehicleKindRaw) ?? .motorcycle }
        set { vehicleKindRaw = newValue.rawValue }
    }

    var isCar: Bool { vehicleKind.isCar }

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

    var bikeDisplayName: String {
        guard let bikeName = bikeName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bikeName.isEmpty else { return "Unassigned vehicle" }
        return bikeName
    }
}

/// The rider's unit choice. `.automatic` follows the iPhone region (US/UK use
/// miles, most other regions use kilometres); the explicit choices pin the app
/// regardless of travel.
nonisolated enum UnitSystemPreference: String, CaseIterable, Identifiable {
    case automatic
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic: "Auto"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Follow the iPhone region"
        case .metric: "Kilometres, km/h, metres"
        case .imperial: "Miles, mph, feet"
        }
    }

    var icon: String {
        switch self {
        case .automatic: "globe"
        case .metric: "ruler"
        case .imperial: "ruler.fill"
        }
    }
}

/// Formatting helpers are pure maths over `UserDefaults`, so they are used
/// from the off-main-actor route planner as well as the UI. Opting the whole
/// namespace out of the project's default main-actor isolation keeps e.g.
/// `distanceText` callable from `RouteBuilder`.
nonisolated enum Units {
    static let metricKey = "units.metric"
    static let systemKey = "units.system"

    /// The explicit preference. Missing or invalid means automatic.
    static var preference: UnitSystemPreference {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: systemKey),
           let stored = UnitSystemPreference(rawValue: raw) {
            return stored
        }
        // Migration from the original on/off metric toggle. Only treat the
        // legacy key as an explicit choice when it was actually written.
        if defaults.object(forKey: metricKey) != nil {
            return defaults.bool(forKey: metricKey) ? .metric : .imperial
        }
        return .automatic
    }

    /// What the region says, ignoring any manual override.
    static var autoIsMetric: Bool {
        let locale = Locale.autoupdatingCurrent
        switch locale.measurementSystem {
        case .metric:
            return true
        case .uk, .us:
            return false
        default:
            // Defensive fallback for older locale data: US, UK, Liberia and
            // Myanmar use road miles; the rest of the world uses kilometres.
            let region = locale.region?.identifier ?? "US"
            return !["US", "GB", "LR", "MM"].contains(region)
        }
    }

    static var isMetric: Bool {
        switch preference {
        case .metric: true
        case .imperial: false
        case .automatic: autoIsMetric
        }
    }

    static var effectiveDescription: String {
        let region = Locale.autoupdatingCurrent.region?.identifier ?? "—"
        switch preference {
        case .metric:
            return "Metric — kilometres, km/h and metres."
        case .imperial:
            return "Imperial — miles, mph and feet."
        case .automatic:
            return autoIsMetric
                ? "Automatic — metric from the \(region) region."
                : "Automatic — imperial from the \(region) region."
        }
    }

    static func setPreference(_ preference: UnitSystemPreference) {
        let defaults = UserDefaults.standard
        defaults.set(preference.rawValue, forKey: systemKey)
        if preference == .automatic {
            defaults.removeObject(forKey: metricKey)
        } else {
            defaults.set(preference == .metric, forKey: metricKey)
        }
    }

    /// Kept for old callers and the previous Settings toggle.
    static func setMetric(_ metric: Bool) {
        setPreference(metric ? .metric : .imperial)
    }

    /// Turn a legacy stored metric on/off into the new preference once, so a
    /// rider who already chose a system never silently flips to automatic.
    static func migrateLegacyPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: systemKey) == nil,
              let legacy = defaults.object(forKey: metricKey) as? Bool else { return }
        setPreference(legacy ? .metric : .imperial)
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
    static var twistUnit: String { isMetric ? "°/km" : "°/mi" }
    static var volumeUnit: String {
        if isMetric { return "L" }
        return Locale.autoupdatingCurrent.measurementSystem == .uk ? "imp gal" : "gal"
    }
    static var pressureUnit: String { isMetric ? "bar" : "psi" }

    private static var volumeFactor: Double {
        if isMetric { return 1 }
        return Locale.autoupdatingCurrent.measurementSystem == .uk ? 0.219969 : 0.264172
    }

    static func volumeValue(_ liters: Double) -> Double { liters * volumeFactor }
    static func volumeToLiters(_ displayValue: Double) -> Double { displayValue / volumeFactor }
    static func volumeText(_ liters: Double) -> String {
        String(format: "%.1f %@", volumeValue(liters), volumeUnit)
    }

    static func pressureValue(_ psi: Double) -> Double {
        isMetric ? psi * 0.0689476 : psi
    }
    static func pressureToPsi(_ displayValue: Double) -> Double {
        isMetric ? displayValue / 0.0689476 : displayValue
    }
    static func pressureText(_ psi: Double) -> String {
        String(format: "%.1f %@", pressureValue(psi), pressureUnit)
    }

    static var temperatureUnit: String { isMetric ? "°C" : "°F" }

    static func temperatureValue(_ celsius: Double) -> Double {
        isMetric ? celsius : celsius * 9 / 5 + 32
    }

    static func temperatureText(_ celsius: Double) -> String {
        "\(RevertFormat.number(temperatureValue(celsius), decimals: 0)) \(temperatureUnit)"
    }

    /// Twist density is stored per kilometre; convert the display value for
    /// imperial riders without changing the underlying score.
    static func twistValue(_ degreesPerKm: Double) -> Double {
        isMetric ? degreesPerKm : degreesPerKm / 1.609344
    }

    static func speedValue(_ mps: Double) -> Double {
        isMetric ? mps * 3.6 : mph(mps)
    }

    static func speedValueFromMph(_ value: Double) -> Double {
        isMetric ? value * 1.60934 : value
    }

    static func speedText(_ mps: Double, decimals: Int = 0) -> String {
        "\(RevertFormat.number(speedValue(mps), decimals: decimals)) \(speedUnit)"
    }

    static func speedTextFromMph(_ value: Double, decimals: Int = 0) -> String {
        "\(RevertFormat.number(speedValueFromMph(value), decimals: decimals)) \(speedUnit)"
    }

    static func distanceValue(_ meters: Double) -> Double {
        isMetric ? kilometers(meters) : miles(meters)
    }

    static func distanceText(_ meters: Double, decimals: Int = 1) -> String {
        "\(RevertFormat.number(distanceValue(meters), decimals: decimals)) \(distanceUnit)"
    }

    static func distanceTextFromMiles(_ miles: Double, decimals: Int = 0) -> String {
        isMetric
            ? "\(RevertFormat.number(miles * 1.60934, decimals: decimals)) km"
            : "\(RevertFormat.number(miles, decimals: decimals)) mi"
    }

    static func elevationValue(_ meters: Double) -> Double {
        isMetric ? meters : feet(meters)
    }

    static func elevationText(_ meters: Double) -> String {
        "\(RevertFormat.number(elevationValue(meters), decimals: 0)) \(elevationUnit)"
    }

    /// Short, glanceable distance for banners: feet/meters when close, then miles/km.
    static func shortDistanceText(_ meters: Double) -> String {
        if isMetric {
            if meters < 1_000 {
                let rounded = max(Int((meters / 10).rounded()) * 10, 10)
                return "\(RevertFormat.number(Double(rounded), decimals: 0)) m"
            }
            return "\(RevertFormat.number(meters / 1_000, decimals: 1)) km"
        }
        let feet = feet(meters)
        if feet < 1_000 {
            let rounded = max(Int((feet / 50).rounded()) * 50, 50)
            return "\(RevertFormat.number(Double(rounded), decimals: 0)) ft"
        }
        return "\(RevertFormat.number(miles(meters), decimals: 1)) mi"
    }

    /// Distance for a device approach: short and precise, never "half a mile"
    /// when the rider needs to know how far the stop sign is.
    static func spokenApproachDistance(_ meters: Double) -> String {
        if isMetric {
            if meters < 1_000 {
                let rounded = max(Int((meters / 25).rounded()) * 25, 25)
                return "\(RevertFormat.number(Double(rounded), decimals: 0)) meters"
            }
            return "\(RevertFormat.number(meters / 1_000, decimals: 1)) kilometers"
        }
        let feet = feet(meters)
        if feet < 1_000 {
            let rounded = max(Int((feet / 50).rounded()) * 50, 50)
            return "\(RevertFormat.number(Double(rounded), decimals: 0)) feet"
        }
        return "\(RevertFormat.number(miles(meters), decimals: 1)) miles"
    }

    /// Spoken distance with natural phrasing for the active unit system.
    /// Spoken distance, bucketed the way navigation voices speak: 50-foot
    /// steps up to 1,000 feet, then tenths and quarters of a mile, then whole
    /// miles. Metric mirrors it with 10/50/100-metre steps and kilometres.
    static func spokenDistance(_ meters: Double) -> String {
        if isMetric {
            if meters < 100 { return "\(max(Int((meters / 10).rounded()) * 10, 10)) meters" }
            if meters < 1_000 {
                let buckets = [100, 150, 200, 250, 300, 400, 500, 600, 700, 800, 900]
                let nearest = buckets.min { abs(Double($0) - meters) < abs(Double($1) - meters) } ?? 100
                return "\(nearest) meters"
            }
            let km = meters / 1_000
            if km < 1.25 { return "one kilometer" }
            if km < 1.75 { return "one and a half kilometers" }
            return "\(Int(km.rounded())) kilometers"
        }

        let ft = feet(meters)
        if ft < 1_100 {
            let buckets = [50, 100, 150, 200, 250, 300, 400, 450, 500, 600, 700, 800, 900, 1_000]
            let nearest = buckets.min { abs(Double($0) - ft) < abs(Double($1) - ft) } ?? 50
            return nearest == 1_000 ? "1,000 feet" : "\(nearest) feet"
        }

        let mi = miles(meters)
        if mi < 0.95 {
            switch (mi * 10).rounded() {
            case 1: return "one tenth of a mile"
            case 2: return "two tenths of a mile"
            case 3: return "three tenths of a mile"
            case 4: return "four tenths of a mile"
            case 5: return "half a mile"
            case 6: return "six tenths of a mile"
            case 7: return "three quarters of a mile"
            case 8: return "eight tenths of a mile"
            default: return "nine tenths of a mile"
            }
        }
        if mi < 1.4 { return "one mile" }
        if mi < 1.75 { return "one and a half miles" }
        return "\(Int(mi.rounded())) miles"
    }

    /// A duration the way a navigation voice says it, not `0:04:12`.
    static func spokenClock(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") \(secs) second\(secs == 1 ? "" : "s")"
        }
        return "\(secs) second\(secs == 1 ? "" : "s")"
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
