import SwiftUI
import UIKit

/// Reference-counted owner for the shared `isIdleTimerDisabled` flag.
///
/// Policy: the screen is held awake only while the rider is riding (cockpit and
/// countdown) and while an offline download is on screen. Browsing screens —
/// Home, Plan, History, Settings — never hold it, so a phone left on the tank
/// bag while planning still locks.
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
