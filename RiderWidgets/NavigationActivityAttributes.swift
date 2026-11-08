import ActivityKit
import Foundation

/// Shared by the app and the Live Activity extension. Keep this type name and
/// shape identical in both targets; ActivityKit uses it as the activity key.
nonisolated struct NavigationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var distance: String
        var speed: String
        var offRoute: Bool
        var updatedAt: Date
    }

    var startedAt: Date
}
