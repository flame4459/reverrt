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
