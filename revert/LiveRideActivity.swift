import ActivityKit
import Foundation

/// Starts, updates and ends the Lock Screen / Dynamic Island Live Activity.
///
/// iOS 18 introduced the small activity family (CarPlay Dashboard and Watch
/// Smart Stack), and declaring it changes the widget's activity type. The
/// activity type is also the widget's key, so the two generations cannot share
/// one: iOS 18+ uses `NavigationActivityAttributes`, iOS 17 uses
/// `LegacyNavigationActivityAttributes`. Both carry the same `ContentState`.
@MainActor
final class LiveRideActivity {
    static let shared = LiveRideActivity()

    /// iOS 18+ activity. Only ever non-nil on iOS 18 and later.
    private var activity: Activity<NavigationActivityAttributes>?
    /// iOS 17 activity. Only ever non-nil before iOS 18.
    private var legacyActivity: Activity<LegacyNavigationActivityAttributes>?

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var isActive: Bool {
        if #available(iOS 18.0, *), activity != nil { return true }
        return legacyActivity != nil
    }

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
        if #available(iOS 18.0, *) {
            activity = try? Activity.request(
                attributes: NavigationActivityAttributes(startedAt: Date()),
                content: content
            )
        } else {
            legacyActivity = try? Activity.request(
                attributes: LegacyNavigationActivityAttributes(startedAt: Date()),
                content: content
            )
        }
        RideDebug.shared.event("LIVE-STARTED", [
            ("modern", activity != nil ? "yes" : "no"),
            ("legacy", legacyActivity != nil ? "yes" : "no"),
            ("id", activity?.id ?? legacyActivity?.id ?? "—")
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
                hazard: String? = nil, isSimulation: Bool = false,
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
            hazard: hazard, isSimulation: isSimulation, vehicleKind: vehicleKind,
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
            ("id", activity?.id ?? legacyActivity?.id ?? "—"),
            ("modern", activity != nil ? "yes" : "no"),
            ("legacy", legacyActivity != nil ? "yes" : "no"),
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
            ("sim", isSimulation ? "yes" : "no"),
            ("vehicle", vehicleKind),
            ("mapImage", mapImage ?? "—"),
            ("progress", String(format: "%.3f", progress)),
            ("stepID", "\(stepID)"),
            ("alert", alert ?? "—")
        ])
        if #available(iOS 18.0, *), let activity {
            Task { await activity.update(content, alertConfiguration: configuration) }
        } else if let legacyActivity {
            Task { await legacyActivity.update(content, alertConfiguration: configuration) }
        }
    }

    func end() {
        let current = activity
        let legacy = legacyActivity
        activity = nil
        legacyActivity = nil
        RideDebug.shared.event("LIVE-END", [
            ("id", current?.id ?? legacy?.id ?? "—"),
            ("modern", current != nil ? "yes" : "no"),
            ("legacy", legacy != nil ? "yes" : "no")
        ])
        Task {
            await current?.end(nil, dismissalPolicy: .immediate)
            await legacy?.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every Live Activity owned by this app. Called on launch, when no
    /// navigation state survives, and before starting a new activity.
    func endStaleActivities() {
        let modernCount = Activity<NavigationActivityAttributes>.activities.count
        let legacyCount = Activity<LegacyNavigationActivityAttributes>.activities.count
        RideDebug.shared.event("LIVE-STALE", [
            ("modern", "\(modernCount)"),
            ("legacy", "\(legacyCount)")
        ])
        activity = nil
        legacyActivity = nil
        for stale in Activity<NavigationActivityAttributes>.activities {
            Task {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
        // Normally empty on iOS 17, but a device that ran the legacy activity
        // and then updated its OS should not keep an orphan around.
        for stale in Activity<LegacyNavigationActivityAttributes>.activities {
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
            isSimulation: false,
            vehicleKind: "motorcycle"
        )
    }
}
