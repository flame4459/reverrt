import SwiftUI
import MapKit
import SwiftData
import CoreLocation

struct RideView: View {
    /// When the cockpit is a tab rather than a presented cover, the shell
    /// supplies the way out instead of SwiftUI's dismiss environment.
    var onExit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Bike.createdAt, order: .reverse) private var garageBikes: [Bike]
    @State private var recorder = RideRecorder()
    @State private var alerts = AlertManager()
    @State private var lean = LeanAngleManager()
    @State private var gForce = GForceModel()
    @State private var voice = VoiceCommandRecognizer()
    @State private var remote = HandlebarRemote()
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var mapStyle: MapStyle = .standard(elevation: .flat,
                                                      emphasis: .muted,
                                                      pointsOfInterest: .excludingAll)
    @State private var mapStyleName = "muted"
    @State private var showingStopConfirmation = false
    @State private var showingSettings = false
    @State private var rideError: String?
    @State private var trackCoordinates: [CLLocationCoordinate2D] = []
    @State private var hazardLoadTask: Task<Void, Never>?
    @State private var savedSummary: Ride?
    @State private var bannerHeight: CGFloat = 0
    @AppStorage("ride.cameraMode") private var cameraMode: RideCameraMode = .cockpit
    @AppStorage("rider.selectedBike") private var selectedBike = BikeCatalog.defaultBike
    @AppStorage("voice.commands") private var voiceCommands = false
    @AppStorage("helmet.binaural") private var binaural = true
    @AppStorage("remote.enabled") private var remoteEnabled = true

    private var cameraIsCockpit: Bool { cameraMode != .northUp }

    var body: some View {
        ZStack(alignment: .bottom) {
            map

            RevertMapScrim(topOpacity: 0.22, bottomOpacity: 0.30)

            panel
        }
        .overlay(alignment: .top) {
            bannerStack
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: BannerHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .overlay(alignment: .topLeading) { mapControls }
        .onPreferenceChange(BannerHeightKey.self) { height in
            bannerHeight = height
        }
        .animation(.spring(duration: 0.3), value: nav.route?.id)
        .animation(.spring(duration: 0.3), value: alerts.activeAlert?.hazard.id)
        .animation(.spring(duration: 0.3), value: alerts.curveAlert?.since)
        .animation(.spring(duration: 0.3), value: alerts.surfaceAlert?.since)
        .onChange(of: nav.route?.id) { _, routeID in
            if let route = nav.route {
                applyCameraMode()
                loadRouteHazards(route)
                LiveRideActivity.shared.start()
                updateLiveActivity()
            } else {
                alerts.clearRouteHazards()
                LiveRideActivity.shared.end()
            }
        }
        .task(id: liveActivityKey) { updateLiveActivity() }
        .onChange(of: cameraMode) { _, _ in applyCameraMode() }
        .onChange(of: nav.cameraPose) { _, pose in
            guard cameraIsCockpit, let pose else { return }
            camera = cameraMode.camera(for: pose)
        }
        .onAppear {
            // NavigationManager already listens for its own GPS updates; feeding
            // them again here would process every fix twice.
            recorder.onLocation = { alerts.handle($0) }
            // Only traffic devices that lie on the active route are eligible
            // for alerts; free-riding or being off-route suppresses them.
            alerts.routeProvider = {
                guard let route = nav.route, nav.isOnRoute else { return nil }
                return RideRouteContext(route: route, progress: nav.routeProgress)
            }
            recorder.requestPermission()
            lean.start()
            applyCameraMode()
            configureVoice()
            configureRemote()
            if let route = nav.route {
                loadRouteHazards(route)
                LiveRideActivity.shared.start()
                updateLiveActivity()
            }
            if binaural { HelmetAudio.shared.start() }
            if recorder.isRecording {
                gForce.start()
                if voiceCommands, !voice.isListening { voice.start() }
            }
            #if DEBUG
            if CommandLine.arguments.contains("-debugHud") {
                let route = DebugScreens.samplePlannedRoute()
                nav.start(route, roads: [])
                if let first = route.points.first {
                    nav.handle(CLLocation(latitude: first.lat, longitude: first.lon))
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
            if CommandLine.arguments.contains("-debugRecord") {
                recorder.isRecording = true
                recorder.currentLean = 27
                recorder.maxLeanAngle = 41
                lean.angle = 27
                lean.maxAngle = 41
                lean.isCalibrated = true
                trackCoordinates = DebugScreens.recordedPreviewCoordinates
            }
            #endif
        }
        .onDisappear {
            lean.stop()
            gForce.stop()
            voice.stop()
            remote.stop()
            hazardLoadTask?.cancel()
            hazardLoadTask = nil
            LiveRideActivity.shared.end()
            HelmetAudio.shared.stop()
            IdleTimer.release("ride")
            // Leaving the screen stops the clock but must not delete the
            // journal: a ride that was still running when the cockpit went away
            // is offered by the recovery prompt instead of vanishing.
            recorder.suspend()
        }
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
                gForce.start()
                if voiceCommands, !voice.isListening { voice.start() }
            } else {
                IdleTimer.release("ride")
                gForce.stop()
                if voice.isListening { voice.stop() }
                if recorder.points.count > 1 {
                    trackCoordinates = recorder.points.map(\.coordinate)
                }
            }
        }
        .onChange(of: voiceCommands) { _, enabled in
            // Settings is a sheet over this screen, so the change can land
            // mid-ride. Start/stop listening immediately instead of waiting
            // for the next recording to begin.
            if enabled, recorder.isRecording, !voice.isListening {
                voice.start()
            } else if !enabled, voice.isListening {
                voice.stop()
            }
        }
        .onChange(of: binaural) { _, enabled in
            if enabled { HelmetAudio.shared.start() } else { HelmetAudio.shared.stop() }
        }
        .onChange(of: remoteEnabled) { _, enabled in
            if enabled { remote.start() } else { remote.stop() }
        }
        .onChange(of: lean.angle) { _, angle in
            recorder.currentLean = angle ?? 0
        }
        .interactiveDismissDisabled(recorder.isRecording)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
        .alert("Ride not saved", isPresented: Binding(
            get: { rideError != nil },
            set: { if !$0 { rideError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rideError ?? "The ride could not be saved.")
        }
        // The cockpit has no scroll surface, so cap very large type before
        // the speedometer and lean gauge run into the map controls.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            if let planned = nav.route {
                MapPolyline(coordinates: planned.coordinates)
                    .stroke(MapUI.cyan.opacity(0.30), lineWidth: 12)
                MapPolyline(coordinates: planned.coordinates)
                    .stroke(
                        LinearGradient(colors: [MapUI.cyan, MapUI.emerald],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }
            if trackCoordinates.count > 1 {
                MapPolyline(coordinates: trackCoordinates)
                    .stroke(MapUI.emerald.opacity(0.85), lineWidth: 5)
            }
            if let coordinate = nav.userCoordinate {
                Annotation("Your location", coordinate: coordinate, anchor: .center) {
                    NavigationArrow(heading: nav.userHeading)
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: nav.cameraPose)
    }

    private var mapControls: some View {
        RevertMapDock {
            Menu {
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
                Button {
                    mapStyle = .imagery(elevation: .flat)
                    mapStyleName = "satellite"
                } label: {
                    mapStyleLabel("Satellite", id: "satellite")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MapUI.ink)
                    .frame(width: RevertMetrics.dockButtonSize, height: RevertMetrics.dockButtonSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ride menu")

            RevertMapDockDivider()

            RevertMapDockButton(
                systemImage: cameraMode.icon,
                label: "Camera: \(cameraMode.title). Switch view",
                tint: MapUI.cyan,
                active: true
            ) {
                cameraMode = nextMode
            }

            RevertMapDockButton(
                systemImage: "location.north.fill",
                label: "Center on my location"
            ) {
                cameraMode = .northUp
                applyCameraMode()
            }

            RevertMapDockDivider()

            RevertMapDockButton(
                systemImage: voice.isListening ? "waveform" : "mic.slash",
                label: voice.isListening ? "Stop voice commands" : "Start on-device voice commands",
                tint: voice.isListening ? MapUI.emerald : MapUI.ink,
                active: voice.isListening
            ) {
                if voice.isListening {
                    voice.stop()
                } else {
                    voice.start()
                }
            }
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
            return
        }
        if let pose = nav.cameraPose {
            camera = cameraMode.camera(for: pose)
        } else {
            camera = .userLocation(followsHeading: true, fallback: .automatic)
        }
    }

    // MARK: Banners

    private var bannerStack: some View {
        VStack(spacing: 8) {
            if recorder.authStatus == .denied || recorder.authStatus == .restricted {
                LocationPermissionBanner()
            }
            if voice.isListening {
                VoiceListeningBanner(transcript: voice.transcript)
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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let c = alerts.curveAlert {
                CurveBanner(alert: c)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let a = alerts.activeAlert {
                AlertBanner(alert: a)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let sf = alerts.surfaceAlert {
                SurfaceBanner(alert: sf)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 12) {
            if let route = nav.route {
                NavigationSummaryCard(
                    instruction: nav.arrived ? "You have arrived" : (nav.step?.instruction ?? "Follow the route"),
                    stepDistance: nav.stepDistance,
                    remaining: nav.remaining,
                    distanceToStart: nav.distanceToStart,
                    joined: nav.joined,
                    routeLength: route.length,
                    eta: nav.estimatedTimeRemaining,
                    lean: lean,
                    isRerouting: nav.rerouting,
                    onEndRoute: nav.stop
                )
            }

            SpeedometerCard(recorder: recorder, alerts: alerts)

            if recorder.isRecording {
                HStack(alignment: .center, spacing: 12) {
                    VectorArcLeanGauge(angle: lean.angle,
                                       maxAngle: max(lean.maxAngle, recorder.maxLeanAngle),
                                       isCalibrated: lean.isCalibrated)
                        .frame(maxWidth: .infinity)
                    GForceRadarView(model: gForce)
                }
                RideStatsView(recorder: recorder)
            }

            controls
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(.ultraThinMaterial)
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
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            calibrateButton

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
                .frame(width: 106)

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
                .frame(width: 100)
            } else {
                Button {
                    RevertHaptics.success()
                    recorder.start()
                } label: {
                    Label("Start ride", systemImage: "play.fill")
                }
                .buttonStyle(RevertPrimaryButtonStyle(minHeight: 50, compact: true))
                .frame(width: 150)

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RevertIconButtonStyle(tint: MapUI.textSecondary, diameter: 50))
                .accessibilityLabel("Close ride screen")
            }
        }
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
        // A 500+ mile route has a continental bounding box; querying all of it
        // would be slow and pointless. The tile cache plus route-corridor
        // filter still handles devices near the rider.
        if route.length > 300_000 {
            hazardLoadTask?.cancel()
            hazardLoadTask = nil
            return
        }
        hazardLoadTask?.cancel()
        hazardLoadTask = Task { @MainActor in
            let hazards = await RouteHazardLoader.load(route: route)
            guard !Task.isCancelled, nav.route?.id == route.id else { return }
            alerts.setRouteHazards(hazards, for: route.id)
        }
    }

    private var liveActivityKey: String {
        let step = nav.step?.id ?? -1
        let distanceBucket = Int(nav.stepDistance / 25)
        let speedBucket = Int(nav.currentSpeedMps)
        return "\(nav.route?.id.uuidString ?? "none")-\(step)-\(distanceBucket)-\(speedBucket)-\(nav.offRoute)-\(nav.rerouting)-\(nav.arrived)"
    }

    private func updateLiveActivity() {
        guard let route = nav.route else { return }
        let title: String
        if nav.arrived {
            title = "Route complete"
        } else if nav.rerouting {
            title = "Recalculating route"
        } else if nav.offRoute {
            title = "Off route — finding a way back"
        } else {
            title = nav.step?.instruction ?? "Follow the route"
        }
        let distance = nav.arrived ? "Done" : Units.shortDistanceText(nav.stepDistance)
        LiveRideActivity.shared.update(
            title: title,
            distance: distance,
            speed: Units.speedText(nav.currentSpeedMps),
            offRoute: nav.offRoute || nav.rerouting
        )
        _ = route
    }

    // MARK: Hands-free

    private func configureVoice() {
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
            }
        }
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
            }
        }
        remote.start()
    }

    // MARK: Ride lifecycle

    private func finishRide(save: Bool) {
        guard save else {
            recorder.discard()
            nav.stop()
            exitCockpit()
            return
        }

        guard let ride = recorder.stop() else {
            rideError = "There was not enough GPS data to create a ride. It was discarded."
            return
        }
        let garageBike = garageBikes.first(where: \.isPrimary) ?? garageBikes.first
        ride.bikeName = garageBike?.displayName ?? selectedBike
        ride.bikeID = garageBike?.id
        ride.routeName = nav.route?.displayName
        ride.maxLeanAngleDegrees = max(ride.maxLeanAngleDegrees, recorder.maxLeanAngle)
        context.insert(ride)
        do {
            try context.save()
            RideJournal.shared.finish()
            if let garageBike {
                garageBike.odometerKm += ride.distanceMeters / 1_000
                try? context.save()
                WidgetBridge.updateBike(name: garageBike.displayName, odometerKm: garageBike.odometerKm)
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
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(speed)")
                                .font(RevertType.number(recorder.isRecording ? 58 : 48))
                                .foregroundStyle(MapUI.ink)
                                .contentTransition(.numericText())
                                .shadow(color: MapUI.cyan.opacity(recorder.isRecording ? 0.38 : 0.16), radius: 13)
                            Text(Units.speedUnitUppercase)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
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
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 17, weight: .semibold))
                            Text("NO DATA")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                        }
                        .foregroundStyle(MapUI.textTertiary)
                        .frame(width: 62, height: 62)
                        .background(MapUI.surfaceHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MapUI.line, lineWidth: 0.8)
                        }
                    }
                }

                RevertProgressBar(
                    value: progress,
                    tint: alerts.isOverLimit ? MapUI.ember : MapUI.aurora,
                    height: 4
                )
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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                RevertStatTile(label: "Distance", value: Units.distanceText(recorder.distanceMeters))
                statDivider
                RevertStatTile(label: "Time", value: Units.clock(recorder.elapsed(at: context.date)))
                statDivider
                RevertStatTile(label: "Climb", value: Units.elevationText(recorder.elevationGain))
                statDivider
                RevertStatTile(label: "Peak", value: "\(Int(Units.speedValue(recorder.maxSpeedMps).rounded())) \(Units.speedUnit)")
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(MapUI.line)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 6)
    }
}

struct NavigationSummaryCard: View {
    let instruction: String
    let stepDistance: Double
    let remaining: Double
    let distanceToStart: Double
    let joined: Bool
    let routeLength: Double
    let eta: TimeInterval?
    let lean: LeanAngleManager
    let isRerouting: Bool
    let onEndRoute: () -> Void

    @State private var showingEndConfirmation = false

    /// Before joining the route, the only meaningful number is how far away
    /// the start is; showing "50 ft left" while the banner says "0.3 mi to the
    /// route" made the two navigation surfaces contradict each other.
    private var displayedDistance: Double {
        joined ? remaining : distanceToStart
    }

    private var distanceCaption: String {
        joined ? "left" : "to route"
    }

    private var showsETA: Bool {
        joined && eta != nil
    }

    private var progress: Double {
        guard joined, routeLength > 0 else { return 0 }
        return max(min((routeLength - remaining) / routeLength, 1), 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: isRerouting ? "arrow.triangle.2.circlepath" : "flag.checkered")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isRerouting ? MapUI.amber : MapUI.cyan)
                    .frame(width: 28, height: 28)
                    .background((isRerouting ? MapUI.amber : MapUI.cyan).opacity(0.12), in: Circle())

                if isRerouting {
                    Text("Recalculating route…")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(navDistance(displayedDistance))
                            .font(RevertType.number(16))
                            .foregroundStyle(MapUI.ink)
                        Text(distanceCaption)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                if showsETA {
                    Label(etaText, systemImage: "clock")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                }

                Label("\(Int(lean.maxAngle.rounded()))°", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)

                Button {
                    RevertHaptics.tap()
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MapUI.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MapUI.surfaceHigh, in: Circle())
                        .overlay(Circle().stroke(MapUI.line, lineWidth: 0.8))
                }
                .buttonStyle(RevertCardButtonStyle())
                .accessibilityLabel("End navigation")
            }

            RevertProgressBar(value: progress, tint: MapUI.aurora, height: 4)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(MapUI.surfaceHigh.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MapUI.line, lineWidth: 0.8)
        }
        .alert("End navigation?", isPresented: $showingEndConfirmation) {
            Button("End route", role: .destructive) { onEndRoute() }
            Button("Keep navigating", role: .cancel) {}
        }
        // Keep the End navigation button reachable for VoiceOver; `.combine`
        // swallowed it into a single static element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(instruction). "
            + (joined
               ? "\(navDistance(remaining)) remaining. \(eta != nil ? "ETA \(etaText)" : "ETA unavailable")"
               : "\(navDistance(distanceToStart)) to the route start.")
        )
    }

    private var etaText: String {
        guard let eta else { return "ETA unavailable" }
        return Duration.seconds(max(eta, 0))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
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

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MapUI.emerald)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text(transcript.isEmpty ? "Listening for a command…" : transcript)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(MapUI.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("VOICE")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MapUI.coral)
            Text(message)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(MapUI.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if showsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Settings") { UIApplication.shared.open(url) }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MapUI.cyan)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
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
