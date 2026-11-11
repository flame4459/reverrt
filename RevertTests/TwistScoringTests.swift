import Testing
import Foundation
import CoreLocation
@testable import Revert

/// Checks for the continuous, locally-normalised curvature scoring: no radius
/// cliff, no curvature lost at chunk boundaries, and relative scoring that
/// lifts the best local road on a plain without inflating it in the mountains.
@MainActor
struct TwistScoringTests {

    private func circle(radius: Double, count: Int = 160) -> [CLLocationCoordinate2D] {
        let latitude = 37.0
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(latitude * .pi / 180)
        return (0...count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            return CLLocationCoordinate2D(
                latitude: latitude + sin(angle) * radius / latitudeScale,
                longitude: -122.0 + cos(angle) * radius / longitudeScale
            )
        }
    }

    // MARK: Continuous curvature

    @Test func curvatureFallsSmoothlyWithRadius() {
        let tight = Curvature.measure(circle(radius: 140))
        let sweeper = Curvature.measure(circle(radius: 250))
        let open = Curvature.measure(circle(radius: 400))

        #expect(tight.raw > sweeper.raw)
        #expect(sweeper.raw > open.raw)
        // A 250 m sweeper used to score zero on the corner-share term.
        #expect(sweeper.raw > 15)
        #expect(open.raw > 0)
        #expect(open.raw < 12)
    }

    @Test func funIsOneAtHairpinsAndZeroOnStraights() {
        #expect(Curvature.fun(radius: 20) == 1)
        #expect(Curvature.fun(radius: .infinity) == 0)
        #expect(Curvature.fun(radius: 450) == 0)
        // Monotonic through the range riders actually ride.
        let values = [50.0, 100, 150, 200, 250, 350].map { Curvature.fun(radius: $0) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func chunkSlicesPreserveCurvatureAtTheSeam() {
        // Straight run, then an arc that straddles the middle of the way.
        let straight = (0...40).map { index in
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0 + Double(index) * 0.0002)
        }
        var arc: [CLLocationCoordinate2D] = []
        let radius = 120.0
        for index in 1...60 {
            let angle = Double(index) / 60 * .pi / 2
            arc.append(CLLocationCoordinate2D(
                latitude: 37.0 + (1 - cos(angle)) * radius / 110_540,
                longitude: -122.0 + 0.008 + sin(angle) * radius / (111_320 * cos(37.0 * .pi / 180))
            ))
        }
        let coordinates = straight + arc
        guard let profile = Curvature.sampled(coordinates) else {
            Issue.record("fixture should be samplable")
            return
        }
        let whole = Curvature.measure(coordinates)
        let front = Curvature.stats(profile, from: 0, to: profile.length / 2)
        let back = Curvature.stats(profile, from: profile.length / 2, to: profile.length)
        #expect(front.lengthMeters > 10)
        #expect(back.lengthMeters > 10)

        let merged = (front.raw * front.lengthMeters + back.raw * back.lengthMeters)
            / (front.lengthMeters + back.lengthMeters)
        // Measuring each half in isolation loses the 15 m either side of the
        // cut; slicing the whole-way profile must not.
        #expect(abs(merged - whole.raw) < 3)
    }

    // MARK: Relative scoring

    private func edge(raw: Double, length: Double = 120) -> RoadGraph.Edge {
        RoadGraph.Edge(from: 0, to: 1, road: 0, i0: 0, i1: 1,
                       length: length, twist: raw * 4, value: raw, raw: raw,
                       cornerShare: 0, sweeperShare: 0, tightShare: 0,
                       comfortableMps: 20, seg: 0)
    }

    @Test func scarceAreaLiftsItsBestLocalRoad() {
        // A plain: every road scores 0...10.
        let plain = TwistProfile.make(edges: (0..<40).map { edge(raw: Double($0 % 5) * 2) })
        #expect(plain.scarcity > 0.9)
        #expect(plain.effective(25) > 0.6)
        #expect(plain.classRelief < 0.5)

        // A mountain area: ordinary roads already score 40...80.
        let rich = TwistProfile.make(edges: (0..<40).map { edge(raw: 40 + Double($0 % 40)) })
        #expect(rich.scarcity < 0.1)
        // A 25-raw road is genuinely poor there and stays poor.
        #expect(rich.effective(25) < 0.35)
        // A tight road is still valuable everywhere.
        #expect(rich.effective(90) > 0.85)
    }

    @Test func routeScorePrefersCurvatureAtTheSameDistance() {
        let twisty = circle(radius: 100, count: 140)
        let straight = (0...90).map { index in
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0 + Double(index) * 0.00006)
        }
        let twistyPoints = twisty.map { RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0) }
        let straightPoints = straight.map { RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0) }
        let twistyLength = Curvature.measure(points: twistyPoints).lengthMeters
        let straightLength = Curvature.measure(points: straightPoints).lengthMeters

        let twistyScore = TwistProfile.scoreRoute(twistyPoints, targetMeters: twistyLength)
        let straightScore = TwistProfile.scoreRoute(straightPoints, targetMeters: straightLength)
        #expect(twistyScore > straightScore + 20)
        #expect(straightScore < 40)
    }

    @Test func graphEdgesCarryContinuousScores() {
        let coordinates = circle(radius: 130, count: 200)
        var coords: [Double] = []
        for coordinate in coordinates {
            coords.append(coordinate.latitude)
            coords.append(coordinate.longitude)
        }
        let road = Road(
            id: 1, highway: "tertiary", name: "Loop", maxspeed: nil,
            maxspeedForward: nil, maxspeedBackward: nil, surface: "asphalt",
            oneway: nil, ref: nil, coords: coords,
            minLat: coords.min()!, maxLat: coords.max()!,
            minLon: coords.min()!, maxLon: coords.max()!
        )
        let graph = RoadGraph(roads: [road])
        #expect(!graph.edges.isEmpty)
        // Every chunk of a tight loop is curvy; none should read as straight.
        #expect(graph.edges.allSatisfy { $0.raw > 5 })
        #expect(graph.edges.allSatisfy { $0.value > 0 })
    }
}
