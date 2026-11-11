import SwiftUI
import CoreMotion
import CoreLocation

// MARK: - Dual-Wing Vector Arc Lean Gauge
struct VectorArcLeanGauge: View {
    let angle: Double?
    let maxAngle: Double
    let isCalibrated: Bool

    // Maximum display angle limit on the gauge wings (degrees)
    private let gaugeLimit: Double = 60.0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background Track Arc
                ArcShape(startAngle: .degrees(150), endAngle: .degrees(390))
                    .stroke(MapUI.titanium, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 170, height: 110)

                // Sub-mark ticks
                GaugeTicks()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 170, height: 110)

                // Ghost needle for session peak max lean angle
                if maxAngle > 2 {
                    let ghostFraction = min(maxAngle / gaugeLimit, 1.0)
                    GhostNeedle(fraction: ghostFraction)
                        .stroke(MapUI.magenta.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                        .frame(width: 170, height: 110)
                }

                // Active Live Sweeping Wing
                if let current = angle, abs(current) >= 0.5 {
                    let clamped = min(abs(current), gaugeLimit)
                    let fraction = clamped / gaugeLimit
                    let isRight = current >= 0
                    ActiveArcWing(fraction: fraction, isRight: isRight)
                        .stroke(
                            gaugeColor(for: abs(current)),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .shadow(color: gaugeColor(for: abs(current)).opacity(0.6), radius: 8)
                        .frame(width: 170, height: 110)
                }

                // Central Lean Display
                VStack(spacing: 0) {
                    if let angle {
                        Text("\(Int(abs(angle).rounded()))°")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(gaugeColor(for: abs(angle)))
                            .monospacedDigit()
                    } else {
                        Text("--°")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(leanDirectionText)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(MapUI.secondaryInk)
                }
                .offset(y: 12)
            }

            // Bottom Footer: Peak Max Lean Badge
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MapUI.magenta)
                Text("PEAK \(Int(maxAngle.rounded()))°")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(MapUI.titanium, in: Capsule())
            .overlay(Capsule().stroke(MapUI.fiberOpticBorder, lineWidth: 0.8))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lean angle: \(Int(abs(angle ?? 0).rounded())) degrees, peak \(Int(maxAngle.rounded())) degrees")
    }

    private var leanDirectionText: String {
        guard let angle, abs(angle) >= 2 else { return "UPRIGHT" }
        return angle > 0 ? "RIGHT LEAN" : "LEFT LEAN"
    }

    private func gaugeColor(for degrees: Double) -> Color {
        if degrees >= 42 {
            return MapUI.magenta
        } else if degrees >= 26 {
            return MapUI.emerald
        } else {
            return MapUI.cyan
        }
    }
}

// Custom shapes for the vector arc
private struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2 - 12
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

private struct ActiveArcWing: Shape {
    let fraction: Double
    let isRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2 - 12
        // Top center upright is 270 degrees
        let baseAngle: Double = 270.0
        let sweep: Double = 80.0 * fraction

        if isRight {
            let start = Angle.degrees(baseAngle)
            let end = Angle.degrees(baseAngle + sweep)
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        } else {
            let start = Angle.degrees(baseAngle - sweep)
            let end = Angle.degrees(baseAngle)
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        }
        return path
    }
}

private struct GhostNeedle: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2 - 12
        let sweep = 80.0 * fraction

        // Draw needles on both left and right for max reached
        for sign in [-1.0, 1.0] {
            let angleRad = (270.0 + sign * sweep) * .pi / 180.0
            let p1 = CGPoint(x: center.x + (radius - 10) * CGFloat(cos(angleRad)),
                             y: center.y + (radius - 10) * CGFloat(sin(angleRad)))
            let p2 = CGPoint(x: center.x + (radius + 10) * CGFloat(cos(angleRad)),
                             y: center.y + (radius + 10) * CGFloat(sin(angleRad)))
            path.move(to: p1)
            path.addLine(to: p2)
        }
        return path
    }
}

private struct GaugeTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2 - 12

        // Ticks from 190 to 350 degrees
        for deg in stride(from: 190.0, through: 350.0, by: 20.0) {
            let rad = deg * .pi / 180.0
            let inner = radius - 6
            let outer = radius + 6
            path.move(to: CGPoint(x: center.x + CGFloat(cos(rad)) * inner, y: center.y + CGFloat(sin(rad)) * inner))
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(rad)) * outer, y: center.y + CGFloat(sin(rad)) * outer))
        }
        return path
    }
}

// MARK: - Traction / G-Force Circle Widget
@Observable
final class GForceModel {
    var lateralG: Double = 0.0     // + = right, - = left
    var longitudinalG: Double = 0.0 // + = acceleration, - = braking
    var history: [CGPoint] = []

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let maxHistory = 10

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let accel = data.userAcceleration
            // Lateral = X, Longitudinal = Y
            let lat = accel.x
            let lon = accel.y
            self.lateralG = lat
            self.longitudinalG = lon
            self.history.append(CGPoint(x: lat, y: lon))
            if self.history.count > self.maxHistory {
                self.history.removeFirst()
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        history.removeAll()
        lateralG = 0
        longitudinalG = 0
    }
}

struct GForceRadarView: View {
    let model: GForceModel
    private let radarSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background Circle
                Circle()
                    .fill(MapUI.titanium)
                    .frame(width: radarSize, height: radarSize)

                // 1.0g Limit Circle
                Circle()
                    .stroke(MapUI.cyan.opacity(0.4), lineWidth: 1.5)
                    .frame(width: radarSize - 10, height: radarSize - 10)

                // 0.5g Inner Circle
                Circle()
                    .stroke(MapUI.cyan.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: (radarSize - 10) * 0.5, height: (radarSize - 10) * 0.5)

                // Crosshairs
                Path { path in
                    path.move(to: CGPoint(x: radarSize / 2, y: 8))
                    path.addLine(to: CGPoint(x: radarSize / 2, y: radarSize - 8))
                    path.move(to: CGPoint(x: 8, y: radarSize / 2))
                    path.addLine(to: CGPoint(x: radarSize - 8, y: radarSize / 2))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                // Trail dots
                ForEach(Array(model.history.enumerated()), id: \.offset) { idx, pt in
                    let progress = Double(idx) / Double(max(model.history.count, 1))
                    let x = radarSize / 2 + CGFloat(max(min(pt.x, 1.2), -1.2)) * ((radarSize - 14) / 2)
                    let y = radarSize / 2 - CGFloat(max(min(pt.y, 1.2), -1.2)) * ((radarSize - 14) / 2)
                    Circle()
                        .fill(trailColor(for: pt).opacity(progress * 0.7))
                        .frame(width: 4, height: 4)
                        .position(x: x, y: y)
                }

                // Active G-Ball
                let liveX = radarSize / 2 + CGFloat(max(min(model.lateralG, 1.2), -1.2)) * ((radarSize - 14) / 2)
                let liveY = radarSize / 2 - CGFloat(max(min(model.longitudinalG, 1.2), -1.2)) * ((radarSize - 14) / 2)
                Circle()
                    .fill(trailColor(for: CGPoint(x: model.lateralG, y: model.longitudinalG)))
                    .frame(width: 8, height: 8)
                    .shadow(color: MapUI.cyan, radius: 4)
                    .position(x: liveX, y: liveY)
            }
            .frame(width: radarSize, height: radarSize)

            // Live G magnitude label
            let totalG = sqrt(pow(model.lateralG, 2) + pow(model.longitudinalG, 2))
            Text(String(format: "%.2f G", totalG))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MapUI.cyan)
        }
        .padding(8)
        .background(MapUI.titanium.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MapUI.fiberOpticBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traction circle")
        .accessibilityValue(String(format: "%.2f G", sqrt(pow(model.lateralG, 2) + pow(model.longitudinalG, 2))))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func trailColor(for pt: CGPoint) -> Color {
        let mag = sqrt(pt.x * pt.x + pt.y * pt.y)
        if mag >= 0.8 { return MapUI.magenta }
        if mag >= 0.45 { return MapUI.emerald }
        return MapUI.cyan
    }
}

// MARK: - Custom Motorcycle Road Marker
struct CockpitBikeMarker: View {
    let bikeName: String
    let heading: Double

    var body: some View {
        ZStack {
            // Road surface glow aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MapUI.cyan.opacity(0.45), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 28
                    )
                )
                .frame(width: 56, height: 56)

            // Superbike Vector Chase Silhouette
            SuperbikeSilhouette()
                .fill(
                    LinearGradient(
                        colors: [MapUI.cyan, Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 38)
                .shadow(color: MapUI.cyan, radius: 6)
                .rotationEffect(.degrees(heading))
        }
        .accessibilityLabel("Motorcycle marker facing \(Int(heading)) degrees")
    }
}

private struct SuperbikeSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Front tire / aero windscreen
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.55))
        // Tail
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.95))
        // Left flank
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.28))
        path.closeSubpath()
        return path
    }
}
