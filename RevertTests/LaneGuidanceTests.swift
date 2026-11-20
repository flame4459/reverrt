import Testing
import Foundation
@testable import Revert

@MainActor
@Suite(.serialized)
struct LaneGuidanceTests {
    @Test func parsesLeftToRightLanes() throws {
        let guidance = try #require(LaneGuidance.parse(turnLanes: "left|through|through;right", turn: .left))
        #expect(guidance.lanes.count == 3)
        #expect(guidance.recommended == [0])
        #expect(guidance.phrase == "use the left lane")
        #expect(guidance.activeFlags == [true, false, false])
    }

    @Test func picksTheLanesThatServeTheTurn() throws {
        let right = try #require(LaneGuidance.parse(turnLanes: "left|through|through;right", turn: .right))
        #expect(right.recommended == [2])
        #expect(right.phrase == "use the right lane")

        let through = try #require(LaneGuidance.parse(turnLanes: "left|through|through;right", turn: .straight))
        #expect(through.recommended == [1, 2])
    }

    @Test func twoLanesOnOneSideAreNamedAsSuch() throws {
        let guidance = try #require(LaneGuidance.parse(turnLanes: "left|left|through", turn: .left))
        #expect(guidance.recommended == [0, 1])
        #expect(guidance.phrase == "use the two left lanes")

        let right = try #require(LaneGuidance.parse(turnLanes: "through|right;right|right", turn: .right))
        #expect(right.recommended == [1, 2])
        #expect(right.phrase == "use the two right lanes")
    }

    @Test func aTurnWithNoServingLaneGivesNoAdvice() {
        #expect(LaneGuidance.parse(turnLanes: "through|through|through", turn: .left) == nil)
    }

    @Test func malformedTagIsIgnored() {
        #expect(LaneGuidance.parse(turnLanes: "", turn: .left) == nil)
        #expect(LaneGuidance.parse(turnLanes: "|", turn: .left) == nil)
        #expect(LaneGuidance.parse(turnLanes: "nonsense", turn: .left) == nil)
    }

    @Test func voiceCalloutIncludesTheLane() throws {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.imperial)

        var step = NavStep(id: 4, turn: .right, road: "Stewart Avenue", at: 20, distance: 900)
        guard let guidance = LaneGuidance.parse(turnLanes: "left|through|through;right", turn: .right) else {
            Issue.record("expected lane guidance for a right turn")
            return
        }
        step.laneGuidance = guidance
        let prompt = Narrator.instruction(step, distance: 152.4)
        #expect(prompt.fallback == "In 500 feet, use the right lane to turn right onto Stewart Avenue",
                "got \(prompt.fallback)")
    }

    @Test func noLanePhraseOnceYouAreAtTheJunction() throws {
        var step = NavStep(id: 4, turn: .right, road: "Stewart Avenue", at: 20, distance: 900)
        guard let guidance = LaneGuidance.parse(turnLanes: "left|through|through;right", turn: .right) else {
            Issue.record("expected lane guidance for a right turn")
            return
        }
        step.laneGuidance = guidance
        let prompt = Narrator.instruction(step, distance: nil)
        #expect(prompt.fallback == "Turn right onto Stewart Avenue")
    }
}

@MainActor
struct LaneRevealTests {
    @Test func laneStripRevealsAtHighwayRange() {
        #expect(LaneGuidance.revealDistance(forSpeed: 30) == 1_600)
        #expect(LaneGuidance.revealDistance(forSpeed: 20) == 800)
        #expect(LaneGuidance.revealDistance(forSpeed: 10) == 400)
    }
}
