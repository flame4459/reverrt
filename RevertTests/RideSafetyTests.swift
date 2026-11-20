import Testing
import Foundation
import CoreLocation
@testable import Revert

/// Regression tests for the safety-critical recording, location and reroute
/// paths. Everything runs against scripted fixes and synthetic geometry, so
/// there is no network and no simulator GPS involved.
///
/// Serialized because `LocationHub`, `RideJournal` and the fuel/tile caches are
/// process-wide singletons; a parallel run would have two tests claiming the
/// same GPS tier.
@Suite(.serialized)
@MainActor
struct RideSafetyTests {

    // MARK: Helpers

    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Fixes at 31.5 m/s (about 70 mph) one second apart, heading east.
    private static func highwayPoints(count: Int = 60) -> [RidePoint] {
        let metersPerSecond = 31.5
        let degreesPerMeter = 1 / (111_320 * cos(40.7 * .pi / 180))
        return (0..<count).map { index in
            RidePoint(lat: 40.7,
                      lon: -73.5 + Double(index) * metersPerSecond * degreesPerMeter,
                      alt: 10,
                      speed: metersPerSecond,
                      time: start.addingTimeInterval(Double(index)),
                      lean: 0)
        }
    }

    private static func fix(lat: Double, lon: Double, speed: Double, at date: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: 10,
                   horizontalAccuracy: 5,
                   verticalAccuracy: 5,
                   course: 90,
                   speed: speed,
                   timestamp: date)
    }

    private static func route(lon: Double) -> PlannedRoute {
        PlannedRoute(points: [
            RoutePoint(lat: 40.7, lon: lon, road: 1),
            RoutePoint(lat: 40.7, lon: lon + 0.001, road: 1),
            RoutePoint(lat: 40.7, lon: lon + 0.002, road: 1)
        ], roads: [:], twistPerKm: 0, retraced: 0, bearing: 90)
    }

    // MARK: Location claims

    @Test func releasingALeaseTwiceDropsOnlyOneClaim() {
        let hub = LocationHub.shared
        let preciseBase = hub.preciseClaimCount
        let backgroundBase = hub.backgroundClaimCount

        let precise = hub.acquirePrecise()
        let background = hub.acquireBackground()
        #expect(hub.preciseClaimCount == preciseBase + 1)
        #expect(hub.backgroundClaimCount == backgroundBase + 1)

        precise.release()
        precise.release()
        background.release()
        background.release()

        #expect(hub.preciseClaimCount == preciseBase)
        #expect(hub.backgroundClaimCount == backgroundBase)
    }

    @Test func navigationKeepsPrecisionWhenTheRecorderLetsGo() {
        let hub = LocationHub.shared
        let base = hub.preciseClaimCount

        let navigation = hub.acquirePrecise()
        let recorder = hub.acquirePrecise()
        recorder.release()

        // The old double release is what dropped this to zero mid-navigation.
        #expect(hub.preciseClaimCount == base + 1)

        navigation.release()
        #expect(hub.preciseClaimCount == base)
    }

    @Test func recorderCleanupCanRunTwice() {
        let hub = LocationHub.shared
        let base = hub.preciseClaimCount

        let recorder = RideRecorder()
        recorder.start()
        #expect(hub.preciseClaimCount == base + 1)

        // `suspend()` releases; `stopUpdates()` used to release again.
        recorder.suspend()
        #expect(hub.preciseClaimCount == base)
        recorder.stopUpdates()
        #expect(hub.preciseClaimCount == base)

        RideJournal.shared.finish()
    }

    // MARK: Auto-pause

    @Test func autoPauseFiresWithoutAnyFurtherFixes() {
        let recorder = RideRecorder()
        recorder.start()

        // A parked bike with distanceFilter = 5 may never deliver another fix,
        // so this single stale fix is all the timer gets.
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.5, speed: 0,
                                 at: Date().addingTimeInterval(-130)))
        recorder.tickAutoPause()
        #expect(recorder.isPaused)
        #expect(recorder.isAutoPaused)

        // Movement resumes the clock automatically.
        recorder.ingest(Self.fix(lat: 40.7002, lon: -73.5, speed: 5, at: Date()))
        #expect(!recorder.isPaused)
        #expect(!recorder.isAutoPaused)

        recorder.discard()
        RideJournal.shared.finish()
    }

    @Test func autoPauseWaitsForTwoMinutesOfStanding() {
        let recorder = RideRecorder()
        recorder.start()
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.5, speed: 0,
                                 at: Date().addingTimeInterval(-30)))
        recorder.tickAutoPause()
        #expect(!recorder.isPaused)

        recorder.discard()
        RideJournal.shared.finish()
    }

    // MARK: Ride stats

    @Test func highwaySpeedFixesKeepTheirDistance() {
        let points = Self.highwayPoints()
        let stats = RideStats.compute(points: points)

        // 59 segments of 31.5 m. The old journal rule dropped every segment of
        // 30 m or more, which turned this into roughly zero.
        #expect(stats.distanceMeters > 1_700)
        #expect(stats.distanceMeters < 1_950)
        #expect(stats.movingSeconds > 50)
    }

    @Test func segmentRejectsSignalGapsAndTeleports() {
        let a = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.5)
        let farAway = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.4) // ~8.4 km
        let drift = CLLocationCoordinate2D(latitude: 40.7004, longitude: -73.5) // ~44 m
        let t0 = Self.start

        // 20 s gap: a tunnel, not riding.
        #expect(RideStats.segmentMeters(from: a, at: t0,
                                        to: farAway, at: t0.addingTimeInterval(20),
                                        nextSpeed: 30) == nil)
        // 8.4 km in one second is impossible.
        #expect(RideStats.segmentMeters(from: a, at: t0,
                                        to: farAway, at: t0.addingTimeInterval(1),
                                        nextSpeed: 30) == nil)
        // 44 m in one second while reporting "not moving" is multipath drift.
        #expect(RideStats.segmentMeters(from: a, at: t0,
                                        to: drift, at: t0.addingTimeInterval(1),
                                        nextSpeed: 0) == nil)
        // A real 31.5 m highway fix at speed still counts.
        #expect(RideStats.segmentMeters(from: a, at: t0,
                                        to: drift, at: t0.addingTimeInterval(1),
                                        nextSpeed: 44) != nil)
    }

    @Test func recorderLiveDistanceUsesTheSharedRule() {
        let recorder = RideRecorder()
        recorder.start()
        let base = Self.start
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.5, speed: 31.5, at: base))
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.49963, speed: 31.5,
                                 at: base.addingTimeInterval(1)))
        #expect(recorder.distanceMeters > 25)
        #expect(recorder.distanceMeters < 40)

        recorder.discard()
        RideJournal.shared.finish()
    }

    @Test func recoveredRideMatchesLiveStats() {
        let points = Self.highwayPoints()
        RideJournal.shared.begin(startDate: Self.start)
        RideJournal.shared.append(points)

        let recovered = RideJournal.shared.recoveredRide()
        let stats = RideStats.compute(points: points)

        #expect(recovered != nil)
        if let recovered {
            #expect(abs(recovered.distanceMeters - stats.distanceMeters) < 0.001)
            #expect(abs(recovered.maxSpeedMps - stats.maxSpeedMps) < 0.001)
            #expect(abs(recovered.movingSeconds - stats.movingSeconds) < 0.001)
        }
        RideJournal.shared.finish()
    }

    // MARK: Journal lifetime

    @Test func suspendKeepsTheJournalForRecovery() {
        let recorder = RideRecorder()
        recorder.start()
        let base = Self.start
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.5, speed: 10, at: base))
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.4995, speed: 10,
                                 at: base.addingTimeInterval(1)))
        recorder.suspend()

        #expect(RideJournal.shared.hasPendingRide)
        #expect(RideJournal.shared.recoveredRide() != nil)

        RideJournal.shared.finish()
    }

    @Test func explicitDiscardStillDeletesTheJournal() {
        let recorder = RideRecorder()
        recorder.start()
        recorder.ingest(Self.fix(lat: 40.7, lon: -73.5, speed: 10, at: Self.start))
        recorder.discard()
        #expect(!RideJournal.shared.hasPendingRide)
    }

    // MARK: Reroute generation

    @Test func staleRerouteCannotReplaceANewRoute() {
        // Speaking in a test host activates an audio session and costs about
        // thirty seconds per prompt; these tests only care about state.
        let voiceKey = "navigation.voice"
        let previousVoice = UserDefaults.standard.object(forKey: voiceKey)
        UserDefaults.standard.set(false, forKey: voiceKey)
        defer {
            if let previousVoice {
                UserDefaults.standard.set(previousVoice, forKey: voiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: voiceKey)
            }
        }

        let first = Self.route(lon: -122.0)
        let second = Self.route(lon: -121.9)
        let staleResult = Self.route(lon: -121.8)

        let nav = NavigationManager()
        nav.start(first, roads: [])
        let generationAtReroute = nav.routeGeneration

        // Revert ends navigation and starts another route while the reroute is
        // still in flight.
        nav.stop()
        nav.start(second, roads: [])
        nav.finishReroute(staleResult, generation: generationAtReroute)
        #expect(nav.route?.id == second.id)

        // A result that belongs to the live route is still applied.
        nav.finishReroute(staleResult, generation: nav.routeGeneration)
        #expect(nav.route?.id == staleResult.id)

        nav.stop()
        #expect(nav.route == nil)
    }

    // MARK: Position accuracy

    /// A 1 km straight run east from `lon` with a turn at `turnAt` and the
    /// finish at 1 km. The geometry has no corners, so the maneuvers are
    /// supplied by hand: these tests are about where the app thinks the rider
    /// is, not about turn detection.
    private static func accuracyRoute(lon: Double = -73.5,
                                      turnAt: Double = 400,
                                      length: Double = 1_000) -> PlannedRoute {
        let degreesPerMeter = 1 / (111_320 * cos(40.7 * .pi / 180))
        let points = stride(from: 0.0, through: length, by: 10).map { meters in
            RoutePoint(lat: 40.7, lon: lon + meters * degreesPerMeter, road: 1)
        }
        var route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 90)
        route.steps = [
            NavStep(id: 0, turn: .start, road: nil, at: 0, distance: 0),
            NavStep(id: 1, turn: .right, road: "Main St", at: 40, distance: turnAt),
            NavStep(id: 2, turn: .arrive, road: nil, at: points.count - 1, distance: length)
        ]
        return route
    }

    /// A fix `meters` along the accuracy route, `lateral` metres off it, taken
    /// `age` seconds ago.
    private static func accuracyFix(on route: PlannedRoute, at meters: Double,
                                    lateral: Double = 0, speed: Double = 20,
                                    course: Double = 90, age: TimeInterval = 0) -> CLLocation {
        let degreesPerMeter = 1 / (111_320 * cos(40.7 * .pi / 180))
        let coordinate = CLLocationCoordinate2D(
            latitude: 40.7 + lateral / 110_540,
            longitude: route.points[0].lon + meters * degreesPerMeter
        )
        return CLLocation(coordinate: coordinate,
                          altitude: 10,
                          horizontalAccuracy: 5,
                          verticalAccuracy: 5,
                          course: course,
                          speed: speed,
                          timestamp: Date().addingTimeInterval(-age))
    }

    /// Navigation with the voice muted: speaking in the test host activates an
    /// audio session and costs about thirty seconds per prompt.
    private static func silentNavigation(_ route: PlannedRoute) -> NavigationManager {
        UserDefaults.standard.set(false, forKey: "navigation.voice")
        let nav = NavigationManager()
        nav.start(route, roads: [])
        return nav
    }

    @Test func approachManeuversSitAtTheEndOfTheirMapKitStep() {
        // Real MKDirections data: a 1290 m "Turn right onto 7th Ave" is the
        // ride east along 46th St, so the turn itself is 1290 m in. Reading
        // each step's distance as its start pointed every maneuver at the
        // previous junction.
        let steps = NavigationManager.approachSteps(from: [
            (instruction: "", distance: 0),
            (instruction: "Continue onto Murray St", distance: 70.6),
            (instruction: "Turn right onto West St", distance: 563.5),
            (instruction: "Turn left onto W 46th St", distance: 2_017.8),
            (instruction: "Turn right onto 7th Ave", distance: 1_290),
            (instruction: "Arrive at the destination", distance: 75.5)
        ])

        #expect(steps.count == 5)
        #expect(abs(steps[0].at - 70.6) < 0.01)
        #expect(abs(steps[4].at - 4_017.4) < 0.01)
        #expect(steps[4].instruction.hasPrefix("Arrive"))
        // Monotonic: the arrival is the furthest maneuver, not one step short
        // of the destination.
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.at < $1.at })
    }

    @Test func turnCounterCoversTheAgeOfTheFix() {
        let route = Self.accuracyRoute()
        let nav = Self.silentNavigation(route)

        nav.handle(Self.accuracyFix(on: route, at: 0))
        #expect(nav.joined)
        #expect(abs(nav.stepDistance - 400) < 1)

        // This fix was taken 1.5 s ago at 20 m/s, so the rider is 30 m past
        // it. The counter used to read the fix position verbatim and show
        // 400 - 300 = 100 m for a junction 70 m away.
        nav.handle(Self.accuracyFix(on: route, at: 300, age: 1.5))
        #expect(abs(nav.routeProgress - 330) < 1.5)
        #expect(abs(nav.stepDistance - 70) < 1.5)

        // The arrow rides the route at the predicted distance instead of
        // hanging back at the stale fix.
        let arrow = nav.userCoordinate
        #expect(arrow != nil)
        if let arrow {
            let expected = route.points[33].lon
            #expect(abs(arrow.longitude - expected) < 1e-6)
            #expect(abs(arrow.latitude - 40.7) < 1e-6)
        }
        nav.stop()
    }

    @Test func predictionNeverPassesTheNextManeuver() {
        let route = Self.accuracyRoute()
        let nav = Self.silentNavigation(route)
        nav.handle(Self.accuracyFix(on: route, at: 0))

        // 2 s at 25 m/s is 50 m of lead with 10 m left to the turn: the
        // counter hits zero and waits for a fix to prove the turn was made.
        nav.handle(Self.accuracyFix(on: route, at: 390, speed: 25, age: 2))
        #expect(nav.routeProgress <= 401)
        #expect(nav.routeProgress >= 399)
        nav.stop()
    }

    @Test func predictionDoesNotRetireTheTurnTheRiderIsLookingAt() {
        let route = Self.accuracyRoute()
        let nav = Self.silentNavigation(route)
        nav.handle(Self.accuracyFix(on: route, at: 0))

        // A stale fix 60 m before the junction with enough lead to reach it:
        // the banner must still be the turn, at zero, not the maneuver after
        // it. This is the "TURN NOW" state at the light.
        nav.handle(Self.accuracyFix(on: route, at: 340, speed: 30, age: 2))
        #expect(nav.step?.id == 1)
        #expect(nav.stepDistance < 0.01, "distance \(nav.stepDistance) progress \(nav.routeProgress)")

        // A fresh fix past the junction retires the turn.
        nav.handle(Self.accuracyFix(on: route, at: 410, speed: 30))
        #expect(nav.step?.id == 2)
        nav.stop()
    }

    @Test func fixNoiseDoesNotTickTheTurnCounterBackwards() {
        let route = Self.accuracyRoute()
        let nav = Self.silentNavigation(route)
        nav.handle(Self.accuracyFix(on: route, at: 0))
        nav.handle(Self.accuracyFix(on: route, at: 300))
        #expect(abs(nav.routeProgress - 300) < 1)

        // Three metres behind the last match is drift, not reversing.
        nav.handle(Self.accuracyFix(on: route, at: 297))
        #expect(abs(nav.routeProgress - 300) < 1)
        nav.stop()
    }

    @Test func leavingTheRouteStopsTheCountdownImmediately() {
        let route = Self.accuracyRoute()
        let nav = Self.silentNavigation(route)
        nav.handle(Self.accuracyFix(on: route, at: 0))
        nav.handle(Self.accuracyFix(on: route, at: 200))
        #expect(!nav.offRoute)

        // 55 m is inside the GPS-bias band that used to flap in and out of
        // "off route" every fix, so it must be tolerated.
        nav.handle(Self.accuracyFix(on: route, at: 205, lateral: 55))
        #expect(!nav.offRoute)

        // 90 m is genuinely off: say so now rather than leaving the last good
        // "70 m to the turn" on screen.
        nav.handle(Self.accuracyFix(on: route, at: 210, lateral: 90))
        #expect(nav.offRoute)
        #expect(abs(nav.routeProgress - 200) < 1)
        nav.stop()
    }

    @Test func stoppedAtALightTheHeadingComesFromTheRoute() {
        let route = Self.accuracyRoute()
        let nav = Self.silentNavigation(route)
        nav.handle(Self.accuracyFix(on: route, at: 0))

        // Stationary with an invalid course used to leave the arrow spinning
        // on whatever the last fix happened to say.
        nav.handle(Self.accuracyFix(on: route, at: 320, speed: 0, course: -1))
        #expect(nav.userHeading > 85 && nav.userHeading < 95)
        nav.stop()
    }

    @Test func fixAgeIsNeverNegative() {
        let future = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.7, longitude: -73.5),
                                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                course: 0, speed: 0,
                                timestamp: Date().addingTimeInterval(30))
        #expect(NavigationManager.fixAge(of: future) == 0)
        let old = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.7, longitude: -73.5),
                             altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                             course: 0, speed: 0,
                             timestamp: Date().addingTimeInterval(-3))
        #expect(abs(NavigationManager.fixAge(of: old) - 3) < 0.5)
    }

    // MARK: Elevation cache

    @Test func elevationKeyDistinguishesLoopsWithTheSameEndpoints() {
        func loop(bulge: Double) -> [CLLocationCoordinate2D] {
            var coordinates: [CLLocationCoordinate2D] = []
            for index in 0..<40 {
                let angle = Double(index) / 39 * 2 * .pi
                coordinates.append(CLLocationCoordinate2D(
                    latitude: 40.7 + sin(angle) * bulge,
                    longitude: -73.5 + cos(angle) * bulge
                ))
            }
            // The key used to be first + last + count, so make those identical.
            coordinates[39] = coordinates[0]
            return coordinates
        }

        let east = loop(bulge: 0.01)
        let west = loop(bulge: -0.01)

        #expect(east.count == west.count)
        #expect(east.first?.latitude == west.first?.latitude)
        #expect(east.last?.latitude == west.last?.latitude)
        #expect(ElevationService.cacheKey(east) != ElevationService.cacheKey(west))
        #expect(ElevationService.cacheKey(east) == ElevationService.cacheKey(east))
    }
}
