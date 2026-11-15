import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import UIKit

/// The Midnight Pulse route planner that replaces the old map sheet. It keeps
/// the full destination flow (search, saved places, recents, waypoints, route
/// options, fuel, elevation and turn previews) inside the new visual language,
/// with a full-screen map available when the rider wants more room.
struct PulseRoutesView: View {
    @Environment(NavigationManager.self) private var nav
    @Environment(\.modelContext) private var context
    let planner: RoutePlanner

    var onOpenCockpit: () -> Void
    var onOpenScenicPlanner: () -> Void
    var onOpenSavedPlaces: () -> Void

    @AppStorage("saved.home.lat") private var homeLat = 0.0
    @AppStorage("saved.home.lon") private var homeLon = 0.0
    @AppStorage("saved.work.lat") private var workLat = 0.0
    @AppStorage("saved.work.lon") private var workLon = 0.0
    @AppStorage("recent.destinations") private var recentDestinationsData = ""
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedLoops: [SavedRoute]
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]

    @State private var preference: DirectionPreference = .fastest
    @SceneStorage("routes.destination") private var destinationText = ""
    @SceneStorage("routes.committedDestination") private var committedDestination = ""
    @SceneStorage("routes.focusOnAppear") private var focusOnAppear = false
    @State private var pin: CLLocationCoordinate2D?
    @State private var waypoints: [CLLocationCoordinate2D] = []
    @State private var addingWaypoint = false
    @State private var selected: UUID?
    @State private var addressSearch = AddressSearchService()
    @State private var resolvingDestination = false
    @State private var addressError: String?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapStyle: MapStyle = .standard(
        elevation: .flat,
        emphasis: .muted,
        pointsOfInterest: .excludingAll
    )
    @State private var savePrompt: SavedPlace?
    @State private var showingFullMap = false
    @State private var leaderboardTarget: LeaderboardTarget?
    @State private var pendingVehicleRoute: PendingVehicleRoute?
    @State private var showingVehicleChoice = false
    @State private var renamingRoute: SavedRoute?
    @State private var showingSprint = false
    @State private var sprintStarted = false
    @State private var board = RivalBoard.shared
    @FocusState private var searchFocused: Bool

    // MARK: Derived state

    private var origin: CLLocationCoordinate2D? { nav.lastLocation?.coordinate }
    private var results: [PlannedRoute] { planner.results }
    private var selectedRoute: PlannedRoute? {
        results.first(where: { $0.id == selected }) ?? results.first
    }
    private var hasResults: Bool { !results.isEmpty }
    private var suggestions: [AddressSearchService.Suggestion] { addressSearch.suggestions }
    private var showingSuggestions: Bool { !suggestions.isEmpty && !destinationText.isEmpty }
    private var canPreview: Bool {
        guard origin != nil else { return false }
        return pin != nil || destinationText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }
    private var phaseError: String? {
        if case .failed(let message) = planner.phase { return message }
        return nil
    }
    private var searchRegion: MKCoordinateRegion? {
        guard let origin else { return nil }
        return MKCoordinateRegion(center: origin, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }
    private var recentDestinations: [RecentDestination] {
        guard let data = recentDestinationsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RecentDestination].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                header

                if nav.route != nil {
                    activeRouteCard
                }

                if nav.locationDenied {
                    LocationOffBanner()
                } else if nav.locationUndetermined {
                    LocationOffBanner(
                        denied: false,
                        onEnable: { LocationHub.shared.requestWhenInUse() }
                    )
                }

                searchCard

                if showingSuggestions {
                    AddressSuggestionList(suggestions: suggestions, onSelect: chooseAddress)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let error = addressError ?? phaseError {
                    PulseRouteNote(text: error, systemImage: "exclamationmark.triangle.fill", tint: Pulse.warning)
                }

                if pin != nil || hasResults || !waypoints.isEmpty {
                    mapCard
                }

                if !rivalGroups.isEmpty {
                    rivalTimesSection
                        .id("rivalTimes")
                }

                if !savedLoops.isEmpty {
                    savedLoopsSection
                        .id("savedLoops")
                }

                if hasResults, let route = selectedRoute {
                    resultsSection(route)
                        .id("routeResults")
                } else {
                    if !waypoints.isEmpty {
                        PulseRouteNote(
                            text: "Add a destination to preview a route through your stops.",
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                    savedPlacesSection
                    recentsSection
                }

                scenicCard
                sprintCard
                footnote
            }
                .padding(.horizontal, PulseMetrics.screenPadding)
                .padding(.top, 14)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hasResults {
                    routesFooter
                }
            }
        .scrollDismissesKeyboard(.interactively)
        .pulseBackground()
        .animation(RevertMotion.smooth, value: suggestions.map(\.id))
        .animation(RevertMotion.smooth, value: hasResults)
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-debugScrollRivals") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(RevertMotion.smooth) {
                        scrollProxy.scrollTo("rivalTimes", anchor: .top)
                    }
                }
            }
            #endif
            guard let route = planner.results.first else { return }
            if selected == nil { selected = route.id }
            if pin == nil { pin = route.destination }
            if destinationText.isEmpty {
                destinationText = committedDestination.isEmpty
                    ? (route.displayName ?? "Destination")
                    : committedDestination
            }
            camera = .region(Self.region(for: planner.results, fallback: route))
        }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-debugSprint") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showingSprint = true
                }
            }
            if CommandLine.arguments.contains("-debugLeaderboard") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    guard let saved = savedLoops.first(where: { !ridesFor($0).isEmpty }) ?? savedLoops.first else { return }
                    leaderboardTarget = LeaderboardTarget(
                        title: saved.name,
                        key: saved.fingerprintKey,
                        savedRouteID: saved.id,
                        routeName: saved.name,
                        laps: saved.laps,
                        isSprint: saved.isSprint
                    )
                }
            }
            if CommandLine.arguments.contains("-debugPulseRoute") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard let origin = nav.lastLocation?.coordinate else { return }
                    let destination = CLLocationCoordinate2D(latitude: 40.7829, longitude: -73.9654)
                    pin = destination
                    destinationText = "Central Park"
                    committedDestination = "Central Park"
                    planner.directions(from: origin, to: destination, via: [], preference: preference)
                    if CommandLine.arguments.contains("-debugPulseFullMap") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            showingFullMap = true
                        }
                    }
                }
            }
            #endif
            if focusOnAppear {
                focusOnAppear = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    searchFocused = true
                }
            }
        }
        .onChange(of: focusOnAppear) { _, requested in
            guard requested else { return }
            focusOnAppear = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                searchFocused = true
            }
        }
        .onChange(of: planner.results.first?.id) { _, _ in
            guard let route = planner.results.first else { return }
            selected = route.id
            camera = .region(Self.region(for: planner.results, fallback: route))
            // Bring the route cards and Start button into view without hiding
            // the search the rider just used.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(RevertMotion.smooth) {
                    scrollProxy.scrollTo("routeResults", anchor: .top)
                }
            }
        }
        .onChange(of: preference) { _, _ in
            guard let origin, let pin else { return }
            planner.directions(from: origin, to: pin, via: waypoints, preference: preference)
        }
        .onChange(of: addingWaypoint) { _, active in
            if active { searchFocused = false }
        }
        .fullScreenCover(isPresented: $showingFullMap) {
            PulsePlannerMapSheet(
                camera: $camera,
                mapStyle: mapStyle,
                pin: pin,
                waypoints: waypoints,
                routes: results,
                activeRoute: nav.route,
                selected: selected,
                addingWaypoint: $addingWaypoint,
                onTap: addWaypoint
            )
        }
        .sheet(isPresented: $showingSprint, onDismiss: {
            if sprintStarted {
                sprintStarted = false
                onOpenCockpit()
            }
        }) {
            SprintPlannerView(onStart: { sprintStarted = true })
        }
        .sheet(item: $leaderboardTarget) { target in
            RouteLeaderboardView(
                title: target.title,
                routeKey: target.key,
                savedRouteID: target.savedRouteID,
                routeName: target.routeName,
                laps: target.laps,
                isSprint: target.isSprint
            )
        }
        .confirmationDialog("Car or bike today?",
                            isPresented: $showingVehicleChoice,
                            titleVisibility: .visible,
                            presenting: pendingVehicleRoute) { pending in
            Button("Bike") { beginVehicleRoute(pending, kind: .motorcycle) }
            Button("Car") { beginVehicleRoute(pending, kind: .car) }
            Button("Cancel") { pendingVehicleRoute = nil }
        } message: { _ in
            Text("This choice changes the cockpit and the vehicle noted on the leaderboard. Garage default: \(VehiclePreferences.primaryKind.title).")
        }
        .sheet(item: $renamingRoute) { saved in
            SavedRouteRenameSheet(saved: saved)
        }
        .alert("Save this place?", isPresented: Binding(
            get: { savePrompt != nil },
            set: { if !$0 { savePrompt = nil } }
        )) {
            Button("Save here") {
                guard let place = savePrompt,
                      let coordinate = nav.currentLocation?.coordinate else { return }
                switch place {
                case .home:
                    homeLat = coordinate.latitude
                    homeLon = coordinate.longitude
                case .work:
                    workLat = coordinate.latitude
                    workLon = coordinate.longitude
                }
                savePrompt = nil
                RevertHaptics.success()
            }
            .disabled(nav.currentLocation == nil)
            if nav.locationDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) { savePrompt = nil }
        } message: {
            if nav.locationDenied {
                Text("Location access is off. Allow it in Settings, then save Home or Work from here.")
            } else if nav.currentLocation == nil {
                Text("Waiting for a GPS fix. Try again in a moment.")
            } else {
                Text("We'll use your current location as \(savePrompt?.title ?? "this place").")
            }
        }
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(eyebrow: "PLAN YOUR WAY",
                     title: "Route planner",
                     variant: .compact,
                     identifier: AccessibilityID.Routes.title) {
            HStack(spacing: 8) {
                PulseCircleButton(systemImage: "map",
                                  label: "Open full map",
                                  identifier: AccessibilityID.Routes.openMap) {
                    showingFullMap = true
                }
                PulseCircleButton(systemImage: "star",
                                  label: "Manage saved places",
                                  identifier: AccessibilityID.Routes.savedPlaces) {
                    onOpenSavedPlaces()
                }
            }
        }
    }

    // MARK: Active navigation

    private var activeRouteCard: some View {
        let route = nav.route
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("RIDE IN PROGRESS")
                    .font(PulseType.eyebrow)
                    .tracking(2)
                    .foregroundStyle(Pulse.accent)
                Spacer()
                PulseTag(text: nav.arrived ? "Arrived" : "Live", systemImage: "location.fill")
            }

            Text(nav.arrived ? "You have arrived" : (nav.step?.instruction ?? "Follow the route"))
                .font(PulseType.display(22))
                .tracking(-0.4)
                .foregroundStyle(Pulse.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(Units.distanceText(nav.remaining), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                if let eta = nav.estimatedTimeRemaining {
                    Label(
                        Duration.seconds(max(eta, 0))
                            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)),
                        systemImage: "clock"
                    )
                }
                Spacer(minLength: 0)
            }
            .font(.scaledSystem(size: 11, weight: .semibold))
            .foregroundStyle(Pulse.mutedStrong)

            HStack(spacing: 9) {
                Button {
                    RevertHaptics.tap()
                    onOpenCockpit()
                } label: {
                    Label("Open cockpit", systemImage: "speedometer")
                }
                .buttonStyle(PulsePrimaryButtonStyle(minHeight: 46, compact: true))

                Button {
                    RevertHaptics.warning()
                    nav.stop()
                } label: {
                    Label("End", systemImage: "stop.fill")
                }
                .buttonStyle(PulseGhostButtonStyle(minHeight: 46, compact: true))
                .frame(width: 96)
            }

            if let route {
                Text(route.displayName ?? "Active route")
                    .font(.scaledSystem(size: 10))
                    .foregroundStyle(Pulse.muted)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.heroGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.accentDeep.opacity(0.45), lineWidth: 0.8)
                }
        }
    }

    // MARK: Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Circle()
                        .fill(Pulse.emerald)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FROM")
                            .font(.scaledSystem(size: 9, weight: .heavy))
                            .tracking(1.3)
                            .foregroundStyle(Pulse.muted)
                        Text("Your location")
                            .font(.scaledSystem(size: 13, weight: .semibold))
                            .foregroundStyle(Pulse.ink)
                    }
                    Spacer(minLength: 6)
                    if nav.hasLocation {
                        PulseTag(text: "GPS ready", systemImage: "location.fill")
                    } else {
                        PulseTag(text: "Waiting for GPS", systemImage: "location.slash", tint: Pulse.warning)
                    }
                }
                .padding(.vertical, 11)

                Rectangle()
                    .fill(Pulse.lineSoft)
                    .frame(height: 0.8)
                    .padding(.leading, 20)

                HStack(spacing: 11) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.scaledSystem(size: 15, weight: .bold))
                        .foregroundStyle(Pulse.coral)
                        .frame(width: 22)

                    TextField("Where to?", text: $destinationText)
                        .font(.scaledSystem(size: 15, weight: .semibold))
                        .foregroundStyle(Pulse.ink)
                        .accessibilityIdentifier(AccessibilityID.Routes.destination)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onChange(of: destinationText) { _, value in
                            handleSearchChanged(value)
                        }
                        .onSubmit(previewRoute)

                    if !destinationText.isEmpty {
                        Button {
                            RevertHaptics.tap()
                            clearDestination()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.scaledSystem(size: 16))
                                .foregroundStyle(Pulse.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear destination")
                    }
                }
                .padding(.vertical, 13)
            }
            .padding(.horizontal, 14)
            .background(Pulse.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("RIDE STYLE")
                    .font(.scaledSystem(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Pulse.muted)
                PulseSegmented(options: DirectionPreference.allCases, selection: $preference) { option in
                    switch option {
                    case .fastest: "Quickest"
                    case .fun: "Scenic"
                    case .sporty: "Twisty"
                    }
                }
                Text(preference.blurb)
                    .font(.scaledSystem(size: 10))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.cardGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
                }
        }
    }

    // MARK: Footer

    private var routesFooter: some View {
        Group {
            if planner.isBusy || resolvingDestination {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(Pulse.accent)
                    Text(resolvingDestination ? "Finding that destination…" : "Building your route…")
                        .font(.scaledSystem(size: 12, weight: .semibold))
                        .foregroundStyle(Pulse.mutedStrong)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(Pulse.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Pulse.line, lineWidth: 0.8)
                }
            } else if canPreview {
                Button {
                    RevertHaptics.tap()
                    previewRoute()
                } label: {
                    Label(footerTitle, systemImage: footerSymbol)
                }
                .buttonStyle(PulsePrimaryButtonStyle())
                .accessibilityIdentifier(AccessibilityID.Routes.findRoute)
            } else {
                Button {} label: {
                    Label(footerTitle, systemImage: footerSymbol)
                }
                .buttonStyle(PulseGhostButtonStyle())
                .disabled(true)
                .accessibilityIdentifier(AccessibilityID.Routes.findRoute)
            }
        }
        .padding(.horizontal, PulseMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(Pulse.canvas)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Pulse.line)
                        .frame(height: 0.8)
                }
                .ignoresSafeArea()
        }
    }

    private var footerTitle: String {
        if canPreview { return "Find route" }
        return origin == nil ? "Waiting for GPS" : "Enter a destination"
    }

    private var footerSymbol: String {
        if canPreview { return "arrow.triangle.turn.up.right.diamond.fill" }
        return origin == nil ? "location.slash" : "mappin.and.ellipse"
    }

    // MARK: Map

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(waypoints.isEmpty ? "Direct route" : "\(waypoints.count) stop\(waypoints.count == 1 ? "" : "s")")
                    .font(.scaledSystem(size: 11, weight: .bold))
                    .foregroundStyle(Pulse.mutedStrong)

                Spacer(minLength: 0)

                Button {
                    RevertHaptics.tap()
                    addingWaypoint.toggle()
                } label: {
                    Label(addingWaypoint ? "Done" : "Add stop",
                          systemImage: addingWaypoint ? "checkmark" : "plus")
                        .font(.scaledSystem(size: 10, weight: .bold))
                        .foregroundStyle(addingWaypoint ? Pulse.accentInk : Pulse.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(addingWaypoint ? Pulse.accent : Pulse.iconWell, in: Capsule())
                        .overlay(Capsule().stroke(addingWaypoint ? .clear : Pulse.lineBright, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            if !waypoints.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(waypoints.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 5) {
                                Text("Stop \(index + 1)")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                Button {
                                    RevertHaptics.tap()
                                    waypoints.remove(at: index)
                                    if pin != nil { previewRoute() }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.scaledSystem(size: 8, weight: .heavy))
                                        .foregroundStyle(Pulse.muted)
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(Pulse.ink)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Pulse.iconWell, in: Capsule())
                            .overlay(Capsule().stroke(Pulse.line, lineWidth: 0.8))
                        }
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                PulsePlannerMap(
                    camera: $camera,
                    mapStyle: mapStyle,
                    pin: pin,
                    waypoints: waypoints,
                    routes: results,
                    activeRoute: nav.route,
                    selected: selected,
                    addingWaypoint: addingWaypoint,
                    onTap: addWaypoint
                )
                .frame(height: 232)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                LinearGradient(
                    colors: [Pulse.canvas.opacity(0.35), .clear, Pulse.canvas.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)

                HStack(alignment: .top) {
                    PulseTag(
                        text: nav.route != nil ? "Live route" : (hasResults ? "Route preview" : "Map"),
                        systemImage: nav.route != nil ? "location.fill" : "map"
                    )
                    .padding(10)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Menu {
                            Button("Standard") {
                                mapStyle = .standard(elevation: .flat)
                            }
                            Button("Satellite") { mapStyle = .imagery(elevation: .flat) }
                            Button("OLED muted") {
                                mapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
                            }
                        } label: {
                            mapControlLabel(systemImage: "map.fill")
                        }
                        .accessibilityLabel("Map style")

                        Button {
                            RevertHaptics.tap()
                            showingFullMap = true
                        } label: {
                            mapControlLabel(systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open full map")
                    }
                    .padding(10)
                }

                if addingWaypoint {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                        Text("Tap the map to add a stop")
                    }
                    .font(.scaledSystem(size: 10, weight: .bold))
                    .foregroundStyle(Pulse.accentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Pulse.accent, in: Capsule())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
            }
        }
    }

    private func mapControlLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.scaledSystem(size: 12, weight: .semibold))
            .foregroundStyle(Pulse.accent)
            .frame(width: 32, height: 32)
            .background(Pulse.bar.opacity(0.85), in: Circle())
            .overlay(Circle().stroke(Pulse.lineBright, lineWidth: 0.8))
    }

    // MARK: Results

    private func resultsSection(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROUTE READY")
                        .font(PulseType.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(Pulse.accent)
                    Text(destinationText.isEmpty ? "Your destination" : destinationText)
                        .font(.scaledSystem(size: 18, weight: .bold))
                        .foregroundStyle(Pulse.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Button {
                    RevertHaptics.tap()
                    clearDestination()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PulseGhostIconStyle())
                .accessibilityLabel("Close route preview")
            }

            ForEach(Array(results.enumerated()), id: \.element.id) { index, option in
                PulseRouteOption(
                    route: option,
                    index: index,
                    isBest: index == 0,
                    isSelected: option.id == selected
                ) {
                    RevertHaptics.select()
                    selected = option.id
                    camera = .region(Self.region(for: [option], fallback: option))
                }
            }

            selectedRouteCard(route)
            routeDetails(route)
        }
        .padding(.top, 2)
    }

    private func selectedRouteCard(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Units.distanceText(route.length, decimals: 1))
                    .font(PulseType.number(34, weight: .heavy))
                    .tracking(-1)
                    .foregroundStyle(Pulse.ink)
                if let time = route.expectedTravelTime {
                    Text(Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .font(.scaledSystem(size: 12, weight: .semibold))
                        .foregroundStyle(Pulse.mutedStrong)
                }
                Spacer(minLength: 0)
                PulseTag(text: "Heads \(route.heading)")
            }

            HStack(spacing: 0) {
                routeStat("Curves", value: "\(route.curviness)/5", tint: Pulse.warning)
                routeDivider
                routeStat("Climb", value: Units.elevationText(route.climbMeters), tint: Pulse.accent)
                routeDivider
                routeStat("Surface", value: route.surface.title, tint: Pulse.mutedStrong)
            }

            HStack(spacing: 9) {
                Button {
                    RevertHaptics.success()
                    start(route)
                } label: {
                    Label("Start navigation", systemImage: "location.north.fill")
                }
                .buttonStyle(PulsePrimaryButtonStyle())
                .accessibilityIdentifier(AccessibilityID.Routes.start)
                .disabled(route.isOfflinePreview)
                .opacity(route.isOfflinePreview ? 0.55 : 1)

                SaveRouteButton(route: route, roads: planner.roads, compact: true)
                    .frame(height: 50)
            }
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.heroGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.accentDeep.opacity(0.5), lineWidth: 0.8)
                }
        }
    }

    private func routeStat(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.scaledSystem(size: 8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Pulse.muted)
            Text(value)
                .font(.scaledSystem(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeDivider: some View {
        Rectangle()
            .fill(Pulse.lineSoft)
            .frame(width: 0.8, height: 26)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func routeDetails(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionHeader(title: "Ride details")

            DirectionsFuelCard(route: route, onAddStop: { coordinate in
                waypoints.append(coordinate)
                previewRoute()
            })

            if !route.elevationProfile.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Elevation", systemImage: "mountain.2")
                            .font(.scaledSystem(size: 12, weight: .semibold))
                            .foregroundStyle(Pulse.ink)
                        Spacer()
                        Text(route.descentMeters > 0
                             ? "\(Units.elevationText(route.climbMeters)) up · \(Units.elevationText(route.descentMeters)) down"
                             : "\(Units.elevationText(route.climbMeters)) climb")
                            .font(.scaledSystem(size: 10, weight: .semibold))
                            .foregroundStyle(Pulse.accent)
                    }
                    RideElevationChart(values: route.elevationProfile.map(\.elevation), totalMeters: route.length)
                        .frame(height: 92)
                }
                .pulseCard(padding: 13)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TURN-BY-TURN")
                        .font(.scaledSystem(size: 9, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(Pulse.muted)
                    Spacer()
                    Text("\(route.steps.count) steps")
                        .font(.scaledSystem(size: 9, weight: .semibold))
                        .foregroundStyle(Pulse.muted)
                }
                .padding(.horizontal, 2)

                VStack(spacing: 0) {
                    ForEach(Array(route.steps.prefix(5).enumerated()), id: \.element.id) { index, step in
                        HStack(spacing: 10) {
                            Image(systemName: step.symbol)
                                .font(.scaledSystem(size: 12, weight: .bold))
                                .foregroundStyle(Pulse.accent)
                                .frame(width: 28, height: 28)
                                .background(Pulse.accent.opacity(0.10), in: Circle())
                            Text(step.instruction)
                                .font(.scaledSystem(size: 12))
                                .foregroundStyle(Pulse.ink)
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Text(Units.distanceText(step.distance, decimals: 1))
                                .font(.scaledSystem(size: 9.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Pulse.muted)
                        }
                        .padding(.vertical, 9)
                        .accessibilityElement(children: .combine)

                        if index < min(route.steps.count, 5) - 1 {
                            Rectangle()
                                .fill(Pulse.lineSoft)
                                .frame(height: 0.7)
                                .padding(.leading, 38)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Pulse.line, lineWidth: 0.8)
                }
            }
        }
    }

    // MARK: Saved & recent

    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Saved places", actionTitle: "Manage", action: onOpenSavedPlaces)

            VStack(spacing: 8) {
                ForEach(SavedPlace.allCases) { place in
                    Button {
                        useSavedPlace(place)
                    } label: {
                        PulseListRow(
                            systemImage: place.icon,
                            title: place.title,
                            subtitle: coordinate(for: place) == nil
                                ? "Set it from your current location"
                                : "Saved destination",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(RevertCardButtonStyle())
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(
                title: "Recent destinations",
                actionTitle: recentDestinations.isEmpty ? nil : "Clear",
                action: recentDestinations.isEmpty ? nil : { clearRecentDestinations() }
            )

            if recentDestinations.isEmpty {
                Text("Destinations you preview are kept here for a one-tap return.")
                    .font(.scaledSystem(size: 10))
                    .foregroundStyle(Pulse.muted)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentDestinations.prefix(4)) { recent in
                        Button {
                            useRecentDestination(recent)
                        } label: {
                            PulseListRow(
                                systemImage: "clock.arrow.circlepath",
                                title: recent.title,
                                subtitle: "Recent destination",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(RevertCardButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Saved loops

    private var savedLoopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionHeader(title: "Saved loops", actionTitle: nil, action: nil)

            ForEach(savedLoops.prefix(6)) { saved in
                HStack(spacing: 6) {
                    Button {
                        rideSaved(saved)
                    } label: {
                        HStack(spacing: 10) {
                            RevertIconBadge(
                                systemImage: saved.isLoop
                                    ? "arrow.triangle.2.circlepath"
                                    : (saved.isSprint
                                       ? "flag.checkered"
                                       : "arrow.triangle.turn.up.right.diamond"),
                                tint: Pulse.accent,
                                size: 36,
                                radius: 11
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .font(.scaledSystem(size: 13, weight: .semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                                Text(savedSubtitle(saved))
                                    .font(.scaledSystem(size: 10))
                                    .foregroundStyle(Pulse.muted)
                                    .lineLimit(1)
                                if let best = bestTime(for: saved) {
                                    Text("Best \(Units.clock(best))")
                                        .font(.scaledSystem(size: 9.5, weight: .bold))
                                        .foregroundStyle(Pulse.emerald)
                                }
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "play.fill")
                                .font(.scaledSystem(size: 11, weight: .bold))
                                .foregroundStyle(Pulse.accent)
                                .frame(width: 34, height: 34)
                                .background(Pulse.accent.opacity(0.12), in: Circle())
                        }
                        .padding(10)
                        .background(Pulse.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ride \(saved.name) again")

                    Button {
                        RevertHaptics.tap()
                        leaderboardTarget = LeaderboardTarget(
                            title: saved.name,
                            key: saved.fingerprintKey,
                            savedRouteID: saved.id,
                            routeName: saved.name,
                            laps: saved.laps,
                            isSprint: saved.isSprint
                        )
                    } label: {
                        Image(systemName: "trophy")
                            .font(.scaledSystem(size: 13, weight: .bold))
                            .foregroundStyle(Pulse.warning)
                            .frame(width: 44, height: 54)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rivals for \(saved.name)")
                }
                .contextMenu {
                    Button {
                        rideSaved(saved)
                    } label: {
                        Label("Ride again", systemImage: "play.fill")
                    }
                    Button {
                        leaderboardTarget = LeaderboardTarget(
                            title: saved.name,
                            key: saved.fingerprintKey,
                            savedRouteID: saved.id,
                            routeName: saved.name,
                            laps: saved.laps,
                            isSprint: saved.isSprint
                        )
                    } label: {
                        Label("Rivals", systemImage: "trophy")
                    }
                    Divider()
                    Button {
                        RevertHaptics.tap()
                        renamingRoute = saved
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        context.delete(saved)
                        try? context.save()
                    } label: {
                        Label("Delete loop", systemImage: "trash")
                    }
                }
            }

            Text("Tap a loop to ride it again. The trophy is the local leaderboard, including times friends send as links.")
                .font(.scaledSystem(size: 10))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pulseCard()
    }

    private func savedSubtitle(_ saved: SavedRoute) -> String {
        let count = ridesFor(saved).count
        let rides = count == 1 ? "1 ride" : "\(count) rides"
        let format = saved.isSprint
            ? "Sprint"
            : "\(saved.laps) lap\(saved.laps == 1 ? "" : "s")"
        return "\(Units.distanceText(saved.distanceMeters, decimals: 1))  •  \(format)  •  \(rides)"
    }

    private func ridesFor(_ saved: SavedRoute) -> [Ride] {
        let key = saved.fingerprintKey
        return rides.filter { ride in
            if ride.savedRouteID == saved.id { return true }
            if let rideKey = ride.routeKey, !rideKey.isEmpty, rideKey == key { return true }
            return ride.routeName == saved.name
        }
    }

    private func bestTime(for saved: SavedRoute) -> Double? {
        ridesFor(saved).map(\.durationSeconds).min()
    }

    private func rideSaved(_ saved: SavedRoute) {
        guard let route = saved.plannedRoute() else { return }
        pendingVehicleRoute = PendingVehicleRoute(route: route, roads: saved.roads)
        showingVehicleChoice = true
    }

    private func beginVehicleRoute(_ pending: PendingVehicleRoute, kind: VehicleKind) {
        RevertHaptics.success()
        nav.start(pending.route, roads: pending.roads, vehicleKind: kind)
        pendingVehicleRoute = nil
        onOpenCockpit()
    }

    // MARK: Rival times

    private struct RivalGroup: Identifiable {
        let key: String
        let name: String
        let count: Int
        let best: Double
        let laps: Int
        let isSprint: Bool
        let hasReplay: Bool
        var id: String { key }
    }

    private var rivalGroups: [RivalGroup] {
        Dictionary(grouping: board.results, by: \.routeKey).compactMap { key, results in
            guard let first = results.first else { return nil }
            return RivalGroup(
                key: key,
                name: first.routeName,
                count: results.count,
                best: results.map(\.durationSeconds).min() ?? 0,
                laps: results.compactMap(\.laps).max() ?? 1,
                isSprint: results.contains { $0.isSprint == true },
                hasReplay: results.contains { $0.hasReplay }
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var rivalTimesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionHeader(title: "Rival times")

            ForEach(rivalGroups) { group in
                Button {
                    RevertHaptics.tap()
                    leaderboardTarget = LeaderboardTarget(
                        title: group.name,
                        key: group.key,
                        savedRouteID: nil,
                        routeName: group.name,
                        laps: group.laps,
                        isSprint: group.isSprint
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.scaledSystem(size: 15, weight: .bold))
                            .foregroundStyle(Pulse.warning)
                            .frame(width: 36, height: 36)
                            .background(Pulse.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.scaledSystem(size: 13, weight: .semibold))
                                .foregroundStyle(Pulse.ink)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(group.isSprint
                                     ? "Sprint · \(group.count) imported"
                                     : "\(group.laps) lap\(group.laps == 1 ? "" : "s") · \(group.count) imported")
                                if group.hasReplay {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(Pulse.accent)
                                }
                            }
                            .font(.scaledSystem(size: 10))
                            .foregroundStyle(Pulse.muted)
                        }

                        Spacer(minLength: 4)

                        Text(Units.clock(group.best))
                            .font(.scaledSystem(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Pulse.emerald)

                        Image(systemName: "chevron.right")
                            .font(.scaledSystem(size: 9, weight: .bold))
                            .foregroundStyle(Pulse.muted)
                    }
                    .padding(10)
                    .background(Pulse.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            Text("Times friends sent as links. Open one to see the board, or ride the same loop to add your own.")
                .font(.scaledSystem(size: 10))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pulseCard()
    }

    // MARK: Scenic planner

    private var scenicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAKE THE LONG WAY")
                        .font(PulseType.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(Pulse.accent)
                    Text("Build a scenic loop")
                        .font(PulseType.display(21))
                        .tracking(-0.4)
                        .foregroundStyle(Pulse.ink)
                }
                Spacer(minLength: 6)
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.scaledSystem(size: 19, weight: .semibold))
                    .foregroundStyle(Pulse.accent)
                    .frame(width: 42, height: 42)
                    .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("Pick a start, a distance and a road style. The planner finds the bends and brings back the strongest loops.")
                .font(.scaledSystem(size: 11.5))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                RevertHaptics.tap()
                onOpenScenicPlanner()
            } label: {
                Label("Open loop planner", systemImage: "sparkles")
            }
            .buttonStyle(PulseGhostButtonStyle(minHeight: 46))
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.cardGradient)
                .overlay(alignment: .topTrailing) {
                    RadialGradient(
                        colors: [Pulse.accent.opacity(0.10), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 180
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
                }
        }
    }

    private var sprintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("POINT TO POINT")
                        .font(PulseType.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(Pulse.warning)
                    Text("Run a sprint")
                        .font(PulseType.display(21))
                        .tracking(-0.4)
                        .foregroundStyle(Pulse.ink)
                }
                Spacer(minLength: 6)
                Image(systemName: "flag.checkered")
                    .font(.scaledSystem(size: 18, weight: .semibold))
                    .foregroundStyle(Pulse.warning)
                    .frame(width: 42, height: 42)
                    .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("Pick one road to start on and another to finish. One run, timed from the start line — no laps, no circuit.")
                .font(.scaledSystem(size: 11.5))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                RevertHaptics.tap()
                showingSprint = true
            } label: {
                Label("Build a sprint", systemImage: "flag.checkered")
            }
            .buttonStyle(PulseGhostButtonStyle(minHeight: 46))
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.cardGradient)
                .overlay(alignment: .topTrailing) {
                    RadialGradient(
                        colors: [Pulse.warning.opacity(0.10), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 180
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.lineSoft, lineWidth: 0.8)
                }
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.scaledSystem(size: 9, weight: .bold))
                .padding(.top, 2)
            Text("Route previews use MapKit and the ride style you choose. Starting navigation opens the cockpit; nothing leaves this iPhone.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaledSystem(size: 10))
        .foregroundStyle(Pulse.muted)
        .padding(.top, 2)
    }

    // MARK: Search actions

    private func handleSearchChanged(_ value: String) {
        addressError = nil

        if value == committedDestination {
            addressSearch.clear()
            return
        }

        if !value.isEmpty {
            if pin != nil {
                pin = nil
                planner.clearResults()
                selected = nil
            }
            addressSearch.update(query: value, region: searchRegion)
        } else {
            addressSearch.clear()
            planner.clearResults()
            selected = nil
            pin = nil
        }
    }

    private func previewRoute() {
        guard let origin else { return }
        searchFocused = false

        if let pin {
            planner.directions(from: origin, to: pin, via: waypoints, preference: preference)
            return
        }

        let query = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !resolvingDestination else { return }

        resolvingDestination = true
        Task { @MainActor in
            defer { resolvingDestination = false }
            do {
                let coordinate = try await addressSearch.coordinate(forQuery: query, region: searchRegion)
                pin = coordinate
                committedDestination = destinationText
                addressSearch.clear()
                addressError = nil
                camera = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 4_000,
                    longitudinalMeters: 4_000
                ))
                rememberDestination(query, coordinate: coordinate)
                planner.directions(from: origin, to: coordinate, via: waypoints, preference: preference)
            } catch {
                addressError = "That destination could not be found. Try a more complete address or pick a suggestion."
            }
        }
    }

    private func chooseAddress(_ suggestion: AddressSearchService.Suggestion) {
        searchFocused = false
        Task { @MainActor in
            do {
                let coordinate = try await addressSearch.coordinate(for: suggestion)
                let label = suggestion.title.isEmpty ? suggestion.subtitle : suggestion.title
                committedDestination = label
                destinationText = label
                pin = coordinate
                addressSearch.clear()
                addressError = nil
                camera = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 4_000,
                    longitudinalMeters: 4_000
                ))
                rememberDestination(label, coordinate: coordinate)
                if let origin {
                    planner.directions(from: origin, to: coordinate, via: waypoints, preference: preference)
                }
            } catch {
                addressError = "Couldn't load that place. Try another search, or check your connection."
            }
        }
    }

    private func addWaypoint(_ coordinate: CLLocationCoordinate2D) {
        guard addingWaypoint else { return }
        RevertHaptics.tap()
        waypoints.append(coordinate)
        if pin != nil { previewRoute() }
    }

    private func start(_ route: PlannedRoute) {
        pendingVehicleRoute = PendingVehicleRoute(route: route, roads: planner.roads)
        showingVehicleChoice = true
    }

    private func clearDestination() {
        pin = nil
        waypoints = []
        addingWaypoint = false
        committedDestination = ""
        destinationText = ""
        addressSearch.clear()
        addressError = nil
        planner.clearResults()
        selected = nil
        camera = .userLocation(fallback: .automatic)
    }

    // MARK: Saved places & recents

    private func coordinate(for place: SavedPlace) -> CLLocationCoordinate2D? {
        switch place {
        case .home:
            return (homeLat != 0 || homeLon != 0)
                ? CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)
                : nil
        case .work:
            return (workLat != 0 || workLon != 0)
                ? CLLocationCoordinate2D(latitude: workLat, longitude: workLon)
                : nil
        }
    }

    private func useSavedPlace(_ place: SavedPlace) {
        guard let coordinate = coordinate(for: place) else {
            savePrompt = place
            return
        }
        pin = coordinate
        waypoints = []
        committedDestination = place.title
        destinationText = place.title
        addressSearch.clear()
        addressError = nil
        camera = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 4_000,
            longitudinalMeters: 4_000
        ))
        if let origin {
            planner.directions(from: origin, to: coordinate, via: [], preference: preference)
        }
    }

    private func useRecentDestination(_ recent: RecentDestination) {
        pin = recent.coordinate
        waypoints = []
        committedDestination = recent.title
        destinationText = recent.title
        addressSearch.clear()
        addressError = nil
        camera = .region(MKCoordinateRegion(
            center: recent.coordinate,
            latitudinalMeters: 4_000,
            longitudinalMeters: 4_000
        ))
        if let origin {
            planner.directions(from: origin, to: recent.coordinate, via: [], preference: preference)
        }
        RevertHaptics.tap()
    }

    private func rememberDestination(_ title: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = recentDestinations
        items.removeAll {
            $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
                || CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 100
        }
        items.insert(
            RecentDestination(title: trimmed, latitude: coordinate.latitude, longitude: coordinate.longitude),
            at: 0
        )
        saveRecentDestinations(Array(items.prefix(5)))
    }

    private func clearRecentDestinations() {
        saveRecentDestinations([])
        RevertHaptics.warning()
    }

    private func saveRecentDestinations(_ items: [RecentDestination]) {
        if items.isEmpty {
            recentDestinationsData = ""
            return
        }
        if let data = try? JSONEncoder().encode(items) {
            recentDestinationsData = String(data: data, encoding: .utf8) ?? ""
        }
    }

    // MARK: Geometry

    private static func region(for routes: [PlannedRoute], fallback: PlannedRoute) -> MKCoordinateRegion {
        var minLat = 90.0
        var maxLat = -90.0
        var minLon = 180.0
        var maxLon = -180.0

        for route in routes {
            for point in route.points {
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLon = min(minLon, point.lon)
                maxLon = max(maxLon, point.lon)
            }
        }

        if minLat > maxLat, let point = fallback.points.first {
            minLat = point.lat
            maxLat = point.lat
            minLon = point.lon
            maxLon = point.lon
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.3, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.3, 0.02)
            )
        )
    }
}

// MARK: - Map

struct PulsePlannerMap: View {
    @Binding var camera: MapCameraPosition
    let mapStyle: MapStyle
    let pin: CLLocationCoordinate2D?
    let waypoints: [CLLocationCoordinate2D]
    let routes: [PlannedRoute]
    let activeRoute: PlannedRoute?
    let selected: UUID?
    var addingWaypoint = false
    var onTap: (CLLocationCoordinate2D) -> Void

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                UserAnnotation()
                if let pin {
                    Marker("Destination", coordinate: pin)
                        .tint(Pulse.accent)
                }
                ForEach(Array(waypoints.enumerated()), id: \.offset) { index, coordinate in
                    Marker("Stop \(index + 1)", coordinate: coordinate)
                        .tint(Pulse.emerald)
                }
                ForEach(routes) { route in
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(
                            route.id == selected ? Pulse.accent : Pulse.muted.opacity(0.45),
                            style: StrokeStyle(
                                lineWidth: route.id == selected ? 6 : 3,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
                if let activeRoute, !routes.contains(where: { $0.id == activeRoute.id }) {
                    MapPolyline(coordinates: activeRoute.coordinates)
                        .stroke(Pulse.emerald.opacity(0.85), lineWidth: 5)
                }
            }
            .mapStyle(mapStyle)
            .mapControlVisibility(.hidden)
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        guard addingWaypoint,
                              let coordinate = proxy.convert(event.location, from: .local) else { return }
                        onTap(coordinate)
                    }
            )
        }
        .accessibilityLabel("Route map")
    }
}

// MARK: - Route option

struct PulseRouteOption: View {
    let route: PlannedRoute
    let index: Int
    let isBest: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    private var letter: String {
        let letters = ["A", "B", "C", "D", "E"]
        return letters[min(max(index, 0), letters.count - 1)]
    }

    private var timeText: String? {
        guard let time = route.expectedTravelTime else { return nil }
        return Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.scaledSystem(size: 15, weight: .heavy))
                    .foregroundStyle(isSelected ? Pulse.accentInk : Pulse.accent)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Pulse.accent : Pulse.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("Option \(letter)")
                            .font(.scaledSystem(size: 12.5, weight: .semibold))
                            .foregroundStyle(Pulse.ink)
                        if isBest {
                            Text("BEST")
                                .font(.scaledSystem(size: 7.5, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(Pulse.accentInk)
                                .padding(.horizontal, 5)
                                .frame(height: 15)
                                .background(Pulse.accent, in: Capsule())
                        }
                    }
                    HStack(spacing: 4) {
                        Text(Units.distanceText(route.length, decimals: 1))
                            .font(.scaledSystem(size: 11, weight: .bold))
                            .foregroundStyle(Pulse.accent)
                        if let timeText {
                            Text("•  \(timeText)")
                                .font(.scaledSystem(size: 10))
                                .foregroundStyle(Pulse.muted)
                        }
                        Text("•  \(route.curviness)/5 curves")
                            .font(.scaledSystem(size: 10))
                            .foregroundStyle(Pulse.muted)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.scaledSystem(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Pulse.accent : Pulse.muted)
            }
            .padding(12)
            .background(
                isSelected
                    ? AnyShapeStyle(Pulse.heroGradient)
                    : AnyShapeStyle(Pulse.panel.opacity(0.9)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Pulse.accentDeep.opacity(0.6) : Pulse.line, lineWidth: 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RevertCardButtonStyle())
        .accessibilityLabel("Option \(letter), \(Units.distanceText(route.length, decimals: 1))\(timeText.map { ", \($0)" } ?? "")\(isSelected ? ", selected" : "")")
    }
}

// MARK: - Small components

struct PulseRouteNote: View {
    let text: String
    var systemImage: String = "info.circle"
    var tint: Color = Pulse.muted

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.scaledSystem(size: 10, weight: .bold))
                .padding(.top, 1)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaledSystem(size: 11))
        .foregroundStyle(tint)
    }
}

struct PulseGhostIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaledSystem(size: 10, weight: .bold))
            .foregroundStyle(Pulse.mutedStrong)
            .frame(width: 30, height: 30)
            .background(Pulse.iconWell, in: Circle())
            .overlay(Circle().stroke(Pulse.line, lineWidth: 0.8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PulsePlannerMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var camera: MapCameraPosition
    let mapStyle: MapStyle
    let pin: CLLocationCoordinate2D?
    let waypoints: [CLLocationCoordinate2D]
    let routes: [PlannedRoute]
    let activeRoute: PlannedRoute?
    let selected: UUID?
    @Binding var addingWaypoint: Bool
    let onTap: (CLLocationCoordinate2D) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            PulsePlannerMap(
                camera: $camera,
                mapStyle: mapStyle,
                pin: pin,
                waypoints: waypoints,
                routes: routes,
                activeRoute: activeRoute,
                selected: selected,
                addingWaypoint: addingWaypoint,
                onTap: onTap
            )
            .ignoresSafeArea()

            HStack(spacing: 8) {
                Button {
                    RevertHaptics.tap()
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.scaledSystem(size: 11, weight: .heavy))
                        Text("Done")
                            .font(.scaledSystem(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Pulse.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Pulse.bar.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(Pulse.lineBright, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close full map")
                .accessibilityIdentifier(AccessibilityID.Routes.closeMap)

                Text("Route map")
                    .font(.scaledSystem(size: 14, weight: .bold))
                    .foregroundStyle(Pulse.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Pulse.bar.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(Pulse.line, lineWidth: 0.8))

                Spacer(minLength: 0)

                Button {
                    RevertHaptics.tap()
                    addingWaypoint.toggle()
                } label: {
                    Label(addingWaypoint ? "Done" : "Add stop",
                          systemImage: addingWaypoint ? "checkmark" : "plus")
                        .font(.scaledSystem(size: 11, weight: .bold))
                        .foregroundStyle(addingWaypoint ? Pulse.accentInk : Pulse.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(addingWaypoint ? Pulse.accent : Pulse.bar.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(addingWaypoint ? .clear : Pulse.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if addingWaypoint {
                Text("Tap the map to add a stop")
                    .font(.scaledSystem(size: 11, weight: .bold))
                    .foregroundStyle(Pulse.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Pulse.accent, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 32)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
    }
}


/// One saved loop opened in the Rivals sheet.
private struct LeaderboardTarget: Identifiable {
    let id = UUID()
    let title: String
    let key: String
    let savedRouteID: UUID?
    let routeName: String?
    var laps = 1
    var isSprint = false
}
