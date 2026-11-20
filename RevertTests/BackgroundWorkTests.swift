import Testing
import UIKit
@testable import Revert

@MainActor
struct BackgroundWorkTests {
    @Test func tokensCanBeTakenAndReleased() {
        let token = BackgroundWork.begin("test")
        #expect(token != .invalid)
        BackgroundWork.end(token)
        // Releasing twice must be harmless: the helper guards `.invalid`.
        BackgroundWork.end(.invalid)
    }
}
