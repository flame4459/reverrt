import SwiftUI
import MapKit

struct DirectorRiderSprite: View {
    let assetName: String
    var height: CGFloat = 92

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Rider")
    }
}

struct DirectorFilmOverlay: View {
    let filmTime: TimeInterval
    let speed: Double
    let shot: FilmShot?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.42), .clear, .clear, .black.opacity(0.58)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, .black.opacity(0.48)],
                           center: .center, startRadius: 180, endRadius: 560)
                .blendMode(.multiply)
            if speed > 11 {
                speedLines
            }
            grain
            letterbox
        }
        .allowsHitTesting(false)
    }

    private var speedLines: some View {
        Canvas { context, size in
            var seed = UInt64(max(filmTime, 0) * 1_000) &+ 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 11) & 0xFFFF) / 65_535
            }
            let intensity = min(max((speed - 11) / 25, 0), 1)
            for _ in 0..<10 {
                let y = next() * size.height
                let length = 18 + next() * 46
                let fromLeft = next() > 0.5
                let x = fromLeft ? 0 : size.width
                let endX = fromLeft ? x + length : x - length
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: endX, y: y + (next() - 0.5) * 3))
                context.stroke(path, with: .color(.white.opacity(0.035 + 0.07 * intensity)),
                               lineWidth: 0.8)
            }
        }
    }

    private var grain: some View {
        Canvas { context, size in
            var seed = UInt64(max(filmTime, 0) * 2_000) &+ 0xDA3E39CB94B95BDB
            func next() -> Double {
                seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                return Double((seed >> 16) & 0xFFFF) / 65_535
            }
            for _ in 0..<80 {
                let rect = CGRect(x: next() * size.width, y: next() * size.height,
                                  width: 1.2, height: 1.2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.024)))
            }
        }
    }

    private var letterbox: some View {
        VStack {
            Rectangle().fill(.black.opacity(0.62)).frame(height: 8)
            Spacer()
            Rectangle().fill(.black.opacity(0.62)).frame(height: 8)
        }
    }
}

struct DirectorTitleCard: View {
    let film: ReplayFilm
    let shot: FilmShot
    let progress: Double

    private var opacity: Double {
        if shot.kind == .outro {
            return max(0.6, min(1, progress * 4))
        }
        return max(0.6, min(1, progress * 5, (1 - progress) * 5))
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(shot.kind == .outro ? "THE FINISH" : "REVERT FILM")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(MapUI.cyan)
            Text(film.routeName)
                .font(PulseType.display(30))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(shot.kind == .outro
                 ? "\(Units.distanceText(film.distanceMeters, decimals: 1)) · \(Units.clock(film.rideDuration)) · \(film.highlights.count) corners"
                 : "\(film.highlights.count) corners · \(film.shots.count) shots · \(Units.distanceText(film.distanceMeters, decimals: 1))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.8)
        }
        .opacity(opacity)
    }
}

struct DirectorScrubber: View {
    let film: ReplayFilm
    @Binding var filmTime: TimeInterval
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = min(max(filmTime / max(film.duration, 0.01), 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.52))
                    .frame(height: 10)
                ForEach(film.shots) { shot in
                    let start = film.startTime(of: shot) / max(film.duration, 0.01)
                    let length = shot.duration / max(film.duration, 0.01)
                    Capsule()
                        .fill(color(for: shot.kind).opacity(0.58))
                        .frame(width: max(width * length - 1, 2), height: 7)
                        .offset(x: width * start + 1)
                }
                Capsule()
                    .fill(MapUI.cyan.opacity(0.42))
                    .frame(width: max(width * progress, 2), height: 10)
                ForEach(film.shots.filter { $0.moment != nil }) { shot in
                    let x = width * film.startTime(of: shot) / max(film.duration, 0.01)
                    Diamond()
                        .fill(MapUI.amber)
                        .frame(width: 7, height: 7)
                        .offset(x: min(max(x - 3.5, 0), width - 7), y: -7)
                }
                Circle()
                    .fill(MapUI.cyan)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                    .offset(x: min(max(width * progress - 6, 0), width - 12))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = min(max(value.location.x / width, 0), 1)
                        onSeek(p * film.duration)
                    }
            )
            .accessibilityLabel("Film timeline")
            .accessibilityValue("\(Units.clock(filmTime)) of \(Units.clock(film.duration))")
        }
    }

    private func color(for kind: DirectorShotKind) -> Color {
        switch kind {
        case .establishing, .outro: MapUI.textTertiary
        case .chase: MapUI.cyan
        case .orbit: MapUI.magenta
        case .trackside: MapUI.amber
        case .flyby: MapUI.emerald
        case .hero: MapUI.orange
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct DirectorTelemetryTrace: View {
    let ride: Ride
    let film: ReplayFilm
    let elapsed: TimeInterval

    var body: some View {
        Canvas { context, size in
            let points = ride.points
            guard points.count > 2, let first = points.first?.time, let last = points.last?.time else {
                return
            }
            let span = max(last.timeIntervalSince(first), 1)
            let maxSpeed = max(points.map(\.speed).max() ?? 1, 1)
            var path = Path()
            let step = max(1, points.count / 180)
            for index in stride(from: 0, to: points.count, by: step) {
                let point = points[index]
                let x = point.time.timeIntervalSince(first) / span * size.width
                let y = size.height - (point.speed / maxSpeed) * (size.height - 3) - 1
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(MapUI.cyan.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            for shot in film.shots where shot.moment != nil {
                let x = min(max(shot.rideStart / max(span, 1) * size.width, 0), size.width)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .color(MapUI.amber.opacity(0.35)), lineWidth: 0.8)
            }
            let x = min(max(elapsed / max(span, 1) * size.width, 0), size.width)
            var marker = Path()
            marker.move(to: CGPoint(x: x, y: 0))
            marker.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(marker, with: .color(.white.opacity(0.65)), lineWidth: 1.2)
        }
        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
