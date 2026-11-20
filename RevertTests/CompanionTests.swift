import Testing
import Foundation
@testable import Revert

@MainActor
struct CompanionTests {
    @Test func stateCyclesOnAskedOff() {
        #expect(CompanionState.on.next == .askedOnly)
        #expect(CompanionState.askedOnly.next == .off)
        #expect(CompanionState.off.next == .on)
    }

    @Test func distanceAnswerUsesLiveNavigationValues() {
        let previous = Units.preference
        defer { Units.setPreference(previous) }
        Units.setPreference(.imperial)
        var context = CompanionContext()
        context.remainingMeters = 17_702
        context.estimatedSeconds = 720
        let answer = CompanionTools.answer("how much further?", context: context)
        #expect(answer != nil)
        #expect(answer?.contains("11") == true)
        #expect(answer?.contains("12:00") == true)
    }

    @Test func hazardAnswerUsesApproachNameAndDistance() {
        var context = CompanionContext()
        context.nearestHazardMeters = 200
        context.hazardName = "Gravel"
        let answer = CompanionTools.answer("anything to worry about?", context: context)
        #expect(answer?.contains("Gravel") == true)
    }

    @Test func arrivalScriptIsDeterministic() {
        let line = CompanionScript.arrival(distance: "82 miles", time: "3:10", address: "boss")
        #expect(line == "That's you, boss. 82 miles in 3:10.")
    }
}
