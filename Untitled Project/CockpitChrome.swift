import SwiftUI

/// A clipped-corner "aero" panel: the upper-left and lower-right corners are
/// chamfered like a fighter-HUD bezel, the other two stay soft.
struct AeroHUDShape: Shape {
    var cut: CGFloat = 18
    var radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cut = min(cut, min(rect.width, rect.height) / 3)
        let radius = min(radius, min(rect.width, rect.height) / 3)

        // Top edge starts after the top-left chamfer, then rounds into the top-right.
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct GlassHUDBackground: View {
    var tint: Color = MapUI.glassTint

    var body: some View {
        ZStack {
            AeroHUDShape().fill(.ultraThinMaterial)
            AeroHUDShape().fill(tint.opacity(0.78))
            AeroHUDShape().fill(
                LinearGradient(colors: [.white.opacity(0.10), .clear, MapUI.cyan.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            AeroHUDShape()
                .stroke(MapUI.hudEdge, lineWidth: 1)
            // Specular highlight along the top edge.
            AeroHUDShape()
                .stroke(LinearGradient(colors: [.white.opacity(0.55), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8)
                .mask(AeroHUDShape().offset(y: 0.5))
        }
    }
}

struct CockpitStat: View {
    let label: String
    let value: String
    var tint: Color = MapUI.ink
    var monospaced = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(MapUI.secondaryInk)
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CockpitGlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MapUI.glassTint.opacity(0.92))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MapUI.hairline, lineWidth: 0.8)
            }
    }
}
