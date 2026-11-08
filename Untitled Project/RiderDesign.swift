import SwiftUI
import UIKit

// MARK: - Layout & motion tokens

/// One spacing/radius scale for the whole app. The cockpit screens use the
/// compact values, the sheet-based screens use the regular ones.
enum RiderMetrics {
    static let screenPadding: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let compactPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 12
    static let tightSpacing: CGFloat = 8

    static let controlSize: CGFloat = 48
    static let dockButtonSize: CGFloat = 44
    static let touchTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 54

    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let sheetRadius: CGFloat = 32
    static let dockRadius: CGFloat = 24
}

enum RiderMotion {
    static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.84)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let soft = Animation.easeInOut(duration: 0.24)
    static let press = Animation.easeOut(duration: 0.14)

    static func optional(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

enum RiderHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}

// MARK: - Palette extensions

extension MapUI {
    /// True-black app canvas. Kept separate from `groupedBackground` so the
    /// OLED surfaces can sit on a slightly lifted charcoal instead of void.
    static let canvas = Color(red: 5 / 255, green: 7 / 255, blue: 11 / 255)
    static let surface = Color(red: 12 / 255, green: 16 / 255, blue: 23 / 255)
    static let surfaceHigh = Color(red: 18 / 255, green: 24 / 255, blue: 33 / 255)
    static let surfaceLift = Color(red: 25 / 255, green: 33 / 255, blue: 45 / 255)

    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.16)
    static let textSecondary = Color.white.opacity(0.66)
    // 0.42 measured just under 4.5:1 on the OLED canvas; captions at this
    // size need the extra lift for WCAG AA contrast.
    static let textTertiary = Color.white.opacity(0.52)

    static let amber = Color(red: 255 / 255, green: 186 / 255, blue: 72 / 255)
    static let violet = Color(red: 170 / 255, green: 134 / 255, blue: 255 / 255)
    static let coral = Color(red: 255 / 255, green: 104 / 255, blue: 120 / 255)
    static let ice = Color(red: 213 / 255, green: 244 / 255, blue: 255 / 255)

    static let aurora = LinearGradient(
        colors: [cyan, emerald],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let ember = LinearGradient(
        colors: [amber, orange, coral],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let panelSheen = LinearGradient(
        colors: [Color.white.opacity(0.09), Color.white.opacity(0.015), MapUI.cyan.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Surfaces

/// The standard lifted card: near-black glass, a hairline rim and a very soft
/// cyan catch-light. Used instead of scattering ad-hoc materials.
struct RiderPanelSurface: View {
    var radius: CGFloat = RiderMetrics.cardRadius
    var tint: Color = MapUI.surface
    var elevated: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: elevated
                        ? [tint.opacity(0.98), MapUI.panel.opacity(0.98)]
                        : [MapUI.panel.opacity(0.96), MapUI.panel.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(MapUI.panelSheen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.03), MapUI.cyan.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
            .shadow(color: .black.opacity(0.38), radius: 20, y: 10)
    }
}

extension View {
    func riderPanel(radius: CGFloat = RiderMetrics.cardRadius, tint: Color = MapUI.surface) -> some View {
        background(RiderPanelSurface(radius: radius, tint: tint))
    }

    func riderCard(padding: CGFloat = RiderMetrics.cardPadding,
                   radius: CGFloat = RiderMetrics.cardRadius,
                   tint: Color = MapUI.surface) -> some View {
        self
            .padding(padding)
            .riderPanel(radius: radius, tint: tint)
    }

    func riderGlow(_ tint: Color, radius: CGFloat = 16, opacity: Double = 0.28, y: CGFloat = 6) -> some View {
        shadow(color: tint.opacity(opacity), radius: radius, y: y)
    }
}

struct RiderGlassBackground: View {
    var radius: CGFloat = RiderMetrics.cardRadius
    var material: Material = .ultraThinMaterial
    var tint: Color = MapUI.panel

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(material)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.opacity(0.78))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MapUI.lineStrong, lineWidth: 0.8)
            }
    }
}

/// Top/bottom vignette that keeps map content readable behind floating HUDs.
struct RiderMapScrim: View {
    var topOpacity: Double = 0.55
    var bottomOpacity: Double = 0.72

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(topOpacity), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, .black.opacity(bottomOpacity)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Typography helpers

enum RiderType {
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static var eyebrow: Font {
        .system(size: 10, weight: .heavy, design: .rounded)
    }

    static var title: Font {
        .system(.title2, design: .rounded).weight(.bold)
    }

    static var headline: Font {
        .system(.headline, design: .rounded).weight(.bold)
    }

    static var body: Font {
        .system(.subheadline, design: .rounded)
    }
}

// MARK: - Headers

struct RiderScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color
    let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = MapUI.cyan,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RiderIconBadge(systemImage: systemImage, tint: tint, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(RiderType.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(tint)
                Text(title)
                    .font(RiderType.title)
                    .foregroundStyle(MapUI.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .combine)
    }
}

extension RiderScreenHeader where Trailing == EmptyView {
    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = MapUI.cyan
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            trailing: { EmptyView() }
        )
    }
}

struct RiderSectionLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(MapUI.textSecondary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MapUI.textTertiary)
            }
        }
    }
}

struct RiderCardHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = MapUI.cyan
    var trailingText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            RiderIconBadge(systemImage: icon, tint: tint, size: 34, radius: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(RiderType.headline)
                    .foregroundStyle(MapUI.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MapUI.textSecondary)
                }
            }
            Spacer(minLength: 6)
            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
        }
    }
}

struct RiderIconBadge: View {
    let systemImage: String
    var tint: Color = MapUI.cyan
    var size: CGFloat = 40
    var radius: CGFloat = 13

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.40, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.20), tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 0.8)
            }
    }
}

// MARK: - Buttons

struct RiderPrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = MapUI.accentGradient
    var glow: Color = MapUI.cyan
    var minHeight: CGFloat = RiderMetrics.primaryButtonHeight
    var compact: Bool = false
    var stretch: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .subheadline : .headline, design: .rounded).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: stretch ? .infinity : nil, minHeight: minHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(gradient, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: glow.opacity(0.30), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(RiderMotion.press, value: configuration.isPressed)
    }
}

struct RiderSecondaryButtonStyle: ButtonStyle {
    var tint: Color = MapUI.ink
    var minHeight: CGFloat = RiderMetrics.primaryButtonHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(tint)
            .background(MapUI.surfaceHigh.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(MapUI.lineStrong, lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(RiderMotion.press, value: configuration.isPressed)
    }
}

struct RiderIconButtonStyle: ButtonStyle {
    var tint: Color = MapUI.ink
    var diameter: CGFloat = RiderMetrics.controlSize
    var active: Bool = false
    var filled: Bool = false
    var fill: Color = MapUI.surfaceHigh

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(filled ? .white : (active ? MapUI.cyan : tint))
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(filled ? AnyShapeStyle(MapUI.accentGradient) : AnyShapeStyle(fill.opacity(active ? 0.92 : 0.82)))
            }
            .overlay {
                Circle()
                    .stroke(active ? MapUI.cyan.opacity(0.55) : MapUI.lineStrong, lineWidth: 0.8)
            }
            .shadow(color: active ? MapUI.cyan.opacity(0.28) : .black.opacity(0.30), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(RiderMotion.press, value: configuration.isPressed)
    }
}

/// Press treatment for large tappable cards without stealing button semantics.
struct RiderCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.02 : 0)
            .animation(RiderMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Chips, pills & stats

struct RiderChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var tint: Color = MapUI.cyan
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                RiderHaptics.select()
                action()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? .black : (action == nil ? MapUI.textSecondary : MapUI.ink))
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .background(
            isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(MapUI.surfaceHigh.opacity(0.92)),
            in: Capsule()
        )
        .overlay {
            Capsule().stroke(isSelected ? tint.opacity(0.8) : MapUI.line, lineWidth: 0.8)
        }
    }
}

struct RiderStatusPill: View {
    let text: String
    var tint: Color = MapUI.emerald
    var pulsing: Bool = false

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.8), radius: pulsing && pulse ? 5 : 0)
                .opacity(pulsing ? (pulse ? 1 : 0.5) : 1)
            Text(text.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 0.7))
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct RiderMetricPill: View {
    let systemImage: String
    let text: String
    var tint: Color = MapUI.textSecondary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct RiderStatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var systemImage: String? = nil
    var tint: Color = MapUI.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.1)
            }
            .foregroundStyle(MapUI.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(RiderType.number(20))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RiderInfoNote: View {
    let text: String
    var systemImage: String = "info.circle"
    var tint: Color = MapUI.textTertiary

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .padding(.top, 1)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(tint)
    }
}

// MARK: - Option picker (replaces stock segmented controls)

struct RiderOptionPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var systemImage: ((Option) -> String)? = nil
    var tint: Color = MapUI.cyan

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    RiderHaptics.select()
                    withAnimation(RiderMotion.snappy) {
                        selection = option
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage {
                            Image(systemName: systemImage(option))
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(title(option))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selected ? .black : MapUI.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        selected ? AnyShapeStyle(tint) : AnyShapeStyle(MapUI.surfaceHigh.opacity(0.86)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? tint.opacity(0.7) : MapUI.line, lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Menu picker (long option lists)

struct RiderMenuPicker<Value: Hashable>: View {
    let title: String
    var systemImage: String? = nil
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var tint: Color = MapUI.cyan

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "—"
    }

    var body: some View {
        HStack(spacing: 9) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.10), in: Circle())
            }

            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.ink)

            Spacer(minLength: 6)

            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        RiderHaptics.select()
                        selection = option.value
                    } label: {
                        if option.value == selection {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(MapUI.surfaceHigh, in: Capsule())
                .overlay(Capsule().stroke(MapUI.line, lineWidth: 0.8))
            }
            .accessibilityLabel(title)
            .accessibilityValue(currentLabel)
        }
    }
}

// MARK: - Progress

struct RiderProgressBar: View {
    var value: Double
    var tint: LinearGradient = MapUI.aurora
    var height: CGFloat = 5
    var track: Color = Color.white.opacity(0.10)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * value)))
                    .shadow(color: MapUI.cyan.opacity(0.35), radius: 5)
            }
        }
        .frame(height: height)
        .animation(RiderMotion.smooth, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
    }
}

// MARK: - Map control dock

/// A single glass rail for map controls. Keeping every map action in one dock
/// removes the scattered, mismatched floating buttons while preserving a
/// glove-sized hit target.
struct RiderMapDock<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 2) {
            content
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RiderMetrics.dockRadius, style: .continuous))
        .background(MapUI.panel.opacity(0.82), in: RoundedRectangle(cornerRadius: RiderMetrics.dockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RiderMetrics.dockRadius, style: .continuous)
                .strokeBorder(MapUI.lineStrong, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.34), radius: 14, y: 6)
    }
}

struct RiderMapDockButton: View {
    let systemImage: String
    let label: String
    var tint: Color = MapUI.ink
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            RiderHaptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? MapUI.cyan : tint)
                .frame(width: RiderMetrics.dockButtonSize, height: RiderMetrics.dockButtonSize)
                .background(
                    active ? MapUI.cyan.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(RiderCardButtonStyle())
        .accessibilityLabel(label)
    }
}

struct RiderMapDockDivider: View {
    var body: some View {
        Rectangle()
            .fill(MapUI.line)
            .frame(width: 20, height: 1)
            .padding(.vertical, 2)
    }
}

// MARK: - Sheet chrome

struct RiderGrabber: View {
    var body: some View {
        Capsule()
            .fill(MapUI.textTertiary)
            .frame(width: 38, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

struct RiderSheetHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)? = nil
    var closeLabel: String = "Close"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(RiderType.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(MapUI.cyan)
                Text(title)
                    .font(RiderType.display(28, weight: .heavy))
                    .foregroundStyle(MapUI.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let onClose {
                Button {
                    RiderHaptics.tap()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RiderIconButtonStyle(tint: MapUI.textSecondary, diameter: 38))
                .accessibilityLabel(closeLabel)
            }
        }
    }
}

// MARK: - Empty state

struct RiderEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryTitle: String? = nil
    var primarySystemImage: String = "play.fill"
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MapUI.cyan.opacity(0.08))
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(MapUI.cyan.opacity(0.22), lineWidth: 0.8)
                    .frame(width: 92, height: 92)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(MapUI.cyan)
            }
            .padding(.bottom, 2)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(MapUI.ink)
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(MapUI.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)

            if let primaryTitle, let primaryAction {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySystemImage)
                }
                .buttonStyle(RiderPrimaryButtonStyle())
                .padding(.top, 4)
            }

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                }
                .buttonStyle(RiderSecondaryButtonStyle())
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Small helpers

struct RiderDot: View {
    var tint: Color = MapUI.cyan
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.7), radius: 4)
    }
}

struct RiderKeyValueRow: View {
    let label: String
    let value: String
    var tint: Color = MapUI.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
