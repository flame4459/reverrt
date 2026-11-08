import SwiftUI

struct AlertBanner: View {
    let alert: ActiveAlert

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: alert.hazard.kind.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(MapUI.orange, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.hazard.kind.title)
                    .font(.headline.weight(.bold))
                Text(distanceText)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.82)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(MapUI.orange.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 0.8)
        }
        .shadow(color: MapUI.shadow, radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var distanceText: String {
        "\(Units.shortDistanceText(alert.distance)) ahead"
    }
}

struct CurveBanner: View {
    let alert: CurveWarning

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: alert.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(MapUI.accentDark, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.headline.weight(.bold))
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.82)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(MapUI.accentGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 0.8)
        }
        .shadow(color: MapUI.shadow, radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let distance = Units.shortDistanceText(alert.distance)
        guard alert.level != .curve else { return distance }
        return "\(distance)  •  slow to \(Units.speedTextFromMph(Double(alert.advisoryMph)))"
    }
}
