import Testing
import Foundation
@testable import Revert

@MainActor
struct NetworkFailureCopyTests {
    @Test func eachTransportFailureGetsItsOwnSentence() {
        let offline = RoutePlanner.failureCopy(for: URLError(.notConnectedToInternet))
        #expect(offline.contains("offline"))

        let timeout = RoutePlanner.failureCopy(for: URLError(.timedOut))
        #expect(timeout.contains("didn't answer"))

        let dns = RoutePlanner.failureCopy(for: URLError(.cannotFindHost))
        #expect(dns.contains("Couldn't reach"))

        let tls = RoutePlanner.failureCopy(for: URLError(.secureConnectionFailed))
        #expect(tls.contains("secure connection"))

        let other = RoutePlanner.failureCopy(for: URLError(.unknown))
        #expect(other.contains("Check your connection"))
    }

    @Test func nonTransportErrorsStillGetCopy() {
        struct Weird: Error {}
        #expect(!RoutePlanner.failureCopy(for: Weird()).isEmpty)
    }
}
