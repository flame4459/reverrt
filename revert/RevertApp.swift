import SwiftUI
import SwiftData

@main
struct RevertApp: App {
    // The same navigation session is used by the CarPlay scene, so a ride
    // started on either screen continues on the other.
    @State private var nav = RevertServices.shared.navigation
    @State private var directionsPlanner = RoutePlanner()
    @State private var theme = RevertThemeStore.shared

    init() {
        #if DEBUG
        SelfCheck.run()
        #endif
        // No navigation state survives a process restart, so any activity from
        // a previous launch is stale.
        RevertDiagnostics.log("launch \(RevertDiagnostics.appVersion) (\(RevertDiagnostics.appBuild))")
        Task { @MainActor in
            LiveRideActivity.shared.endStaleActivities()
            VoicePackLibrary.shared.installBuiltInsIfNeeded()
            #if DEBUG
            if let id = DebugScreens.installPackID,
               let pack = VoicePack.catalog.first(where: { $0.id == id }) {
                VoicePackLibrary.shared.install(pack)
            }
            #endif
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
            } else if DebugScreens.isBikePicker {
                DebugBikePickerRoot()
                    .environment(nav)
            } else if DebugScreens.isVoicePacks {
                DebugVoicePacksRoot()
                    .environment(nav)
            } else if DebugScreens.isVoicePackBrowser {
                DebugVoicePackBrowserRoot()
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
            } else if DebugScreens.isCarPlayMap {
                DebugCarPlayMapRoot()
            } else if DebugScreens.isRide {
                RideView()
                    .environment(nav)
            } else {
                PulseShellView(planner: directionsPlanner)
                    .environment(nav)
            }
            #else
            PulseShellView(planner: directionsPlanner)
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
                NotificationCenter.default.post(name: .revertOpenIntent, object: nil)
            }
                // The cockpit is designed for an OLED panel: true black with
                // cyan/emerald light. Pinning the scheme prevents the
                // white-on-white materials bug in light mode.
                .preferredColorScheme(.dark)
                .tint(theme.palette.accent)
        }
        .modelContainer(RevertServices.shared.modelContainer)
    }
}
