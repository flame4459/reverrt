import SwiftUI
import CoreLocation
import Foundation

enum RideHeatMetric: String, CaseIterable, Identifiable {
    case speed
    case lean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: "Speed"
        case .lean: "Lean"
        }
    }

    func color(for point: RidePoint) -> Color {
        switch self {
        case .speed:
            let speed = point.speed
            switch speed {
            case ..<10: return Color(red: 0.18, green: 0.55, blue: 1.0)    // < 22 mph
            case ..<22: return MapUI.cyan                                  // 22–49 mph
            case ..<33: return MapUI.emerald                               // 49–74 mph
            case ..<42: return MapUI.orange                                // 74–94 mph
            default: return MapUI.magenta
            }
        case .lean:
            let lean = abs(point.lean ?? 0)
            switch lean {
            case ..<8: return MapUI.cyan
            case ..<18: return MapUI.emerald
            case ..<28: return MapUI.orange
            case ..<40: return MapUI.magenta
            default: return Color(red: 1.0, green: 0.10, blue: 0.55)
            }
        }
    }
}

struct RideHeatSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

struct RideTurn: Identifiable {
    let id: Int
    let apexIndex: Int
    let direction: Int          // +1 right, -1 left
    let peakLean: Double
    let speed: Double
    let coordinate: CLLocationCoordinate2D

    var label: String {
        direction > 0 ? "Right" : "Left"
    }
}

enum RideAnalysis {
    /// Colored, consecutive polyline runs for the heatmap. Kept to a few hundred
    /// segments so MapKit stays smooth even on a two-hour ride.
    static func heatSegments(from points: [RidePoint], metric: RideHeatMetric) -> [RideHeatSegment] {
        guard points.count > 1 else { return [] }
        let stride = max(1, points.count / 1_500)
        var segments: [RideHeatSegment] = []
        var current: [CLLocationCoordinate2D] = []
        var currentColor: Color?
        var lastIncluded: CLLocationCoordinate2D?

        func flush() {
            if current.count > 1, let color = currentColor {
                segments.append(RideHeatSegment(id: segments.count, coordinates: current, color: color))
            }
            current = []
        }

        for index in Swift.stride(from: 0, to: points.count, by: stride) {
            let point = points[index]
            guard CLLocationCoordinate2DIsValid(point.coordinate) else { continue }
            // Skip duplicate consecutive coordinates; MapKit dislikes them.
            if let last = lastIncluded,
               abs(last.latitude - point.lat) < 0.0000001,
               abs(last.longitude - point.lon) < 0.0000001 { continue }
            lastIncluded = point.coordinate
            let color = metric.color(for: point)
            if color != currentColor {
                // Reuse the last point so the colored runs join up.
                if let last = current.last { current = [last] }
                flush()
                currentColor = color
                current = [point.coordinate]
            } else {
                current.append(point.coordinate)
            }
        }
        if current.count > 1, let color = currentColor {
            segments.append(RideHeatSegment(id: segments.count, coordinates: current, color: color))
        }
        return segments
    }

    /// Finds the meaningful corners in a recorded track: heading changes over a
    /// 25 m window, grouped into one entry per corner, with peak lean and apex
    /// speed. Runs entirely on-device over the recorded points.
    static func turns(from points: [RidePoint]) -> [RideTurn] {
        guard points.count > 6 else { return [] }
        let window = max(2, min(8, points.count / 80))
        var turns: [RideTurn] = []
        var index = window
        var lastApex = -window * 2

        while index < points.count - window {
            let before = points[index - window]
            let after = points[index + window]
            let beforeHeading = RoadGraph.flat(before.lat, before.lon, points[index].lat, points[index].lon).heading
            let afterHeading = RoadGraph.flat(points[index].lat, points[index].lon, after.lat, after.lon).heading
            var delta = afterHeading - beforeHeading
            while delta > 180 { delta -= 360 }
            while delta <= -180 { delta += 360 }

            if abs(delta) >= 18, index - lastApex > window {
                // Walk to the apex of this corner.
                var apex = index
                var apexDelta = abs(delta)
                var probe = index + 1
                while probe < min(index + window * 3, points.count - window) {
                    let b = RoadGraph.flat(points[probe - window].lat, points[probe - window].lon,
                                           points[probe].lat, points[probe].lon).heading
                    let a = RoadGraph.flat(points[probe].lat, points[probe].lon,
                                           points[probe + window].lat, points[probe + window].lon).heading
                    var d = a - b
                    while d > 180 { d -= 360 }
                    while d <= -180 { d += 360 }
                    if abs(d) > apexDelta { apexDelta = abs(d); apex = probe }
                    probe += 1
                }
                let leanWindow = points[max(0, apex - window * 2)...min(points.count - 1, apex + window * 2)]
                let peakLean = leanWindow.map { abs($0.lean ?? 0) }.max() ?? 0
                let speed = points[apex].speed
                turns.append(RideTurn(id: turns.count, apexIndex: apex, direction: delta > 0 ? 1 : -1,
                                      peakLean: peakLean, speed: speed,
                                      coordinate: points[apex].coordinate))
                lastApex = apex
                index = apex + window
            } else {
                index += 1
            }
        }
        return turns
    }

    static func averageSpeed(_ points: [RidePoint]) -> Double {
        let moving = points.filter { $0.speed > 1 }
        guard !moving.isEmpty else { return 0 }
        return moving.reduce(0) { $0 + $1.speed } / Double(moving.count)
    }

    static func maxLean(_ points: [RidePoint]) -> Double {
        points.map { abs($0.lean ?? 0) }.max() ?? 0
    }

    static func elevationProfile(_ points: [RidePoint]) -> [Double] {
        // Light smoothing: barometric/GPS altitude is noisy at 1 Hz.
        guard points.count > 2 else { return points.map(\.alt) }
        var result: [Double] = []
        result.reserveCapacity(points.count)
        for index in points.indices {
            let lower = max(0, index - 3)
            let upper = min(points.count - 1, index + 3)
            let slice = points[lower...upper]
            result.append(slice.reduce(0) { $0 + $1.alt } / Double(slice.count))
        }
        return result
    }
}
