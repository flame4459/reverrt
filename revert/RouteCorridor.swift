import Foundation
import CoreLocation

/// A hazard projected onto the active route.
nonisolated struct RouteCorridorMatch {
    let along: Double       // meters from the route start
    let lateral: Double     // meters from the route centreline
}

nonisolated enum RouteCorridor {
    /// Projects a point onto the route within a window around the rider's
    /// progress. Returns nil when the point is not alongside that stretch.
    static func project(latitude: Double,
                        longitude: Double,
                        route: PlannedRoute,
                        near progress: Double,
                        behind: Double = 25,
                        ahead: Double,
                        maxLateral: Double) -> RouteCorridorMatch? {
        let points = route.points
        let cumulative = route.cumulative
        guard points.count > 1, cumulative.count == points.count else { return nil }

        let lower = max(progress - behind, 0)
        let upper = progress + ahead
        var index = lowerBound(cumulative, value: lower)
        if index >= points.count - 1 { return nil }

        let kx = 111_320.0 * cos(latitude * .pi / 180)
        let ky = 110_540.0
        var best: RouteCorridorMatch?
        var bestLateral = maxLateral

        while index < points.count - 1, cumulative[index] <= upper + 40 {
            let a = points[index], b = points[index + 1]
            let ax = (a.lon - longitude) * kx
            let ay = (a.lat - latitude) * ky
            let bx = (b.lon - longitude) * kx
            let by = (b.lat - latitude) * ky
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t: Double
            if lengthSquared > 0.01 {
                t = min(max(-(ax * dx + ay * dy) / lengthSquared, 0), 1)
            } else {
                t = 0
            }
            let px = ax + t * dx
            let py = ay + t * dy
            let lateral = (px * px + py * py).squareRoot()
            let along = cumulative[index] + t * (cumulative[index + 1] - cumulative[index])

            if lateral < bestLateral, along >= lower, along <= upper {
                bestLateral = lateral
                best = RouteCorridorMatch(along: along, lateral: lateral)
            }
            index += 1
        }
        return best
    }

    private static func lowerBound(_ values: [Double], value: Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < value { low = mid + 1 } else { high = mid }
        }
        return max(0, min(low, values.count - 1))
    }
}
