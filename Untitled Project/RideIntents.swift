import AppIntents
import Foundation

/// Opens the planner from Shortcuts, Siri or the Action button. The actual
/// presentation is handled by the root view so the app keeps one navigation
/// state machine.
struct PlanRideIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan a ride"
    static var description = IntentDescription("Open Rider’s scenic loop planner.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await RiderIntentRouter.open(.plan)
        return .result()
    }
}

struct OpenGarageIntent: AppIntent {
    static var title: LocalizedStringResource = "Open my garage"
    static var description = IntentDescription("Open the bike garage and maintenance log.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await RiderIntentRouter.open(.garage)
        return .result()
    }
}

/// Bridges App Intents to the running UI. The UserDefaults flag covers a cold
/// launch; the notification reaches an app that is already on screen, where
/// `onAppear` will not fire again.
@MainActor
private enum RiderIntentRouter {
    enum Destination {
        case plan
        case garage
    }

    static func open(_ destination: Destination) async {
        switch destination {
        case .plan:
            UserDefaults.standard.set(true, forKey: "intent.openPlan")
        case .garage:
            UserDefaults.standard.set(true, forKey: "intent.openGarage")
        }
        NotificationCenter.default.post(name: .riderOpenIntent, object: nil)
    }
}

struct RiderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlanRideIntent(),
            phrases: [
                "Plan a ride with \(.applicationName)",
                "Find a motorcycle loop with \(.applicationName)"
            ],
            shortTitle: "Plan a ride",
            systemImageName: "map.fill"
        )
        AppShortcut(
            intent: OpenGarageIntent(),
            phrases: ["Open my garage in \(.applicationName)"],
            shortTitle: "Open garage",
            systemImageName: "motorcycle"
        )
    }
}
