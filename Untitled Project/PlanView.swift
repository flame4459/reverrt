import SwiftUI
import MapKit
import SwiftData
import UIKit

struct PlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var tab: Int
    @Environment(NavigationManager.self) private var nav
    let planner: RoutePlanner
    var onStartNavigation: (() -> Void)? = nil

    @State private var miles = 40.0
    @State private var style: RouteStyle = .twisty
    @State private var mode: LoopMode = .extended
    @State private var surface: LoopSurface = .paved
    @State private var prefersPasses = false
    @State private var roadText = ""
    /// Search for the start: a road name, an address or a place.
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var pinLabel: String?
    @State private var searchError: String?
    @State private var searchingPlace = false
    @State private var roadSearch = AddressSearchService()
    /// Optional: skip the comparison and highlight the strongest loop.
    @AppStorage("plan.autoPickBest") private var autoPickBest = false
    @State private var pin: CLLocationCoordinate2D?
    @State private var shapingPins: [CLLocationCoordinate2D] = []
    @State private var pinMode: PlanPinMode = .start
    @Environment(\.modelContext) private var context
    @State private var selected: UUID?
    @State private var previewRoute: PlannedRoute?
    @State private var pendingStart: PlannedRoute?
    @State private var previewRoads: [Road] = []
    @State private var savedRouteQuery = ""
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Query(sort: \Ride.startDate, order: .reverse) private var savedRides: [Ride]
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapStyle: MapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
    @State private var aim = PlanAimModel()
    @State private var pinStrike: PlanPinStrike?
    @State private var showOptions = false
    @FocusState private var roadTextFocused: Bool

    /// The crosshair takes the color of the pin it will drop.
    private var aimTint: Color { pinMode == .shaping ? MapUI.orange : MapUI.emerald }
    private var aimLabel: String { pinMode == .shaping ? "PIN \(shapingPins.count + 1)" : "START" }
    private var dropPinTitle: String {
        pinMode == .shaping ? "Drop shaping pin \(shapingPins.count + 1)" : "Drop start pin"
    }

    /// Logarithmic so 1–10 miles gets useful resolution while 1,000 miles is
    /// still reachable with one thumb.
    private var distanceFraction: Binding<Double> {
        Binding(
            get: { RideDistanceScale.fraction(for: miles) },
            set: { miles = RideDistanceScale.miles(for: $0) }
        )
    }

    private var loopOrigin: CLLocationCoordinate2D? { pin ?? nav.currentLocation?.coordinate }
    /// Observing this stable flag avoids re-rendering the sheet on every GPS fix.
    private var originAvailable: Bool { pin != nil || nav.hasLocation }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: RiderMetrics.sectionSpacing) {
                    planHeader
                    if nav.locationDenied {
                        LocationOffBanner()
                    } else if nav.locationUndetermined {
                        LocationOffBanner(
                            denied: false,
                            onEnable: { LocationHub.shared.requestWhenInUse() }
                        )
                    }
                    mapView
                    if nav.route != nil { activeRouteCard }
                    rideShapeCard
                        .id("planShape")
                    optionsCard
                        .id("planOptions")
                    if showsStatus { statusCard }
                    if !planner.results.isEmpty {
                        resultsCards
                            .id("planResults")
                    }
                    if !savedRoutes.isEmpty { savedRoutesCard }
                    if showsLocalRoutes { localRoutesCard }
                }
                .padding(.horizontal, RiderMetrics.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: planner.results.first?.id) { _, newID in
                guard newID != nil else { return }
                // Results are inserted below the shape/options cards while the
                // rider is still looking at the sticky footer. Bring them into
                // view so a finished build never looks like a no-op.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(RiderMotion.smooth) {
                        scrollProxy.scrollTo("planResults", anchor: .top)
                    }
                }
            }
            .onAppear {
                #if DEBUG
                let arguments = CommandLine.arguments
                let target: String? = arguments.contains("-debugPlanResult")
                    ? "planResults"
                    : (arguments.contains("-debugPlanScroll") ? "planOptions" : nil)
                if let target {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(RiderMotion.smooth) {
                            scrollProxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
                #endif
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stickyFooter
        }
        .background(MapUI.canvas.ignoresSafeArea())
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-debugPlanResult") {
                var route = DebugScreens.samplePlannedRoute()
                route.climbMeters = 320
                route.maxElevation = 880
                route.isMountainPassRoute = true
                route.surface = .mixed
                planner.results = [route]
                selected = route.id
                camera = .region(Self.region(for: [route], fallback: route))
                if CommandLine.arguments.contains("-debugPreview") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        previewRoute = route
                    }
                }
            } else if let origin = loopOrigin {
                planner.prefetchRoads(around: origin, miles: miles, surface: surface)
                if planner.localResults.isEmpty {
                    planner.discoverLocalRoutes(center: origin)
                }
            }
            #else
            if let origin = loopOrigin {
                planner.prefetchRoads(around: origin, miles: miles, surface: surface)
                if planner.localResults.isEmpty {
                    planner.discoverLocalRoutes(center: origin)
                }
            }
            #endif
        }
        .onChange(of: nav.hasLocation) { _, hasLocation in
            guard hasLocation, let origin = loopOrigin else { return }
            planner.prefetchRoads(around: origin, miles: miles, surface: surface)
        }
        .onChange(of: miles) { _, value in
            guard let origin = loopOrigin else { return }
            planner.prefetchRoads(around: origin, miles: value, surface: surface)
        }
        .onChange(of: surface) { _, value in
            guard let origin = loopOrigin else { return }
            planner.prefetchRoads(around: origin, miles: miles, surface: value)
        }
        .onChange(of: planner.results.first?.id) { _, _ in
            guard !planner.results.isEmpty else { return }
            let pick = autoPickBest
                ? (LoopRanking.best(in: planner.results, targetMeters: miles * 1609.344) ?? planner.results[0])
                : planner.results[0]
            selected = pick.id
            camera = .region(Self.region(for: planner.results, fallback: pick))
        }
        .onChange(of: planner.phase) { _, newPhase in
            // Keep the extra local-route searches out of the critical path.
            // They start only once the main generation has finished.
            if newPhase == .done, planner.progress >= 0.99,
               let origin = loopOrigin, planner.localResults.isEmpty {
                planner.discoverLocalRoutes(center: origin)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    roadTextFocused = false
                    searchFocused = false
                }
            }
        }
        .sheet(item: $previewRoute, onDismiss: {
            // Start only after the preview sheet is fully gone, then let
            // the presenting sheet dismiss before the ride cover appears.
            if let route = pendingStart {
                pendingStart = nil
                start(route, roads: previewRoads)
            }
        }) { route in
            RoutePreviewView(
                route: route,
                roads: previewRoads,
                onStart: {
                    pendingStart = route
                    previewRoute = nil
                },
                onClose: {
                    previewRoute = nil
                }
            )
        }
    }

    private var planHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SCENIC ROUTES")
                    .font(RiderType.eyebrow)
                    .tracking(1.7)
                    .foregroundStyle(MapUI.cyan)
                Text("Plan a loop")
                    .font(RiderType.display(30, weight: .heavy))
                    .foregroundStyle(MapUI.ink)
                Text("Choose a start, a shape and a distance. Rider finds the bends.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(MapUI.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                RiderHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(RiderIconButtonStyle(tint: MapUI.textSecondary, diameter: 38))
            .accessibilityLabel("Close plan")
        }
    }

    private var activeRouteCard: some View {
        HStack(spacing: 11) {
            RiderIconBadge(systemImage: "location.north.line.fill", tint: MapUI.emerald, size: 36, radius: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text("NAVIGATING")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(MapUI.emerald)
                Text(nav.route?.displayName ?? "Active route")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("End") {
                RiderHaptics.tap()
                nav.stop()
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(MapUI.coral)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(MapUI.coral.opacity(0.12), in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(MapUI.surfaceHigh.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MapUI.line, lineWidth: 0.8)
        }
    }

    // MARK: Map
    private var mapView: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let pin {
                    Marker("Start", coordinate: pin)
                        .tint(.green)
                }
                ForEach(Array(shapingPins.enumerated()), id: \.offset) { index, coordinate in
                    Marker("Pin \(index + 1)", coordinate: coordinate)
                        .tint(MapUI.orange)
                }
                if let pinStrike {
                    Annotation("", coordinate: pinStrike.coordinate, anchor: .center) {
                        PlanDropPulse(tint: aimTint)
                            .id(pinStrike.id)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(planner.results) { route in
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(route.id == selected ? MapUI.cyan : Color.gray.opacity(0.55),
                                lineWidth: route.id == selected ? 6 : 3)
                }
            }
            .mapStyle(mapStyle)
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .continuous) { context in
                aim.center = context.region.center
            }
            .overlay {
                PlanCrosshair(tint: aimTint)
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.32), .clear, .clear, .black.opacity(0.44)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                PlanAimReadout(model: aim, tint: aimTint, target: aimLabel)
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                mapDock
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                pinModeSwitcher
                    .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                dropPinButton(proxy: proxy)
            }
            // SpatialTapGesture reports the exact touch location and avoids
            // competing with Map's default tap handling.
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        if let coordinate = proxy.convert(event.location, from: .local) {
                            dropPin(at: coordinate)
                        }
                    }
            )
        }
        .frame(height: 278)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), MapUI.cyan.opacity(0.18), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .shadow(color: .black.opacity(0.45), radius: 20, y: 9)
    }

    private var mapDock: some View {
        RiderMapDock {
            RiderMapDockButton(
                systemImage: "location.fill",
                label: "Center on my location"
            ) {
                camera = .userLocation(fallback: .automatic)
            }

            RiderMapDockDivider()

            Menu {
                Button {
                    mapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
                } label: {
                    Label("Muted map", systemImage: "map")
                }
                Button {
                    mapStyle = .standard(elevation: .flat)
                } label: {
                    Label("Standard map", systemImage: "map.fill")
                }
                Button {
                    mapStyle = .imagery(elevation: .realistic)
                } label: {
                    Label("Satellite map", systemImage: "globe.americas.fill")
                }
            } label: {
                Image(systemName: "map")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MapUI.ink)
                    .frame(width: RiderMetrics.dockButtonSize, height: RiderMetrics.dockButtonSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Map style")
        }
    }

    private var pinModeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(PlanPinMode.allCases, id: \.self) { option in
                let selected = pinMode == option
                let tint = option == .shaping ? MapUI.orange : MapUI.emerald
                Button {
                    guard !selected else { return }
                    RiderHaptics.select()
                    withAnimation(RiderMotion.snappy) {
                        pinMode = option
                    }
                } label: {
                    Text(option == .shaping ? "Shaping" : "Start")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? .black : MapUI.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(selected ? tint : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(MapUI.panel.opacity(0.88), in: Capsule())
        .overlay(Capsule().stroke(MapUI.lineStrong, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func dropPinButton(proxy: MapProxy) -> some View {
        GeometryReader { geometry in
            Button {
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                if let coordinate = proxy.convert(center, from: .local) {
                    dropPin(at: coordinate)
                }
            } label: {
                Label(dropPinTitle, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(aimTint)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(MapUI.panel.opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(aimTint.opacity(0.55), lineWidth: 0.9))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(RiderCardButtonStyle())
            .accessibilityHint("Drops a pin at the crosshair in the center of the map")
            .padding(.leading, 12)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    /// Drops a pin at the given coordinate and flashes a lock-on pulse there so
    /// the exact spot is unambiguous, even under the rider's thumb.
    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        roadTextFocused = false
        searchFocused = false
        if pinMode == .shaping {
            shapingPins.append(coordinate)
        } else {
            pin = coordinate
            pinLabel = nil
            searchQuery = ""
            searchError = nil
            roadSearch.clear()
            planner.prefetchRoads(around: coordinate, miles: miles, surface: surface)
        }
        flashPin(at: coordinate)
    }

    /// Flashes a lock-on pulse so the exact spot is unambiguous, even under the
    /// rider's thumb.
    private func flashPin(at coordinate: CLLocationCoordinate2D) {
        let strike = PlanPinStrike(coordinate: coordinate)
        pinStrike = strike
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            guard pinStrike?.id == strike.id else { return }
            pinStrike = nil
        }
    }

    // MARK: Start search

    /// Search for where the loop starts: a road name, an address, or a place.
    ///
    /// Dropping a pin on the crosshair is exact but slow if the rider is not
    /// already looking at the right part of the map. This lets them type
    /// "Skyline Blvd" and starts the loop there instead.
    private var roadSearchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MapUI.cyan)

                TextField("Search a road or place", text: $searchQuery)
                    .font(.system(.subheadline, design: .rounded))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { resolveSearchText() }
                    .onChange(of: searchQuery) { _, query in
                        searchError = nil
                        // Only ask for suggestions while the rider is typing.
                        // Committing a result writes the label back into the
                        // field, and that must not repopulate the list.
                        guard searchFocused else { return }
                        roadSearch.update(query: query, region: searchRegion)
                    }

                if searchingPlace {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(MapUI.cyan)
                } else if !searchQuery.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 42)
            .background(MapUI.surfaceHigh.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(searchFocused ? MapUI.cyan.opacity(0.55) : MapUI.lineStrong, lineWidth: 0.8)
            }

            if searchFocused, !roadSearch.suggestions.isEmpty {
                AddressSuggestionList(suggestions: roadSearch.suggestions) { suggestion in
                    chooseSearchResult(suggestion)
                }
                .padding(.top, 2)
            }

            if let searchError {
                Text(searchError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchRegion: MKCoordinateRegion? {
        let center = pin ?? nav.currentLocation?.coordinate ?? aim.center
        guard let center else { return nil }
        return MKCoordinateRegion(center: center, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
    }

    private func clearSearch() {
        searchQuery = ""
        searchError = nil
        roadSearch.clear()
    }

    private func chooseSearchResult(_ suggestion: AddressSearchService.Suggestion) {
        guard !searchingPlace else { return }
        searchingPlace = true
        Task { @MainActor in
            defer { searchingPlace = false }
            do {
                let coordinate = try await roadSearch.coordinate(for: suggestion)
                commitSearchResult(
                    coordinate,
                    label: suggestion.title.isEmpty ? suggestion.subtitle : suggestion.title
                )
            } catch {
                searchError = "That place could not be found. Try a nearby town or a full street name."
            }
        }
    }

    private func resolveSearchText() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !searchingPlace else { return }
        searchingPlace = true
        Task { @MainActor in
            defer { searchingPlace = false }
            do {
                let coordinate = try await roadSearch.coordinate(forQuery: query, region: searchRegion)
                commitSearchResult(coordinate, label: query)
            } catch {
                searchError = "That road could not be found. Try a nearby town or a full street name."
            }
        }
    }

    /// Moves the pin to the searched coordinate and gets its roads ready.
    ///
    /// Respects the Start/Shaping switch: in Shaping mode the searched road
    /// becomes a waypoint the loop is pulled through, exactly as a map tap
    /// would.
    private func commitSearchResult(_ coordinate: CLLocationCoordinate2D, label: String) {
        if pinMode == .shaping {
            shapingPins.append(coordinate)
        } else {
            pin = coordinate
            pinLabel = label
            planner.prefetchRoads(around: coordinate, miles: miles, surface: surface)
        }
        searchQuery = label
        searchFocused = false
        searchError = nil
        roadSearch.clear()
        camera = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 6_000,
            longitudinalMeters: 6_000
        ))
        flashPin(at: coordinate)
    }

    // MARK: Sections

    private var showsStatus: Bool {
        switch planner.phase {
        case .downloading, .planning, .routing, .failed: return true
        case .idle: return planner.prefetchingRoads
        case .done: return false
        }
    }

    private var showsLocalRoutes: Bool {
        planner.localRoutesLoading || planner.localRoutesError != nil || !planner.localResults.isEmpty
    }

    private var statusTitle: String {
        switch planner.phase {
        case .downloading: return "Saving local road data"
        case .planning: return "Building scenic loops"
        case .routing: return "Building your route"
        case .failed: return "Couldn't build a loop"
        case .done: return "Routes ready"
        case .idle: return "Caching roads"
        }
    }

    private var statusDetail: String {
        switch planner.phase {
        case .downloading(let done, let total):
            return "\(done) of \(max(total, 1)) map tiles ready"
        case .planning:
            return "Searching for the most interesting bends near your start."
        case .routing:
            return "Connecting the selected loop."
        case .failed(let message):
            return message
        case .done:
            return "Tap a route to preview it."
        case .idle:
            return "The first search in an area downloads the roads it needs."
        }
    }

    private var statusProgress: Double? {
        switch planner.phase {
        case .downloading(let done, let total):
            return Double(done) / Double(max(total, 1))
        case .planning:
            return planner.progress
        default:
            return nil
        }
    }

    private var statusIcon: String {
        switch planner.phase {
        case .downloading: return "antenna.radiowaves.left.and.right"
        case .planning: return "point.topleft.down.curvedto.point.bottomright.up"
        case .routing: return "arrow.triangle.turn.up.right.diamond"
        case .failed: return "exclamationmark.triangle.fill"
        case .done: return "checkmark.circle.fill"
        case .idle: return "arrow.down.circle"
        }
    }

    private var statusTint: Color {
        switch planner.phase {
        case .failed: return MapUI.coral
        case .done: return MapUI.emerald
        default: return MapUI.cyan
        }
    }

    private var stickyFooter: some View {
        HStack(spacing: 10) {
            if planner.isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(MapUI.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusTitle)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                            .lineLimit(1)
                        Text("\(Int(min(max(planner.progress, 0), 1) * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: RiderMetrics.primaryButtonHeight)
                .background(MapUI.surfaceHigh, in: Capsule())
                .overlay(Capsule().stroke(MapUI.lineStrong, lineWidth: 0.8))

                Button {
                    RiderHaptics.tap()
                    planner.cancel()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RiderIconButtonStyle(tint: MapUI.textSecondary, diameter: 50))
                .accessibilityLabel("Cancel route building")
            } else if !planner.results.isEmpty {
                Button {
                    findLoops()
                } label: {
                    Label(autoPickBest ? "Update best loop" : "Update loops",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(RiderSecondaryButtonStyle())
                .disabled(!originAvailable)
                .opacity(originAvailable ? 1 : 0.55)
            } else {
                Button {
                    findLoops()
                } label: {
                    Label(originAvailable
                              ? (autoPickBest ? "Find my best loop" : "Find scenic loops")
                              : "Waiting for location",
                          systemImage: originAvailable ? "sparkles" : "location.slash")
                }
                .buttonStyle(RiderPrimaryButtonStyle())
                .disabled(!originAvailable)
                .opacity(originAvailable ? 1 : 0.55)
            }
        }
        .padding(.horizontal, RiderMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            LinearGradient(
                colors: [MapUI.canvas.opacity(0), MapUI.canvas.opacity(0.94), MapUI.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var rideShapeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RiderCardHeader(
                icon: "arrow.triangle.2.circlepath",
                title: "Ride shape",
                subtitle: "Distance, style and surface",
                tint: MapUI.cyan
            )

            roadSearchField

            HStack(spacing: 9) {
                RiderIconBadge(
                    systemImage: pin == nil ? "location.fill" : "mappin.and.ellipse",
                    tint: pin == nil ? MapUI.emerald : MapUI.cyan,
                    size: 32,
                    radius: 10
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("START")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(MapUI.textTertiary)
                    Text(pin == nil ? "My location" : (pinLabel ?? "Dropped pin"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                }
                Spacer(minLength: 4)
                if pin != nil {
                    Button("Use my location") {
                        RiderHaptics.tap()
                        pin = nil
                        pinLabel = nil
                        searchQuery = ""
                        searchError = nil
                        roadSearch.clear()
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MapUI.cyan)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(MapUI.cyan.opacity(0.10), in: Capsule())
                    .buttonStyle(.plain)
                }
            }

            if !originAvailable {
                RiderInfoNote(
                    text: "Waiting for your location. Allow location access, or drop a start pin on the map.",
                    systemImage: "location.slash",
                    tint: MapUI.amber
                )
            }

            Rectangle().fill(MapUI.line).frame(height: 0.8)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Distance")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                    Spacer()
                    Text(Units.distanceTextFromMiles(miles, decimals: miles < 10 ? 1 : 0))
                        .font(RiderType.number(22))
                        .foregroundStyle(MapUI.cyan)
                }

                Slider(value: distanceFraction, in: 0...1)
                    .tint(MapUI.cyan)
                    .accessibilityLabel("Ride distance")
                    .accessibilityValue(Units.distanceTextFromMiles(miles, decimals: 1))

                HStack {
                    Text(Units.distanceTextFromMiles(RideDistanceScale.minimumMiles, decimals: 1))
                    Spacer()
                    Text(Units.distanceTextFromMiles(RideDistanceScale.maximumMiles, decimals: 0))
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RideDistanceScale.presets, id: \.self) { preset in
                            RiderChip(
                                title: RideDistanceScale.presetLabel(preset),
                                isSelected: miles == preset,
                                tint: MapUI.cyan,
                                action: {
                                    RiderHaptics.select()
                                    withAnimation(RiderMotion.snappy) { miles = preset }
                                }
                            )
                        }
                    }
                }
            }

            Rectangle().fill(MapUI.line).frame(height: 0.8)

            VStack(alignment: .leading, spacing: 8) {
                RiderSectionLabel(title: "Style", detail: style.title)
                RiderOptionPicker(
                    options: RouteStyle.allCases,
                    selection: $style,
                    title: { $0.title },
                    systemImage: { styleIcon($0) }
                )
                Text(style.blurb)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                RiderSectionLabel(title: "Loop type", detail: mode.title)
                RiderOptionPicker(
                    options: LoopMode.allCases,
                    selection: $mode,
                    title: { $0.title },
                    systemImage: { modeIcon($0) }
                )
                Text(mode.blurb)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Toggle(isOn: $autoPickBest) {
                    Label("Auto-pick the best loop", systemImage: "wand.and.stars")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                }
                .tint(MapUI.emerald)
                .accessibilityHint("Highlights the strongest loop in this area as soon as planning finishes")

                Text("Rider ranks every loop it builds and selects the strongest one for you, instead of leaving you to compare cards.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                RiderSectionLabel(title: "Surface", detail: surface.title)
                RiderOptionPicker(
                    options: LoopSurface.allCases,
                    selection: $surface,
                    title: { $0.title },
                    systemImage: { $0.icon },
                    tint: MapUI.emerald
                )
                Text(surface.blurb)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .riderCard()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                RiderHaptics.tap()
                roadTextFocused = false
                withAnimation(RiderMotion.smooth) {
                    showOptions.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    RiderIconBadge(systemImage: "slider.horizontal.3", tint: MapUI.amber, size: 34, radius: 11)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Options")
                            .font(RiderType.headline)
                            .foregroundStyle(MapUI.ink)
                        Text("Passes, shaping pins and roads")
                            .font(.caption)
                            .foregroundStyle(MapUI.textSecondary)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MapUI.textTertiary)
                        .rotationEffect(.degrees(showOptions ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RiderCardButtonStyle())
            .accessibilityHint(showOptions ? "Hides advanced options" : "Shows advanced options")

            if showOptions {
                Rectangle().fill(MapUI.line).frame(height: 0.8)

                Toggle(isOn: $prefersPasses) {
                    Label("Prioritize mountain passes", systemImage: "mountain.2.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                }
                .tint(MapUI.cyan)

                Text("Sorts results by climb and summit when elevation data is available.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)

                VStack(alignment: .leading, spacing: 6) {
                    RiderSectionLabel(title: "Roads to include")
                    TextField("e.g. Highway 1, Skyline Blvd", text: $roadText)
                        .font(.system(.subheadline, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($roadTextFocused)
                        .submitLabel(.done)
                        .onSubmit { roadTextFocused = false }
                        .padding(12)
                        .background(MapUI.surfaceHigh.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MapUI.lineStrong, lineWidth: 0.8)
                        }
                    Text("Optional: enter road names or route numbers and Rider will favor them while building the loop.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 7) {
                    RiderSectionLabel(
                        title: "Shaping pins",
                        detail: shapingPins.isEmpty ? "None" : "\(shapingPins.count)"
                    )

                    if shapingPins.isEmpty {
                        Text("Switch the map to Shaping, then tap a road you love to pull the loop through it.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Array(shapingPins.enumerated()), id: \.offset) { index, _ in
                                    HStack(spacing: 5) {
                                        Text("Pin \(index + 1)")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                        Button {
                                            RiderHaptics.tap()
                                            shapingPins.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .heavy))
                                                .foregroundStyle(MapUI.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .foregroundStyle(MapUI.ink)
                                    .padding(.horizontal, 9)
                                    .frame(height: 26)
                                    .background(MapUI.surfaceHigh, in: Capsule())
                                    .overlay(Capsule().stroke(MapUI.line, lineWidth: 0.8))
                                }
                            }
                        }

                        Button("Clear all pins") {
                            RiderHaptics.tap()
                            shapingPins.removeAll()
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.coral)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .riderCard()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                RiderIconBadge(systemImage: statusIcon, tint: statusTint, size: 34, radius: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(RiderType.headline)
                        .foregroundStyle(MapUI.ink)
                    Text(statusDetail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if planner.isBusy {
                    ProgressView()
                        .tint(MapUI.cyan)
                } else if case .failed = planner.phase {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MapUI.coral)
                }
            }

            if let progress = statusProgress {
                RiderProgressBar(value: progress, tint: MapUI.aurora, height: 5)
            }

            if planner.isBusy {
                Button {
                    RiderHaptics.tap()
                    planner.cancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(MapUI.surfaceHigh, in: Capsule())
                        .overlay(Capsule().stroke(MapUI.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            if case .failed = planner.phase {
                RiderInfoNote(
                    text: "Check your connection, or try a different start or a shorter distance.",
                    systemImage: "lightbulb",
                    tint: MapUI.textTertiary
                )
                Button {
                    RiderHaptics.tap()
                    findLoops()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(RiderSecondaryButtonStyle(minHeight: 44))
                .disabled(!originAvailable)
                .opacity(originAvailable ? 1 : 0.55)
            }
        }
        .riderCard()
    }

    private var resultsCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RiderSectionLabel(title: "Routes", detail: "\(planner.results.count) found")
                Spacer(minLength: 8)
                if planner.elevationLoading {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).tint(MapUI.cyan)
                        Text("Elevation")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                }
            }

            if let notice = planner.notice {
                RiderInfoNote(text: notice, systemImage: "mappin.and.ellipse", tint: MapUI.cyan)
            }

            ForEach(Array(planner.results.enumerated()), id: \.element.id) { index, route in
                planRouteCard(route, index: index)
            }
        }
    }

    private func planRouteCard(_ route: PlannedRoute, index: Int) -> some View {
        let isSelected = route.id == selected
        let letters = ["A", "B", "C", "D", "E"]
        let letter = letters[min(max(index, 0), letters.count - 1)]
        let time = route.expectedTravelTime.map {
            Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text("OPTION \(letter)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? .black : MapUI.cyan)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(isSelected ? MapUI.cyan : MapUI.cyan.opacity(0.12), in: Capsule())

                if index == 0 {
                    RiderChip(title: "Best match", systemImage: "sparkles", isSelected: true, tint: MapUI.emerald)
                }

                Spacer(minLength: 4)

                Text("Heads \(route.heading)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? MapUI.cyan : MapUI.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Units.distanceText(route.length, decimals: 1))
                    .font(RiderType.number(27))
                    .foregroundStyle(MapUI.ink)

                if let time {
                    Text(time)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.textSecondary)
                }

                Spacer(minLength: 4)

                if let label = route.scoreLabel, let score = route.overallScore {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(score.rounded()))")
                            .font(RiderType.number(18))
                            .foregroundStyle(MapUI.emerald)
                        Text(label.uppercased())
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(MapUI.textTertiary)
                    }
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Text("Curves")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { dot in
                            Circle()
                                .fill(dot < route.curviness ? MapUI.amber : MapUI.lineStrong)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .fixedSize()
                }
                .fixedSize()

                Rectangle().fill(MapUI.line).frame(width: 1, height: 11)

                RiderMetricPill(
                    systemImage: "arrow.triangle.turn.up.right.diamond",
                    text: "\(Int(route.twistPerKm.rounded()))°/km",
                    tint: MapUI.textTertiary
                )

                if route.climbMeters > 0 {
                    Rectangle().fill(MapUI.line).frame(width: 1, height: 11)
                    RiderMetricPill(
                        systemImage: "mountain.2",
                        text: Units.elevationText(route.climbMeters),
                        tint: MapUI.textTertiary
                    )
                }

                if route.surface != .paved {
                    Rectangle().fill(MapUI.line).frame(width: 1, height: 11)
                    RiderMetricPill(
                        systemImage: route.surface.icon,
                        text: route.surface.title,
                        tint: MapUI.emerald
                    )
                }

                Spacer(minLength: 0)
            }

            if route.isOfflinePreview {
                RiderInfoNote(
                    text: "Preview only — waiting for live map data.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: MapUI.amber
                )
            }

            if isSelected {
                Rectangle().fill(MapUI.line).frame(height: 0.8)

                HStack(spacing: 9) {
                    Button {
                        RiderHaptics.tap()
                        previewRoads = planner.roads
                        previewRoute = route
                    } label: {
                        Label("Preview", systemImage: "play.rectangle")
                    }
                    .buttonStyle(RiderSecondaryButtonStyle(minHeight: 48))

                    Button {
                        RiderHaptics.rigid()
                        start(route)
                    } label: {
                        Label("Start", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(RiderPrimaryButtonStyle(minHeight: 48, compact: true))
                    .disabled(route.isOfflinePreview)
                    .opacity(route.isOfflinePreview ? 0.5 : 1)
                }

                SaveRouteButton(route: route, roads: planner.roads, compact: true)

                if !route.elevationProfile.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Elevation", systemImage: "mountain.2")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(MapUI.ink)
                            Spacer()
                            Text("Climb \(Units.elevationText(route.climbMeters))  •  peak \(Units.elevationText(route.maxElevation))")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(MapUI.cyan)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        RideElevationChart(values: route.elevationProfile.map(\.elevation), totalMeters: route.length)
                            .frame(height: 90)
                    }
                    .padding(10)
                    .background(MapUI.surfaceHigh.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if route.isMountainPassRoute {
                    RiderChip(title: "Mountain pass route", systemImage: "crown.fill", tint: MapUI.amber)
                }

                if let flow = route.flowScore, let lap = route.lapScore {
                    Text("Flow \(Int(flow.rounded())) · Lap \(Int(lap.rounded())) · multi-scale curvature + maneuvers")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }

                if let interruptions = route.interruptions, interruptions > 0 {
                    Text("\(interruptions) junction\(interruptions == 1 ? "" : "s") or maneuver\(interruptions == 1 ? "" : "s") on route")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }

                if route.retraced > 0.05 {
                    Text("\(Int((route.retraced * 100).rounded()))% repeated road")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: [MapUI.cyan.opacity(0.16), MapUI.surfaceHigh],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(MapUI.surfaceHigh.opacity(0.88))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isSelected
                            ? [MapUI.cyan.opacity(0.7), MapUI.emerald.opacity(0.3)]
                            : [MapUI.lineStrong, MapUI.line],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.2 : 0.8
                )
        }
        .shadow(color: isSelected ? MapUI.cyan.opacity(0.16) : .clear, radius: 16, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectPlanRoute(route)
        }
        .animation(RiderMotion.snappy, value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Option \(letter), \(Units.distanceText(route.length, decimals: 1))\(time.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var filteredSavedRoutes: [SavedRoute] {
        let needle = savedRouteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return savedRoutes }
        return savedRoutes.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.createdAt.formatted(date: .abbreviated, time: .omitted)
                    .localizedCaseInsensitiveContains(needle)
        }
    }

    private var savedRoutesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RiderSectionLabel(title: "Saved routes", detail: "\(savedRoutes.count)")

            if savedRoutes.count > 3 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MapUI.textTertiary)
                    TextField("Search saved routes", text: $savedRouteQuery)
                        .font(.system(.subheadline, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 11)
                .frame(height: 42)
                .background(MapUI.surfaceHigh.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if filteredSavedRoutes.isEmpty {
                Text("No saved route matches “\(savedRouteQuery)”.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
            }

            ForEach(filteredSavedRoutes) { saved in
                HStack(spacing: 6) {
                Button {
                    RiderHaptics.tap()
                    if let route = saved.plannedRoute() {
                        previewRoads = saved.roads
                        previewRoute = route
                    }
                } label: {
                    HStack(spacing: 10) {
                        RiderIconBadge(
                            systemImage: saved.isLoop ? "arrow.triangle.2.circlepath" : "arrow.triangle.turn.up.right.diamond",
                            tint: MapUI.cyan,
                            size: 34,
                            radius: 11
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(saved.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                                .lineLimit(1)
                            Text("\(Units.distanceText(saved.distanceMeters, decimals: 1))  •  \(saved.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(MapUI.textTertiary)
                            if let best = savedRides
                                .filter({ $0.routeName == saved.name })
                                .map(\.durationSeconds)
                                .min() {
                                Text("Best time \(Units.clock(best))")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(MapUI.emerald)
                            }
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .padding(9)
                    .background(MapUI.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(RiderCardButtonStyle())
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        context.delete(saved)
                        try? context.save()
                    }
                }

                Menu {
                    Button(role: .destructive) {
                        context.delete(saved)
                        try? context.save()
                    } label: {
                        Label("Delete route", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MapUI.textTertiary)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Saved route actions")
                }
            }
        }
        .riderCard()
    }

    private var localRoutesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RiderIconBadge(systemImage: "binoculars.fill", tint: MapUI.emerald, size: 34, radius: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nearby rides")
                        .font(RiderType.headline)
                        .foregroundStyle(MapUI.ink)
                    Text("Community-listed destinations")
                        .font(.caption)
                        .foregroundStyle(MapUI.textSecondary)
                }
                Spacer(minLength: 6)
                if planner.localRoutesLoading {
                    ProgressView().controlSize(.small).tint(MapUI.emerald)
                }
            }

            if let error = planner.localRoutesError {
                RiderInfoNote(text: error, systemImage: "info.circle", tint: MapUI.textTertiary)
            }

            Text("Names come from local listings; verify the route and signage before riding.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)

            if planner.localRoutesLoading && planner.localResults.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(MapUI.cyan)
                    Text("Finding scenic rides within 50 miles…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
                .padding(.vertical, 6)
            }

            ForEach(planner.localResults) { route in
                Button {
                    RiderHaptics.tap()
                    previewRoads = planner.roads
                    previewRoute = route
                } label: {
                    HStack(spacing: 10) {
                        RiderIconBadge(systemImage: "binoculars.fill", tint: MapUI.emerald, size: 30, radius: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(route.displayName ?? "Local scenic loop")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                                .lineLimit(2)
                            Text(Units.distanceText(route.length, decimals: 1))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(MapUI.textTertiary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .padding(9)
                    .background(MapUI.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(RiderCardButtonStyle())
            }
        }
        .riderCard()
    }

    private func styleIcon(_ style: RouteStyle) -> String {
        switch style {
        case .relaxed: return "leaf.fill"
        case .twisty: return "arrow.triangle.turn.up.right.diamond.fill"
        case .extreme: return "bolt.fill"
        }
    }

    private func modeIcon(_ mode: LoopMode) -> String {
        switch mode {
        case .compact: return "circle.dashed"
        case .extended: return "circle.dotted"
        }
    }

    private func selectPlanRoute(_ route: PlannedRoute) {
        guard selected != route.id else { return }
        RiderHaptics.select()
        withAnimation(RiderMotion.snappy) {
            selected = route.id
        }
        camera = .region(Self.region(for: [route], fallback: route))
    }

    private func findLoops() {
        // The road-name field sits inside Options; leaving the keyboard up
        // covers the results the rider just asked for.
        roadTextFocused = false
        guard let origin = loopOrigin else {
            planner.localRoutesError = "Your location is not available yet. Allow location access, or drop a pin on the map first."
            return
        }

        let preferredRoads = roadText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        RiderHaptics.rigid()
        planner.generate(
            start: origin,
            miles: miles,
            style: style,
            mode: mode,
            surface: surface,
            shapingPins: shapingPins,
            prefersPasses: prefersPasses,
            preferredRoads: preferredRoads
        )
    }

    private func start(_ route: PlannedRoute, roads: [Road]? = nil) {
        // Implicit signal: only roads the rider actually chose to ride get a
        // small preference on the next plan.
        RouteTaste.shared.recordStarted(route.usedRoadNames)
        nav.start(route, roads: roads ?? planner.roads)
        tab = 0
        dismiss()
        onStartNavigation?()
    }

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
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.02),
                                   longitudeDelta: max((maxLon - minLon) * 1.3, 0.02))
        )
    }
}

private struct RoutePreviewView: View {
    let route: PlannedRoute
    let roads: [Road]
    let onStart: () -> Void
    let onClose: () -> Void

    @State private var mapStyle: MapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
    @State private var camera: MapCameraPosition = .automatic

    private var timeText: String? {
        guard let time = route.expectedTravelTime else { return nil }
        return Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        Map(position: $camera) {
                            MapPolyline(coordinates: route.coordinates)
                                .stroke(MapUI.cyan.opacity(0.35), lineWidth: 11)
                            MapPolyline(coordinates: route.coordinates)
                                .stroke(MapUI.aurora, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }
                        .mapStyle(mapStyle)
                        .mapControlVisibility(.hidden)
                        .frame(height: 250)

                        Menu {
                            Button {
                                mapStyle = .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
                            } label: {
                                Label("Muted map", systemImage: "map")
                            }
                            Button {
                                mapStyle = .standard(elevation: .flat)
                            } label: {
                                Label("Standard map", systemImage: "map.fill")
                            }
                            Button {
                                mapStyle = .imagery(elevation: .realistic)
                            } label: {
                                Label("Satellite map", systemImage: "globe.americas.fill")
                            }
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(MapUI.ink)
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial, in: Circle())
                                .background(MapUI.panel.opacity(0.72), in: Circle())
                                .overlay(Circle().stroke(MapUI.lineStrong, lineWidth: 0.8))
                        }
                        .accessibilityLabel("Preview map style")
                        .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(MapUI.lineStrong, lineWidth: 0.9)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                    RiderScreenHeader(
                        eyebrow: "RIDE PREVIEW",
                        title: route.displayName ?? "Scenic loop",
                        subtitle: "\(Units.distanceText(route.length, decimals: 1)) · \(route.curviness)/5 curves",
                        systemImage: "map.fill"
                    )

                    MapCard {
                        HStack(spacing: 0) {
                            RiderStatTile(label: "Distance", value: Units.distanceText(route.length, decimals: 1))
                            Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                            RiderStatTile(label: "Curves", value: "\(route.curviness)/5", tint: MapUI.amber)
                            Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                            RiderStatTile(label: "Time", value: timeText ?? "—")
                        }
                    }

                    if route.isOfflinePreview {
                        RiderInfoNote(
                            text: "Preview only — live map data is still loading.",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: MapUI.amber
                        )
                    }

                    MapCard {
                        VStack(alignment: .leading, spacing: 10) {
                            RiderSectionLabel(title: "Route shape")
                            IsometricRouteRibbon(points: route.points, lineWidth: 4)
                                .frame(height: 140)
                                .background(MapUI.pitchBlack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(MapUI.line, lineWidth: 0.8)
                                }
                            if !route.elevationProfile.isEmpty {
                                Rectangle().fill(MapUI.line).frame(height: 0.8)
                                HStack(alignment: .firstTextBaseline) {
                                    Label("Elevation", systemImage: "mountain.2")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(MapUI.ink)
                                    Spacer()
                                    Text("Climb \(Units.elevationText(route.climbMeters))  •  peak \(Units.elevationText(route.maxElevation))")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(MapUI.cyan)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                RideElevationChart(values: route.elevationProfile.map(\.elevation), totalMeters: route.length)
                                    .frame(height: 100)
                            }
                        }
                    }

                    MapCard {
                        VStack(alignment: .leading, spacing: 0) {
                            RiderSectionLabel(title: "Turn-by-turn")
                                .padding(.bottom, 8)

                            ForEach(Array(route.steps.prefix(12).enumerated()), id: \.element.id) { index, step in
                                HStack(spacing: 11) {
                                    Image(systemName: step.symbol)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(MapUI.cyan)
                                        .frame(width: 28, height: 28)
                                        .background(MapUI.cyan.opacity(0.10), in: Circle())
                                    Text(step.instruction)
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(MapUI.ink)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(Units.distanceText(step.distance, decimals: 1))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(MapUI.textTertiary)
                                }
                                .padding(.vertical, 8)

                                if index < min(route.steps.count, 12) - 1 {
                                    Rectangle().fill(MapUI.line).frame(height: 0.7).padding(.leading, 39)
                                }
                            }
                        }
                    }

                    Button {
                        RiderHaptics.rigid()
                        onStart()
                    } label: {
                        Label("Start navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(RiderPrimaryButtonStyle())
                    .disabled(route.isOfflinePreview)
                    .opacity(route.isOfflinePreview ? 0.5 : 1)

                    Button(action: onClose) {
                        Text("Close preview")
                    }
                    .buttonStyle(RiderSecondaryButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 26)
            }
            .background(MapUI.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Ride preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close route preview")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}


enum PlanPinMode: String, CaseIterable {
    case start
    case shaping
}
