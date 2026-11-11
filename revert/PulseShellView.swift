import SwiftUI
import SwiftData

/// Secondary destinations that open as sheets over the tab shell.
enum PulseSheet: String, Identifiable {
    case settings
    case insights
    case safety
    case savedPlaces
    case offline
    case posters

    var id: String { rawValue }
}

/// The Midnight Pulse app frame: five primary destinations in the bottom rail,
/// with the map kept as an immersive full-screen experience and the cockpit
/// presented without chrome once a ride starts.
struct PulseShellView: View {
    let planner: RoutePlanner

    @Environment(NavigationManager.self) private var nav
    @Environment(\.modelContext) private var context
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    @State private var tab: PulseTab = .home
    @State private var sheet: PulseSheet?
    @State private var showingRide = false
    @State private var showingOnboarding = false
    @State private var showingPlan = false
    @State private var pendingRideStart = false
    @State private var cockpitReturnTab: PulseTab = .home
    @State private var recoveredRide: Ride?

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PulseTabBar(selection: tab) { selected in
                    select(selected)
                }
            }
            .background {
                PulseBackdrop().ignoresSafeArea()
            }
            .sheet(item: $sheet) { destination in
                sheetView(for: destination)
            }
            .fullScreenCover(isPresented: $showingRide) {
                RideView(onExit: {
                    showingRide = false
                    tab = cockpitReturnTab
                    cockpitReturnTab = .home
                })
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView {
                    onboardingCompleted = true
                    showingOnboarding = false
                }
            }
            .sheet(isPresented: $showingPlan, onDismiss: {
                if pendingRideStart {
                    pendingRideStart = false
                    openCockpit()
                }
            }) {
                PlanView(
                    tab: .constant(0),
                    planner: planner,
                    onStartNavigation: { pendingRideStart = true }
                )
            }
            .alert("Recover unfinished ride?", isPresented: Binding(
                get: { recoveredRide != nil },
                set: { if !$0 { recoveredRide = nil } }
            )) {
                Button("Save ride") {
                    guard let ride = recoveredRide else { return }
                    context.insert(ride)
                    if (try? context.save()) != nil {
                        RideJournal.shared.finish()
                    }
                    recoveredRide = nil
                }
                Button("Discard", role: .destructive) {
                    RideJournal.shared.finish()
                    recoveredRide = nil
                }
                Button("Later", role: .cancel) { recoveredRide = nil }
            } message: {
                Text("Revert was recording when the app closed. Save the recovered track to History?")
            }
            .onReceive(NotificationCenter.default.publisher(for: .revertOpenIntent)) { _ in
                handleIntents()
            }
            .onAppear(perform: onAppear)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            PulseHomeView(
                onOpenRoutes: { select(.routes) },
                onOpenCockpit: { openCockpit() },
                onOpenGarage: { select(.garage) },
                onOpenHistory: { select(.history) },
                onOpen: { sheet = $0 }
            )
        case .routes:
            PulseRoutesView(
                planner: planner,
                onOpenCockpit: { openCockpit() },
                onOpenScenicPlanner: { showingPlan = true },
                onOpenSavedPlaces: { sheet = .savedPlaces }
            )
        case .ride:
            // Covered immediately by the cockpit; keeps the tab's identity
            // while the full-screen presentation is on top.
            PulseBackdrop().ignoresSafeArea()
        case .garage:
            NavigationStack {
                GarageView(showsNavigationTitle: false)
            }
        case .history:
            HistoryView(showsCloseButton: false, showsNavigationTitle: false)
        }
    }

    @ViewBuilder
    private func sheetView(for destination: PulseSheet) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .insights:
            PulseInsightsView()
        case .safety:
            PulseSafetyView()
        case .savedPlaces:
            NavigationStack {
                SavedPlacesView(showsDone: false)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { sheet = nil }
                                .font(.headline.weight(.semibold))
                        }
                    }
            }
        case .offline:
            NavigationStack {
                OfflineView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { sheet = nil }
                                .font(.headline.weight(.semibold))
                        }
                    }
            }
        case .posters:
            PulsePostersView()
        }
    }

    private func select(_ destination: PulseTab) {
        if destination == .ride {
            openCockpit()
            return
        }
        if tab != destination {
            withAnimation(RevertMotion.smooth) {
                tab = destination
            }
        }
    }

    private func openCockpit() {
        cockpitReturnTab = tab == .ride ? .home : tab
        tab = .ride
        showingRide = true
    }

    private func onAppear() {
        #if DEBUG
        if CommandLine.arguments.contains("-resetOnboarding") {
            onboardingCompleted = false
        }
        #endif
        if !onboardingCompleted, !CommandLine.arguments.contains("-skipOnboarding") {
            showingOnboarding = true
        }
        if UserDefaults.standard.bool(forKey: "intent.endRoute") {
            UserDefaults.standard.set(false, forKey: "intent.endRoute")
            nav.stop()
        }
        if recoveredRide == nil, RideJournal.shared.hasPendingRide {
            if let ride = RideJournal.shared.recoveredRide(), ride.points.count > 1 {
                recoveredRide = ride
            } else {
                RideJournal.shared.finish()
            }
        }
        handleIntents()
        #if DEBUG
        applyDebugScreen()
        seedDebugRideIfNeeded()
        #endif
    }

    #if DEBUG
    /// The seeded ride used by UI tests and screenshots. It used to be
    /// inserted by the map screen, which is no longer the launch screen.
    private func seedDebugRideIfNeeded() {
        guard CommandLine.arguments.contains("-debugSeedRide") else { return }
        let descriptor = FetchDescriptor<Ride>()
        if (try? context.fetchCount(descriptor)) == 0 {
            context.insert(DebugScreens.sampleRide())
            try? context.save()
        }
    }

    /// Screenshot / QA entry points. Debug-only; they simply preselect a tab
    /// or a sheet on launch, exactly as a rider would.
    private func applyDebugScreen() {
        let arguments = CommandLine.arguments
        if arguments.contains("-debugTabRoutes") { tab = .routes }
        if arguments.contains("-debugTabGarage") { tab = .garage }
        if arguments.contains("-debugTabHistory") { tab = .history }
        if arguments.contains("-debugTabRide") { openCockpit() }
        if arguments.contains("-debugSheetInsights") { sheet = .insights }
        if arguments.contains("-debugSheetSafety") { sheet = .safety }
        if arguments.contains("-debugSheetPosters") { sheet = .posters }
        if arguments.contains("-debugSheetSaved") { sheet = .savedPlaces }
        if arguments.contains("-debugSheetOffline") { sheet = .offline }
        if arguments.contains("-debugSheetSettings") { sheet = .settings }
        if let menu = DebugScreens.menu {
            switch menu {
            case .plan:
                tab = .routes
                showingPlan = true
            case .settings:
                sheet = .settings
            case .history:
                tab = .history
            case .savedPlaces:
                sheet = .savedPlaces
            case .offline:
                sheet = .offline
            }
        }
    }
    #endif

    private func handleIntents() {
        if UserDefaults.standard.bool(forKey: "intent.openGarage") {
            UserDefaults.standard.set(false, forKey: "intent.openGarage")
            tab = .garage
            return
        }
        if UserDefaults.standard.bool(forKey: "intent.openPlan") {
            UserDefaults.standard.set(false, forKey: "intent.openPlan")
            tab = .routes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingPlan = true
            }
        }
    }
}
