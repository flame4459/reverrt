import SwiftUI
import SwiftData

@main
struct RevertApp: App {
    // The same navigation session is used by the CarPlay scene, so a ride
    // started on either screen continues on the other.
    @State private var nav = RevertServices.shared.navigation
    @State private var directionsPlanner = RoutePlanner()
    @State private var theme = RevertThemeStore.shared
    @State private var importedRival: RivalResult?
    @Environment(\.scenePhase) private var scenePhase
    @State private var importedRouteLink: PlannedRoute?

    init() {
        // Install before anything else so an early SwiftUI or SwiftData crash
        // is still written to the debug folder.
        CrashReporter.install()
        #if DEBUG
        SelfCheck.run()
        #endif
        // No navigation state survives a process restart, so any activity from
        // a previous launch is stale.
        RevertDiagnostics.log("launch \(RevertDiagnostics.appVersion) (\(RevertDiagnostics.appBuild))")
        Units.migrateLegacyPreferenceIfNeeded()
        #if DEBUG
        if CommandLine.arguments.contains("-debugUnitsMetric") {
            Units.setPreference(.metric)
        } else if CommandLine.arguments.contains("-debugUnitsImperial") {
            Units.setPreference(.imperial)
        } else if CommandLine.arguments.contains("-debugUnitsAuto") {
            Units.setPreference(.automatic)
        }
        #endif
        WidgetBridge.updateUnits()
        RevertServices.shared.syncVehiclePreferences()
        #if DEBUG
        if CommandLine.arguments.contains("-debugRaiseException") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSException(name: NSExceptionName("DebugCrash"),
                            reason: "Deliberate debug exception for crash-report testing",
                            userInfo: nil).raise()
            }
        }
        if CommandLine.arguments.contains("-debugRaiseSignal") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                raise(SIGABRT)
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "-debugRival"),
           CommandLine.arguments.indices.contains(index + 1),
           let url = URL(string: CommandLine.arguments[index + 1]) {
            Task { @MainActor in
                _ = RivalBoard.shared.importURL(url)
            }
        }
        #endif
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
            } else if DebugScreens.isDebugReports {
                NavigationStack {
                    DebugReportsView()
                }
                .environment(nav)
            } else if DebugScreens.isRideDebug {
                NavigationStack {
                    RideDebugView()
                }
                .environment(nav)
            } else if DebugScreens.isWidgetDiagnostics {
                NavigationStack {
                    WidgetDiagnosticsView()
                }
                .environment(nav)
            } else if DebugScreens.isFeatureLab {
                FeatureHubView()
                    .environment(nav)
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
                case "drive":
                    UserDefaults.standard.set(true, forKey: "intent.openRide")
                case RouteLink.host:
                    if let payload = RouteLink.payload(from: url),
                       let route = RouteLink.route(from: payload) {
                        importedRouteLink = route
                    }
                    return
                case RivalLink.host:
                    if let result = RivalBoard.shared.importURL(url) {
                        importedRival = result
                    }
                    return
                default:
                    break
                }
                NotificationCenter.default.post(name: .revertOpenIntent, object: nil)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                // A live ride keeps navigating in the background, so its card
                // stays. With no ride there is nothing behind the card, and
                // leaving it there is what froze a turn on the car screen.
                if nav.route == nil {
                    LiveRideActivity.shared.end()
                    WidgetBridge.setRideActive(false)
                }
            }
                // The cockpit is designed for an OLED panel: true black with
                // cyan/emerald light. Pinning the scheme prevents the
                // white-on-white materials bug in light mode.
                .preferredColorScheme(.dark)
                .tint(theme.palette.accent)
                .sheet(item: $importedRouteLink) { route in
                    IncomingRouteLinkView(route: route)
                }
                .alert("Time added", isPresented: Binding(
                    get: { importedRival != nil },
                    set: { if !$0 { importedRival = nil } }
                )) {
                    Button("OK", role: .cancel) { importedRival = nil }
                } message: {
                    Text(importedRival.map { result in
                        let replay = result.hasReplay ? " The ride replay is included." : ""
                        return "\(result.rider) · \(Units.clock(result.durationSeconds)) on \(result.routeName). It is waiting under Rival times on the Routes screen.\(replay)"
                    } ?? "")
                }
        }
        .modelContainer(RevertServices.shared.modelContainer)
    }
}
