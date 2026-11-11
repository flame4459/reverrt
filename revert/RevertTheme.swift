import SwiftUI

// MARK: - Revert themes
//
// Five paint schemes for the whole app. The palette is deliberately a single
// value type so every existing `Pulse.*` / `MapUI.*` token can read the
// current scheme at render time instead of being captured once at launch.

enum RevertThemeID: String, CaseIterable, Identifiable {
    case midnightPulse
    case kawasakiLime
    case suzukiGrandPrix
    case yamahaSpeedBlock
    case hondaWinningRed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnightPulse: "Midnight Pulse"
        case .kawasakiLime: "Kawasaki Lime Green"
        case .suzukiGrandPrix: "Suzuki Grand Prix"
        case .yamahaSpeedBlock: "Yamaha Speed Block"
        case .hondaWinningRed: "Honda Winning Red"
        }
    }

    var subtitle: String {
        switch self {
        case .midnightPulse: "Teal light on OLED black"
        case .kawasakiLime: "Lime green on black"
        case .suzukiGrandPrix: "Grand Prix blue and white"
        case .yamahaSpeedBlock: "Yellow and black race blocks"
        case .hondaWinningRed: "Winning red and white"
        }
    }

    var palette: RevertPalette {
        switch self {
        case .midnightPulse: .midnightPulse
        case .kawasakiLime: .kawasakiLime
        case .suzukiGrandPrix: .suzukiGrandPrix
        case .yamahaSpeedBlock: .yamahaSpeedBlock
        case .hondaWinningRed: .hondaWinningRed
        }
    }
}

struct RevertPalette {
    let canvas: Color
    let canvasGlow: Color
    let canvasMid: Color
    let bar: Color

    let panel: Color
    let panelHigh: Color
    let panelLift: Color
    let panelDeep: Color

    let line: Color
    let lineSoft: Color
    let lineBright: Color

    let ink: Color
    let mutedStrong: Color
    let muted: Color
    let tabInactive: Color

    let accent: Color
    let accentBright: Color
    let accentDeep: Color
    let accentInk: Color
    let accentWell: Color
    let accentLine: Color

    /// Primary action buttons. Kept separate from the accent so a bright brand
    /// colour can still produce a readable dark- or light-ink button.
    let buttonStart: Color
    let buttonEnd: Color

    let heroStart: Color
    let heroEnd: Color
    let warning: Color

    var cardGradient: LinearGradient {
        LinearGradient(colors: [panelLift, panelDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accentGradient: LinearGradient {
        LinearGradient(colors: [buttonStart, buttonEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var heroGradient: LinearGradient {
        LinearGradient(colors: [heroStart, heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private func revertColor(_ hex: UInt32) -> Color {
    Color(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255
    )
}

extension RevertPalette {
    // 01 — Midnight Pulse (the original scheme)
    static let midnightPulse = RevertPalette(
        canvas: revertColor(0x04090D),
        canvasGlow: revertColor(0x16343E),
        canvasMid: revertColor(0x08141B),
        bar: revertColor(0x07141B),
        panel: revertColor(0x0C1921),
        panelHigh: revertColor(0x101F29),
        panelLift: revertColor(0x11232D),
        panelDeep: revertColor(0x0A151C),
        line: revertColor(0x213A46),
        lineSoft: revertColor(0x1E3842),
        lineBright: revertColor(0x2A4C57),
        ink: revertColor(0xEAF9FB),
        mutedStrong: revertColor(0x9BB2BA),
        muted: revertColor(0x7794A0),
        tabInactive: revertColor(0x7C9AA3),
        accent: revertColor(0x65F3DF),
        accentBright: revertColor(0x8BF9E9),
        accentDeep: revertColor(0x3DA7AB),
        accentInk: revertColor(0x042123),
        accentWell: revertColor(0x0D3033),
        accentLine: revertColor(0x2C7D80),
        buttonStart: revertColor(0x8BF9E9),
        buttonEnd: revertColor(0x3DA7AB),
        heroStart: revertColor(0x102F37),
        heroEnd: revertColor(0x0D1922),
        warning: revertColor(0xFFBE78)
    )

    // 02 — Kawasaki Lime Green
    static let kawasakiLime = RevertPalette(
        canvas: revertColor(0x050803),
        canvasGlow: revertColor(0x1D3413),
        canvasMid: revertColor(0x0A1207),
        bar: revertColor(0x081006),
        panel: revertColor(0x101A0D),
        panelHigh: revertColor(0x152213),
        panelLift: revertColor(0x192A16),
        panelDeep: revertColor(0x0C150B),
        line: revertColor(0x2A3C24),
        lineSoft: revertColor(0x25361F),
        lineBright: revertColor(0x37502D),
        ink: revertColor(0xF4FBEA),
        mutedStrong: revertColor(0xB2C6A3),
        muted: revertColor(0x8AA37C),
        tabInactive: revertColor(0x8DA57F),
        accent: revertColor(0xB6FF3C),
        accentBright: revertColor(0xD6FF85),
        accentDeep: revertColor(0x5FA800),
        accentInk: revertColor(0x0A1400),
        accentWell: revertColor(0x1B2B0B),
        accentLine: revertColor(0x4E7A1F),
        buttonStart: revertColor(0xC7FF5A),
        buttonEnd: revertColor(0x6FBF00),
        heroStart: revertColor(0x1C2E12),
        heroEnd: revertColor(0x0E170A),
        warning: revertColor(0xFFC66B)
    )

    // 03 — Suzuki Grand Prix Blue and White
    static let suzukiGrandPrix = RevertPalette(
        canvas: revertColor(0x050912),
        canvasGlow: revertColor(0x12305C),
        canvasMid: revertColor(0x081226),
        bar: revertColor(0x060E1C),
        panel: revertColor(0x0C1526),
        panelHigh: revertColor(0x101D33),
        panelLift: revertColor(0x14233D),
        panelDeep: revertColor(0x0A1322),
        line: revertColor(0x22385A),
        lineSoft: revertColor(0x1E3352),
        lineBright: revertColor(0x2E4A75),
        ink: revertColor(0xF2F7FF),
        mutedStrong: revertColor(0xA8BDD9),
        muted: revertColor(0x7C94B5),
        tabInactive: revertColor(0x8197B4),
        accent: revertColor(0x4C8DFF),
        accentBright: revertColor(0x8FBAFF),
        accentDeep: revertColor(0x1D4FBD),
        accentInk: revertColor(0xFFFFFF),
        accentWell: revertColor(0x0D1F44),
        accentLine: revertColor(0x2F5FA8),
        buttonStart: revertColor(0x2F6BE0),
        buttonEnd: revertColor(0x1740A8),
        heroStart: revertColor(0x12284D),
        heroEnd: revertColor(0x0A1830),
        warning: revertColor(0xFFC66B)
    )

    // 04 — Yamaha "Speed Block" Yellow/Black
    static let yamahaSpeedBlock = RevertPalette(
        canvas: revertColor(0x080705),
        canvasGlow: revertColor(0x2B2611),
        canvasMid: revertColor(0x0F0D08),
        bar: revertColor(0x0C0B07),
        panel: revertColor(0x14120B),
        panelHigh: revertColor(0x1A1810),
        panelLift: revertColor(0x1F1C12),
        panelDeep: revertColor(0x100F09),
        line: revertColor(0x3A3420),
        lineSoft: revertColor(0x332E1D),
        lineBright: revertColor(0x4A4229),
        ink: revertColor(0xFFF9E8),
        mutedStrong: revertColor(0xC9C0A8),
        muted: revertColor(0x9C937D),
        tabInactive: revertColor(0x9E967F),
        accent: revertColor(0xFFD400),
        accentBright: revertColor(0xFFE97A),
        accentDeep: revertColor(0xC79A00),
        accentInk: revertColor(0x171200),
        accentWell: revertColor(0x2B2408),
        accentLine: revertColor(0x7A6414),
        buttonStart: revertColor(0xFFE14D),
        buttonEnd: revertColor(0xD4A600),
        heroStart: revertColor(0x2A2510),
        heroEnd: revertColor(0x141208),
        warning: revertColor(0xFF9F5A)
    )

    // 05 — Honda Winning Red
    static let hondaWinningRed = RevertPalette(
        canvas: revertColor(0x0A0506),
        canvasGlow: revertColor(0x38141A),
        canvasMid: revertColor(0x14080B),
        bar: revertColor(0x100609),
        panel: revertColor(0x190B0E),
        panelHigh: revertColor(0x211015),
        panelLift: revertColor(0x271318),
        panelDeep: revertColor(0x140A0C),
        line: revertColor(0x452028),
        lineSoft: revertColor(0x3D1C23),
        lineBright: revertColor(0x5A2A33),
        ink: revertColor(0xFFF4F4),
        mutedStrong: revertColor(0xD6B4B8),
        muted: revertColor(0xA98A8E),
        tabInactive: revertColor(0xAC8C90),
        accent: revertColor(0xFF3B47),
        accentBright: revertColor(0xFF7A82),
        accentDeep: revertColor(0xB00012),
        accentInk: revertColor(0xFFFFFF),
        accentWell: revertColor(0x330A10),
        accentLine: revertColor(0x7A1A24),
        buttonStart: revertColor(0xDE1120),
        buttonEnd: revertColor(0x9C000C),
        heroStart: revertColor(0x331017),
        heroEnd: revertColor(0x1A0A0D),
        warning: revertColor(0xFFC66B)
    )
}

// MARK: - Store

@MainActor
@Observable
final class RevertThemeStore {
    static let shared = RevertThemeStore()
    private static let defaultsKey = "appearance.colorScheme"

    private(set) var theme: RevertThemeID

    var palette: RevertPalette { theme.palette }

    private init() {
        var resolved = RevertThemeID(
            rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        ) ?? .midnightPulse

        #if DEBUG
        // Screenshot / QA override without changing the saved preference.
        if let index = CommandLine.arguments.firstIndex(of: "-theme"),
           CommandLine.arguments.indices.contains(index + 1),
           let debugTheme = RevertThemeID(rawValue: CommandLine.arguments[index + 1]) {
            resolved = debugTheme
        }
        #endif

        theme = resolved
    }

    func select(_ theme: RevertThemeID) {
        guard theme != self.theme else { return }
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
    }
}

// MARK: - Picker

/// The five-scheme picker used by Settings. Selecting a scheme applies it to
/// the whole app immediately; the choice is persisted on this iPhone.
struct ColorSchemePicker: View {
    private var store: RevertThemeStore { RevertThemeStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(RevertThemeID.allCases) { theme in
                let selected = store.theme == theme

                Button {
                    withAnimation(RevertMotion.smooth) {
                        store.select(theme)
                    }
                    RevertHaptics.select()
                } label: {
                    HStack(spacing: 12) {
                        RevertThemeSwatch(palette: theme.palette)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(theme.title)
                                .font(.system(size: 13, weight: selected ? .bold : .semibold))
                                .foregroundStyle(Pulse.ink)
                            Text(theme.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(Pulse.muted)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected ? Pulse.accent : Pulse.muted)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(theme.title), \(theme.subtitle)")
                .accessibilityAddTraits(selected ? .isSelected : [])

                if theme != RevertThemeID.allCases.last {
                    Rectangle()
                        .fill(Pulse.lineSoft)
                        .frame(height: 0.8)
                        .padding(.leading, 64)
                }
            }
        }
    }
}

struct RevertThemeSwatch: View {
    let palette: RevertPalette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardGradient)

            VStack(alignment: .leading, spacing: 3) {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 25, height: 4)
                Capsule()
                    .fill(palette.accentDeep)
                    .frame(width: 15, height: 3)
            }
            .padding(7)
        }
        .frame(width: 52, height: 40)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.lineBright, lineWidth: 0.8)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(palette.ink.opacity(0.85))
                .frame(width: 5, height: 5)
                .padding(7)
        }
        .accessibilityHidden(true)
    }
}
