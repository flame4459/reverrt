import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct DirectorTests {
    @Test func filmHasABeginningMiddleAndEnd() {
        let ride = DebugScreens.sampleRide()
        let film = ReplayFilm.make(ride: ride)
        #expect(!film.shots.isEmpty)
        #expect(film.shots.first?.kind == .establishing)
        #expect(film.shots.last?.kind == .outro)
        #expect(film.highlights.count <= 5)
        #expect(film.duration > 10)
        #expect(film.shots.contains { $0.moment != nil })
        let cornerShots = film.shots.filter { $0.moment != nil }
        #expect(Set(cornerShots.map(\.kind)).count >= 2)
    }

    @Test func shotTimeWarpsNeverGoBackwards() {
        let ride = DebugScreens.sampleRide()
        let film = ReplayFilm.make(ride: ride)
        for shot in film.shots {
            var previous = shot.rideElapsed(at: 0)
            for index in 1...100 {
                let next = shot.rideElapsed(at: Double(index) / 100)
                #expect(next >= previous - 0.001)
                previous = next
            }
            #expect(abs(shot.rideElapsed(at: 0) - shot.rideStart) < 0.01)
            #expect(abs(shot.rideElapsed(at: 1) - shot.rideEnd) < 0.01)
        }
    }

    @Test func filmLookupLandsInsideAShot() {
        let ride = DebugScreens.sampleRide()
        let film = ReplayFilm.make(ride: ride)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let time = film.duration * fraction
            let found = film.shot(at: time)
            #expect(found != nil)
            if let found {
                #expect(found.elapsed >= found.shot.rideStart - 0.01)
                #expect(found.elapsed <= found.shot.rideEnd + 0.01)
            }
        }
    }

    @Test func riderDirectionsAndCameraPlansAreWired() {
        let rear = RiderViewDirection.from(relativeBearing: 0)
        #expect(rear == .rear)
        #expect(RiderSpriteAtlas.assetName(for: rear) == "chase-rider-straight")
        let right = RiderViewDirection.from(relativeBearing: 90)
        #expect(RiderSpriteAtlas.assetName(for: right) == "chase-rider-right")
        let left = RiderViewDirection.from(relativeBearing: -90)
        #expect(RiderSpriteAtlas.assetName(for: left) == "chase-rider-left")

        let ride = DebugScreens.sampleRide()
        let film = ReplayFilm.make(ride: ride)
        guard let shot = film.shots.first(where: { $0.moment != nil }),
              let sample = DirectorSample.at(points: ride.points,
                                             elapsed: shot.rideStart) else {
            Issue.record("missing shot/sample")
            return
        }
        let plan = DirectorCamera.plan(shot: shot, sample: sample, progress: 0.5, route: nil)
        #expect(plan.distance > 100)
        #expect(plan.showRider)
    }
}
