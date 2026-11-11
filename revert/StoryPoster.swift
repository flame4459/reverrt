import SwiftUI
import CoreLocation
import UIKit

enum StoryPosterTheme: String, CaseIterable, Identifiable {
    case oled
    case sunset
    case topo
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oled: "OLED cockpit"
        case .sunset: "Sunset pass"
        case .topo: "Topo map"
        case .paper: "Ride journal"
        }
    }

    var background: [Color] {
        switch self {
        case .oled: [.black, Color(red: 0.02, green: 0.06, blue: 0.09)]
        case .sunset: [Color(red: 0.12, green: 0.04, blue: 0.12), Color(red: 0.48, green: 0.12, blue: 0.09)]
        case .topo: [Color(red: 0.03, green: 0.12, blue: 0.10), Color(red: 0.02, green: 0.05, blue: 0.06)]
        case .paper: [Color(red: 0.93, green: 0.90, blue: 0.82), Color(red: 0.80, green: 0.76, blue: 0.66)]
        }
    }

    var accent: Color {
        switch self {
        case .oled: MapUI.cyan
        case .sunset: Color(red: 1.0, green: 0.55, blue: 0.22)
        case .topo: MapUI.emerald
        case .paper: Color(red: 0.12, green: 0.30, blue: 0.24)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .oled: MapUI.emerald
        case .sunset: Color(red: 1.0, green: 0.84, blue: 0.45)
        case .topo: Color(red: 0.55, green: 0.95, blue: 0.70)
        case .paper: Color(red: 0.55, green: 0.22, blue: 0.10)
        }
    }

    var ink: Color {
        self == .paper ? Color(red: 0.10, green: 0.10, blue: 0.09) : .white
    }

    var secondaryInk: Color {
        self == .paper ? Color.black.opacity(0.58) : Color.white.opacity(0.62)
    }
}

struct StoryPosterView: View {
    let ride: Ride
    let points: [RidePoint]
    let turns: [RideTurn]
    let theme: StoryPosterTheme

    private var averageSpeed: Double {
        ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
    }

    private var topSpeed: Double { ride.maxSpeedMps }
    private var maxLean: Double {
        max(ride.maxLeanAngleDegrees, points.map { abs($0.lean ?? 0) }.max() ?? 0)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Subtle grid / contour texture.
            Canvas { context, size in
                var path = Path()
                let step: CGFloat = 54
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
                context.stroke(path, with: .color(theme.ink.opacity(0.035)), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REVERT")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .tracking(7)
                            .foregroundStyle(theme.accent)
                        Text("RIDE STORY")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(5)
                            .foregroundStyle(theme.secondaryInk)
                    }
                    Spacer()
                    Text(ride.startDate.formatted(date: .abbreviated, time: .omitted).uppercased())
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.ink)
                }

                Spacer(minLength: 34)

                Text(ride.routeName ?? "A ride worth remembering")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)

                Text(ride.bikeDisplayName.uppercased())
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(theme.accent)
                    .padding(.top, 10)

                RoutePosterCanvas(points: points, turns: turns, accent: theme.accent,
                                  secondary: theme.secondaryAccent, ink: theme.ink)
                    .frame(height: 420)
                    .padding(.vertical, 26)

                Spacer(minLength: 12)

                HStack(alignment: .top, spacing: 0) {
                    posterMetric(Units.distanceText(ride.distanceMeters, decimals: 1), "DISTANCE")
                    posterMetric(Units.clock(ride.movingTimeSeconds), "MOVING TIME")
                    posterMetric("\(turns.count)", turns.count == 1 ? "CORNER" : "CORNERS")
                }

                HStack(alignment: .top, spacing: 0) {
                    posterMetric(Units.speedText(averageSpeed), "AVERAGE")
                    posterMetric(Units.speedText(topSpeed), "TOP SPEED")
                    posterMetric("\(Int(maxLean.rounded()))°", "MAX LEAN")
                }
                .padding(.top, 22)

                Spacer(minLength: 18)

                HStack {
                    Text("\(Int(turns.filter { $0.direction > 0 }.count)) right · \(Int(turns.filter { $0.direction < 0 }.count)) left · \(Units.elevationText(ride.elevationGainMeters)) climbed")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.secondaryInk)
                    Spacer()
                    Text("NO SIGNAL NEEDED")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(theme.accent.opacity(0.8))
                }

                // Credit stays on the exported PNG as well as the preview.
                Text("WHOOPTEH")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(theme.secondaryInk.opacity(0.5))
                    .padding(.top, 14)
            }
            .padding(54)
        }
        .frame(width: 1080, height: 1350)
    }

    private func posterMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
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

    @State private var theme: StoryPosterTheme = .oled
    @State private var posterURL: URL?
    @State private var rendering = false
    @State private var renderError: String?

    private let posterSize = CGSize(width: 1080, height: 1350)

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
                        StoryPosterView(ride: ride, points: points, turns: turns, theme: theme)
                            .scaleEffect(0.30, anchor: .center)
                            .frame(width: posterSize.width * 0.30, height: posterSize.height * 0.30)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(MapUI.lineStrong, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)

                        Text("1080 × 1350  •  optimized for stories")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .revertPanel(radius: 24)

                    VStack(alignment: .leading, spacing: 9) {
                        RevertSectionLabel(title: "Theme", detail: theme.title)
                        RevertOptionPicker(
                            options: StoryPosterTheme.allCases,
                            selection: $theme,
                            title: { $0.title }
                        )
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
        .alert("Couldn't render the poster", isPresented: Binding(
            get: { renderError != nil },
            set: { if !$0 { renderError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renderError ?? "")
        }
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
        let content = StoryPosterView(ride: ride, points: points, turns: turns, theme: theme)
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
