import SwiftUI
import UIKit

/// Reference-counted owner for the shared `isIdleTimerDisabled` flag.
///
/// Three screens used to write the global flag directly (ride recording,
/// offline downloads and route planning). One finishing could re-enable the
/// lock screen while another was still working. Every owner now acquires and
/// releases a token instead, and the flag is only cleared when the last owner
/// lets go.
@MainActor
enum IdleTimer {
    private static var owners: Set<String> = []

    /// Owners currently holding the screen awake.
    static var activeOwners: Set<String> { owners }

    static func acquire(_ owner: String) {
        owners.insert(owner)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release(_ owner: String) {
        owners.remove(owner)
        UIApplication.shared.isIdleTimerDisabled = !owners.isEmpty
    }

    static func releaseAll() {
        owners.removeAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

/// Holds an `IdleTimer` token for exactly as long as the view it is attached
/// to is on screen, so the display never dims or locks underneath a live map.
private struct KeepsScreenAwake: ViewModifier {
    let owner: String
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // `onAppear` can fire again without an intervening disappear
                // (tab switches, cover dismissal); never double-hold.
                guard !holding else { return }
                holding = true
                IdleTimer.acquire(owner)
            }
            .onDisappear {
                guard holding else { return }
                holding = false
                IdleTimer.release(owner)
            }
    }
}

extension View {
    /// Keeps the screen on for as long as this view is visible, without
    /// clobbering the other owners of the shared flag (ride recording, offline
    /// downloads, route planning).
    func keepsScreenAwake(_ owner: String) -> some View {
        modifier(KeepsScreenAwake(owner: owner))
    }
}
