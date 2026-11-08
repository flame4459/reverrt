import SwiftUI
import CoreLocation
import UIKit

struct NavigationArrow: View {
    let heading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(MapUI.accent)
                .frame(width: 42, height: 42)
                .shadow(color: MapUI.accent.opacity(0.35), radius: 10, y: 4)

            Image(systemName: "location.north.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
        .rotationEffect(.degrees(heading))
        .accessibilityLabel("Current direction")
    }
}

enum MapUI {
    // OLED Digital Superbike Cockpit Palette
    static let pitchBlack = Color.black
    static let titanium = Color(red: 10/255, green: 13/255, blue: 20/255) // #0A0D14
    static let deepNavy = Color(red: 4/255, green: 8/255, blue: 16/255)  // #040810
    static let cyan = Color(red: 38/255, green: 230/255, blue: 255/255)  // #26E6FF
    static let emerald = Color(red: 51/255, green: 255/255, blue: 136/255) // #33FF88
    static let magenta = Color(red: 255/255, green: 51/255, blue: 102/255) // #FF3366
    /// Destructive controls (Stop ride) sit outside the cyan/emerald language.
    static let danger = Color(red: 255/255, green: 38/255, blue: 84/255)   // #FF2654

    // Primary Accents
    static let accent = cyan
    static let accentDark = deepNavy
    // Compatibility aliases for existing map and route components.
    static let blue = cyan
    static let blueDark = deepNavy
    static let teal = cyan
    static let green = emerald
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.18)
    static let groupedBackground = pitchBlack
    static let cardBackground = titanium
    static let panel = Color(red: 8/255, green: 10/255, blue: 15/255)          // OLED-safe card
    static let panelElevated = Color(red: 13/255, green: 17/255, blue: 25/255)
    static let glassTint = Color(red: 14/255, green: 22/255, blue: 32/255)
    static let hairline = Color.white.opacity(0.14)
    static let ink = Color.white
    static let secondaryInk = Color.white.opacity(0.65)
    static let shadow = Color.black.opacity(0.6)
    /// Bright cyan specular line used on the aero HUD banners.
    static let hudEdge = LinearGradient(
        colors: [cyan.opacity(0.95), cyan.opacity(0.15), emerald.opacity(0.55)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let fiberOpticBorder = LinearGradient(
        colors: [cyan.opacity(0.85), deepNavy.opacity(0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [cyan, Color(red: 0.12, green: 0.48, blue: 0.98)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let heroGradient = LinearGradient(
        colors: [deepNavy, titanium],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct FiberOpticCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(MapUI.titanium.opacity(0.92), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MapUI.fiberOpticBorder, lineWidth: 1)
            }
            .shadow(color: MapUI.cyan.opacity(0.12), radius: 12, y: 4)
    }
}

extension View {
    func fiberOpticCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(FiberOpticCardModifier(cornerRadius: cornerRadius))
    }
}

struct AppScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            MapUI.groupedBackground
                .ignoresSafeArea()
            content
        }
    }
}

struct MapCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(RiderPanelSurface(radius: 22))
    }
}

struct MapFloatingButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(MapUI.ink)
                .frame(width: 46, height: 46)
                .background(MapUI.panel.opacity(0.96), in: Circle())
                .overlay(Circle().stroke(MapUI.hairline, lineWidth: 0.8))
                .shadow(color: MapUI.shadow, radius: 10, y: 4)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Compact recovery affordance for a denied location permission. Without it
/// the planner just says "Waiting for GPS" forever and the rider has no path
/// back to the app's core features.
struct LocationOffBanner: View {
    var denied = true
    var onEnable: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: denied ? "location.slash.fill" : "location.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MapUI.amber)
                .frame(width: 30, height: 30)
                .background(MapUI.amber.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(denied ? "Location is off" : "Location access needed")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                Text(denied
                     ? "Allow access to plan and record rides."
                     : "Enable it to plan and record rides.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
            }

            Spacer(minLength: 4)

            Button(denied ? "Open Settings" : "Enable") {
                if !denied, let onEnable {
                    onEnable()
                    return
                }
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(MapUI.cyan)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(MapUI.cyan.opacity(0.12), in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(MapUI.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(MapUI.lineStrong, lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }
}

struct MapSectionTitle: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(MapUI.ink)
    }
}

struct ModernSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(MapUI.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(MapUI.accent)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MapUI.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MapUI.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct GradientActionButtonStyle: ButtonStyle {
    var tint: AnyShapeStyle = AnyShapeStyle(MapUI.accentGradient)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.8)
            }
            .shadow(color: MapUI.accent.opacity(0.24), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
