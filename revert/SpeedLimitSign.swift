import SwiftUI

struct SpeedLimitSign: View {
    /// Posted limit in mph (the OSM model's canonical unit).
    let limit: Int
    let over: Bool

    private var displayedLimit: Int {
        Int(Units.speedValueFromMph(Double(limit)).rounded())
    }

    private var unitLabel: String {
        Units.isMetric ? "km/h" : "MPH"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("SPEED\nLIMIT")
                .font(.system(size: 10, weight: .heavy))
                .multilineTextAlignment(.center)
            Text("\(displayedLimit)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            Text(unitLabel)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .opacity(0.7)
        }
        .foregroundStyle(over ? Color.white : Color.black)
        .frame(width: 86)
        .padding(.vertical, 7)
        .background(over ? Color.red : Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(over ? Color.white : Color.black, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed limit \(displayedLimit) \(unitLabel)\(over ? ", you are over the limit" : "")")
    }
}

struct SurfaceBanner: View {
    let alert: SurfaceAlert

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .bold))
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("UNPAVED ROAD")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(alert.text)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            Spacer()
        }
        .foregroundStyle(.black)
        .padding(14)
        .background(Color(red: 0.86, green: 0.72, blue: 0.50), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
