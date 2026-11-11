import Foundation
import CoreLocation

/// How twisty the roads around a start are, and how an individual road should
/// be scored relative to them.
///
/// An absolute curvature scale is wrong in both directions. In the mountains a
/// 150 m corner is ordinary; on a coastal plain it is the best road for thirty
/// miles. Scoring every road on the same absolute scale therefore makes flat
/// areas look like they have nothing worth riding and keeps the router on
/// arterials, because the class penalty outweighs any curvature difference.
///
/// The profile is built once per plan from the loaded graph. Absolute score
/// still dominates where twisty roads are plentiful; where they are scarce the
/// top few percent of local roads is allowed to reach full value, class
/// penalties are relaxed, and the "twisty kilometres" of a loop count for more
/// than its mean.
nonisolated struct TwistProfile: Sendable, Equatable {
    /// Length-weighted median of edge `raw` scores.
    var p50: Double = 0
    /// Length-weighted 97th percentile of edge `raw` scores.
    var p97: Double = 100
    /// Share of loaded road length scoring `raw >= 30` (roughly 230 m radius
    /// or tighter).
    var richness: Double = 0
    var edgeCount: Int = 0

    static let neutral = TwistProfile()

    /// 1 when there is almost no twisty road around, 0 when there is plenty.
    var scarcity: Double {
        min(max(1 - richness / 0.15, 0), 1)
    }

    /// Position of a road within the local distribution, 0...1.
    ///
    /// The 12-point floor stops GPS/OSM noise on a flat grid from being
    /// amplified into "relative" value.
    func relative(_ raw: Double) -> Double {
        min(max((raw - p50) / max(p97 - p50, 12), 0), 1)
    }

    /// 0...1 curvature score the router should use instead of `raw / 100`.
    ///
    /// The absolute term is a floor, never a ceiling: a genuinely tight road
    /// stays valuable everywhere. The relative term grows as twisty roads
    /// become scarce.
    func effective(_ raw: Double) -> Double {
        max(min(raw / 100, 1), relative(raw) * (0.4 + 0.6 * scarcity))
    }

    /// Exponent applied to `RouteBuilder.classFactor`. 1 keeps the normal class
    /// penalty; lower values stop a curvy residential road from losing to a
    /// straight secondary purely because of its tag.
    var classRelief: Double {
        1 - 0.6 * scarcity
    }

    static func make(edges: [RoadGraph.Edge]) -> TwistProfile {
        guard !edges.isEmpty else { return .neutral }

        var total = 0.0
        var twisty = 0.0
        var pairs: [(raw: Double, length: Double)] = []
        pairs.reserveCapacity(edges.count)
        for edge in edges {
            total += edge.length
            if edge.raw >= 30 { twisty += edge.length }
            pairs.append((edge.raw, edge.length))
        }
        guard total > 0 else { return .neutral }

        pairs.sort { $0.raw < $1.raw }
        var cumulative = 0.0
        var p50 = pairs[0].raw
        var p97 = pairs[pairs.count - 1].raw
        var halfDone = false
        for pair in pairs {
            cumulative += pair.length
            if !halfDone, cumulative >= total * 0.5 {
                p50 = pair.raw
                halfDone = true
            }
            if cumulative >= total * 0.97 {
                p97 = pair.raw
                break
            }
        }
        return TwistProfile(p50: p50, p97: max(p97, p50), richness: twisty / total,
                            edgeCount: edges.count)
    }

    /// Score a finished route with the same metric whether MapKit or the
    /// offline graph produced it.
    ///
    /// Mean curvature alone punishes the unavoidable connector roads, so
    /// twisty kilometres count for a third. The distance penalty is small: the
    /// caller has already filtered to the distance band.
    static func scoreRoute(
        _ points: [RoutePoint],
        targetMeters: Double,
        profile: TwistProfile? = nil
    ) -> Double {
        guard points.count > 2, targetMeters > 0 else { return 0 }
        let measured = Curvature.measure(points: points)
        guard measured.lengthMeters > 1 else { return 0 }
        let mean = (profile?.effective(measured.raw) ?? measured.raw / 100) * 100
        let twisty = measured.twistyShare * 100
        let distanceError = abs(measured.lengthMeters / targetMeters - 1)
        let penalty = min(40, distanceError * 120)
        return min(max(0.65 * mean + 0.35 * twisty - penalty, 0), 100)
    }
}
