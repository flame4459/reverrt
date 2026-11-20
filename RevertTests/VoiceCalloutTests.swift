import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
@Suite(.serialized)
struct VoiceCalloutTests {
    // MARK: Distance wording

    @Test func imperialDistancesUseNavigationBuckets() {
        #expect(Units.spokenDistance(15) == "50 feet")
        #expect(Units.spokenDistance(61) == "200 feet")
        #expect(Units.spokenDistance(91) == "300 feet")
        #expect(Units.spokenDistance(152) == "500 feet")
        #expect(Units.spokenDistance(305) == "1,000 feet")
        #expect(Units.spokenDistance(1609) == "one mile")
        #expect(Units.spokenDistance(2414) == "one and a half miles")
        #expect(Units.spokenDistance(8047) == "5 miles")
    }

    @Test func metricDistancesUseNavigationBuckets() {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.metric)
        #expect(Units.spokenDistance(95) == "100 meters")
        #expect(Units.spokenDistance(152) == "150 meters")
        #expect(Units.spokenDistance(402) == "400 meters")
        #expect(Units.spokenDistance(1609) == "one and a half kilometers")
        #expect(Units.spokenDistance(8047) == "8 kilometers")
    }

    // MARK: Phrasing

    @Test func instructionsLeadWithDistanceAndNameTheRoad() {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.imperial)

        let step = NavStep(id: 1, turn: .left, road: "Stewart Avenue", at: 10, distance: 500)
        let prompt = Narrator.instruction(step, distance: 91.44)
        #expect(prompt.fallback == "In 300 feet, turn left onto Stewart Avenue",
                "got \(prompt.fallback)")
    }

    @Test func arrivalIsAnnouncedInAdvanceNotOnTheSpot() {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.imperial)
        let step = NavStep(id: 9, turn: .arrive, road: nil, at: 300, distance: 5_000)
        let early = Narrator.instruction(step, distance: 152.4)
        #expect(early.fallback == "In 500 feet, you will arrive", "got \(early.fallback)")
        let now = Narrator.instruction(step, distance: nil)
        #expect(now.fallback == "You have arrived")
    }

    @Test func straightCalloutSaysHowFarToStayOnTheRoad() {
        let prompt = Narrator.straight(road: "Stewart Avenue", distance: 4_828)
        #expect(prompt.fallback == "Continue on Stewart Avenue for 3 miles")
    }

    // MARK: Live guidance

    @Test func approachSpeaksADistanceBeforeTheJunction() {
        var points: [RoutePoint] = []
        for index in 0...20 {
            points.append(RoutePoint(lat: 40.0 + Double(index) * 0.00018, lon: -73.0, road: 0))
        }
        for index in 1...20 {
            points.append(RoutePoint(lat: points[20].lat, lon: -73.0 + Double(index) * 0.000235, road: 0))
        }
        let route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0, kind: .directions)
        // The simulator's app host keeps real defaults; make sure voice is on
        // for the duration of the test.
        let defaults = UserDefaults.standard
        let previousMuted = defaults.object(forKey: "voice.muted")
        let previousNavigationVoice = defaults.object(forKey: "navigation.voice")
        defaults.set(false, forKey: "voice.muted")
        defaults.set(true, forKey: "navigation.voice")
        defer {
            if let previousMuted { defaults.set(previousMuted, forKey: "voice.muted") }
            else { defaults.removeObject(forKey: "voice.muted") }
            if let previousNavigationVoice { defaults.set(previousNavigationVoice, forKey: "navigation.voice") }
            else { defaults.removeObject(forKey: "navigation.voice") }
        }

        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])

        // Ride the whole approach so the step actually becomes current.
        var heardDistanceCallout = false
        for index in 0..<19 {
            let a = route.points[index], b = route.points[index + 1]
            let heading = RoadGraph.flat(a.lat, a.lon, b.lat, b.lon).heading
            nav.handle(CLLocation(coordinate: a.coordinate, altitude: 10,
                                  horizontalAccuracy: 4, verticalAccuracy: 4,
                                  course: heading, speed: 12, timestamp: Date()))
            if let spoken = Speaker.shared.lastSpokenFallback,
               spoken.hasPrefix("In "), spoken.lowercased().contains("right") {
                heardDistanceCallout = true
            }
        }
        #expect(heardDistanceCallout,
                "expected 'In <distance>, turn right', last was \(Speaker.shared.lastSpokenFallback ?? "nil")")
    }
}

    @Test func aStepThatStartsCloseAnnouncesOnce() {
        var points: [RoutePoint] = []
        for index in 0...20 {
            points.append(RoutePoint(lat: 40.0 + Double(index) * 0.00018, lon: -73.0, road: 0))
        }
        for index in 1...20 {
            points.append(RoutePoint(lat: points[20].lat, lon: -73.0 + Double(index) * 0.000235, road: 0))
        }
        let route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0, kind: .directions)

        let defaults = UserDefaults.standard
        let previousMuted = defaults.object(forKey: "voice.muted")
        let previousNavigationVoice = defaults.object(forKey: "navigation.voice")
        defaults.set(false, forKey: "voice.muted")
        defaults.set(true, forKey: "navigation.voice")
        defer {
            if let previousMuted { defaults.set(previousMuted, forKey: "voice.muted") }
            else { defaults.removeObject(forKey: "voice.muted") }
            if let previousNavigationVoice { defaults.set(previousNavigationVoice, forKey: "navigation.voice") }
            else { defaults.removeObject(forKey: "navigation.voice") }
        }

        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])
        Speaker.shared.clearSpokenHistory()

        // Two fixes ~40 m before the corner: the step becomes current already
        // inside every rung, which used to fire rung 1, 2, 3 and "now" within
        // three seconds.
        for index in [17, 18] {
            let a = points[index], b = points[index + 1]
            let heading = RoadGraph.flat(a.lat, a.lon, b.lat, b.lon).heading
            nav.handle(CLLocation(coordinate: a.coordinate, altitude: 10,
                                  horizontalAccuracy: 4, verticalAccuracy: 4,
                                  course: heading, speed: 12, timestamp: Date()))
        }
        let callouts = Speaker.shared.spokenHistory.filter { $0.contains("turn right") }
        #expect(callouts.count == 1, "expected one callout, got \(callouts)")
        #expect(callouts.first?.hasPrefix("In ") == true)
    }
