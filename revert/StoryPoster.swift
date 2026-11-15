import SwiftUI
import CoreLocation
import UIKit

enum StoryPosterTheme: String, CaseIterable, Identifiable {
    case oled
    case sunset
    case topo
    case paper
    case neon
    case desert
    case alpine
    case coast
    case mono
    case carbon
    case vapor
    case forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oled: "OLED cockpit"
        case .sunset: "Sunset pass"
        case .topo: "Topo map"
        case .paper: "Ride journal"
        case .neon: "Neon grid"
        case .desert: "Desert run"
        case .alpine: "Alpine pass"
        case .coast: "Coast road"
        case .mono: "Monochrome"
        case .carbon: "Carbon"
        case .vapor: "Vaporwave"
        case .forest: "Forest pass"
        }
    }

    var isLight: Bool {
        switch self {
        case .paper, .desert, .alpine: true
        default: false
        }
    }

    var background: [Color] {
        switch self {
        case .oled: [.black, Color(red: 0.02, green: 0.06, blue: 0.09)]
        case .sunset: [Color(red: 0.12, green: 0.04, blue: 0.12), Color(red: 0.48, green: 0.12, blue: 0.09)]
        case .topo: [Color(red: 0.03, green: 0.12, blue: 0.10), Color(red: 0.02, green: 0.05, blue: 0.06)]
        case .paper: [Color(red: 0.93, green: 0.90, blue: 0.82), Color(red: 0.80, green: 0.76, blue: 0.66)]
        case .neon: [Color(red: 0.04, green: 0.00, blue: 0.08), Color(red: 0.15, green: 0.00, blue: 0.30)]
        case .desert: [Color(red: 0.96, green: 0.86, blue: 0.72), Color(red: 0.85, green: 0.60, blue: 0.39)]
        case .alpine: [Color(red: 0.93, green: 0.96, blue: 0.99), Color(red: 0.72, green: 0.83, blue: 0.91)]
        case .coast: [Color(red: 0.02, green: 0.11, blue: 0.14), Color(red: 0.04, green: 0.23, blue: 0.27)]
        case .mono: [Color(red: 0.04, green: 0.04, blue: 0.04), Color(red: 0.15, green: 0.15, blue: 0.15)]
        case .carbon: [Color(red: 0.06, green: 0.08, blue: 0.06), Color(red: 0.13, green: 0.18, blue: 0.10)]
        case .vapor: [Color(red: 0.10, green: 0.04, blue: 0.18), Color(red: 0.23, green: 0.08, blue: 0.33)]
        case .forest: [Color(red: 0.03, green: 0.10, blue: 0.07), Color(red: 0.07, green: 0.20, blue: 0.15)]
        }
    }

    var accent: Color {
        switch self {
        case .oled: MapUI.cyan
        case .sunset: Color(red: 1.0, green: 0.55, blue: 0.22)
        case .topo: MapUI.emerald
        case .paper: Color(red: 0.12, green: 0.30, blue: 0.24)
        case .neon: Color(red: 1.0, green: 0.24, blue: 0.65)
        case .desert: Color(red: 0.55, green: 0.23, blue: 0.12)
        case .alpine: Color(red: 0.12, green: 0.37, blue: 0.55)
        case .coast: Color(red: 1.0, green: 0.54, blue: 0.36)
        case .mono: Color(red: 0.95, green: 0.95, blue: 0.95)
        case .carbon: Color(red: 0.78, green: 1.0, blue: 0.24)
        case .vapor: Color(red: 1.0, green: 0.42, blue: 0.84)
        case .forest: Color(red: 0.72, green: 0.91, blue: 0.53)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .oled: MapUI.emerald
        case .sunset: Color(red: 1.0, green: 0.84, blue: 0.45)
        case .topo: Color(red: 0.55, green: 0.95, blue: 0.70)
        case .paper: Color(red: 0.55, green: 0.22, blue: 0.10)
        case .neon: Color(red: 0.29, green: 0.91, blue: 1.0)
        case .desert: Color(red: 0.18, green: 0.44, blue: 0.41)
        case .alpine: Color(red: 0.42, green: 0.62, blue: 0.37)
        case .coast: Color(red: 0.44, green: 0.89, blue: 0.82)
        case .mono: Color(red: 0.62, green: 0.62, blue: 0.62)
        case .carbon: Color(red: 0.43, green: 0.55, blue: 0.35)
        case .vapor: Color(red: 0.50, green: 1.0, blue: 0.83)
        case .forest: Color(red: 0.31, green: 0.66, blue: 0.48)
        }
    }

    var ink: Color {
        switch self {
        case .paper: Color(red: 0.10, green: 0.10, blue: 0.09)
        case .desert: Color(red: 0.17, green: 0.10, blue: 0.07)
        case .alpine: Color(red: 0.06, green: 0.16, blue: 0.23)
        default: .white
        }
    }

    var secondaryInk: Color {
        isLight ? ink.opacity(0.60) : Color.white.opacity(0.62)
    }

    var cardFill: Color {
        isLight ? Color.white.opacity(0.42) : Color.white.opacity(0.06)
    }

    var cardStroke: Color {
        ink.opacity(0.14)
    }
}

enum StoryPosterStyle: String, CaseIterable, Identifiable {
    case classic
    case minimal
    case dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .dashboard: "Dashboard"
        }
    }

    var blurb: String {
        switch self {
        case .classic: "The original hero layout, with the full route in the middle."
        case .minimal: "A full-bleed route with big type and no clutter."
        case .dashboard: "A framed route card and a dense grid of ride numbers."
        }
    }
}

struct StoryPosterView: View {
    let ride: Ride
    let points: [RidePoint]
    let turns: [RideTurn]
    let theme: StoryPosterTheme
    var style: StoryPosterStyle = .classic

    private var averageSpeed: Double {
        ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
    }

    private var topSpeed: Double { ride.maxSpeedMps }
    private var maxLean: Double {
        max(ride.maxLeanAngleDegrees, points.map { abs($0.lean ?? 0) }.max() ?? 0)
    }

    private var baseline: Color { theme.background.first ?? .black }

    var body: some View {
        ZStack {
            background
            layout
        }
        .frame(width: 1080, height: 1350)
    }

    @ViewBuilder
    private var layout: some View {
        switch style {
        case .classic: classicLayout
        case .minimal: minimalLayout
        case .dashboard: dashboardLayout
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                var path = Path()
                let step: CGFloat = style == .minimal ? 84 : 54
                var x: CGFloat = 0
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(theme.ink.opacity(theme.isLight ? 0.06 : 0.035)),
                               lineWidth: 1)
            }
        }
    }

    // MARK: Layouts

    private var classicLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow
            Spacer(minLength: 34)
            titleText
            bikeLine.padding(.top, 10)
            routeCanvas
                .frame(height: 420)
                .padding(.vertical, 26)
            Spacer(minLength: 12)
            metricsGrid
            Spacer(minLength: 18)
            footerRow
            credit.padding(.top, 14)
        }
        .padding(54)
    }

    private var minimalLayout: some View {
        ZStack {
            routeCanvas
            LinearGradient(
                stops: [
                    .init(color: baseline.opacity(0.90), location: 0),
                    .init(color: baseline.opacity(0.0), location: 0.26),
                    .init(color: baseline.opacity(0.0), location: 0.48),
                    .init(color: baseline.opacity(0.94), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                brandRow
                Spacer(minLength: 0)
                Text(ride.routeName ?? "A ride worth remembering")
                    .font(.scaledSystem(size: 76, weight: .black, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.55)
                bikeLine.padding(.top, 12)
                Rectangle()
                    .fill(theme.ink.opacity(0.22))
                    .frame(height: 1)
                    .padding(.vertical, 22)
                HStack(alignment: .top, spacing: 0) {
                    posterMetric(Units.distanceText(ride.distanceMeters, decimals: 1), "DISTANCE")
                    posterMetric(Units.clock(ride.movingTimeSeconds), "MOVING TIME")
                    if ride.isCar {
                        posterMetric("\(max(ride.laps, 1))", ride.laps == 1 ? "LAP" : "LAPS")
                    } else {
                        if ride.isCar {
                    posterMetric("\(max(ride.laps, 1))", ride.laps == 1 ? "LAP" : "LAPS")
                } else {
                    posterMetric("\(Int(maxLean.rounded()))°", "MAX LEAN")
                }
                    }
                }
                footerRow.padding(.top, 24)
                credit.padding(.top, 12)
            }
            .padding(64)
        }
    }

    private var dashboardLayout: some View {
        VStack(alignment: .leading, spacing: 26) {
            brandRow

            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(theme.cardFill)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(theme.cardStroke, lineWidth: 1.5)

                routeCanvas.padding(26)

                VStack {
                    HStack(alignment: .top) {
                        Text(ride.isSprint ? "SPRINT" : "\(max(ride.laps, 1)) LAP\(ride.laps == 1 ? "" : "S")")
                            .font(.scaledSystem(size: 11, weight: .heavy, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(theme.accent)
                        Spacer()
                        Text("NO SIGNAL")
                            .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(26)
            }
            .frame(height: 560)

            VStack(alignment: .leading, spacing: 2) {
                titleText
                bikeLine.padding(.top, 8)
            }

            metricsGrid

            Spacer(minLength: 0)
            footerRow
            credit.padding(.top, 10)
        }
        .padding(54)
    }

    // MARK: Shared pieces

    private var brandRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("REVERT")
                    .font(.scaledSystem(size: 28, weight: .black, design: .rounded))
                    .tracking(7)
                    .foregroundStyle(theme.accent)
                Text(ride.isCar ? "DRIVE STORY" : "RIDE STORY")
                    .font(.scaledSystem(size: 13, weight: .bold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(theme.secondaryInk)
            }
            Spacer()
            Text(ride.startDate.formatted(date: .abbreviated, time: .omitted).uppercased())
                .font(.scaledSystem(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.ink)
        }
    }

    private var titleText: some View {
        Text(ride.routeName ?? "A ride worth remembering")
            .font(.scaledSystem(size: 52, weight: .black, design: .rounded))
            .foregroundStyle(theme.ink)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
    }

    private var bikeLine: some View {
        Text(ride.bikeDisplayName.uppercased())
            .font(.scaledSystem(size: 17, weight: .bold, design: .rounded))
            .tracking(3)
            .foregroundStyle(theme.accent)
    }

    private var routeCanvas: some View {
        RoutePosterCanvas(points: points, turns: turns, accent: theme.accent,
                          secondary: theme.secondaryAccent, ink: theme.ink)
    }

    private var metricsGrid: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 0) {
                posterMetric(Units.distanceText(ride.distanceMeters, decimals: 1), "DISTANCE")
                posterMetric(Units.clock(ride.movingTimeSeconds), "MOVING TIME")
                if ride.isCar {
                    posterMetric(Units.elevationText(ride.elevationGainMeters), "CLIMBED")
                } else {
                    posterMetric("\(turns.count)", turns.count == 1 ? "CORNER" : "CORNERS")
                }
            }
            HStack(alignment: .top, spacing: 0) {
                posterMetric(Units.speedText(averageSpeed), "AVERAGE")
                posterMetric(Units.speedText(topSpeed), "TOP SPEED")
                posterMetric("\(Int(maxLean.rounded()))°", "MAX LEAN")
            }
        }
    }

    private var footerRow: some View {
        HStack {
            Text(ride.isCar
                 ? "\(max(ride.laps, 1)) lap\(ride.laps == 1 ? "" : "s") · \(Units.elevationText(ride.elevationGainMeters)) climbed"
                 : "\(Int(turns.filter { $0.direction > 0 }.count)) right · \(Int(turns.filter { $0.direction < 0 }.count)) left · \(Units.elevationText(ride.elevationGainMeters)) climbed")
                .font(.scaledSystem(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryInk)
            Spacer()
            Text("NO SIGNAL NEEDED")
                .font(.scaledSystem(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(theme.accent.opacity(0.8))
        }
    }

    private var credit: some View {
        Text("WHOOPTEH")
            .font(.scaledSystem(size: 10, weight: .black, design: .rounded))
            .tracking(5)
            .foregroundStyle(theme.secondaryInk.opacity(0.5))
    }

    private func posterMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.scaledSystem(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.scaledSystem(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoutePosterCanvas: View {
    let points: [RidePoint]
    let turns: [RideTurn]
    let accent: Color
    let secondary: Color
    let ink: Color

    var body: some View {
        Canvas { context, size in
            let path = routePath(in: size)
            guard !path.isEmpty else { return }
            // Glow underlay.
            context.stroke(path, with: .color(accent.opacity(0.22)), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(accent.opacity(0.45)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            context.stroke(
                path,
                with: .linearGradient(Gradient(colors: [accent, secondary]),
                                      startPoint: .zero,
                                      endPoint: CGPoint(x: size.width, y: size.height)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )

            if let startCoordinate = points.first?.coordinate,
               let first = project(startCoordinate, in: size) {
                let dot = Path(ellipseIn: CGRect(x: first.x - 7, y: first.y - 7, width: 14, height: 14))
                context.fill(dot, with: .color(ink))
                context.stroke(Path(ellipseIn: CGRect(x: first.x - 9, y: first.y - 9, width: 18, height: 18)),
                               with: .color(accent), lineWidth: 2)
            }

            for turn in turns.prefix(60) {
                guard let point = project(turn.coordinate, in: size) else { continue }
                let r: CGFloat = 4
                let dot = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(secondary.opacity(0.9)))
            }
        }
    }

    private func routePath(in size: CGSize) -> Path {
        var path = Path()
        var started = false
        let stride = max(1, points.count / 900)
        for index in Swift.stride(from: 0, to: points.count, by: stride) {
            guard let point = project(points[index].coordinate, in: size) else { continue }
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        return path
    }

    private func project(_ coordinate: CLLocationCoordinate2D, in size: CGSize) -> CGPoint? {
        guard let bounds = bounds else { return nil }
        let padding: CGFloat = 24
        let width = max(bounds.width, 1e-6)
        let height = max(bounds.height, 1e-6)
        let scale = min((size.width - padding * 2) / width, (size.height - padding * 2) / height)
        let x = (coordinate.longitude - bounds.minLon) / width
        let y = (coordinate.latitude - bounds.minLat) / height
        return CGPoint(x: padding + x * width * scale,
                       y: size.height - padding - y * height * scale)
    }

    private var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, width: Double, height: Double)? {
        guard let first = points.first?.coordinate else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        let width = max((maxLon - minLon) * cos((minLat + maxLat) / 2 * .pi / 180), 1e-6)
        let height = max(maxLat - minLat, 1e-6)
        return (minLat, maxLat, minLon, maxLon, width, height)
    }
}

struct StoryPosterStudio: View {
    @Environment(\.dismiss) private var dismiss
    let ride: Ride
    let points: [RidePoint]
    let turns: [RideTurn]

    @State private var theme: StoryPosterTheme
    @State private var style: StoryPosterStyle
    @State private var posterURL: URL?
    @State private var rendering = false
    @State private var renderError: String?

    private let posterSize = CGSize(width: 1080, height: 1350)

    init(ride: Ride,
         points: [RidePoint],
         turns: [RideTurn],
         initialTheme: StoryPosterTheme = .oled,
         initialStyle: StoryPosterStyle = .classic) {
        self.ride = ride
        self.points = points
        self.turns = turns
        _theme = State(initialValue: initialTheme)
        _style = State(initialValue: initialStyle)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RevertScreenHeader(
                        eyebrow: "EXPORT STUDIO",
                        title: "Story poster",
                        subtitle: "Render a 1080 × 1350 poster from the recorded ride. Everything is generated on this iPhone.",
                        systemImage: "photo.artframe"
                    )

                    VStack(spacing: 10) {
                        StoryPosterView(ride: ride, points: points, turns: turns,
                                        theme: theme, style: style)
                            .scaleEffect(0.30, anchor: .center)
                            .frame(width: posterSize.width * 0.30, height: posterSize.height * 0.30)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(MapUI.lineStrong, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)

                        Text("1080 × 1350  •  optimized for stories")
                            .font(.scaledSystem(size: 9, weight: .semibold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .revertPanel(radius: 24)

                    VStack(alignment: .leading, spacing: 9) {
                        RevertSectionLabel(title: "Theme", detail: theme.title)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                            GridItem(.flexible(), spacing: 8)],
                                  spacing: 8) {
                            ForEach(StoryPosterTheme.allCases) { option in
                                themeButton(option)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        RevertSectionLabel(title: "Layout", detail: style.title)
                        RevertOptionPicker(
                            options: StoryPosterStyle.allCases,
                            selection: $style,
                            title: { $0.title }
                        )
                        Text(style.blurb)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    RevertInfoNote(
                        text: "The poster stays in this iPhone's temporary folder until you share it.",
                        systemImage: "iphone",
                        tint: MapUI.textTertiary
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .pulseBackground()
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close poster studio")
                }
            }
        }
        .preferredColorScheme(.dark)
        // The preview redraws instantly, but the PNG behind "Share poster"
        // belongs to the old theme. Invalidate it so a rider cannot share a
        // poster that no longer matches what they see.
        .onChange(of: theme) { _, _ in
            posterURL = nil
        }
        .onChange(of: style) { _, _ in
            posterURL = nil
        }
        .alert("Couldn't render the poster", isPresented: Binding(
            get: { renderError != nil },
            set: { if !$0 { renderError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renderError ?? "")
        }
    }

    private func themeButton(_ option: StoryPosterTheme) -> some View {
        let selected = option == theme
        return Button {
            RevertHaptics.select()
            withAnimation(RevertMotion.snappy) { theme = option }
        } label: {
            HStack(spacing: 8) {
                LinearGradient(colors: option.background,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(option.ink.opacity(0.25), lineWidth: 0.8))

                Text(option.title)
                    .font(.scaledSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? option.accent : MapUI.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 2)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.scaledSystem(size: 9, weight: .heavy))
                        .foregroundStyle(option.accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(selected ? option.accent.opacity(0.12) : MapUI.surfaceHigh.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(selected ? option.accent.opacity(0.55) : MapUI.line, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Pinned above the home indicator. The action used to live at the end of
    /// the scroll content, half off-screen, which made Share hard to hit.
    private var actionBar: some View {
        VStack(spacing: 8) {
            if let posterURL {
                ShareLink(item: posterURL) {
                    Label("Share poster", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(RevertPrimaryButtonStyle())

                Button {
                    RevertHaptics.tap()
                    render()
                } label: {
                    Label("Render again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
            } else {
                Button {
                    render()
                } label: {
                    Label(rendering ? "Rendering…" : "Render poster",
                          systemImage: "photo.artframe")
                }
                .buttonStyle(RevertPrimaryButtonStyle())
                .disabled(rendering)
                .opacity(rendering ? 0.55 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            ZStack {
                MapUI.canvas.opacity(0.97)
                LinearGradient(colors: [.clear, MapUI.canvas],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
    }

    private func render() {
        rendering = true
        let content = StoryPosterView(ride: ride, points: points, turns: turns,
                                      theme: theme, style: style)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            rendering = false
            renderError = "The poster could not be drawn on this device. Try another theme."
            RevertDiagnostics.log("poster render failed: no image")
            return
        }
        let previous = posterURL
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RidePoster-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            rendering = false
            renderError = "The poster could not be written to disk: \(error.localizedDescription)"
            RevertDiagnostics.log("poster write failed: \(error.localizedDescription)")
            return
        }
        if let previous, previous != url {
            try? FileManager.default.removeItem(at: previous)
        }
        posterURL = url
        rendering = false
        RevertHaptics.success()
    }
}
