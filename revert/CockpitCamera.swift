import SwiftUI
import MapKit

/// The three camera languages the cockpit offers.
enum RideCameraMode: String, CaseIterable, Identifiable {
    case cockpit
    case chase
    case northUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cockpit: "2.5D cockpit"
        case .chase: "Chase"
        case .northUp: "North up"
        }
    }

    var icon: String {
        switch self {
        case .cockpit: "view.3d"
        case .chase: "location.north.line.fill"
        case .northUp: "map.fill"
        }
    }

    var pitch: Double {
        switch self {
        case .cockpit: 46
        case .chase: 34
        case .northUp: 0
        }
    }

    var usesPose: Bool { self != .northUp }

    /// Lower camera when slow, pull back at speed. A bike at 70 mph needs to
    /// see further down the road than one easing out of a village. The old
    /// 58° pitch at 250 m filled the screen with the nearest buildings and hid
    /// the road at town speeds.
    func distance(for speed: Double) -> Double {
        switch self {
        case .cockpit: min(max(300 + speed * 8.5, 320), 820)
        case .chase: min(max(340 + speed * 6, 360), 760)
        case .northUp: 0
        }
    }

    func camera(for pose: RideCameraPose) -> MapCameraPosition {
        let camera = MapCamera(
            centerCoordinate: pose.coordinate,
            distance: distance(for: pose.speed),
            heading: usesPose ? pose.heading : 0,
            pitch: pitch
        )
        return .camera(camera)
    }
}

/// A small 2.5D route ribbon used in the plan preview. It is a pure SwiftUI
/// isometric projection of the route, so it renders instantly and needs no
/// map tiles while the route is being planned.
struct IsometricRouteRibbon: View {
    let points: [RoutePoint]
    var lineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let projected = project(in: geometry.size)
            ZStack {
                Path { path in
                    guard let first = projected.first else { return }
                    path.move(to: first)
                    for point in projected.dropFirst() { path.addLine(to: point) }
                }
                .stroke(
                    LinearGradient(colors: [MapUI.cyan, MapUI.emerald],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: MapUI.cyan.opacity(0.7), radius: 8)
            }
        }
        .accessibilityHidden(true)
    }

    /// x' = (x - y) * cos(30°), y' = (x + y) * sin(30°) with a vertical squash.
    private func project(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        var raw: [(Double, Double)] = []
        for point in points {
            let x = point.lon * 111_320
            let y = point.lat * 110_540
            raw.append((x, y))
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let scale = min(Double(size.width) / width, Double(size.height) / height) * 0.72
        let angle = Double.pi / 6
        let cosA = cos(angle), sinA = sin(angle)
        var output: [CGPoint] = []
        output.reserveCapacity(raw.count)
        for (x, y) in raw {
            let nx = (x - minX) / width - 0.5
            let ny = (y - minY) / height - 0.5
            let isoX = (nx - ny) * cosA
            let isoY = (nx + ny) * sinA * 0.62
            output.append(CGPoint(x: size.width / 2 + isoX * width * scale * 0.7,
                                  y: size.height / 2 + isoY * height * scale))
        }
        return output
    }
}
