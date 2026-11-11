import SwiftUI

// MARK: - Midnight Pulse design tokens
//
// The visual language from the Midnight Pulse concept: a deep, teal-washed
// OLED canvas, soft glass panels with a single hairline rim, mint-cyan light
// for anything live, and wide-tracked uppercase micro-type.
//
// Everything here is additive: the rest of the app keeps using MapUI and the
// Revert* components, which are re-pointed at these values so old screens pick
// up the new skin without changing how they work.

enum Pulse {
    static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Every token resolves through the active scheme at render time. Views
    /// that read any of these colours observe the theme store, so a switch in
    /// Settings repaints the app immediately.
    private static var palette: RevertPalette { RevertThemeStore.shared.palette }

    // Canvas
    static var canvas: Color { palette.canvas }
    static var canvasGlow: Color { palette.canvasGlow }
    static var canvasMid: Color { palette.canvasMid }
    static var bar: Color { palette.bar }

    // Surfaces
    static var panel: Color { palette.panel }
    static var panelHigh: Color { palette.panelHigh }
    static var panelLift: Color { palette.panelLift }
    static var panelDeep: Color { palette.panelDeep }
    static var field: Color { palette.panelDeep }
    static var iconWell: Color { palette.panelHigh }
    static var metricWell: Color { palette.panel }

    // Hairlines
    static var line: Color { palette.line }
    static var lineSoft: Color { palette.lineSoft }
    static var lineBright: Color { palette.lineBright }
    static var fieldLine: Color { palette.lineBright }

    // Text
    static var ink: Color { palette.ink }
    static var mutedStrong: Color { palette.mutedStrong }
    static var muted: Color { palette.muted }
    static var tabInactive: Color { palette.tabInactive }

    // Accents
    static var accent: Color { palette.accent }
    static var accentBright: Color { palette.accentBright }
    static var accentDeep: Color { palette.accentDeep }
    static var accentInk: Color { palette.accentInk }
    static var accentWell: Color { palette.accentWell }
    static var accentLine: Color { palette.accentLine }

    static var warning: Color { palette.warning }

    // Semantic colours stay stable across schemes so a hazard still reads as
    // a hazard regardless of the paint job.
    static let danger = color(0xFF8F83)
    static let emerald = color(0x62E7BF)
    static let coral = color(0xFFA89C)
    static let orange = color(0xFFA96B)
    static let violet = color(0xBEB2FF)
    static let magenta = color(0xFFA8B8)
    static let ice = color(0xDAF8F5)

    static var accentGradient: LinearGradient { palette.accentGradient }

    static var heroGradient: LinearGradient { palette.heroGradient }

    static var cardGradient: LinearGradient { palette.cardGradient }

    static var barGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.75), accentDeep.opacity(0.25), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

enum PulseMetrics {
    static let screenPadding: CGFloat = 19
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 17
    static let fieldRadius: CGFloat = 11
    static let controlRadius: CGFloat = 13
    static let chipRadius: CGFloat = 30
    static let sectionSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 10
}

enum PulseType {
    static func display(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .heavy)
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static var eyebrow: Font { .system(size: 10, weight: .black) }
    static var section: Font { .system(size: 11, weight: .heavy) }
    static var title: Font { .system(size: 17, weight: .bold) }
    static var body: Font { .system(size: 13) }
    static var caption: Font { .system(size: 10.5) }
}

// MARK: - Background

/// The concept's radial teal wash: brightest behind the app header and
/// falling to near-black at the bottom of the screen.
struct PulseBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height)
            ZStack {
                Pulse.canvas
                RadialGradient(
                    stops: [
                        .init(color: Pulse.canvasGlow, location: 0),
                        .init(color: Pulse.canvasMid, location: 0.38),
                        .init(color: Pulse.canvas, location: 0.82)
                    ],
                    center: UnitPoint(x: 0.5, y: -0.18),
                    startRadius: 0,
                    endRadius: radius * 0.95
                )
                // A barely-there lift at the very bottom keeps the tab rail
                // and scroll content from reading as pure void on OLED.
                LinearGradient(
                    colors: [.clear, Pulse.canvasMid.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
    }
}

extension View {
    /// Full-screen Midnight Pulse canvas. Use on scroll/screen roots instead
    /// of `.background(MapUI.canvas)`.
    func pulseBackground() -> some View {
        background {
            PulseBackdrop().ignoresSafeArea()
        }
    }

    func pulseCard(
        padding: CGFloat = PulseMetrics.cardPadding,
        radius: CGFloat = PulseMetrics.cardRadius,
        highlight: Bool = false
    ) -> some View {
        self
            .padding(padding)
            .background {
                PulseCardSurface(radius: radius, highlight: highlight)
            }
    }
}

struct PulseCardSurface: View {
    var radius: CGFloat = PulseMetrics.cardRadius
    var highlight: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                highlight
                    ? AnyShapeStyle(Pulse.heroGradient)
                    : AnyShapeStyle(Pulse.cardGradient)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.045), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        highlight ? Pulse.accentDeep.opacity(0.45) : Pulse.lineSoft,
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.32), radius: 18, y: 9)
    }
}

// MARK: - Headers

struct PulseScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(PulseType.eyebrow)
                    .tracking(2)
                    .foregroundStyle(Pulse.accent)
                Text(title)
                    .font(PulseType.display(27))
                    .tracking(-0.7)
                    .foregroundStyle(Pulse.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Pulse.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .contain)
    }
}

extension PulseScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

struct PulseSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title.uppercased())
                .font(PulseType.section)
                .tracking(1.6)
                .foregroundStyle(Pulse.ink)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button {
                    RevertHaptics.tap()
                    action()
                } label: {
                    Text(actionTitle.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Pulse.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}

struct PulseCircleButton: View {
    let systemImage: String
    var tint: Color = Pulse.accent
    var label: String
    var action: () -> Void

    var body: some View {
        Button {
            RevertHaptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 37, height: 37)
                .background(Pulse.iconWell, in: Circle())
                .overlay(Circle().stroke(Pulse.accentLine.opacity(0.7), lineWidth: 0.8))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Cards & metrics

struct PulseMetric: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = Pulse.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Pulse.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(PulseType.number(20, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit.uppercased())
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Pulse.accent)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Pulse.metricWell, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Pulse.line, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PulseTag: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Pulse.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 23)
        .background(Pulse.accentWell.opacity(tint == Pulse.accent ? 1 : 0.55), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.7))
    }
}

struct PulseListRow: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var showsChevron: Bool = true
    var tint: Color = Pulse.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Pulse.ink)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Pulse.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Pulse.muted)
            }
        }
        .padding(14)
        .background(Pulse.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Pulse.line, lineWidth: 0.8)
        }
        .contentShape(Rectangle())
    }
}

struct PulseEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Pulse.accent)
                .frame(width: 76, height: 76)
                .background(Pulse.accent.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(Pulse.accent.opacity(0.22), lineWidth: 0.8))

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Pulse.ink)
            Text(message)
                .font(PulseType.body)
                .foregroundStyle(Pulse.muted)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PulsePrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Buttons

struct PulsePrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .heavy))
            .tracking(0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(Pulse.accentInk)
            .background(Pulse.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
            }
            .shadow(color: Pulse.accent.opacity(0.22), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(RevertMotion.press, value: configuration.isPressed)
    }
}

struct PulseGhostButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 14)
            .foregroundStyle(Pulse.ink.opacity(0.92))
            .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Pulse.lineBright, lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(RevertMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Segmented pills

struct PulseSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    RevertHaptics.select()
                    withAnimation(RevertMotion.snappy) {
                        selection = option
                    }
                } label: {
                    Text(title(option).uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Pulse.accentBright : Pulse.mutedStrong)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            selected ? Pulse.accentWell : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Pulse.panelDeep, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Pulse.line, lineWidth: 0.8)
        }
    }
}

// MARK: - Toggles

struct PulseSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Pulse.accentDeep : Pulse.line)
            .frame(width: 41, height: 24)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Pulse.ink : Pulse.mutedStrong)
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .animation(RevertMotion.snappy, value: isOn)
            .accessibilityHidden(true)
    }
}

struct PulseToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var onChanged: ((Bool) -> Void)? = nil

    var body: some View {
        Button {
            RevertHaptics.select()
            withAnimation(RevertMotion.snappy) {
                isOn.toggle()
            }
            onChanged?(isOn)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Pulse.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Pulse.muted)
                    }
                }
                Spacer(minLength: 8)
                PulseSwitch(isOn: isOn)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Bottom navigation

enum PulseTab: String, CaseIterable, Identifiable {
    case home, routes, ride, garage, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .routes: "Routes"
        case .ride: "Ride"
        case .garage: "Garage"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .routes: "point.topleft.down.curvedto.point.bottomright.up"
        case .ride: "speedometer"
        case .garage: "motorcycle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct PulseTabBar: View {
    let selection: PulseTab
    let onSelect: (PulseTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PulseTab.allCases) { tab in
                let active = tab == selection
                Button {
                    guard !active else { return }
                    RevertHaptics.select()
                    onSelect(tab)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .frame(height: 22)
                        Text(tab.title.uppercased())
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.7)
                    }
                    .foregroundStyle(active ? Pulse.accent : Pulse.tabInactive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Pulse.bar.opacity(0.90))
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Pulse.line.opacity(0.9))
                    .frame(height: 0.8)
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
    }
}
