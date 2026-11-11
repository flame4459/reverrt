import Foundation
import CoreLocation

/// Chooses which loop a rider sees first.
///
/// When "auto-pick the best loop" is on, the planner still builds and ranks
/// every candidate; this just decides which one is selected without asking the
/// rider to compare cards. It is shared with the tests because the tie-break
/// (score first, distance accuracy second) is easy to get subtly wrong.
nonisolated enum LoopRanking {
    /// The strongest loop: highest planner score, then closest to the distance
    /// the rider asked for.
    static func best(in routes: [PlannedRoute], targetMeters: Double) -> PlannedRoute? {
        guard !routes.isEmpty else { return nil }
        let target = max(targetMeters, 1)
        return routes.max { score($0, targetMeters: target) < score($1, targetMeters: target) }
    }

    static func score(_ route: PlannedRoute, targetMeters: Double) -> Double {
        let target = max(targetMeters, 1)
        // Graph routes carry a score; MapKit loops also carry one. If a route
        // arrives without either, measure its geometry rather than ranking it
        // as zero.
        let base = route.overallScore ?? TwistProfile.scoreRoute(route.points, targetMeters: target)
        let distanceError = abs(route.length / target - 1)
        // A small nudge only: the planner's own score already weighs distance,
        // this breaks ties toward the loop the rider actually asked for.
        return base - min(20, distanceError * 60)
    }
}
