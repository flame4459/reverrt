import UIKit

/// A small wrapper around the one background-task API, so downloads and
/// exports that outlive the screen do not rely on each caller remembering the
/// invalid-identifier rules.
@MainActor
enum BackgroundWork {
    static func begin(_ name: String) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name) {}
    }

    static func end(_ id: UIBackgroundTaskIdentifier) {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }
}
