import SwiftUI
import SwiftData

@main
struct RiderApp: App {
    @State private var nav = NavigationManager()
    @State private var directionsPlanner = RoutePlanner()

    init() {
        #if DEBUG
        SelfCheck.run()
        #endif
        // No navigation state survives a process restart, so any activity from
        // a previous launch is stale.
        RiderDiagnostics.log("launch \(RiderDiagnostics.appVersion) (\(RiderDiagnostics.appBuild))")
        Task { @MainActor in
            LiveRideActivity.shared.endStaleActivities()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if DebugScreens.isSummary {
                RideSavedSummaryView(ride: DebugScreens.sampleRide()) {}
            } else if DebugScreens.isRideDetail {
                DebugRideDetailRoot()
                    .environment(nav)
            } else if DebugScreens.isGarage {
                NavigationStack {
                    GarageView()
                }
                .environment(nav)
            } else if DebugScreens.isOffline {
                NavigationStack {
                    OfflineView()
                }
                .environment(nav)
            } else if DebugScreens.isRide {
                RideView()
                    .environment(nav)
            } else {
                DirectionsView(planner: directionsPlanner, initialMenu: DebugScreens.menu)
                    .environment(nav)
            }
            #else
            DirectionsView(planner: directionsPlanner)
                .environment(nav)
            #endif
            }
            .onOpenURL { url in
                switch url.host {
                case "plan":
                    UserDefaults.standard.set(true, forKey: "intent.openPlan")
                case "garage":
                    UserDefaults.standard.set(true, forKey: "intent.openGarage")
                case "end":
                    UserDefaults.standard.set(true, forKey: "intent.endRoute")
                default:
                    break
                }
                NotificationCenter.default.post(name: .riderOpenIntent, object: nil)
            }
                // The cockpit is designed for an OLED panel: true black with
                // cyan/emerald light. Pinning the scheme prevents the
                // white-on-white materials bug in light mode.
                .preferredColorScheme(.dark)
                .tint(MapUI.cyan)
        }
        .modelContainer(for: [Ride.self, Bike.self, MaintenanceEntry.self, SavedRoute.self])
    }
}
