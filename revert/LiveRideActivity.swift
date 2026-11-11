import ActivityKit
import Foundation

/// Starts, updates and ends the Lock Screen / Dynamic Island Live Activity.
@MainActor
final class LiveRideActivity {
    static let shared = LiveRideActivity()
    private var activity: Activity<NavigationActivityAttributes>?

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start() {
        guard activity == nil, isSupported else { return }
        // A previous process (or a crash) can leave orphaned activities behind.
        endStaleActivities()
        let attributes = NavigationActivityAttributes(startedAt: Date())
        let state = NavigationActivityAttributes.ContentState(
            title: "Ride in progress",
            distance: "—",
            speed: "—",
            offRoute: false,
            updatedAt: Date()
        )
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: Date().addingTimeInterval(90)))
    }

    func update(title: String, distance: String, speed: String, offRoute: Bool) {
        guard let activity else { return }
        let state = NavigationActivityAttributes.ContentState(
            title: title, distance: distance, speed: speed, offRoute: offRoute, updatedAt: Date()
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every Live Activity owned by this app. Called on launch, when no
    /// navigation state survives, and before starting a new activity.
    func endStaleActivities() {
        activity = nil
        for stale in Activity<NavigationActivityAttributes>.activities {
            Task {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
