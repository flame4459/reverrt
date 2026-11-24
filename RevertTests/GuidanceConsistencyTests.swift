import Testing
import Foundation
@testable import Revert

@MainActor
struct GuidanceConsistencyTests {
    @Test func everyPathUsesOneClassifier() {
        // The same sentences MapKit hands to directions, reroutes and the
        // approach to a loop must mean the same thing everywhere.
        let cases: [(String, NavStep.Turn)] = [
            ("Turn left onto Main Street", .left),
            ("Turn right onto Main Street", .right),
            ("Keep left onto Route 9", .slightLeft),
            ("Keep right to stay on I-495", .slightRight),
            ("Take a slight right onto Town Path", .slightRight),
            ("Bear left at the fork", .slightLeft),
            ("Make a sharp left", .sharpLeft),
            ("At the roundabout, take the second exit", .slightRight),
            ("Make a U-turn", .uTurn),
            ("Continue straight", .straight)
        ]
        for (phrase, expected) in cases {
            #expect(NavStep.Turn.parse(phrase) == expected, "\(phrase)")
        }
    }

    @Test func approachSymbolsComeFromTheSameClassifier() {
        let steps = NavigationManager.approachSteps(from: [
            (instruction: "Turn left onto Main Street", distance: 100),
            (instruction: "Keep right onto Route 9", distance: 150)
        ])
        #expect(steps.count == 2)
        #expect(steps[0].symbol == NavStep.Turn.parse("Turn left onto Main Street").symbol)
        #expect(steps[1].symbol == NavStep.Turn.parse("Keep right onto Route 9").symbol)
    }

    @Test func proseStepsKeepTheirWordingEvenWithARoadName() {
        let step = NavStep(id: 1, turn: .left, road: "Main Street", at: 1,
                           distance: 100, text: "Turn left onto Main Street")
        let prompt = Narrator.instruction(step, distance: 91.44)
        #expect(prompt.fallback == "In 300 feet, turn left onto Main Street",
                "got \(prompt.fallback)")
    }

    @Test func flippingIsSymmetric() {
        for turn in [NavStep.Turn.left, .right, .slightLeft, .slightRight,
                     .sharpLeft, .sharpRight, .uTurn, .straight, .start, .arrive] {
            #expect(turn.flipped.flipped == turn)
        }
        #expect(NavStep.Turn.left.flipped == .right)
    }
}
