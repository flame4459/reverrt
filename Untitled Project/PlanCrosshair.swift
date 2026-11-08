import SwiftUI
import CoreLocation
import Observation

/// Tracks the coordinate under the center of the planning map. The camera
/// callback writes into this reference type, so panning/zooming only refreshes
/// the tiny reticle and readout views instead of the whole plan sheet.
@Observable
final class PlanAimModel {
    /// `nil` until MapKit reports the first camera update.
    var center: CLLocationCoordinate2D?
}

/// One pin drop, used to animate a short "lock-on" pulse where the pin landed.
struct PlanPinStrike: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// Precision reticle centered on the planning map. The exact point where the
/// crosshair meets is the point that the drop-pin button will place the pin, so
/// the rider can pan the map under it and commit only when the target is right.
/// Kept label-free so a pin dropped at the center is not buried under captions.
struct PlanCrosshair: View {
    let tint: Color

    var body: some View {
        PlanCrosshairGlyph(tint: tint)
            .frame(width: 56, height: 56)
            .animation(.easeInOut(duration: 0.2), value: tint)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The reticle itself: four arms with a clear center, a thin ring, and a bright
/// dot. Every element has a dark underlay so it stays legible on both the
/// standard map and bright satellite imagery.
struct PlanCrosshairGlyph: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.45), lineWidth: 3.4)
                .frame(width: 30, height: 30)
            Circle()
                .stroke(tint, lineWidth: 1.3)
                .frame(width: 30, height: 30)

            CrosshairArms()
                .stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            CrosshairArms()
                .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

            Circle()
                .fill(.black.opacity(0.55))
                .frame(width: 9, height: 9)
            Circle()
                .fill(tint)
                .frame(width: 5.5, height: 5.5)
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

private struct CrosshairArms: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let gap: CGFloat = 7.5
        let reach: CGFloat = 24

        var path = Path()
        path.move(to: CGPoint(x: center.x - reach, y: center.y))
        path.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        path.move(to: CGPoint(x: center.x + gap, y: center.y))
        path.addLine(to: CGPoint(x: center.x + reach, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - reach))
        path.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        path.move(to: CGPoint(x: center.x, y: center.y + gap))
        path.addLine(to: CGPoint(x: center.x, y: center.y + reach))
        return path
    }
}

/// Small HUD chip showing the crosshair's coordinate, so the rider can tell
/// where the aim point actually is while panning.
struct PlanAimReadout: View {
    let model: PlanAimModel
    let tint: Color
    let target: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(target)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(tint)
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(width: 0.7, height: 10)
            Text(coordinateText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
        }
        .animation(.easeInOut(duration: 0.2), value: target)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(MapUI.pitchBlack.opacity(0.72), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
        .opacity(model.center == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var coordinateText: String {
        guard let center = model.center else { return "—" }
        return String(format: "%.4f, %.4f", center.latitude, center.longitude)
    }
}

/// Expanding ring flashed at the exact point a pin was dropped. It sits on the
/// map coordinate (rather than the screen) so it stays locked to the spot even
/// if the camera settles during the animation.
struct PlanDropPulse: View {
    let tint: Color

    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(expanded ? 0 : 0.95), lineWidth: 2)
                .frame(width: 22, height: 22)
                .scaleEffect(expanded ? 2.6 : 0.55)
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .opacity(expanded ? 0 : 1)
        }
        .frame(width: 62, height: 62)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                expanded = true
            }
        }
    }
}
