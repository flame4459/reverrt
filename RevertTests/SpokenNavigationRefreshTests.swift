import Testing
import Foundation
import CoreLocation
@testable import Revert

/// Regression coverage for the spoken-navigation refresh.
@MainActor
struct SpokenNavigationRefreshTests {

    // MARK: - Scheduler

    @Test func highwayEarlyPromptThenDecelerationStillDeliversClosePrompts() {
        var state = AnnouncementScheduler.State()
        // 105 km/h: early prompt at 3.2 km.
        let early = AnnouncementScheduler.decide(state: &state, distance: 3_200,
                                                 speed: 29, now: Date(timeIntervalSince1970: 1))
        #expect(early?.stage == .early)
        #expect(early?.spokenDistance == 3_200)

        // The rider slows to 45 km/h. At 200 m the middle stage has never been
        // spoken at this distance and must not be suppressed by the old rung.
        let middle = AnnouncementScheduler.decide(state: &state, distance: 200,
                                                  speed: 12.5, now: Date(timeIntervalSince1970: 2))
        #expect(middle?.stage == .middle)

        let close = AnnouncementScheduler.decide(state: &state, distance: 140,
                                                 speed: 12.5, now: Date(timeIntervalSince1970: 3))
        #expect(close?.stage == .close)

        let final = AnnouncementScheduler.decide(state: &state, distance: 35,
                                                 speed: 12.5, now: Date(timeIntervalSince1970: 4))
        #expect(final?.stage == .final)
        #expect(final?.spokenDistance == nil, "the immediate prompt drops the distance")
    }

    @Test func acceleratingDoesNotReplayAlreadySpokenStages() {
        var state = AnnouncementScheduler.State()
        let early = AnnouncementScheduler.decide(state: &state, distance: 300,
                                                 speed: 12.5, now: Date(timeIntervalSince1970: 1))
        #expect(early?.stage == .early)

        // Same distance again at the same speed: no duplicate.
        #expect(AnnouncementScheduler.decide(state: &state, distance: 300,
                                            speed: 12.5,
                                            now: Date(timeIntervalSince1970: 1.5)) == nil)

        // Rider accelerates; the middle band is still due and is delivered.
        // At 160 m the rider is inside both the middle and the close bands;
        // the closer stage is the useful one.
        let closer = AnnouncementScheduler.decide(state: &state, distance: 160,
                                                  speed: 29, now: Date(timeIntervalSince1970: 2))
        #expect(closer?.stage == .close)
    }

    @Test func aStepThatBecomesCurrentCloseIsAnnouncedOnceWithADistance() {
        var state = AnnouncementScheduler.State()
        let decision = AnnouncementScheduler.decide(state: &state, distance: 40,
                                                    speed: 12, now: Date(timeIntervalSince1970: 1))
        #expect(decision?.stage == .close)
        #expect(decision?.spokenDistance == 40,
                "first announcement of a close step still needs its distance")
        #expect(AnnouncementScheduler.decide(state: &state, distance: 36,
                                            speed: 12,
                                            now: Date(timeIntervalSince1970: 2)) == nil)
    }

    // MARK: - Distance accuracy

    @Test func distancesAreSpokenAtTheirRealValueNotTheNearestClip() {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.metric)

        let step = NavStep(id: 3, turn: .left, road: "Main Street", at: 0, distance: 0)
        let prompt = Narrator.instruction(step, distance: 55)
        guard case .text(let lead)? = prompt.parts.first else {
            Issue.record("expected a spoken distance first")
            return
        }
        #expect(lead == "In 60 meters", "55 m must not become 200 m; got \(lead)")
        #expect(!lead.contains("200"))
    }

    @Test func aPackWithoutDistanceClipsStillSpeaksTheDistance() {
        let step = NavStep(id: 4, turn: .right, road: "Oak Road", at: 0, distance: 0)
        let prompt = Narrator.instruction(step, distance: 300)
        let plan = Speaker.plan(for: prompt, available: [.turnRight])
        guard case .speech(let lead) = plan.first else {
            Issue.record("missing distance clip must fall back to TTS")
            return
        }
        #expect(lead.hasPrefix("In "))
        #expect(plan.contains(.clip(.turnRight)))
    }

    @Test func laneAdviceSurvivesTheFinalPrompt() {
        let lanes = LaneGuidance(lanes: [.init(directions: [.left]),
                                         .init(directions: [.through])],
                                 recommended: [0])
        let step = NavStep(id: 5, turn: .left, road: "Elm Street", at: 0,
                           distance: 0, laneGuidance: lanes)
        let prompt = Narrator.instruction(step, distance: nil)
        #expect(prompt.parts.contains(.text("use the left lane.")))
    }

    // MARK: - Sprint identity

    @Test func applyingSprintKindPreservesGeometry() {
        let points = [RoutePoint(lat: 40, lon: -73, road: 1),
                      RoutePoint(lat: 40.01, lon: -73.01, road: 2),
                      RoutePoint(lat: 40.02, lon: -73.02, road: 3)]
        let base = PlannedRoute(points: points, roads: [:], twistPerKm: 10,
                                retraced: 0, bearing: 0, kind: .directions)
        let sprint = RoutePlanner.applying(routeKind: .sprint, to: base)
        #expect(sprint.kind == .sprint)
        #expect(sprint.laps == 1)
        #expect(sprint.points == base.points)
        #expect(sprint.length == base.length)
        #expect(sprint.steps.count == base.steps.count)
    }

    // MARK: - Completion wording

    @Test func loopAndSprintCompletionAreSpecific() {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.metric)

        #expect(Narrator.lap(2, of: 3, last: 252).fallback
                == "Lap 2 of 3. 4 minutes 12 seconds for the last one.")
        #expect(Narrator.loopComplete(total: 1_000).fallback
                == "Loop complete. 16 minutes 40 seconds total.")
        #expect(Narrator.sprintFinish(time: 252).fallback
                == "Finish. 4 minutes 12 seconds.")
        #expect(Narrator.startGuidance(distance: 800).fallback
                == "Head to the start. 800 meters away.")
        #expect(Narrator.approach("Turn left onto Main Street", distance: 300).fallback
                == "In 300 meters, turn left onto Main Street")
    }

    // MARK: - Live behaviour

    private func directionsRoute() -> PlannedRoute {
        var points: [RoutePoint] = []
        for index in 0...60 {
            points.append(RoutePoint(lat: 40.0 + Double(index) * 0.0007,
                                     lon: -73.0, road: index < 30 ? 1 : 2))
        }
        var route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0, kind: .directions)
        route.steps = [
            NavStep(id: 0, turn: .start, road: "Start Road", at: 0, distance: 0),
            NavStep(id: 1, turn: .right, road: "Turn Road", at: 30,
                    distance: route.cumulative[30]),
            NavStep(id: 2, turn: .arrive, road: nil, at: points.count - 1,
                    distance: route.length)
        ]
        return route
    }

    private func enableVoice() {
        UserDefaults.standard.set(false, forKey: "voice.muted")
        UserDefaults.standard.set(true, forKey: "navigation.voice")
        UserDefaults.standard.set(true, forKey: "alert.voice")
        UserDefaults.standard.set(true, forKey: "companion.voice")
        Speaker.shared.clearSpokenHistory()
    }

    @Test func aTurnProtectsItselfFromTheStraightCalloutInTheSameFix() throws {
        enableVoice()
        defer { Speaker.shared.stop() }
        let route = directionsRoute()
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])
        let first = route.points[0]
        let second = route.points[1]
        let heading = RoadGraph.flat(first.lat, first.lon, second.lat, second.lon).heading
        nav.handle(CLLocation(coordinate: first.coordinate, altitude: 10,
                              horizontalAccuracy: 5, verticalAccuracy: 5,
                              course: heading, speed: 30, timestamp: Date()))
        let history = Speaker.shared.spokenHistory
        #expect(history.contains { $0.lowercased().contains("turn right") },
                "turn prompt missing: \(history)")
        #expect(!history.contains { $0.hasPrefix("Continue") },
                "a straight callout must not run in the same fix as a turn")
    }

    @Test func repeatLastInstructionSpeaksTheSameManeuver() throws {
        enableVoice()
        defer { Speaker.shared.stop() }
        let route = directionsRoute()
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])
        let first = route.points[0]
        let second = route.points[1]
        let heading = RoadGraph.flat(first.lat, first.lon, second.lat, second.lon).heading
        nav.handle(CLLocation(coordinate: first.coordinate, altitude: 10,
                              horizontalAccuracy: 5, verticalAccuracy: 5,
                              course: heading, speed: 30, timestamp: Date()))
        let before = Speaker.shared.spokenHistory.count
        #expect(nav.repeatLastInstruction())
        let after = Speaker.shared.spokenHistory.count
        if after != before + 1 {
            Issue.record("repeat count before=\(before) after=\(after) history=\(Speaker.shared.spokenHistory)")
        }
        #expect(Speaker.shared.spokenHistory.last?.lowercased().contains("turn right") == true)
    }

    @Test func aTimedRouteAnnouncesTheStartLineWhenTheRiderIsAwayFromIt() {
        enableVoice()
        defer { Speaker.shared.stop() }
        // A small loop around 41.0, -73.0; the rider is ~140 km away.
        var points: [RoutePoint] = []
        let corners = [(41.0, -73.0), (41.01, -73.0), (41.01, -73.01), (41.0, -73.01)]
        for (index, corner) in corners.enumerated() {
            let next = corners[(index + 1) % corners.count]
            for step in 0..<20 {
                let t = Double(step) / 20
                points.append(RoutePoint(lat: corner.0 + (next.0 - corner.0) * t,
                                         lon: corner.1 + (next.1 - corner.1) * t,
                                         road: Int64(index + 1)))
            }
        }
        points.append(points[0])
        let route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0, kind: .loop)
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])
        nav.handle(CLLocation(latitude: 40.0, longitude: -74.0))
        #expect(Speaker.shared.spokenHistory.contains { $0.hasPrefix("Head to the start") },
                "got \(Speaker.shared.spokenHistory)")
    }

    @Test func aceRepeatsTheLastInstruction() {
        let director = CompanionDirector.shared
        let previousState = director.state
        director.setState(.on)
        defer { director.setState(previousState) }

        let context = CompanionContext(lastInstruction: "In 300 meters, turn left onto Main Street")
        #expect(director.answer("say that again", context: context)
                == "In 300 meters, turn left onto Main Street")
        #expect(director.answer("what was that turn", context: context)
                == "In 300 meters, turn left onto Main Street")
    }

    @Test func aceAnswersUseTheCompanionChannelNotHazardVoice() {
        enableVoice()
        defer { Speaker.shared.stop() }
        UserDefaults.standard.set(false, forKey: "alert.voice")
        defer { UserDefaults.standard.set(true, forKey: "alert.voice") }
        Speaker.shared.clearSpokenHistory()

        Speaker.shared.say("Ace line", kind: .companion)
        #expect(Speaker.shared.spokenHistory.contains("Ace line"),
                "hazard voice must not silence the companion channel")
    }
}
