import Testing
import Foundation
import CoreLocation
@testable import Rider

/// The planner must not answer "couldn't build a loop" when the roads can
/// produce *a* loop that just is not textbook. These tests pin down the
/// best-effort fallback and the auto-pick ranking.
@MainActor
struct LoopFallbackTests {

    private let start = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    private let noonSunday = Date(timeIntervalSince1970: 1_700_000_000)

    /// A loop on the end of a two-lane stick: the only way round it is to ride
    /// the stick out and back. Every strict check rejects the shared stick;
    /// best effort may keep it.
    private func lollipop(stickMeters: Double, loopRadius: Double) -> [Road] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(start.latitude * .pi / 180)
        let junctionLongitude = start.longitude + stickMeters / longitudeScale
        let centerLongitude = junctionLongitude + loopRadius / longitudeScale

        let stick = Road(
            id: 1, highway: "tertiary", name: "Stick Road", maxspeed: nil,
            maxspeedForward: nil, maxspeedBackward: nil, surface: "asphalt",
            oneway: nil, ref: nil,
            coords: [start.latitude, start.longitude, start.latitude, junctionLongitude],
            minLat: start.latitude, maxLat: start.latitude,
            minLon: start.longitude, maxLon: junctionLongitude
        )

        var coords: [Double] = []
        let count = 120
        for index in 0...count {
            let angle = .pi + Double(index) / Double(count) * 2 * .pi
            coords.append(start.latitude + sin(angle) * loopRadius / latitudeScale)
            coords.append(centerLongitude + cos(angle) * loopRadius / longitudeScale)
        }
        let loop = Road(
            id: 2, highway: "tertiary", name: "Loop Road", maxspeed: nil,
            maxspeedForward: nil, maxspeedBackward: nil, surface: "asphalt",
            oneway: nil, ref: nil, coords: coords,
            minLat: start.latitude - loopRadius / latitudeScale,
            maxLat: start.latitude + loopRadius / latitudeScale,
            minLon: junctionLongitude,
            maxLon: junctionLongitude + 2 * loopRadius / longitudeScale
        )
        return [stick, loop]
    }

    @Test func sharedConnectorIsOfferedInsteadOfAnError() {
        let roads = lollipop(stickMeters: 1_200, loopRadius: 400)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: start,
            length: 4_900,
            style: .twisty,
            date: noonSunday,
            deadline: Date().addingTimeInterval(10),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        #expect(routes.contains { $0.retraced > 0.24 },
                "the fallback should keep the shared stick rather than fail")
        #expect(RouteBuilder.lastNotice?.contains("best route") == true
                    || RouteBuilder.lastNotice?.contains("longest loop") == true,
                "the rider should be told the result is a fallback, got: \(RouteBuilder.lastNotice ?? "nil")")
    }

    @Test func impossibleDistanceStillProducesTheLongestLoop() {
        // Ask for 60 miles around a 1.3 km loop; the planner must clamp to what
        // exists instead of failing.
        let roads = lollipop(stickMeters: 300, loopRadius: 200)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: start,
            length: 96_000,
            style: .relaxed,
            date: noonSunday,
            deadline: Date().addingTimeInterval(10),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        #expect(routes.allSatisfy { $0.length < 96_000 })
    }

    // MARK: Auto-pick ranking

    private func route(score: Double, length: Double) -> PlannedRoute {
        // ~111 m per 0.001 degree at this latitude; a straight out-and-back
        // strip long enough to give the route the requested length.
        let metersPerDegree = 111_320.0 * cos(37.0 * .pi / 180)
        let span = length / metersPerDegree
        return PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 0),
                RoutePoint(lat: 37.0, lon: -122.0 + span, road: 0)
            ],
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 90,
            overallScore: score
        )
    }

    @Test func autoPickChoosesTheHighestScore() {
        let best = route(score: 78, length: 10_000)
        let second = route(score: 71, length: 10_000)
        let picked = LoopRanking.best(in: [second, best], targetMeters: 10_000)
        #expect(picked?.id == best.id)
    }

    @Test func autoPickBreaksTiesTowardTheRequestedDistance() {
        let onDistance = route(score: 70, length: 10_000)
        let tooLong = route(score: 74, length: 13_000)
        // 30% over loses 18 points on the tie-break, so the honest distance wins.
        let picked = LoopRanking.best(in: [tooLong, onDistance], targetMeters: 10_000)
        #expect(picked?.id == onDistance.id)
    }

    @Test func autoPickIgnoresScorelessRoutesByMeasuringThem() {
        // A route with no planner score still ranks on measured geometry.
        let scored = route(score: 40, length: 10_000)
        let unscored = PlannedRoute(
            points: (0...40).map { index in
                RoutePoint(lat: 37.0, lon: -122.0 + Double(index) * 0.00006, road: 0)
            },
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 90
        )
        #expect(LoopRanking.best(in: [scored, unscored], targetMeters: 10_000) != nil)
    }
}
