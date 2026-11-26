import ActivityKit
import Foundation

/// Starts, updates and ends the Lock Screen / Dynamic Island Live Activity.
///
/// The deployment target is iOS 18, so the adaptive `NavigationActivityAttributes`
/// (which can also render the small Watch Smart Stack / car dashboard family) is
/// the only activity type the app requests.
@MainActor
final class LiveRideActivity {
    static let shared = LiveRideActivity()

    private var activity: Activity<NavigationActivityAttributes>?

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var isActive: Bool { activity != nil }

    func start() {
        RideDebug.shared.event("LIVE-START", [
            ("supported", isSupported ? "yes" : "no"),
            ("alreadyActive", isActive ? "yes" : "no")
        ])
        guard !isActive, isSupported else { return }
        // A previous process (or a crash) can leave orphaned activities behind.
        endStaleActivities()
        let content = ActivityContent(state: Self.placeholderState(),
                                      staleDate: Date().addingTimeInterval(90))
        activity = try? Activity.request(
            attributes: NavigationActivityAttributes(startedAt: Date()),
            content: content
        )
        RideDebug.shared.event("LIVE-STARTED", [
            ("started", activity != nil ? "yes" : "no"),
            ("id", activity?.id ?? "—")
        ])
    }

    /// At most one push per second unless the payload actually changed; alerts
    /// always go through. Navigation updates ran at display rate before, which
    /// burns the system budget and battery for no visible difference.
    private static let minimumPushInterval: TimeInterval = 1.0
    @ObservationIgnored private var lastPushAt = Date.distantPast
    @ObservationIgnored private var lastSignature = ""

    func update(title: String, distance: String, speed: String, offRoute: Bool,
                turnSymbol: String, remaining: String, eta: String,
                speedLimit: String? = nil, lap: Int = 0, totalLaps: Int = 0,
                hazard: String? = nil,
                vehicleKind: String = "motorcycle", mapImage: String? = nil,
                progress: Double = 0, alert: String? = nil, stepID: Int = -1) {
        let signature = "\(title)|\(distance)|\(stepID)|\(mapImage ?? "")"
            + "|\(Int(progress * 100))|\(offRoute ? 1 : 0)|\(alert ?? "")"
        let now = Date()
        if alert == nil,
           signature == lastSignature,
           now.timeIntervalSince(lastPushAt) < Self.minimumPushInterval {
            return
        }
        lastPushAt = now
        lastSignature = signature

        let state = NavigationActivityAttributes.ContentState(
            title: title, distance: distance, speed: speed, offRoute: offRoute,
            updatedAt: Date(), turnSymbol: turnSymbol, remaining: remaining, eta: eta,
            speedLimit: speedLimit, lap: lap, totalLaps: totalLaps,
            hazard: hazard, vehicleKind: vehicleKind,
            mapImage: mapImage, progress: progress, stepID: stepID
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
        // A navigation app interrupts with a banner at the manoeuvre. An update
        // carrying an alert is how a Live Activity does the same: it appears
        // over whatever is on the car screen, with a chime.
        let configuration: AlertConfiguration? = alert.map { message in
            AlertConfiguration(title: LocalizedStringResource("Revert"),
                               body: LocalizedStringResource(stringLiteral: message),
                               sound: .default)
        }
        RideDebug.shared.event("LIVE-UPDATE", [
            ("supported", isSupported ? "yes" : "no"),
            ("id", activity?.id ?? "—"),
            ("title", title),
            ("distance", distance),
            ("speed", speed),
            ("offRoute", offRoute ? "yes" : "no"),
            ("turn", turnSymbol),
            ("remaining", remaining),
            ("eta", eta),
            ("limit", speedLimit ?? "—"),
            ("lap", "\(lap)/\(totalLaps)"),
            ("hazard", hazard ?? "—"),
            ("vehicle", vehicleKind),
            ("mapImage", mapImage ?? "—"),
            ("progress", String(format: "%.3f", progress)),
            ("stepID", "\(stepID)"),
            ("alert", alert ?? "—")
        ])
        guard let activity else { return }
        Task { await activity.update(content, alertConfiguration: configuration) }
    }

    func end() {
        let current = activity
        activity = nil
        RideDebug.shared.event("LIVE-END", [
            ("id", current?.id ?? "—"),
            ("started", current != nil ? "yes" : "no")
        ])
        Task {
            await current?.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every Live Activity owned by this app. Called on launch, when no
    /// navigation state survives, and before starting a new activity.
    func endStaleActivities() {
        let count = Activity<NavigationActivityAttributes>.activities.count
        RideDebug.shared.event("LIVE-STALE", [("count", "\(count)")])
        activity = nil
        for stale in Activity<NavigationActivityAttributes>.activities {
            Task {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func placeholderState() -> NavigationActivityAttributes.ContentState {
        NavigationActivityAttributes.ContentState(
            title: "Ride in progress",
            distance: "—",
            speed: "—",
            offRoute: false,
            updatedAt: Date(),
            turnSymbol: "location.north.fill",
            remaining: "—",
            eta: "—",
            speedLimit: nil,
            lap: 0,
            totalLaps: 0,
            hazard: nil,
            vehicleKind: "motorcycle"
        )
    }
}
