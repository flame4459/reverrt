import Testing
@testable import Revert

@MainActor
struct AlertTimingTests {
    private func mph(_ value: Double) -> Double { value * 0.44704 }

    @Test func approachBandExpandsWithSpeed() {
        #expect(NavigationManager.approachDistance(forSpeed: mph(40)) == 305)
        #expect(NavigationManager.approachDistance(forSpeed: mph(50)) == 805)
        #expect(NavigationManager.approachDistance(forSpeed: mph(60)) == 3_218)
        #expect(NavigationManager.approachDistance(forSpeed: mph(80)) == 3_218)
        #expect(NavigationManager.approachDistance(forSpeed: mph(100)) == 4_828)
    }

    @Test func turnRungsAreOrderedAndScaled() {
        let rungs = NavigationManager.calloutRungs(forSpeed: mph(80))
        #expect(rungs.count == 3)
        #expect(rungs[0] == 3_218)
        #expect(rungs[0] > rungs[1])
        #expect(rungs[1] > rungs[2])
        #expect(rungs[2] >= 150)
    }

    @Test func finalPromptScalesWithSpeed() {
        #expect(NavigationManager.finalPromptDistance(forSpeed: 0) == 35)
        #expect(abs(NavigationManager.finalPromptDistance(forSpeed: mph(80)) - 107.3) < 0.2)
        #expect(NavigationManager.finalPromptDistance(forSpeed: mph(100)) <= 150)
    }
}
