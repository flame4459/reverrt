import SwiftUI
import Combine
import UIKit
import MapKit
import SwiftData
import CoreLocation

struct RideView: View {
    /// When the cockpit is a tab rather than a presented cover, the shell
    /// supplies the way out instead of SwiftUI's dismiss environment.
    var onExit: (() -> Void)? = nil
    /// Opens the route planner from the no-route cockpit state.
    var onPlanRoute: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query(sort: \Bike.createdAt, order: .reverse) private var garageBikes: [Bike]
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Query(sort: \Ride.startDate, order: .reverse) private var pastRides: [Ride]
    @Query(sort: \SetupNote.createdAt, order: .reverse) private var setupNotes: [SetupNote]
    @Query(sort: \MaintenanceEntry.date, order: .reverse) private var maintenanceEntries: [MaintenanceEntry]
    @State private var recorder = RideRecorder()
    @State private var alerts = AlertManager()
    @State private var lean = LeanAngleManager()
    @State private var gForce = GForceModel()
    @State private var voice = VoiceCommandRecognizer()
    @State private var remote = HandlebarRemote()
    @State private var companion = CompanionDirector.shared
    @State private var audioRoute = AudioRouteMonitor.shared
    @State private var companionWeather: CompanionWeather?
    @State private var gpsStale = false
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var cameraDriver = RideCameraDriver()
    @State private var matchedPuck: CLLocationCoordinate2D?
    @State private var mapStyle: MapStyle = MapConfig.style
    @State private var mapStyleName = "muted"
    @State private var showingStopConfirmation = false
    @State private var showingHandoffPrompt = false
    @State private var handoffRoute: PlannedRoute?
    @State private var handoffChipDismissed = false
    @State private var showingSettings = false
    @State private var rideError: String?
    @State private var trackCoordinates: [CLLocationCoordinate2D] = []
    @State private var hazardLoadTask: Task<Void, Never>?
    @State private var savedSummary: Ride?
    @State private var bannerHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var autoStartedRouteID: UUID?
    @State private var liveMapImage: String?
    @State private var lastMapRender = Date.distantPast
    @State private var lastMapStep = -1
    @State private var lastLiveActivityUpdate = Date.distantPast
    @State private var lastLiveStep = -2
    @State private var lastLiveLap = -1
    @State private var overviewImage: String?
    @State private var alertedSteps: Set<Int> = []
    @State private var showsBackgroundLocationWarning = false
    @State private var lapNotice: Int?
    @State private var lapNoticeTask: Task<Void, Never>?
    @State private var simulator = RouteSimulator.shared
    @State private var showingSimulator = false
    @State private var lastPublishedCarMode: CarWidgetSnapshot.Mode = .parked
    @State private var lastWidgetTurnKey = ""
    @AppStorage("ride.cameraMode") private var cameraMode: RideCameraMode = .cockpit
    @AppStorage("rider.selectedBike") private var selectedBike = BikeCatalog.defaultBike
    @AppStorage("units.system") private var unitSystem = UnitSystemPreference.automatic.rawValue
    @AppStorage("voice.commands") private var voiceCommands = false
    @AppStorage("companion.wakeWord") private var wakeWord = true
    @AppStorage("map.renderer") private var mapRenderer = MapRendererKind.immersive.rawValue
    @AppStorage("helmet.binaural") private var binaural = true
    @AppStorage("remote.enabled") private var remoteEnabled = true
    @AppStorage("voice.muted") private var voiceMuted = false
    @AppStorage("ride.launchCountdown") private var launchCountdown = true
    @AppStorage("ride.ghostEnabled") private var ghostEnabled = false
    @AppStorage("ride.longRideMode") private var longRideMode = false
    @AppStorage("ride.focusMode") private var focusMode = false
    @State private var ghost: GhostTrack?
    @State private var marks = UserMarksStore.shared
    @State private var dimmed = false
    @State private var lastInteraction = Date()
    @State private var lastCompanionTick = Date.distantPast
    @State private var voiceStartedManually = false
    @State private var pushToTalk = false

    private var cameraIsCockpit: Bool { cameraMode != .northUp }

    private var wantsVoiceListening: Bool {
        guard companion.state != .off else { return false }
        return voiceCommands || wakeWord
    }

    private func updateVoiceListening() {
        guard recorder.isRecording else { return }
        if wantsVoiceListening, !voice.isListening, VoiceCommandRecognizer.permissionGranted {
            voiceStartedManually = false
            voice.start()
        } else if !wantsVoiceListening, voice.isListening, !pushToTalk {
            voiceStartedManually = false
            voice.stop()
        }
    }

    private var primaryVehicle: Bike? {
        garageBikes.first(where: \.isPrimary)
            ?? garageBikes.first(where: { $0.displayName == selectedBike })
            ?? garageBikes.first
    }

    private var isCar: Bool {
        if nav.route != nil { return nav.vehicleKind.isCar }
        return primaryVehicle?.isCar == true
    }
    private var carLandscape: Bool { isCar && verticalSizeClass == .compact }

    /// The garage vehicle matching the route's chosen kind. With no matching
    /// car/bike this returns nil; the cockpit still follows `nav.vehicleKind`
    /// and the ride is labelled with the chosen kind.
    private var selectedVehicle: Bike? {
        let kind = nav.route != nil ? nav.vehicleKind : (primaryVehicle?.kind ?? .motorcycle)
        if let primaryMatch = garageBikes.first(where: { $0.kind == kind && $0.isPrimary }) {
            return primaryMatch
        }
        if let anyMatch = garageBikes.first(where: { $0.kind == kind }) {
            return anyMatch
        }
        if kind == .motorcycle, let primaryVehicle, primaryVehicle.kind == .motorcycle {
            return primaryVehicle
        }
        return nil
    }

    var body: some View {
        cockpitPresentations
        .overlay { countdownCover }
        .overlay { batteryDimOverlay }
        .animation(.easeOut(duration: 0.18), value: countdown)
        // The cockpit has no scroll surface, so cap very large type before
        // the speedometer and lean gauge run into the map controls.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .modifier(RideDebugHooks(recorder: recorder, nav: nav))
        .onChange(of: mapStyleName) { _, value in
            RideDebug.shared.event("SETTING", [("key", "ride.mapStyle"), ("value", value)])
        }
    }

    /// Sheets, covers and alerts. Kept out of `body` so the SwiftUI type
    /// checker sees a small chain rather than the whole cockpit at once.
    private var cockpitPresentations: some View {
        cockpitLifecycle
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingSimulator) {
            RouteSimulatorView(holdAtStart: launchCountdown ? 3.4 : 0.6)
        }
        .fullScreenCover(item: $savedSummary, onDismiss: {
            exitCockpit()
        }) { ride in
            RideSavedSummaryView(ride: ride) {
                savedSummary = nil
            }
        }
        // Use an alert rather than a confirmation dialog so "Keep Riding"
        // stays visible: a popover presentation can omit the cancel role,
        // leaving no obvious way back with gloves on.
        .alert("Finish this ride?", isPresented: $showingStopConfirmation) {
            Button("Save Ride") { finishRide(save: true) }
            Button("Discard Ride", role: .destructive) { finishRide(save: false) }
            Button("Keep Riding", role: .cancel) {}
        } message: {
            Text("Save this route to History, or discard it if it was only a test ride.")
        }
        .alert("Background location is off", isPresented: $showsBackgroundLocationWarning) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Revert only has \u{201C}While Using the App\u{201D} location, so recording stops when the phone screen locks. Set Location to \u{201C}Always\u{201D} to record a ride in a pocket.")
        }
        .alert("Ride not saved", isPresented: isRideErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rideError ?? "The ride could not be saved.")
        }
        // The launch countdown covers everything, including the maneuver
        // banner and map controls, so it is the last overlay in the stack.
    }

    private var cockpitLifecycle: some View {
        cockpitObservers
        .onAppear {
            setUpRide()
            presentHandoffPromptIfNeeded()
        }
        .confirmationDialog("Send this route to the car screen?",
                            isPresented: $showingHandoffPrompt,
                            titleVisibility: .visible) {
            Button("Send to Organic Maps") {
                handoffRoute = nav.route
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Revert keeps navigating and talking. Organic Maps draws the line on the car display with its voice off.")
        }
        .sheet(item: $handoffRoute) { route in
            CarHandoffSheet(route: CarHandoffRoute(route: route))
        }
        .onDisappear { tearDownRide() }
        .onChange(of: recorder.points.count) { _, count in
            // Rebuilding the whole polyline on every 5 m fix is expensive.
            // Refresh it in batches so the map stays smooth on long rides.
            guard count > 1 else {
                trackCoordinates = []
                return
            }
            guard count == 2 || count % 25 == 0 else { return }
            trackCoordinates = recorder.points.map(\.coordinate)
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording {
                // The previous ride's breadcrumb must not survive into a new one.
                trackCoordinates = []
                IdleTimer.acquire("ride")
                if isCar { gForce.start() }
                if wantsVoiceListening, !voice.isListening, VoiceCommandRecognizer.permissionGranted {
                    voiceStartedManually = false
                    voice.start()
                }
            } else {
                IdleTimer.release("ride")
                gForce.stop()
                if voice.isListening { voice.stop() }
                if recorder.points.count > 1 {
                    trackCoordinates = recorder.points.map(\.coordinate)
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { now in
            // A ride with no fix is not "0 mph": it is a phone that has lost the
            // sky. Say so rather than leaving a frozen speed on screen.
            guard recorder.isRecording else {
                gpsStale = false
                return
            }
            if let last = recorder.lastFixAt {
                gpsStale = now.timeIntervalSince(last) > 10
            } else {
                gpsStale = recorder.elapsed(at: now) > 8
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app must end the mic session. A voice recogniser that
            // survives a locked screen keeps the orange indicator on and drains
            // the battery for nothing.
            if phase == .background {
                pushToTalk = false
                voiceStartedManually = false
                if voice.isListening { voice.stop() }
            }
        }
        .onChange(of: voiceCommands) { _, _ in
            updateVoiceListening()
        }
        .onChange(of: wakeWord) { _, _ in
            updateVoiceListening()
        }
        .onChange(of: companion.state) { _, state in
            if state == .off {
                voiceStartedManually = false
                if voice.isListening { voice.stop() }
            } else {
                updateVoiceListening()
            }
        }
        .onChange(of: binaural) { _, enabled in
            if enabled, !isCar { HelmetAudio.shared.start() } else { HelmetAudio.shared.stop() }
        }
        .onChange(of: remoteEnabled) { _, enabled in
            if enabled { remote.start() } else { remote.stop() }
        }
        .onChange(of: lean.angle) { _, angle in
            recorder.currentLean = angle ?? 0
        }
        .interactiveDismissDisabled(recorder.isRecording)
    }

    /// Gesture/animation observers, separate from the layout and the
    /// presentation chain below, so SwiftUI's type checker does not have to
    /// solve the whole cockpit in one expression.
    private var cockpitObservers: some View {
        cockpitSurface
        .onPreferenceChange(BannerHeightKey.self) { height in
            bannerHeight = height
        }
        .onPreferenceChange(PanelHeightKey.self) { height in
            panelHeight = height
        }
        .animation(.spring(duration: 0.3), value: nav.route?.id)
        .animation(.spring(duration: 0.3), value: alerts.activeAlert?.hazard.id)
        .animation(.spring(duration: 0.3), value: alerts.curveAlert?.since)
        .animation(.spring(duration: 0.3), value: alerts.surfaceAlert?.since)
        .onChange(of: nav.route?.id) { _, routeID in
            autoStartedRouteID = nil
            matchedPuck = nil
            cameraDriver.clearOverview()
            cameraDriver.start()
            if (simulator.isRunning || simulator.isPaused),
               simulator.route?.id != nav.route?.id {
                simulator.stop()
            }
            if let route = nav.route {
                applyCameraMode()
                loadGhost()
                loadRouteHazards(route)
                LiveRideActivity.shared.start()
                liveMapImage = nil
                overviewImage = nil
                alertedSteps.removeAll()
                lastMapRender = .distantPast
                lastMapStep = -1
                renderRouteOverview(route)
                WidgetBridge.setRideActive(true, routeName: route.displayName)
                updateLiveActivity()
                refreshCompanionWeather()
            } else {
                alerts.clearRouteHazards()
                LiveRideActivity.shared.end()
                WidgetBridge.setRideActive(false)
                var parked = CarWidgetSnapshot.parked
                parked.vehicleKind = isCar ? "car" : "motorcycle"
                parked.updatedAt = Date()
                WidgetBridge.updateCarState(parked, force: true, reason: "parked")
                WidgetBridge.flushWidgetDebug()
                lastPublishedCarMode = .parked
            }
        }
        .task(id: liveActivityKey) { updateLiveActivity() }
        .task(id: recorder.isRecording) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if recorder.currentSpeedMps <= 3, dimmed {
                    withAnimation(.easeOut(duration: 0.25)) { dimmed = false }
                }
                guard longRideMode, recorder.isRecording, !recorder.isPaused,
                      recorder.currentSpeedMps > 3,
                      Date().timeIntervalSince(lastInteraction) > 10 else {
                    if !longRideMode, dimmed { dimmed = false }
                    continue
                }
                withAnimation(.easeIn(duration: 0.6)) { dimmed = true }
            }
        }
        .onChange(of: nav.route?.id) { _, _ in
            lastInteraction = Date()
            dimmed = false
        }
        .onChange(of: nav.joined) { _, joined in
            // The rider has reached the official start area. This is where the
            // loop clock belongs, not the driveway.
            if joined { autoStartTimedRunIfNeeded() }
        }
        .onChange(of: nav.lap) { _, lap in
            guard lap > 1, !nav.arrived, nav.totalLaps > 1 else { return }
            showLapNotice(lap)
        }
        .onChange(of: nav.arrived) { _, arrived in
            if arrived {
                companion.arrived(context: companionContext())
                if let route = nav.route {
                    cameraDriver.showOverview(route: route)
                }
            }
        }
        #if DEBUG
        .onChange(of: showsBackgroundLocationWarning) { _, value in
            if value, CommandLine.arguments.contains("-debugNoBackgroundWarning") {
                showsBackgroundLocationWarning = false
            }
        }
        #endif
        .onChange(of: cameraMode) { _, _ in applyCameraMode() }
        .onChange(of: nav.cameraPose) { _, pose in
            guard cameraIsCockpit, let pose else {
                matchedPuck = nil
                return
            }
            if reduceMotion {
                camera = cameraMode.camera(for: pose)
                cameraDriver.present(staticFrame: stillFrame(for: pose, northUp: !cameraIsCockpit))
            } else {
                cameraDriver.update(route: nav.route,
                                    progress: nav.routeProgress,
                                    speed: pose.speed,
                                    maneuverMeters: nav.stepDistance,
                                    fallbackHeading: pose.heading,
                                    centered: !cameraMode.usesLookAhead,
                                    mode: cameraMode)
            }
            updateMatchedPuck(pose)
        }
        .onChange(of: cameraDriver.frame) { _, frame in
            guard !reduceMotion, cameraIsCockpit, let frame else { return }
            camera = .camera(MapCamera(centerCoordinate: frame.coordinate,
                                       distance: frame.distance,
                                       heading: frame.heading,
                                       pitch: frame.pitch))
        }
    }

    private var cockpitSurface: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            if !carLandscape {
                panel
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background {
            ZStack {
                map
                RevertMapScrim(topOpacity: 0.22, bottomOpacity: 0.30)
            }
            .padding(.bottom, carLandscape ? 0 : panelHeight)
            .clipped()
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if !carLandscape {
                bannerStack
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: BannerHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if carLandscape {
                carLandscapeHUD
            }
        }
        .overlay(alignment: .topLeading) {
            if !carLandscape {
                if focusMode {
                    focusExitButton
                } else {
                    mapControls
                }
            }
        }
    }

    private var isRideErrorPresented: Binding<Bool> {
        Binding(
            get: { rideError != nil },
            set: { if !$0 { rideError = nil } }
        )
    }

    @ViewBuilder
    private var countdownCover: some View {
        if let countdown {
            LaunchCountdownView(
                value: countdown,
                routeName: nav.route?.displayName,
                isSprint: nav.route?.kind.isSprint == true,
                onCancel: cancelLaunchCountdown
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var batteryDimOverlay: some View {
        if dimmed {
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()
                VStack(spacing: 7) {
                    Text("LONG RIDE")
                        .font(.scaledSystem(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(MapUI.emerald.opacity(0.8))
                    Text("Tap to wake")
                        .font(.scaledSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                lastInteraction = Date()
                withAnimation(.easeOut(duration: 0.25)) { dimmed = false }
            }
            .transition(.opacity)
        }
    }

    private var focusExitButton: some View {
        Button {
            focusMode = false
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.compress.vertical")
                Text("FOCUS")
            }
            .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(MapUI.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(MapUI.line, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .padding(.top, mapControlsTopPadding)
        .padding(.leading, 16)
    }

    #if DEBUG
    private func applyDebugRideState() {
        if CommandLine.arguments.contains("-debugNoBackgroundWarning") {
            showsBackgroundLocationWarning = false
        }
        if CommandLine.arguments.contains("-debugCarLandscape") {
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        if CommandLine.arguments.contains("-debugCar") {
            if let car = garageBikes.first(where: \.isCar) {
                for bike in garageBikes { bike.isPrimary = bike.id == car.id }
                try? context.save()
                VehiclePreferences.sync(primaryKind: .car,
                                        avoidTolls: car.avoidTolls,
                                        avoidHighways: car.avoidHighways)
            } else {
                let car = Bike(name: "Friends' car", make: "Volkswagen",
                               model: "Golf GTI", year: 2024, odometerKm: 18_400,
                               fuelRangeKm: 520, serviceIntervalKm: 15_000,
                               isPrimary: true, kind: .car)
                for bike in garageBikes { bike.isPrimary = false }
                context.insert(car)
                try? context.save()
                VehiclePreferences.sync(primaryKind: .car,
                                        avoidTolls: false,
                                        avoidHighways: false)
            }
        }
        if CommandLine.arguments.contains("-debugHud") {
            let route = DebugScreens.samplePlannedRoute()
            nav.start(route, roads: [])
            if !CommandLine.arguments.contains("-debugAutoLaunch") {
                // Screenshot/debug launches normally want the cockpit at
                // rest, not a live loop timer.
                autoStartedRouteID = route.id
            }
            if !CommandLine.arguments.contains("-debugApproach"),
               let first = route.points.first {
                nav.handle(CLLocation(latitude: first.lat, longitude: first.lon))
            }
        }
        if CommandLine.arguments.contains("-debugSimulate")
            || CommandLine.arguments.contains("-debugSimulatePanel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let route = nav.route else { return }
                let arguments = CommandLine.arguments
                if let index = arguments.firstIndex(of: "-debugSimSpeed"),
                   arguments.indices.contains(index + 1),
                   let value = Double(arguments[index + 1]) {
                    RouteSimulator.shared.setMultiplier(value)
                }
                RouteSimulator.shared.start(route: route, holdAtStart: 3.4)
                if arguments.contains("-debugSimulatePanel") {
                    showingSimulator = true
                }
                if let index = arguments.firstIndex(of: "-debugSimulateStop"),
                   arguments.indices.contains(index + 1),
                   let seconds = Double(arguments[index + 1]) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                        RouteSimulator.shared.stop()
                    }
                }
            }
        }
        if CommandLine.arguments.contains("-debugAlert") {
            let route = DebugScreens.samplePlannedRoute()
            nav.start(route, roads: [])
            if let first = route.points.first {
                let location = CLLocation(coordinate: first.coordinate, altitude: 30,
                                           horizontalAccuracy: 5, verticalAccuracy: 5,
                                           course: 45, speed: 18, timestamp: Date())
                nav.handle(location)
                if route.points.indices.contains(3) {
                    let target = route.points[3]
                    Task { @MainActor in
                        // Let the route-change reload clear first.
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        guard nav.route?.id == route.id else { return }
                        alerts.setRouteHazards(
                            [Hazard(id: 900_001, kind: .stop, lat: target.lat, lon: target.lon)],
                            for: route.id
                        )
                        alerts.handle(location)
                    }
                }
            }
        }
        if CommandLine.arguments.contains("-debugLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard countdown == nil, !recorder.isRecording else { return }
                beginLaunchCountdown()
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "-debugFinishSave"),
           CommandLine.arguments.indices.contains(index + 1),
           let seconds = Double(CommandLine.arguments[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                if recorder.isRecording { finishRide(save: true) }
            }
        }
        if CommandLine.arguments.contains("-debugRecord") {
            recorder.isRecording = true
            recorder.currentLean = 27
            recorder.maxLeanAngle = 41
            lean.angle = 27
            lean.maxAngle = 41
            lean.isCalibrated = true
            trackCoordinates = DebugScreens.recordedPreviewCoordinates
        }
    }
    #endif

    private var alertSuppressionReason: String {
        if nav.route == nil { return "no-route" }
        if nav.rerouting { return "rerouting" }
        if nav.arrived { return "arrived" }
        if nav.offRoute { return "off-route" }
        if !nav.joined { return "not-joined" }
        return "unknown"
    }

    private func setUpRide() {
        // NavigationManager already listens for its own GPS updates; feeding
        // them again here would process every fix twice.
        recorder.onLocation = { location in
            alerts.handle(location)
            let now = Date()
            if now.timeIntervalSince(lastCompanionTick) >= 5 {
                lastCompanionTick = now
                companion.tick(context: companionContext())
            }
            // Throttled to one line every 15 s inside RideDebug, and a no-op
            // unless a ride is actually being recorded.
            RideDebug.shared.sample(location,
                                    progress: nav.routeProgress,
                                    remaining: nav.remaining,
                                    step: nav.step?.instruction,
                                    stepDistance: nav.stepDistance,
                                    turn: nav.step.map { "\($0.turn)" },
                                    lap: nav.lap,
                                    totalLaps: nav.totalLaps,
                                    speedLimit: alerts.speedLimitMph,
                                    offRoute: nav.offRoute)
        }
        // Only traffic devices that lie on the active route are eligible for
        // alerts; free-riding or being off-route suppresses them.
        alerts.routeProvider = {
            guard let route = nav.route, nav.isOnRoute else {
                // Without a context the hazard loop returns before it logs
                // anything, which used to make a silent ride unexplainable.
                let reason = alertSuppressionReason
                RideDebug.shared.note("NO-ALERTS", key: reason, [("reason", reason)])
                return nil
            }
            return RideRouteContext(route: route, progress: nav.routeProgress, lap: nav.lap)
        }
        #if DEBUG
        if !CommandLine.arguments.contains("-noPerm") { recorder.requestPermission() }
        #else
        recorder.requestPermission()
        #endif
        recorder.onStart = {
            let bike = selectedVehicle?.displayName
                ?? (nav.vehicleKind.isCar ? "Car" : selectedBike)
            RideDebug.shared.begin(route: nav.route, bike: bike)
            RideDebug.shared.event("NAV-SNAPSHOT", [
                ("joined", nav.joined ? "yes" : "no"),
                ("vehicle", "\(nav.vehicleKind)"),
                ("step", nav.step?.instruction ?? "—"),
                ("turn", nav.step.map { "\($0.turn)" } ?? "—"),
                ("stepDistance", "\(Int(nav.stepDistance))"),
                ("remaining", "\(Int(nav.remaining))"),
                ("lap", "\(nav.lap)/\(nav.totalLaps)"),
                ("offRoute", nav.offRoute ? "yes" : "no"),
                ("limit", alerts.speedLimitMph.map { "\($0) mph" } ?? "—")
            ])
            companion.rideStarted(context: companionContext())
            // "While Using" stops delivering fixes when the screen locks, so a
            // ride recorded in a pocket shows a running clock and no distance.
            let background = LocationHub.shared.hasBackgroundAuthorization
            RideDebug.shared.event("PERMISSION", [("background", background ? "on" : "off")])
            RevertDiagnostics.log("ride.start background=\(background)")
            if !background { showsBackgroundLocationWarning = true }
        }
        AudioRouteMonitor.shared.start()
        cameraDriver.start()
        MapHangMonitor.shared.start()
        if !isCar {
            lean.start()
            configureRemote()
        }
        applyCameraMode()
        autoStartTimedRunIfNeeded()
        configureVoice()
        if let route = nav.route {
            loadGhost()
            loadRouteHazards(route)
            LiveRideActivity.shared.start()
            WidgetBridge.setRideActive(true, routeName: route.displayName)
            updateLiveActivity()
        }
        refreshCompanionWeather()
        if binaural, !isCar { HelmetAudio.shared.start() }
        if recorder.isRecording {
            if isCar { gForce.start() }
            if wantsVoiceListening, !voice.isListening, VoiceCommandRecognizer.permissionGranted {
                voiceStartedManually = false
                voice.start()
            }
        }
        #if DEBUG
        applyDebugRideState()
        if CommandLine.arguments.contains("-debugNoBackgroundWarning") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                showsBackgroundLocationWarning = false
            }
        }
        #endif
    }

    /// One-shot prompt after the bike-or-car choice. The flag is cleared as
    /// soon as it is read so relaunching the cockpit never repeats it.
    private func presentHandoffPromptIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "intent.handoffPrompt") else { return }
        defaults.set(false, forKey: "intent.handoffPrompt")
        guard nav.route != nil else { return }
        showingHandoffPrompt = true
    }

    private func tearDownRide() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        lapNoticeTask?.cancel()
        lapNoticeTask = nil
        lapNotice = nil
        lean.stop()
        gForce.stop()
        voice.stop()
        remote.stop()
        AudioRouteMonitor.shared.stop()
        cameraDriver.stop()
        MapHangMonitor.shared.stop()
        hazardLoadTask?.cancel()
        hazardLoadTask = nil
        RouteSimulator.shared.stop()
        LiveRideActivity.shared.end()
        WidgetBridge.setRideActive(false)
        var parked = CarWidgetSnapshot.parked
        parked.vehicleKind = isCar ? "car" : "motorcycle"
        parked.updatedAt = Date()
        WidgetBridge.updateCarState(parked, force: true, reason: "teardown")
        WidgetBridge.flushWidgetDebug()
        RideDebug.shared.finishIfActive()
        HelmetAudio.shared.stop()
        IdleTimer.release("ride")
        // Leaving the screen stops the clock but must not delete the journal: a
        // ride that was still running when the cockpit went away is offered by
        // the recovery prompt instead of vanishing.
        if recorder.wasSimulated {
            recorder.discard()
        } else {
            recorder.suspend()
        }
        // These closures capture this view, and the view owns the recorder and
        // the alert engine, so leaving them installed leaks a recorder (and its
        // whole track) per cockpit session.
        recorder.onLocation = nil
        recorder.onStart = nil
        alerts.routeProvider = nil
        voice.onCommand = nil
        voice.onUtterance = nil
    }

    // MARK: Map

    @ViewBuilder
    private var map: some View {
        if mapRenderer == MapRendererKind.immersive.rawValue {
            RideImmersiveMapView(route: nav.route,
                                 progress: nav.routeProgress,
                                 cameraFrame: cameraDriver.frame,
                                 puck: puckCoordinate,
                                 driver: cameraDriver)
                .ignoresSafeArea()
        } else if mapRenderer == MapRendererKind.mapKit.rawValue {
            RideMapKitView(route: nav.route,
                           progress: nav.routeProgress,
                           cameraFrame: cameraDriver.frame,
                           puck: puckCoordinate,
                           heading: cameraIsCockpit ? 0 : nav.userHeading,
                           speed: nav.currentSpeedMps,
                           track: trackCoordinates,
                           approach: nav.approachCoordinates,
                           ghost: ghostCoordinate,
                           hazards: marks.hazards)
                .ignoresSafeArea()
        } else {
            swiftUIMap
        }
    }

    private var ghostCoordinate: CLLocationCoordinate2D? {
        guard ghostEnabled, let ghost else { return nil }
        return ghost.coordinate(at: recorder.elapsed(at: Date()))
    }

    private var swiftUIMap: some View {
        Map(position: $camera) {
            if nav.approachCoordinates.count > 1 {
                MapPolyline(coordinates: nav.approachCoordinates)
                    .stroke(MapUI.amber.opacity(0.85),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round,
                                               dash: [10, 8]))
            }
            if let ribbon {
                if ribbon.travelled.count > 1 {
                    MapPolyline(coordinates: ribbon.travelled)
                        .stroke(MapConfig.casing, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: ribbon.travelled)
                        .stroke(MapConfig.accent.opacity(0.35),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if ribbon.remaining.count > 1 {
                    MapPolyline(coordinates: ribbon.remaining)
                        .stroke(MapConfig.casing, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    ForEach(ribbon.remainingSegments) { segment in
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(MapConfig.paceColor(segment.merit),
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            if trackCoordinates.count > 1 {
                MapPolyline(coordinates: trackCoordinates)
                    .stroke(MapUI.emerald.opacity(0.85), lineWidth: 5)
            }
            if let coordinate = puckCoordinate {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    // In heading-up modes the map already rotates, so the puck
                    // must point straight up. Rotating it by absolute heading
                    // as well is what made it sit diagonally.
                    NavigationPuck(heading: cameraIsCockpit ? 0 : nav.userHeading,
                                   speed: nav.currentSpeedMps)
                }
            }
            if ghostEnabled, let ghost,
               let coordinate = ghost.coordinate(at: recorder.elapsed(at: Date())) {
                Annotation("Ghost", coordinate: coordinate, anchor: .center) {
                    Image(systemName: "figure.run")
                        .accessibilityLabel("Ghost of the reference ride")
                        .font(.scaledSystem(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(MapUI.magenta, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                }
            }
            ForEach(marks.hazards) { mark in
                Annotation("Rider mark", coordinate: mark.coordinate, anchor: .center) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.scaledSystem(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(3)
                        .background(MapUI.amber, in: Circle())
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    private var mapControls: some View {
        RevertMapDock {
            Menu {
                Button {
                    voiceMuted.toggle()
                    RevertHaptics.tap()
                    RevertDiagnostics.log("voice.muted=\(voiceMuted)")
                } label: {
                    Label(voiceMuted ? "Unmute voice" : "Mute voice",
                          systemImage: voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                Divider()
                Button {
                    showingSettings = true
                } label: {
                    Label("App settings", systemImage: "slider.horizontal.3")
                }
                Divider()
                ForEach(RideCameraMode.allCases) { mode in
                    Button {
                        cameraMode = mode
                    } label: {
                        if cameraMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Label(mode.title, systemImage: mode.icon)
                        }
                    }
                }
                Divider()
                Menu {
                    ForEach(RideProfile.allCases.filter { $0 != .custom }) { profile in
                        Button {
                            profile.apply()
                            RevertHaptics.tap()
                        } label: {
                            Label(profile.title, systemImage: profile.symbol)
                        }
                    }
                } label: {
                    Label("Ride profile", systemImage: "slider.horizontal.3")
                }
                if nav.route != nil {
                    Button {
                        handoffRoute = nav.route
                    } label: {
                        Label("Send to car screen", systemImage: "car.side.fill")
                    }
                }
                Divider()
                Button {
                    mapStyle = .standard(elevation: .flat)
                    mapStyleName = "standard"
                } label: {
                    mapStyleLabel("Standard", id: "standard")
                }
                Button {
                    mapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
                    mapStyleName = "muted"
                } label: {
                    mapStyleLabel("OLED muted", id: "muted")
                }
                Divider()
                Menu {
                    ForEach(MapRendererKind.allCases) { renderer in
                        Button {
                            guard renderer.isAvailable else { return }
                            mapRenderer = renderer.rawValue
                        } label: {
                            if mapRenderer == renderer.rawValue {
                                Label(renderer.title, systemImage: "checkmark")
                            } else {
                                Label(renderer.title, systemImage: renderer.isAvailable ? "map" : "lock")
                            }
                        }
                        .disabled(!renderer.isAvailable)
                    }
                } label: {
                    Label("Map renderer", systemImage: "square.stack.3d.up")
                }

                Divider()
                Menu {
                    ForEach(UnitSystemPreference.allCases) { preference in
                        Button {
                            setUnitPreference(preference)
                        } label: {
                            if Units.preference == preference {
                                Label(preference.title, systemImage: "checkmark")
                            } else {
                                Label(preference.title, systemImage: preference.icon)
                            }
                        }
                    }
                } label: {
                    Label("Units: \(Units.preference.shortTitle)", systemImage: "ruler")
                }

                Divider()
                Button {
                    markHazard()
                } label: {
                    Label("Mark hazard here", systemImage: "exclamationmark.triangle")
                }
                Button {
                    avoidCurrentRoad()
                } label: {
                    Label("Avoid this road", systemImage: "nosign")
                }
                Button {
                    ghostEnabled.toggle()
                    loadGhost()
                } label: {
                    Label(ghostEnabled ? "Ghost on" : "Ghost off", systemImage: ghostEnabled ? "figure.run.circle.fill" : "figure.run.circle")
                }
                Button {
                    longRideMode.toggle()
                    if !longRideMode { dimmed = false }
                } label: {
                    Label(longRideMode ? "Battery mode on" : "Battery mode off", systemImage: "battery.25percent")
                }

                #if DEBUG
                if nav.route != nil {
                    Divider()
                    Button {
                        showingSimulator = true
                    } label: {
                        Label("Route simulator", systemImage: "play.circle")
                    }
                }
                #endif
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.scaledSystem(size: 16, weight: .bold))
                    .foregroundStyle(MapUI.ink)
                    .frame(width: RevertMetrics.dockButtonSize, height: RevertMetrics.dockButtonSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ride menu")

            RevertMapDockDivider()

            RevertMapDockButton(
                systemImage: "location.north.fill",
                label: "Center on my location"
            ) {
                cameraMode = .northUp
                applyCameraMode()
            }

            RevertMapDockDivider()

            RevertMapDockButton(
                systemImage: companion.state == .off
                    ? "speaker.slash.fill"
                    : (voice.isListening ? "waveform" : "mic.slash"),
                label: companion.state == .off
                    ? "Companion off"
                    : (voice.isListening ? "Stop voice commands" : "Start on-device voice commands"),
                tint: voice.isListening ? MapUI.emerald : MapUI.ink,
                active: voice.isListening
            ) {
                guard companion.state != .off else { return }
                if voice.isListening {
                    voiceStartedManually = false
                    voice.stop()
                } else {
                    Speaker.shared.stop()
                    voiceStartedManually = true
                    voice.start(requestingPermission: true)
                }
            }
            .disabled(companion.state == .off)
        }
        .padding(.top, mapControlsTopPadding)
        .padding(.leading, 16)
    }

    @ViewBuilder
    private func mapStyleLabel(_ title: String, id: String) -> some View {
        if mapStyleName == id {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// The controls rail sits below the banner stack instead of guessing at
    /// banner heights: navigation, curve and hazard banners can stack two or
    /// three deep, and a fixed offset used to push the last button into the
    /// ride panel.
    private var mapControlsTopPadding: CGFloat {
        max(bannerHeight + 12, 68)
    }

    private var nextMode: RideCameraMode {
        let all = RideCameraMode.allCases
        let index = all.firstIndex(of: cameraMode) ?? 0
        return all[(index + 1) % all.count]
    }

    private func applyCameraMode() {
        guard cameraIsCockpit else {
            camera = .userLocation(followsHeading: false, fallback: .automatic)
            // The map renderer needs a pose too: stopping the driver used to
            // freeze the last heading-up frame, so "North up" appeared to do
            // nothing on the vector renderer.
            if let pose = nav.cameraPose {
                cameraDriver.present(staticFrame: stillFrame(for: pose, northUp: true))
            } else {
                cameraDriver.stop()
            }
            return
        }
        if reduceMotion {
            if let pose = nav.cameraPose {
                camera = cameraMode.camera(for: pose)
                cameraDriver.present(staticFrame: stillFrame(for: pose, northUp: false))
            } else {
                cameraDriver.stop()
            }
            return
        }
        cameraDriver.start()
        if let pose = nav.cameraPose {
            cameraDriver.update(route: nav.route,
                                progress: nav.routeProgress,
                                speed: pose.speed,
                                maneuverMeters: nav.stepDistance,
                                fallbackHeading: pose.heading,
                                centered: !cameraMode.usesLookAhead,
                                mode: cameraMode)
        }
    }

    /// A pose for the renderers when the camera must not follow: north-up and
    /// Reduce Motion both need one fixed frame per position change.
    private func stillFrame(for pose: RideCameraPose, northUp: Bool) -> RideCameraFrame {
        RideCameraFrame(latitude: pose.latitude,
                        longitude: pose.longitude,
                        heading: northUp ? 0 : pose.heading,
                        pitch: northUp ? 0 : cameraMode.pitch,
                        distance: cameraMode.distance(for: pose.speed))
    }

    // MARK: Banners

    /// The car-screen offer belongs where a rider is about to set off, not in a
    /// settings screen: it sits under the navigation banner until dismissed.
    private var handoffChip: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.scaledSystem(size: 15, weight: .semibold))
                .foregroundStyle(MapUI.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("Car screen?")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                Text("Send this route to Organic Maps")
                    .font(.scaledSystem(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(MapUI.secondaryInk)
            }
            Spacer(minLength: 6)
            Button("Send") {
                handoffChipDismissed = true
                handoffRoute = nav.route
            }
            .buttonStyle(RevertPrimaryButtonStyle(minHeight: 36))
            Button {
                handoffChipDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.scaledSystem(size: 11, weight: .bold))
                    .foregroundStyle(MapUI.secondaryInk)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss car screen offer")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Pulse.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MapUI.cyan.opacity(0.25), lineWidth: 1))
    }

    private var bannerStack: some View {
        VStack(spacing: 8) {
            if recorder.authStatus == .denied || recorder.authStatus == .restricted {
                LocationPermissionBanner()
            }
            if gpsStale {
                GpsSearchingBanner()
            }
            if LocationHub.shared.isReducedAccuracy,
               recorder.authStatus == .authorizedWhenInUse || recorder.authStatus == .authorizedAlways {
                ReducedAccuracyBanner()
            }
            if voice.isListening {
                VoiceListeningBanner(transcript: voice.transcript,
                                     inputName: audioRoute.isUsingBluetoothInput ? audioRoute.inputName : nil)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let message = voice.statusMessage {
                VoiceErrorBanner(
                    message: message,
                    showsSettings: voice.authorizationDenied,
                    onDismiss: { voice.statusMessage = nil }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if nav.route != nil {
                NavBanner(nav: nav)
                    .accessibilityIdentifier(AccessibilityID.Cockpit.banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if nav.route != nil, !handoffChipDismissed, !carLandscape {
                handoffChip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let lapNotice {
                LapNoticeBanner(lap: lapNotice,
                                total: nav.totalLaps,
                                lastLap: nav.lastLapDuration)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if simulator.isRunning || simulator.isPaused {
                SimulationHUD(simulator: simulator) {
                    showingSimulator = true
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if ghostEnabled, let ghost {
                GhostDeltaChip(delta: recorder.distanceMeters - ghost.distance(at: recorder.elapsed(at: Date())))
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if ghostEnabled, nav.route != nil {
                GhostUnavailableChip()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // One secondary alert at a time. Stacking a hazard, a curve and a
            // surface warning under the maneuver banner made the cockpit read
            // as a wall of cards at exactly the moment it should be calm.
            if let a = alerts.activeAlert {
                AlertBanner(alert: a)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let c = alerts.curveAlert {
                CurveBanner(alert: c)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let sf = alerts.surfaceAlert {
                SurfaceBanner(alert: sf)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Panel

    @ViewBuilder private var panel: some View {
        if carLandscape {
            EmptyView()
        } else {
            standardPanel
        }
    }

    private var standardPanel: some View {
        VStack(spacing: 12) {
            HStack {
                CompanionStateChip()
                Spacer(minLength: 0)
            }
            if isCar {
                carModeCaption
            }

            if nav.route == nil, !recorder.isRecording {
                noRoutePrompt
            } else {
                SpeedometerCard(recorder: recorder, alerts: alerts)

                if !isCar, !lean.isAvailable || !lean.isCalibrated {
                    LeanAngleCard(lean: lean)
                        .padding(.horizontal, 2)
                }

                if recorder.isRecording {
                    if !isCar, lean.isAvailable {
                        VectorArcLeanGauge(angle: lean.angle,
                                           maxAngle: max(lean.maxAngle, recorder.maxLeanAngle),
                                           isCalibrated: lean.isCalibrated)
                            .frame(maxWidth: .infinity)
                    }
                    RideStatsView(recorder: recorder)
                }
            }

            controls
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background { panelBackground }
    }

    /// A single compact line replaces the old 42pt card for one line of
    /// vehicle information. G-force is a car readout, not a second hero.
    private var carModeCaption: some View {
        HStack(spacing: 7) {
            Image(systemName: "car.fill")
                .font(.scaledSystem(size: 11, weight: .bold))
                .foregroundStyle(Pulse.positive)
            Text("CAR MODE")
                .font(.scaledSystem(size: 8.5, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Pulse.positive)
            Text(selectedVehicle?.displayName ?? (isCar ? "Car" : "Vehicle"))
                .font(.scaledSystem(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Pulse.mutedStrong)
                .lineLimit(1)
            Spacer(minLength: 4)
            if recorder.isRecording {
                Text(gForceText)
                    .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Pulse.accent)
            }
        }
        .padding(.horizontal, 4)
    }

    private var gForceText: String {
        let total = sqrt(pow(gForce.lateralG, 2) + pow(gForce.longitudinalG, 2))
        return "\(RevertFormat.number(total, decimals: 2)) G"
    }

    /// Before a route or a free ride, the cockpit has nothing to instrument.
    /// Show one clear next step instead of a fake 0 mph dashboard.
    private var noRoutePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "map")
                    .font(.scaledSystem(size: 16, weight: .semibold))
                    .foregroundStyle(Pulse.accent)
                    .frame(width: 38, height: 38)
                    .background(Pulse.accentWell, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("No route yet")
                        .font(.scaledSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Pulse.ink)
                    Text("Plan a route for guidance, or start a free ride below.")
                        .font(.scaledSystem(size: 10.5))
                        .foregroundStyle(Pulse.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button {
                RevertHaptics.tap()
                if let onPlanRoute {
                    onPlanRoute()
                } else {
                    exitCockpit()
                }
            } label: {
                Label("Plan route", systemImage: "map.fill")
            }
            .buttonStyle(PulseGhostButtonStyle(minHeight: 42, compact: true))
            .accessibilityIdentifier(AccessibilityID.Cockpit.planRoute)
        }
        .padding(12)
        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Pulse.line, lineWidth: 0.8)
        }
    }

    /// Landscape car cockpit, Google-style: the map is the screen, the
    /// maneuver card floats top-left, ETA and speed sit in the lower corners,
    /// and the controls live in a thumb rail at the trailing edge.
    private var carLandscapeHUD: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    carManeuverCard
                    Spacer(minLength: 100)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    carETACard
                        .frame(width: 168, alignment: .leading)
                    Spacer(minLength: 0)
                    carSpeedCard
                    controls
                        .frame(width: 340)
                    Spacer(minLength: 58)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .safeAreaPadding(.horizontal, 4)

            HStack {
                Spacer(minLength: 0)
                carRightRail
            }
            .padding(.trailing, 18)
            .padding(.top, 18)
        }
        .allowsHitTesting(true)
    }

    private var carLaneGuidance: LaneGuidance? {
        guard nav.joined, !nav.arrived, let lanes = nav.step?.laneGuidance else { return nil }
        let reveal = LaneGuidance.revealDistance(forSpeed: nav.currentSpeedMps)
        return nav.stepDistance <= reveal ? lanes : nil
    }

    private var carManeuverCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: nav.arrived ? "flag.checkered" : (nav.step?.symbol ?? "arrow.up"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(MapUI.emerald, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(nav.arrived ? "ARRIVED" : "NEXT · \(navDistance(nav.stepDistance).uppercased())")
                    .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(MapUI.emerald)
                Text(nav.arrived ? "You have arrived" : (nav.step?.instruction ?? "Follow the route"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let lanes = carLaneGuidance {
                    LaneStrip(guidance: lanes)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 540, alignment: .leading)
        .background(MapUI.panel.opacity(0.93), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(MapUI.emerald.opacity(0.28), lineWidth: 0.8))
    }

    private var carETACard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ETA")
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            Text(carETAText)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MapUI.emerald)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(carETAUnderline)
                .font(.scaledSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(MapUI.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ETA")
        .accessibilityValue("\(carETAText), \(carETAUnderline)")
    }

    private var carETAText: String {
        if nav.arrived { return "Arrived" }
        var seconds = nav.estimatedTimeRemaining
        if seconds == nil, nav.remaining > 0, recorder.currentSpeedMps > 1 {
            seconds = nav.remaining / recorder.currentSpeedMps
        }
        guard let seconds, seconds > 0 else { return "Pending" }
        let minutes = max(Int((seconds / 60).rounded()), 1)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private var carETAUnderline: String {
        let remaining = Units.shortDistanceText(nav.remaining)
        if nav.arrived { return remaining }
        guard let seconds = nav.estimatedTimeRemaining, seconds > 0 else { return remaining }
        let arrival = Date().addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened)
        return "\(remaining) · \(arrival)"
    }

    private var carSpeedCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(Int(Units.speedValue(recorder.currentSpeedMps).rounded()))")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(Units.speedUnitUppercase)
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.62))
            if let limit = alerts.speedLimitMph {
                SpeedLimitSign(limit: limit, over: alerts.isOverLimit)
                    .scaleEffect(0.58)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(MapUI.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }

    private var carRightRail: some View {
        VStack(spacing: 10) {
            carRailButton("location.north.fill", label: "Recenter") {
                cameraMode = .northUp
                applyCameraMode()
            }
            carRailButton(voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                          label: voiceMuted ? "Unmute voice" : "Mute voice") {
                voiceMuted.toggle()
            }
            carRailButton(companion.state == .off ? "speaker.slash.fill" : "waveform",
                          label: "Companion \(companion.state.title)") {
                companion.cycleState()
            }
            carRailButton("slider.horizontal.3", label: "App settings") {
                showingSettings = true
            }
            carRailButton("xmark", label: "Close ride screen") {
                close()
            }
        }
    }

    private func carRailButton(_ systemImage: String, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.58), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Landscape car cockpit. The map keeps the space above a shallow bottom
    /// strip; speed and limit are the hero, the four drive stats sit beside
    /// them, and the same start/pause/stop controls remain reachable.
    private var carLandscapePanel: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "car.fill")
                    .font(.scaledSystem(size: 11, weight: .bold))
                    .foregroundStyle(MapUI.emerald)
                Text("CAR MODE")
                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(MapUI.emerald)
                Text(selectedVehicle?.displayName ?? (isCar ? "Car" : "Vehicle"))
                    .font(.scaledSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MapUI.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                CompanionStateChip(compact: true)
                if let limit = alerts.speedLimitMph {
                    Text("\(limit) LIMIT")
                        .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
                Button {
                    RevertHaptics.tap()
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.scaledSystem(size: 10, weight: .bold))
                        .foregroundStyle(MapUI.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(MapUI.surfaceHigh.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("App settings")
            }

            HStack(alignment: .center, spacing: 12) {
                SpeedometerCard(recorder: recorder, alerts: alerts)
                    .frame(width: 265)

                VStack(spacing: 6) {
                    RideStatsView(recorder: recorder)
                    controls
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background { panelBackground }
    }

    private var panelBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
            .fill(reduceTransparency ? AnyShapeStyle(MapUI.canvas) : AnyShapeStyle(.ultraThinMaterial))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                    .fill(MapUI.canvas.opacity(0.92))
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.clear, MapUI.cyan.opacity(0.55), .white.opacity(0.10), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, 34)
            }
            .shadow(color: .black.opacity(0.58), radius: 26, y: -10)
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            if !isCar {
                calibrateButton
            }

            Spacer(minLength: 4)

            if recorder.isRecording {
                Button {
                    RevertHaptics.tap()
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                } label: {
                    Label(recorder.isPaused ? "Resume" : "Pause",
                          systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 50))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(AccessibilityID.Cockpit.pause)

                Button {
                    RevertHaptics.warning()
                    showingStopConfirmation = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(RevertPrimaryButtonStyle(
                    gradient: LinearGradient(
                        colors: [Color(red: 1.00, green: 0.29, blue: 0.35),
                                 Color(red: 0.78, green: 0.06, blue: 0.17)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    glow: MapUI.danger,
                    minHeight: 50,
                    compact: true,
                    labelColor: .white
                ))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(AccessibilityID.Cockpit.stop)
            } else if waitingForStart {
                startLinePill
                closeButton
            } else {
                Button {
                    startRide()
                } label: {
                    Label(startButtonTitle,
                          systemImage: countdown == nil ? "play.fill" : "hourglass")
                }
                .disabled(countdown != nil)
                .buttonStyle(RevertPrimaryButtonStyle(minHeight: 50, compact: true))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(AccessibilityID.Cockpit.start)

                closeButton
            }
        }
    }

    private var startButtonTitle: String {
        if countdown != nil { return "Get ready" }
        if nav.route == nil { return isCar ? "Start free drive" : "Start free ride" }
        switch nav.route?.kind {
        case .loop: return isCar ? "Start drive" : "Start loop"
        case .sprint: return isCar ? "Start drive" : "Start sprint"
        default: return isCar ? "Start drive" : "Start ride"
        }
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(RevertIconButtonStyle(tint: MapUI.textSecondary, diameter: 50))
        .accessibilityLabel("Close ride screen")
        .accessibilityIdentifier(AccessibilityID.Cockpit.close)
    }

    /// Until the rider reaches the start, the Start button would start the
    /// clock in the wrong place. Explain the wait instead.
    /// Not yet at the start line, but never a dead end: tapping starts the
    /// recording from here. The pill is a button, not a notice.
    private var startLinePill: some View {
        Button {
            startRide()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "play.fill")
                    .font(.scaledSystem(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(MapUI.amber, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start now")
                        .font(.scaledSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(1)
                    Text("Timer starts at the loop start · \(navDistance(nav.approachActive ? nav.approachRemaining : nav.distanceToStart)) to go")
                        .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.amber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(MapUI.surfaceHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MapUI.amber.opacity(0.28), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start recording now. Timer starts at the loop start. \(navDistance(nav.approachActive ? nav.approachRemaining : nav.distanceToStart)) to go.")
    }

    private var calibrateButton: some View {
        Button {
            RevertHaptics.tap()
            lean.calibrate()
        } label: {
            Image(systemName: "gyroscope")
        }
        .buttonStyle(RevertIconButtonStyle(
            tint: lean.isCalibrated ? MapUI.textSecondary : MapUI.cyan,
            diameter: 50
        ))
        .accessibilityLabel("Calibrate lean angle")
    }

    private func loadRouteHazards(_ route: PlannedRoute) {
        alerts.clearRouteHazards()
        hazardLoadTask?.cancel()
        hazardLoadTask = Task { @MainActor in
            let started = Date()
            let outcome = await RouteHazardLoader.load(route: route)
            guard !Task.isCancelled, nav.route?.id == route.id else { return }
            let marks = UserMarksStore.shared.routeHazards
            alerts.setRouteHazards((outcome.hazards ?? []) + marks, for: route.id)
            // "corridor=failed" means every endpoint failed and the tile cache
            // is the only source. "why" separates a dead network from a
            // timeout or a route too big to query; "corridor=0" means the
            // query answered with nothing and the engine stays silent.
            RideDebug.shared.event("HAZARD-SOURCE", [
                ("route", route.displayName ?? "(unnamed)"),
                ("corridor", outcome.hazards.map { "\($0.count)" } ?? "failed"),
                ("why", outcome.reason),
                ("ms", "\(Int(Date().timeIntervalSince(started) * 1000))"),
                ("tiles", "\(alerts.hazardItemCount)")
            ])
        }
    }

    private var liveActivityKey: String {
        let step = nav.step?.id ?? -1
        let distanceBucket = Int(nav.stepDistance / 100)
        return "\(nav.route?.id.uuidString ?? "none")-\(step)-\(distanceBucket)-\(nav.offRoute)-\(nav.rerouting)-\(nav.arrived)-\(nav.lap)-\(recorder.isPaused)"
    }

    private func updateLiveActivity() {
        guard let route = nav.route else { return }
        // Live Activity and widget snapshots are expensive. Turn changes,
        // off-route, arrival and pausing update immediately; everything else
        // publishes at most every 10 seconds.
        let stepID = nav.step?.id ?? -1
        let now = Date()
        let critical = nav.arrived || nav.offRoute || nav.rerouting
            || stepID != lastLiveStep || nav.lap != lastLiveLap
        guard critical || now.timeIntervalSince(lastLiveActivityUpdate) >= 10 else { return }
        lastLiveStep = stepID
        lastLiveLap = nav.lap
        lastLiveActivityUpdate = now
        let title: String
        if nav.arrived {
            title = "Route complete"
        } else if nav.rerouting {
            title = "Recalculating route"
        } else if nav.offRoute {
            title = "Off route — finding a way back"
        } else {
            let instruction = nav.step?.instruction ?? "Follow the route"
            title = nav.totalLaps > 1
                ? "Lap \(nav.lap)/\(nav.totalLaps) · \(instruction)"
                : instruction
        }
        let distance = nav.arrived ? "Done" : Units.shortDistanceText(nav.stepDistance)
        // The car card leads with the maneuver glyph and closes with the
        // projected finish, so both are computed here where `Units` and
        // `NavStep` live.
        let symbol: String
        if nav.arrived {
            symbol = "flag.checkered"
        } else if nav.rerouting {
            symbol = "arrow.triangle.2.circlepath"
        } else {
            symbol = nav.step?.symbol ?? "location.north.fill"
        }
        let eta: String
        if nav.arrived {
            eta = "Arrived"
        } else if let seconds = nav.estimatedTimeRemaining, seconds > 0 {
            eta = Date().addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened)
        } else {
            eta = "—"
        }
        let speedLimit = alerts.speedLimitMph.map { Units.speedTextFromMph(Double($0)) }
        let hazard = alerts.activeAlert?.hazard.kind.title
            ?? alerts.curveAlert?.title
            ?? alerts.surfaceAlert?.text
        let simulation = simulator.isRunning || simulator.isPaused
        let vehicle = isCar ? "car" : "motorcycle"
        let progressValue = route.length > 0
            ? min(max(1 - nav.remaining / route.length, 0), 1)
            : 0
        // One banner per manoeuvre, inside the last 200 m, like a nav app.
        var alert: String?
        if let stepID = nav.step?.id,
           !nav.arrived, !nav.rerouting,
           nav.stepDistance <= 200,
           !alertedSteps.contains(stepID) {
            alertedSteps.insert(stepID)
            alert = title
        }
        let mode: CarWidgetSnapshot.Mode = nav.arrived
            ? .arrived
            : (simulation ? .simulation : (recorder.isPaused ? .paused : .driving))

        LiveRideActivity.shared.update(
            title: title,
            distance: distance,
            speed: Units.speedText(nav.currentSpeedMps),
            offRoute: nav.offRoute || nav.rerouting,
            turnSymbol: symbol,
            remaining: Units.shortDistanceText(nav.remaining),
            eta: eta,
            speedLimit: speedLimit,
            lap: nav.totalLaps > 1 ? nav.lap : 0,
            totalLaps: nav.totalLaps > 1 ? nav.totalLaps : 0,
            hazard: hazard,
            isSimulation: simulation,
            vehicleKind: vehicle,
            mapImage: liveMapImage,
            progress: progressValue,
            alert: alert,
            stepID: nav.step?.id ?? -1
        )

        let snapshot = CarWidgetSnapshot(
            schema: CarWidgetSnapshot.currentSchema,
            mode: mode,
            vehicleKind: vehicle,
            routeName: route.displayName ?? "",
            turnSymbol: symbol,
            turnDistance: distance,
            instruction: nav.step?.instruction ?? title,
            remaining: Units.shortDistanceText(nav.remaining),
            eta: eta,
            speed: Units.speedText(nav.currentSpeedMps),
            speedLimit: speedLimit,
            lap: nav.totalLaps > 1 ? nav.lap : 0,
            totalLaps: nav.totalLaps > 1 ? nav.totalLaps : 0,
            hazard: hazard,
            isSimulation: simulation,
            mapImage: overviewImage ?? liveMapImage,
            progress: progressValue,
            stepID: nav.step?.id ?? -1,
            updatedAt: Date()
        )
        let turnKey = "\(nav.lap)-\(nav.step?.id ?? -1)"
        let turnChanged = turnKey != lastWidgetTurnKey
        let reason = turnChanged
            ? "turn"
            : (mode != lastPublishedCarMode ? "mode" : (nav.arrived ? "arrived" : "state"))
        WidgetBridge.updateCarState(snapshot,
                                    force: turnChanged || mode != lastPublishedCarMode || nav.arrived,
                                    reason: reason)
        lastWidgetTurnKey = turnKey
        lastPublishedCarMode = mode
        WidgetBridge.flushWidgetDebug()
        refreshLiveMapCard()
    }

    /// The widget strip gets a north-up picture of the whole ride once, which
    /// stays useful for the entire route instead of ageing out in a minute.
    private func renderRouteOverview(_ route: PlannedRoute) {
        let coordinates = route.coordinates
        Task { @MainActor in
            guard let name = await LiveActivityMap.renderOverview(route: coordinates) else { return }
            overviewImage = name
            updateLiveActivity()
        }
    }

    /// The car card is a picture, so it is redrawn rather than animated: on a
    /// new maneuver, or every twelve seconds, whichever comes first. That is
    /// enough to read as a map without spending the snapshot budget on frames
    /// nobody looks at.
    private func refreshLiveMapCard() {
        guard let route = nav.route, !nav.arrived, let location = nav.currentLocation else { return }
        let step = nav.step?.id ?? -1
        // Five seconds on the approach to a turn, twenty on a straight. This is
        // what makes the card feel alive without redrawing a map nobody is
        // looking at.
        let interval: TimeInterval = nav.stepDistance <= 300 ? 30 : 60
        guard Date().timeIntervalSince(lastMapRender) > interval || step != lastMapStep else { return }
        lastMapRender = Date()
        lastMapStep = step

        let next: CLLocationCoordinate2D? = {
            guard let step = nav.step, route.points.indices.contains(step.at) else { return nil }
            return route.points[step.at].coordinate
        }()
        let coordinates = route.coordinates
        let course = location.course
        Task { @MainActor in
            let name = await LiveActivityMap.render(rider: location,
                                                    course: course,
                                                    route: coordinates,
                                                    nextManeuver: next)
            guard let name, name != liveMapImage else { return }
            liveMapImage = name
            updateLiveActivity()
        }
    }

    // MARK: Hands-free

    private func configureVoice() {
        voice.onUtterance = { text in
            guard companion.state != .off else { return }
            var query = text
            if wakeWord, !voiceStartedManually {
                guard let wakeQuery = CompanionWakeWord.query(from: text) else { return }
                query = wakeQuery
            }
            let context = companionContext()
            if let answer = companion.answer(query, context: context) {
                Speaker.shared.say(answer, kind: .alert)
                return
            }
            Task { @MainActor in
                guard let generated = await companion.freeFormAnswer(query, context: context) else { return }
                Speaker.shared.say(generated, kind: .alert)
            }
        }
        voice.onCommand = { command in
            switch command {
            case .startRide:
                if !recorder.isRecording { recorder.start() }
            case .pause:
                recorder.pause()
            case .resume:
                recorder.resume()
            case .saveRide:
                if recorder.isRecording { finishRide(save: true) }
            case .endRoute:
                nav.stop()
            case .repeatInstruction:
                if let step = nav.step {
                    Speaker.shared.say(Narrator.instruction(step, distance: nil), kind: .navigation)
                }
            case .calibrate:
                lean.calibrate()
            case .nextCamera:
                cameraMode = nextMode
            case .markHazard:
                markHazard()
            case .avoidRoad:
                avoidCurrentRoad()
            }
        }
    }

    private var ribbon: RouteRibbon? {
        guard let route = nav.route else { return nil }
        return RouteRibbon(route: route, progress: nav.routeProgress)
    }

    private var puckCoordinate: CLLocationCoordinate2D? {
        matchedPuck ?? nav.userCoordinate
    }

    private func updateMatchedPuck(_ pose: RideCameraPose) {
        guard let route = nav.route,
              let fix = nav.userCoordinate,
              let match = RouteMatcher.match(fix, route: route,
                                             minimumProgress: max(nav.routeProgress - 25, 0)) else {
            matchedPuck = nav.userCoordinate
            return
        }
        // 80 % snapped, 20 % raw: on the road without a visible snap.
        matchedPuck = CLLocationCoordinate2D(
            latitude: fix.latitude * 0.2 + match.coordinate.latitude * 0.8,
            longitude: fix.longitude * 0.2 + match.coordinate.longitude * 0.8
        )
    }

    private func companionContext() -> CompanionContext {
        let route = nav.route
        let routeKey = route.map { RouteFingerprint.key(for: $0) }
        let month = Calendar.current
        let loopCount = routeKey.map { key in
            pastRides.filter {
                $0.routeKey == key && month.isDate($0.startDate, equalTo: Date(), toGranularity: .month)
            }.count
        } ?? 0
        let conditions = ConditionsService.snapshot(route: route, bike: selectedVehicle)
        let tankFraction = UserDefaults.standard.object(forKey: "fuel.tankFraction") as? Double ?? 0.8
        let bike = selectedVehicle
        let bikeID = bike?.id
        let setup = setupNotes.first { $0.bikeID == bikeID }
        let maintenance = maintenanceEntries.first { $0.bike?.id == bikeID }
        let elapsed = recorder.elapsed(at: Date())
        let progress = (route?.length ?? 0) > 0 ? nav.routeProgress / max(route?.length ?? 1, 1) : 0
        let home = savedPlaceDistance(latKey: "saved.home.lat", lonKey: "saved.home.lon")
        let work = savedPlaceDistance(latKey: "saved.work.lat", lonKey: "saved.work.lon")
        return CompanionContext(
            speedMps: recorder.currentSpeedMps,
            remainingMeters: nav.remaining,
            estimatedSeconds: nav.estimatedTimeRemaining,
            nextManeuverMeters: nav.step == nil ? 9_999 : nav.stepDistance,
            nearestHazardMeters: alerts.activeAlert?.distance,
            hazardName: alerts.activeAlert?.hazard.kind.approachName,
            routeName: route?.displayName,
            routeKey: routeKey,
            routeIsLoop: route?.kind.isLoop ?? false,
            routeLengthMeters: route?.length ?? 0,
            routeClimbMeters: route?.climbMeters ?? 0,
            routeMaxElevation: route?.maxElevation ?? 0,
            routeTwistPerKm: route?.twistPerKm ?? 0,
            routeSurface: route?.surface.title,
            routeProgress: progress,
            nextInstruction: nav.step?.instruction,
            nextRoad: nav.step?.road,
            turnsRemaining: route?.steps.filter { $0.distance > nav.routeProgress && $0.turn != .arrive && $0.turn != .start }.count ?? 0,
            currentRoad: alerts.currentRoadName,
            speedLimitMph: alerts.speedLimitMph,
            lap: nav.lap,
            totalLaps: nav.totalLaps,
            offRoute: nav.offRoute,
            rideDistanceMeters: recorder.distanceMeters,
            rideDurationSeconds: elapsed,
            averageSpeedMps: elapsed > 0 ? recorder.distanceMeters / elapsed : 0,
            maxSpeedMps: recorder.maxSpeedMps,
            maxLeanAngle: recorder.maxLeanAngle,
            bike: bike,
            conditions: conditions,
            lastRide: pastRides.first,
            weather: companionWeather,
            surfaceAlert: alerts.surfaceAlert?.text,
            curveAlert: alerts.curveAlert?.title,
            homeDistanceMeters: home,
            workDistanceMeters: work,
            startHome: startHomeRoute,
            startWork: startWorkRoute,
            setupNote: setup,
            lastMaintenance: maintenance,
            loopCountThisMonth: loopCount,
            isStopped: recorder.currentSpeedMps < 1,
            tankFraction: tankFraction
        )
    }

    private func startHomeRoute() {
        startSavedPlaceRoute(place: "Home", latKey: "saved.home.lat", lonKey: "saved.home.lon")
    }

    private func startWorkRoute() {
        startSavedPlaceRoute(place: "Work", latKey: "saved.work.lat", lonKey: "saved.work.lon")
    }

    private func startSavedPlaceRoute(place: String, latKey: String, lonKey: String) {
        let lat = UserDefaults.standard.double(forKey: latKey)
        let lon = UserDefaults.standard.double(forKey: lonKey)
        guard lat != 0 || lon != 0, let current = nav.currentLocation else { return }
        Task { @MainActor in
            let request = MKDirections.Request()
            request.source = MKMapItem.revert(location: current)
            request.destination = MKMapItem.revert(location: CLLocation(latitude: lat, longitude: lon))
            request.transportType = .automobile
            VehiclePreferences.apply(to: request)
            request.requestsAlternateRoutes = false
            guard let response = try? await MKDirections(request: request).calculate(),
                  let first = response.routes.first else { return }
            var route = PlannedRoute(mapRoutes: [first],
                                     waypoints: [current.coordinate,
                                                 CLLocationCoordinate2D(latitude: lat, longitude: lon)],
                                     kind: .directions, surface: .paved)
            route.displayName = place
            nav.start(route, roads: [])
        }
    }

    private func savedPlaceDistance(latKey: String, lonKey: String) -> Double? {
        let lat = UserDefaults.standard.double(forKey: latKey)
        let lon = UserDefaults.standard.double(forKey: lonKey)
        guard lat != 0 || lon != 0, let current = nav.currentLocation else { return nil }
        return current.distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    private func refreshCompanionWeather() {
        guard let coordinate = nav.route?.points.first?.coordinate
                ?? nav.currentLocation?.coordinate else { return }
        Task { @MainActor in
            companionWeather = await CompanionWeatherService.shared.weather(for: coordinate)
        }
    }

    private func loadGhost() {
        ghost = nil
        guard ghostEnabled, let route = nav.route else { return }
        let key = RouteFingerprint.key(for: route)
        guard !key.isEmpty else { return }
        let matches = pastRides.filter { $0.routeKey == key && $0.distanceMeters > 0 }
        guard let previous = matches.min(by: { $0.durationSeconds < $1.durationSeconds }) else { return }
        ghost = GhostTrack(ride: previous)
    }

    private func setUnitPreference(_ preference: UnitSystemPreference) {
        unitSystem = preference.rawValue
        Units.setPreference(preference)
        WidgetBridge.updateUnits()
        RideDebug.shared.event("SETTING", [("key", "units.system"), ("value", preference.rawValue)])
        updateLiveActivity()
    }

    private func markHazard() {
        guard let coordinate = nav.userCoordinate else {
            Speaker.shared.say("No location yet", kind: .navigation)
            return
        }
        let road = alerts.currentRoadName
        marks.addHazard(kind: "Rider mark", coordinate: coordinate, road: road)
        if let route = nav.route, let hazard = marks.hazards.first?.asHazard {
            alerts.addRouteHazard(hazard, for: route.id)
        }
        Speaker.shared.say("Hazard marked", kind: .navigation)
        RideDebug.shared.event("RIDE-MARK", [
            ("road", road ?? "—"),
            ("lat", String(format: "%.5f", coordinate.latitude)),
            ("lon", String(format: "%.5f", coordinate.longitude))
        ])
    }

    private func avoidCurrentRoad() {
        guard let road = alerts.currentRoadName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !road.isEmpty else {
            Speaker.shared.say("No road name yet", kind: .navigation)
            return
        }
        marks.avoid(road)
        Speaker.shared.say("Avoiding \(road)", kind: .navigation)
        RideDebug.shared.event("RIDE-AVOID", [("road", road)])
    }

    private func configureRemote() {
        remote.onAction = { action in
            switch action {
            case .pauseResume:
                guard recorder.isRecording else { return }
                recorder.isPaused ? recorder.resume() : recorder.pause()
            case .repeatInstruction:
                if let step = nav.step {
                    Speaker.shared.say(Narrator.instruction(step, distance: nil), kind: .navigation)
                }
            case .endRoute:
                nav.stop()
            case .calibrate:
                lean.calibrate()
            case .nextCamera:
                cameraMode = nextMode
            case .companionState:
                companion.cycleState()
            case .pushToTalkStart:
                guard companion.state != .off else { return }
                Speaker.shared.stop()
                pushToTalk = true
                voiceStartedManually = true
                if !voice.isListening { voice.start(requestingPermission: true) }
            case .pushToTalkEnd:
                pushToTalk = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !pushToTalk else { return }
                    voiceStartedManually = false
                    if !wantsVoiceListening {
                        voice.stop()
                    }
                }
            }
        }
        remote.start()
    }

    // MARK: Ride lifecycle

    private func finishRide(save: Bool) {
        if save, recorder.wasSimulated {
            RouteSimulator.shared.stop()
            recorder.discard()
            nav.stop()
            RevertDiagnostics.log("sim.ride.discard route=\(nav.route?.displayName ?? "—")")
            rideError = "Simulation finished. This ride was not saved to History — its SIMULATION transcript and Simulation report are in the Ride debug folder."
            return
        }
        guard save else {
            recorder.discard()
            nav.stop()
            exitCockpit()
            return
        }

        companion.rideFinished(context: companionContext())

        guard let ride = recorder.stop() else {
            rideError = "There was not enough GPS data to create a ride. It was discarded."
            return
        }
        // Close the transcript with the numbers the rider will see in History,
        // before SwiftData is asked to save anything.
        LiveRideActivity.shared.end()
        WidgetBridge.setRideActive(false)
        var parked = CarWidgetSnapshot.parked
        parked.vehicleKind = nav.vehicleKind.isCar ? "car" : "motorcycle"
        parked.updatedAt = Date()
        WidgetBridge.updateCarState(parked, force: true, reason: "ride-saved")
        WidgetBridge.flushWidgetDebug()
        RideDebug.shared.finish(distanceMeters: ride.distanceMeters,
                                duration: ride.durationSeconds,
                                maxLean: max(ride.maxLeanAngleDegrees, recorder.maxLeanAngle),
                                endedAt: ride.endDate)
        let garageBike = selectedVehicle
        ride.bikeName = garageBike?.displayName
            ?? (nav.vehicleKind.isCar ? "Car" : selectedBike)
        ride.bikeID = garageBike?.id
        ride.routeName = nav.route?.displayName
        ride.laps = nav.route?.laps ?? 1
        ride.isSprint = nav.route?.kind.isSprint == true
        ride.vehicleKind = nav.vehicleKind
        if let route = nav.route {
            ride.routeKey = RouteFingerprint.key(for: route)
            ride.savedRouteID = route.savedRouteID
        }
        // A loop can be re-planned from a saved route without carrying the
        // saved id (older plans, CarPlay starts); match it by fingerprint so
        // the time still joins the right leaderboard.
        if ride.savedRouteID == nil, let key = ride.routeKey, !key.isEmpty {
            ride.savedRouteID = savedRoutes.first(where: { $0.fingerprintKey == key })?.id
        }
        ride.maxLeanAngleDegrees = max(ride.maxLeanAngleDegrees, recorder.maxLeanAngle)
        context.insert(ride)
        do {
            try context.save()
            RideJournal.shared.finish()
            if let garageBike {
                garageBike.odometerKm += ride.distanceMeters / 1_000
                try? context.save()
                WidgetBridge.updateBike(name: garageBike.displayName, odometerKm: garageBike.odometerKm, kind: garageBike.kind)
            }
            WidgetBridge.updateRide(distanceMeters: ride.distanceMeters,
                                    date: ride.startDate,
                                    routeName: ride.routeName,
                                    bikeName: garageBike?.displayName)
            nav.stop()
            savedSummary = ride
        } catch {
            // An inserted-but-unsaved object still appears in @Query. Remove it
            // before reporting the failure so History has no ghost ride.
            context.delete(ride)
            rideError = "SwiftData could not save this ride: \(error.localizedDescription). The ride was kept in the recovery journal and will be offered again next time."
        }
    }

    // MARK: Launch countdown

    /// Starting a loop is a two-handed job: mount the phone, pull gloves on,
    /// then find the button again. A short countdown gives the rider time to
    /// pocket the phone while the recording starts on its own.
    private func showLapNotice(_ lap: Int) {
        lapNoticeTask?.cancel()
        lapNotice = lap
        RevertHaptics.success()
        lapNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { lapNotice = nil }
        }
    }

    private func startRide() {
        guard countdown == nil else { return }
        RevertHaptics.success()
        if let route = nav.route, route.kind.isTimed {
            // Manual start is allowed even before the start line: a failed
            // join used to leave the rider in the cockpit with no way to
            // record at all. Auto-start is suppressed so joining later does
            // not start a second recording.
            autoStartedRouteID = route.id
            if launchCountdown {
                beginLaunchCountdown()
            } else {
                recorder.start()
            }
        } else {
            recorder.start()
        }
    }

    private var waitingForStart: Bool {
        guard let kind = nav.route?.kind else { return false }
        return kind.isTimed && !nav.joined
    }

    /// Reaching the start area starts the timed clock: a 3-2-1 countdown, then
    /// recording. This is deliberately automatic so the rider can follow the
    /// approach directions without touching the phone, and so the time is the
    /// loop, not the ride from the house to the start.
    private func autoStartTimedRunIfNeeded() {
        guard let route = nav.route,
              route.kind.isTimed,
              nav.joined,
              nav.routeProgress < 150,
              !recorder.isRecording,
              countdown == nil,
              autoStartedRouteID != route.id else { return }
        autoStartedRouteID = route.id
        if launchCountdown {
            beginLaunchCountdown()
        } else {
            recorder.start()
        }
    }

    private func beginLaunchCountdown() {
        countdownTask?.cancel()
        countdown = 3
        countdownTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countdown = value
                RevertHaptics.select()
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            countdown = 0
            RevertHaptics.success()
            recorder.start()
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            countdown = nil
        }
    }

    private func cancelLaunchCountdown() {
        RevertHaptics.tap()
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func close() {
        if recorder.isRecording {
            showingStopConfirmation = true
        } else {
            // Closing the cockpit is not the same as ending navigation. A
            // rider who opens it for a glance and closes it should still see
            // the nav banner on the map.
            exitCockpit()
        }
    }

    private func exitCockpit() {
        if let onExit {
            onExit()
        } else {
            dismiss()
        }
    }
}

/// Reports the live height of the banner stack so the map controls can sit
/// directly below it, whatever combination of banners is on screen.
private nonisolated struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private nonisolated struct BannerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Speed and stats

struct SpeedometerCard: View {
    let recorder: RideRecorder
    let alerts: AlertManager

    private var speed: Int {
        Int(Units.speedValue(recorder.currentSpeedMps).rounded())
    }

    private var progress: Double {
        if let limit = alerts.speedLimitMph {
            let displayLimit = Units.speedValueFromMph(Double(limit))
            guard displayLimit > 0 else { return 0 }
            return min(Double(speed) / displayLimit, 1)
        }
        return min(Double(speed) / 100, 1)
    }

    private var statusTint: Color {
        if recorder.isPaused { return MapUI.amber }
        return recorder.isRecording ? MapUI.emerald : MapUI.textTertiary
    }

    private var statusText: String {
        if recorder.isPaused { return "Paused" }
        return recorder.isRecording ? "Recording" : "Ready"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 7) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            RevertStatusPill(
                                text: statusText,
                                tint: statusTint,
                                pulsing: recorder.isRecording && !recorder.isPaused
                            )

                            if recorder.isRecording {
                                Text(Units.clock(recorder.elapsed(at: context.date)))
                                    .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(speed)")
                                .font(RevertType.number(recorder.isRecording ? 64 : 54))
                                .monospacedDigit()
                                .foregroundStyle(MapUI.ink)
                                .contentTransition(.numericText())
                                .shadow(color: MapUI.cyan.opacity(recorder.isRecording ? 0.38 : 0.16), radius: 13)
                            Text(Units.speedUnitUppercase)
                                .font(.scaledSystem(size: 10, weight: .heavy, design: .rounded))
                                .tracking(1.8)
                                .foregroundStyle(MapUI.textSecondary)
                        }
                    }

                    Spacer(minLength: 4)

                    if let limit = alerts.speedLimitMph {
                        SpeedLimitSign(limit: limit, over: alerts.isOverLimit)
                            .scaleEffect(0.82)
                            .frame(width: 72, height: 72)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                if alerts.speedLimitMph != nil {
                    RevertProgressBar(
                        value: progress,
                        tint: alerts.isOverLimit ? MapUI.ember : MapUI.aurora,
                        height: 4
                    )
                }
            }
            .animation(RevertMotion.smooth, value: speed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Speed \(speed) \(Units.speedUnit)\(recorder.isRecording ? ", recording" : "")")
    }
}

struct RideStatsView: View {
    let recorder: RideRecorder

    var body: some View {
        HStack(spacing: 0) {
            RevertStatTile(label: "Distance", value: Units.distanceText(recorder.distanceMeters))
            statDivider
            RevertStatTile(label: "Climb", value: Units.elevationText(recorder.elevationGain))
            statDivider
            RevertStatTile(label: "Peak", value: "\(Int(Units.speedValue(recorder.maxSpeedMps).rounded())) \(Units.speedUnit)")
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(MapUI.line)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 6)
    }
}

struct LeanAngleCard: View {
    let lean: LeanAngleManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title3)
                .foregroundStyle(MapUI.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("Lean angle")
                    .font(.subheadline.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(MapUI.secondaryInk)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let angle = lean.angle {
                    Text("\(Int(abs(angle).rounded()))°")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
                Text("\(Int(lean.maxAngle.rounded()))° max")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MapUI.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if !lean.isAvailable { return "Motion sensor unavailable" }
        if !lean.isCalibrated { return "Hold upright, then calibrate" }
        return "Auto-detected \(lean.detectedAxis.title.lowercased()) phone position"
    }
}

struct LocationPermissionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Location access is off")
                    .font(.headline)
                Text("Enable it in Settings to record rides and navigate.")
                    .font(.caption)
                    .foregroundStyle(MapUI.secondaryInk)
            }
            Spacer()
            Button("Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .foregroundStyle(.primary)
        .background(MapUI.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(MapUI.hairline, lineWidth: 0.8)
        }
        // The Settings button must remain its own accessibility element.
        .accessibilityElement(children: .contain)
    }
}

/// Small visible acknowledgement that the microphone is live, so tapping the
/// mic button does not feel like a no-op on a quiet road.
struct VoiceListeningBanner: View {
    let transcript: String
    var inputName: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.scaledSystem(size: 14, weight: .bold))
                .foregroundStyle(MapUI.emerald)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text(transcript.isEmpty
                 ? (inputName.map { "Listening on \($0) · say Hey Ace" } ?? "Listening for Hey Ace…")
                 : transcript)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(MapUI.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(inputName == nil ? "VOICE" : "HELMET")
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(MapUI.emerald)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MapUI.panel.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(MapUI.emerald.opacity(0.35), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transcript.isEmpty ? "Listening for a voice command" : "Heard \(transcript)")
    }
}

/// Explains why the microphone did not start (permission, on-device model or
/// audio-session failure) instead of leaving the rider with a dead button.
struct VoiceErrorBanner: View {
    let message: String
    let showsSettings: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "mic.slash.fill")
                .font(.scaledSystem(size: 13, weight: .bold))
                .foregroundStyle(MapUI.coral)
            Text(message)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(MapUI.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if showsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Settings") { UIApplication.shared.open(url) }
                    .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MapUI.cyan)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.scaledSystem(size: 9, weight: .heavy))
                    .foregroundStyle(MapUI.textSecondary)
            }
            .accessibilityLabel("Dismiss voice message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MapUI.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MapUI.coral.opacity(0.35), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }
}


/// Full-screen 3 · 2 · 1 before a loop starts recording.
struct LaunchCountdownView: View {
    let value: Int
    let routeName: String?
    var isSprint = false
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isGo: Bool { value <= 0 }
    private var progress: Double {
        Double(3 - min(max(value, 0), 3)) / 3
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text(isGo ? "LAUNCH" : (isSprint ? "SPRINT START" : "LOOP START"))
                    .font(.scaledSystem(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3.4)
                    .foregroundStyle(isGo ? MapUI.emerald : MapUI.cyan)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [MapUI.cyan, MapUI.emerald, MapUI.cyan],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: progress)

                    Text(isGo ? "GO" : "\(value)")
                        .font(.scaledSystem(size: isGo ? 84 : 132, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .shadow(color: (isGo ? MapUI.emerald : MapUI.cyan).opacity(0.55), radius: 26)
                }
                .frame(width: 248, height: 248)

                VStack(spacing: 6) {
                    Text(routeName ?? "Your loop")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(isGo
                         ? "Timer running. Ride safe."
                         : "The \(isSprint ? "sprint" : "loop") timer starts at GO. Pocket the phone and ride.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 300)

                if !isGo {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel launch")
                    }
                    .buttonStyle(RevertSecondaryButtonStyle(minHeight: 48))
                    .frame(width: 190)
                }
            }
            .padding(28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGo ? "Launch" : "Launching in \(value)")
        .accessibilityAddTraits(.isModal)
    }
}


/// Small transient confirmation when a circuit lap is banked.
struct LapNoticeBanner: View {
    let lap: Int
    let total: Int
    let lastLap: TimeInterval?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.scaledSystem(size: 13, weight: .bold))
                .foregroundStyle(MapUI.emerald)
                .frame(width: 28, height: 28)
                .background(MapUI.emerald.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("LAP \(lap) OF \(total)")
                    .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(MapUI.emerald)
                if let lastLap {
                    Text("Last lap \(Units.clock(lastLap))")
                        .font(.scaledSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MapUI.ink)
                }
            }

            Spacer(minLength: 0)

            Text("KEEP GOING")
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(MapUI.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MapUI.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MapUI.emerald.opacity(0.25), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lap \(lap) of \(total). \(lastLap.map { "Last lap \(Units.clock($0))" } ?? "")")
    }
}


/// Ride-debug transcript hooks. A modifier rather than five more `.onChange`
/// calls on the cockpit, which is already the largest expression in the app.
private struct RideDebugHooks: ViewModifier {
    let recorder: RideRecorder
    let nav: NavigationManager

    @AppStorage("ride.cameraMode") private var cameraMode: RideCameraMode = .cockpit
    @AppStorage("ride.launchCountdown") private var launchCountdown = true
    @AppStorage("ride.autoPause") private var autoPause = true
    @AppStorage("navigation.voice") private var navigationVoice = true
    @AppStorage("alert.voice") private var alertVoice = true
    @AppStorage("helmet.binaural") private var binaural = true
    @AppStorage("remote.enabled") private var remoteEnabled = true
    @AppStorage("rider.selectedBike") private var selectedBike = BikeCatalog.defaultBike
    @AppStorage("units.system") private var unitSystem = UnitSystemPreference.automatic.rawValue

    func body(content: Content) -> some View {
        content
            .onChange(of: recorder.isPaused) { _, paused in
                RideDebug.shared.event(paused ? "PAUSE" : "RESUME")
            }
            .onChange(of: nav.rerouting) { _, rerouting in
                RideDebug.shared.event(rerouting ? "REROUTE-START" : "REROUTE-END")
            }
            .onChange(of: nav.offRoute) { _, off in
                RideDebug.shared.event(off ? "OFF-ROUTE" : "ON-ROUTE")
            }
            .onChange(of: nav.arrived) { _, arrived in
                if arrived { RideDebug.shared.event("ARRIVED") }
            }
            .onChange(of: cameraMode) { _, value in
                RideDebug.shared.event("SETTING", [("key", "ride.cameraMode"), ("value", "\(value)")])
            }
            .onChange(of: launchCountdown) { _, value in
                RideDebug.shared.event("SETTING", [("key", "ride.launchCountdown"), ("value", value ? "yes" : "no")])
            }
            .onChange(of: autoPause) { _, value in
                RideDebug.shared.event("SETTING", [("key", "ride.autoPause"), ("value", value ? "yes" : "no")])
            }
            .onChange(of: navigationVoice) { _, value in
                RideDebug.shared.event("SETTING", [("key", "navigation.voice"), ("value", value ? "yes" : "no")])
            }
            .onChange(of: alertVoice) { _, value in
                RideDebug.shared.event("SETTING", [("key", "alert.voice"), ("value", value ? "yes" : "no")])
            }
            .onChange(of: binaural) { _, value in
                RideDebug.shared.event("SETTING", [("key", "helmet.binaural"), ("value", value ? "yes" : "no")])
            }
            .onChange(of: remoteEnabled) { _, value in
                RideDebug.shared.event("SETTING", [("key", "remote.enabled"), ("value", value ? "yes" : "no")])
            }
            .onChange(of: selectedBike) { _, value in
                RideDebug.shared.event("SETTING", [("key", "rider.selectedBike"), ("value", value)])
            }
            .onChange(of: unitSystem) { _, value in
                RideDebug.shared.event("SETTING", [("key", "units.system"), ("value", value)])
            }
    }
}

private struct GhostUnavailableChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 9, weight: .bold))
            Text("NO GHOST · SAME ROUTE")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.7)
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(MapUI.panel.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(MapUI.line, lineWidth: 0.7))
    }
}

private struct GhostDeltaChip: View {
    let delta: Double

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.scaledSystem(size: 9, weight: .heavy))
            Text(delta >= 0 ? "AHEAD" : "BEHIND")
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
            Text(Units.distanceText(abs(delta), decimals: 1))
                .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 27)
        .background(MapUI.magenta.opacity(0.88), in: Capsule())
        .accessibilityLabel(delta >= 0 ? "Ahead of the ghost by \(Units.distanceText(delta, decimals: 1))" : "Behind the ghost by \(Units.distanceText(abs(delta), decimals: 1))")
    }
}


/// Shown when the cockpit has been recording without a usable GPS fix.
struct GpsSearchingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.magnifyingglass")
                .foregroundStyle(MapUI.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Searching for GPS")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(MapUI.ink)
                Text("The clock is running; distance and guidance resume with the next fix.")
                    .font(.caption2)
                    .foregroundStyle(MapUI.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(MapUI.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MapUI.amber.opacity(0.35), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }
}


/// Shown when iOS is only providing an approximate location.
struct ReducedAccuracyBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.circle")
                .foregroundStyle(MapUI.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Precise location is off")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(MapUI.ink)
                Text("Turns and off-route detection need it. Settings → Privacy → Location → Precise Location.")
                    .font(.caption2)
                    .foregroundStyle(MapUI.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(MapUI.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MapUI.amber.opacity(0.35), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
