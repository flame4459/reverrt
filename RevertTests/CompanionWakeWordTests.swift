import Testing
@testable import Revert

struct CompanionWakeWordTests {
    @Test func heyAcePrefixIsRemoved() {
        #expect(CompanionWakeWord.query(from: "Hey Ace how much further?") == "how much further")
        #expect(CompanionWakeWord.query(from: "Ace, where is fuel?") == "where is fuel")
    }

    @Test func wakeWordNeedsAWholeWord() {
        #expect(CompanionWakeWord.query(from: "race pace") == nil)
        #expect(CompanionWakeWord.query(from: "Ace") == nil)
        #expect(CompanionWakeWord.query(from: "Jarvis how much further?") == nil)
    }

    @Test func acePrefixStillWorks() {
        #expect(CompanionWakeWord.query(from: "Ace take me home") == "take me home")
    }
}
