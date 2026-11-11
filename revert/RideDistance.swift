import Foundation

/// The loop-distance selector uses a logarithmic scale: 1–10 miles gets
/// sub-mile resolution while the top of the slider still reaches 1,000.
nonisolated enum RideDistanceScale {
    static let minimumMiles = 1.0
    static let maximumMiles = 1_000.0
    static let presets: [Double] = [1, 2, 5, 10, 15, 25, 40, 60, 100, 250, 500, 1_000]

    static func fraction(for miles: Double) -> Double {
        let value = min(max(miles, minimumMiles), maximumMiles)
        return min(max(log(value) / log(maximumMiles), 0), 1)
    }

    static func miles(for fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        let raw = pow(maximumMiles, clamped)
        if raw < 10 {
            return min(max((raw * 2).rounded() / 2, minimumMiles), maximumMiles)
        }
        if raw < 50 {
            return min(max(raw.rounded(), minimumMiles), maximumMiles)
        }
        if raw < 200 {
            return min(max((raw / 5).rounded() * 5, minimumMiles), maximumMiles)
        }
        return min(max((raw / 10).rounded() * 10, minimumMiles), maximumMiles)
    }

    static func presetLabel(_ miles: Double) -> String {
        if UserDefaults.standard.bool(forKey: "units.metric") {
            let km = miles * 1.609344
            return km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
        }
        return miles >= 1_000 ? "1,000" : String(format: "%.0f", miles)
    }
}
