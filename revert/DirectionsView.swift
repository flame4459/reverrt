import SwiftUI
import MapKit
import SwiftData
import UIKit

// The legacy full-screen map and bottom sheet. The Midnight Pulse route
// planner (PulseRoutesView) now owns the Routes destination; the shared
// models and DirectionsFuelCard still live here because other screens use them.

enum SavedPlace: String, CaseIterable, Identifiable {
    case home
    case work

    var id: String { rawValue }
    var title: String { self == .home ? "Home" : "Work" }
    var icon: String { self == .home ? "house.fill" : "briefcase.fill" }
}

struct RecentDestination: Codable, Identifiable, Equatable {
    let title: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(title)|\(latitude)|\(longitude)" }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum CentralMenuDestination: String, Identifiable {
    case plan
    case history
    case settings
    case offline
    case savedPlaces

    var id: String { rawValue }
}

enum CentralMenuItem: String, CaseIterable, Identifiable, Codable {
    case plan
    case history
    case settings
    case offline
    case savedPlaces

    static let defaultOrder: [CentralMenuItem] = [.plan, .history, .settings, .offline, .savedPlaces]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan a ride"
        case .history: "Ride history"
        case .settings: "Settings"
        case .offline: "Offline data"
        case .savedPlaces: "Saved places"
        }
    }

    var subtitle: String {
        switch self {
        case .plan: "Scenic routes"
        case .history: "Your saved rides"
        case .settings: "Tune alerts"
        case .offline: "No-signal riding"
        case .savedPlaces: "Home and work"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "map.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        case .offline: "arrow.down.circle.fill"
        case .savedPlaces: "star.fill"
        }
    }

    var tint: Color {
        switch self {
        case .plan: MapUI.accent
        case .history: MapUI.teal
        case .settings: MapUI.orange
        case .offline: MapUI.green
        case .savedPlaces: .purple
        }
    }

    var destination: CentralMenuDestination {
        switch self {
        case .plan: .plan
        case .history: .history
        case .settings: .settings
        case .offline: .offline
        case .savedPlaces: .savedPlaces
        }
    }
}

struct DirectionsView: View {
    @Environment(NavigationManager.self) private var nav
    @Environment(\.modelContext) private var context
    let planner: RoutePlanner
    var initialMenu: CentralMenuDestination? = nil
    /// Supplied by the tab shell: the map is immersive, so it needs its own
    /// way back to the dashboard.
    var onCloseMap: (() -> Void)? = nil

    @State private var preference: DirectionPreference = .fastest
    @State private var pin: CLLocationCoordinate2D?
    @State private var waypoints: [CLLocationCoordinate2D] = []
    @State private var addingWaypoint = false
    @State private var savePlacePrompt: SavedPlace?
    @State private var recoveredRide: Ride?
    @State private var showingGarage = false
    @State private var selected: UUID?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapStyle: MapStyle = .standard(elevation: .flat)
    @State private var destinationText = ""
    /// Text that was set programmatically (saved place or picked suggestion).
    /// Keeps a TextField onChange from turning that value back into a search
    /// query and reopening a stale suggestion list.
    @State private var committedDestination = ""
    @State private var resolvingDestination = false
    @State private var addressSearch = AddressSearchService()
    @State private var addressError: String?
    @State private var showingMapOptions = false
    @State private var presentedMenu: CentralMenuDestination?
    @State private var editingLayout = false
    @State private var showingRide = false
    @State private var pendingRideStart = false
    @AppStorage("directionsMenuOffsetX") private var menuOffsetX = 0.0
    @AppStorage("directionsMenuOffset") private var menuOffset = 0.0
    @AppStorage("directionsControlsOffsetX") private var controlsOffsetX = 0.0
    @AppStorage("directionsControlsOffsetY") private var controlsOffsetY = 0.0
    @AppStorage("directionsLayoutVersion") private var layoutVersion = 0
    @AppStorage("recent.destinations") private var recentDestinationsData = ""
    @AppStorage("saved.home.lat") private var homeLat = 0.0
    @AppStorage("saved.home.lon") private var homeLon = 0.0
    @AppStorage("saved.work.lat") private var workLat = 0.0
    @AppStorage("saved.work.lon") private var workLon = 0.0

    private var origin: CLLocationCoordinate2D? {
        nav.lastLocation?.coordinate
    }

    private var recentDestinations: [RecentDestination] {
        guard let data = recentDestinationsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RecentDestination].self, from: data) else {
            return []
        }
        return decoded
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DirectionsMap(
                camera: $camera,
                mapStyle: mapStyle,
                pin: pin,
                waypoints: waypoints,
                addingWaypoint: addingWaypoint,
                routes: planner.results,
                activeRoute: nav.route,
                selected: selected,
                onMapTap: { coordinate in
                    guard addingWaypoint else { return }
                    waypoints.append(coordinate)
                    if pin != nil { previewRoute() }
                }
            )

            RevertMapScrim()
                .zIndex(1)

            VStack(spacing: 8) {
                if nav.locationDenied {
                    LocationOffBanner()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                } else if nav.locationUndetermined {
                    LocationOffBanner(
                        denied: false,
                        onEnable: { LocationHub.shared.requestWhenInUse() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                if nav.route != nil {
                    NavBanner(nav: nav)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                if editingLayout {
                    LayoutEditorBanner(
                        onReset: {
                            menuOffsetX = 0
                            menuOffset = 0
                            controlsOffsetX = 0
                            controlsOffsetY = 0
                        },
                        onDone: { editingLayout = false }
                    )
                    .padding(.horizontal, 16)
                }

                DirectionsTopBar(
                    showingMapOptions: $showingMapOptions,
                    mapStyle: $mapStyle,
                    onCenter: {
                        guard !editingLayout else { return }
                        camera = .userLocation(fallback: .automatic)
                    },
                    onOpenSettings: { if !editingLayout { presentedMenu = .settings } },
                    onOpenRide: { if !editingLayout { showingRide = true } },
                    editingLayout: editingLayout,
                    controlsOffsetX: $controlsOffsetX,
                    controlsOffsetY: $controlsOffsetY,
                    onEditLayout: { editingLayout = true },
                    onCloseMap: onCloseMap
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .zIndex(2)

            DirectionsBottomSheet(
                destinationText: $destinationText,
                preference: $preference,
                suggestions: addressSearch.suggestions,
                results: planner.results,
                selected: selected,
                originAvailable: nav.hasLocation,
                isBusy: planner.isBusy,
                isResolvingAddress: resolvingDestination,
                phase: planner.phase,
                addressError: addressError,
                onSearchChanged: handleSearchChanged,
                onSelectSuggestion: chooseAddress,
                onClear: clearDestination,
                onPreview: previewRoute,
                onSelectRoute: { selected = $0 },
                onStart: startNavigation,
                onAddFuelStop: { coordinate in
                    waypoints.append(coordinate)
                    previewRoute()
                },
                waypoints: waypoints,
                addingWaypoint: addingWaypoint,
                onToggleAddWaypoint: {
                    addingWaypoint.toggle()
                },
                onSavedPlace: { useSavedPlace($0) },
                onRemoveWaypoint: { index in
                    guard waypoints.indices.contains(index) else { return }
                    waypoints.remove(at: index)
                    if pin != nil { previewRoute() }
                },
                onOpenMenu: { presentedMenu = $0 },
                onEditLayout: { editingLayout = true },
                recentDestinations: recentDestinations,
                onSelectRecent: useRecentDestination,
                onRemoveRecent: removeRecentDestination,
                onClearRecents: clearRecentDestinations,
                editingLayout: editingLayout,
                menuOffsetX: $menuOffsetX,
                menuOffset: $menuOffset
            )
            .zIndex(1)
        }
        // The map is the app's home screen. Keep the display on while it is
        // up so the phone doesn't lock in the middle of a glance down at the
        // route — including while a route/plan sheet is open over it.
        .keepsScreenAwake("map")
        .animation(.spring(duration: 0.3), value: planner.results.first?.id)
        .onChange(of: planner.results.first?.id) { _, _ in
            selected = planner.results.first?.id
            if let route = planner.results.first {
                camera = .region(Self.region(for: planner.results, fallback: route))
            }
        }
        .sheet(item: $presentedMenu, onDismiss: {
            // Present the ride screen only after the plan sheet has finished
            // dismissing; presenting a full-screen cover during dismissal is
            // the classic "presentation in progress" race.
            if pendingRideStart {
                pendingRideStart = false
                showingRide = true
            }
        }) { destination in
            switch destination {
            case .plan:
                PlanView(tab: .constant(0), planner: planner, onStartNavigation: {
                    pendingRideStart = true
                })
            case .history:
                HistoryView()
            case .settings:
                SettingsView()
            case .offline:
                NavigationStack {
                    OfflineView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { presentedMenu = nil }
                                    .font(.headline.weight(.semibold))
                            }
                        }
                }
            case .savedPlaces:
                NavigationStack {
                    SavedPlacesView()
                }
            }
        }
        .fullScreenCover(isPresented: $showingRide) {
            RideView()
        }
        .sheet(isPresented: $showingGarage) {
            NavigationStack {
                GarageView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingGarage = false }
                                .font(.headline.weight(.semibold))
                        }
                    }
            }
        }
        .alert("Save this place?", isPresented: Binding(
            get: { savePlacePrompt != nil },
            set: { if !$0 { savePlacePrompt = nil } }
        )) {
            Button("Save here") {
                guard let place = savePlacePrompt,
                      let coordinate = nav.currentLocation?.coordinate else { return }
                switch place {
                case .home:
                    homeLat = coordinate.latitude; homeLon = coordinate.longitude
                case .work:
                    workLat = coordinate.latitude; workLon = coordinate.longitude
                }
                savePlacePrompt = nil
                useSavedPlace(place, preview: false)
                RevertHaptics.success()
            }
            .disabled(nav.currentLocation == nil)
            if nav.locationDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) { savePlacePrompt = nil }
        } message: {
            if nav.locationDenied {
                Text("Location access is off. Allow it in Settings, then save Home or Work from the map.")
            } else if nav.currentLocation == nil {
                Text("Waiting for a GPS fix. Try again in a moment.")
            } else {
                Text("We'll use your current location as \(savePlacePrompt?.title ?? "this place").")
            }
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
            if UserDefaults.standard.bool(forKey: "intent.endRoute") {
                UserDefaults.standard.set(false, forKey: "intent.endRoute")
                nav.stop()
            }
            if UserDefaults.standard.bool(forKey: "intent.openPlan") {
                UserDefaults.standard.set(false, forKey: "intent.openPlan")
                presentedMenu = .plan
            } else if UserDefaults.standard.bool(forKey: "intent.openGarage") {
                UserDefaults.standard.set(false, forKey: "intent.openGarage")
                showingGarage = true
            }
        }
        .onAppear {
            #if DEBUG
            // Deterministic history/poster data for UI tests and screenshots.
            if CommandLine.arguments.contains("-debugSeedRide") {
                let descriptor = FetchDescriptor<Ride>()
                if (try? context.fetchCount(descriptor)) == 0 {
                    context.insert(DebugScreens.sampleRide())
                    try? context.save()
                }
            }
            #endif
            if recoveredRide == nil, RideJournal.shared.hasPendingRide {
                if let ride = RideJournal.shared.recoveredRide(), ride.points.count > 1 {
                    recoveredRide = ride
                } else {
                    RideJournal.shared.finish()
                }
            }
            if UserDefaults.standard.bool(forKey: "intent.endRoute") {
                UserDefaults.standard.set(false, forKey: "intent.endRoute")
                nav.stop()
            }
            if UserDefaults.standard.bool(forKey: "intent.openPlan") {
                UserDefaults.standard.set(false, forKey: "intent.openPlan")
                presentedMenu = .plan
            } else if UserDefaults.standard.bool(forKey: "intent.openGarage") {
                UserDefaults.standard.set(false, forKey: "intent.openGarage")
                showingGarage = true
            } else if let initialMenu, presentedMenu == nil {
                presentedMenu = initialMenu
            }
            // Migrate offsets saved by the earlier layout editor. Those values
            // could place the search field partly outside the screen.
            guard layoutVersion < 1 else { return }
            menuOffsetX = 0
            menuOffset = 0
            controlsOffsetX = 0
            controlsOffsetY = 0
            layoutVersion = 1
        }
    }

    private var searchRegion: MKCoordinateRegion? {
        guard let origin else { return nil }
        return MKCoordinateRegion(
            center: origin,
            latitudinalMeters: 80_000,
            longitudinalMeters: 80_000
        )
    }

    private func handleSearchChanged(_ value: String) {
        addressError = nil

        // Programmatic text (a saved place or a picked suggestion) is not a
        // query. Without this guard the field's own onChange fires after the
        // pick and reopens the suggestion list for "Home" or a full address.
        if value == committedDestination {
            addressSearch.clear()
            return
        }

        // The rider is editing the destination by hand. The old pin no longer
        // describes what is in the field, so stop showing a route to it.
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
        }
    }

    /// Previews the route to the current destination. When the rider typed a
    /// destination but has not tapped a suggestion yet, resolves that text
    /// first instead of silently doing nothing against a stale pin.
    private func previewRoute() {
        guard let origin else { return }
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
                addressError = "That destination could not be found. Try a more complete address or tap a suggestion."
            }
        }
    }

    private func startNavigation(_ route: PlannedRoute) {
        nav.start(route, roads: planner.roads)
        // The ride screen is where alerts, speed limits and lean angle live.
        showingRide = true
    }

    private func chooseAddress(_ suggestion: AddressSearchService.Suggestion) {
        Task {
            do {
                let coordinate = try await addressSearch.coordinate(for: suggestion)
                // Keep the field and the results header compact; the subtitle
                // is mostly a street address and made both truncate badly.
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
                // Picking a suggestion is a commit; show the route right away
                // instead of making the rider press Preview again.
                rememberDestination(label, coordinate: coordinate)
                if let origin {
                    planner.directions(from: origin, to: coordinate, via: waypoints, preference: preference)
                }
            } catch {
                addressError = "Couldn't load that place. Try another search, or check your connection."
            }
        }
    }

    private func useSavedPlace(_ place: SavedPlace, preview: Bool = true) {
        let coordinate: CLLocationCoordinate2D?
        switch place {
        case .home: coordinate = (homeLat != 0 || homeLon != 0) ? CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon) : nil
        case .work: coordinate = (workLat != 0 || workLon != 0) ? CLLocationCoordinate2D(latitude: workLat, longitude: workLon) : nil
        }
        guard let coordinate else {
            savePlacePrompt = place
            return
        }
        pin = coordinate
        waypoints = []
        committedDestination = place.title
        destinationText = place.title
        addressSearch.clear()
        addressError = nil
        camera = .region(MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 4_000,
                                            longitudinalMeters: 4_000))
        // A saved place is a one-tap destination: show the route immediately
        // instead of leaving the chip looking like a dead control. The one
        // exception is right after saving the place from this exact spot;
        // routing to where the bike is parked is just "you're already there".
        if preview, let origin {
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
        items.insert(RecentDestination(title: trimmed, latitude: coordinate.latitude, longitude: coordinate.longitude), at: 0)
        saveRecentDestinations(Array(items.prefix(5)))
    }

    private func removeRecentDestination(_ recent: RecentDestination) {
        var items = recentDestinations
        items.removeAll { $0 == recent }
        saveRecentDestinations(items)
        RevertHaptics.tap()
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

    private func clearDestination() {
        pin = nil
        waypoints = []
        addingWaypoint = false
        committedDestination = ""
        destinationText = ""
        addressSearch.clear()
        addressError = nil
        planner.clearResults()
        camera = .userLocation(fallback: .automatic)
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

struct DirectionsMap: View {
    @Binding var camera: MapCameraPosition
    let mapStyle: MapStyle
    let pin: CLLocationCoordinate2D?
    let waypoints: [CLLocationCoordinate2D]
    let addingWaypoint: Bool
    let routes: [PlannedRoute]
    let activeRoute: PlannedRoute?
    let selected: UUID?
    let onMapTap: (CLLocationCoordinate2D) -> Void

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let pin {
                    Marker("Destination", coordinate: pin)
                        .tint(.red)
                }
                ForEach(Array(waypoints.enumerated()), id: \.offset) { index, coordinate in
                    Marker("Stop \(index + 1)", coordinate: coordinate)
                        .tint(MapUI.cyan)
                }
                ForEach(routes) { route in
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(
                            route.id == selected ? MapUI.cyan : Color.gray.opacity(0.45),
                            lineWidth: route.id == selected ? 7 : 3
                        )
                }
                // Keep the route visible on the map after its preview sheet is
                // dismissed while navigation is still active.
                if let activeRoute, !routes.contains(where: { $0.id == activeRoute.id }) {
                    MapPolyline(coordinates: activeRoute.coordinates)
                        .stroke(MapUI.emerald.opacity(0.9), lineWidth: 5)
                }
            }
            .mapStyle(mapStyle)
            .ignoresSafeArea()
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .mapControlVisibility(.automatic)
            .overlay(alignment: .top) {
                if addingWaypoint {
                    Label("Tap the map to add a stop", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(MapUI.cyan, in: Capsule())
                        .padding(.top, 64)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        guard addingWaypoint,
                              let coordinate = proxy.convert(event.location, from: .local) else { return }
                        onMapTap(coordinate)
                    }
            )
        }
    }
}

struct DirectionsTopBar: View {
    @Binding var showingMapOptions: Bool
    @Binding var mapStyle: MapStyle

    let onCenter: () -> Void
    let onOpenSettings: () -> Void
    let onOpenRide: () -> Void
    let editingLayout: Bool
    @Binding var controlsOffsetX: Double
    @Binding var controlsOffsetY: Double
    let onEditLayout: () -> Void
    var onCloseMap: (() -> Void)? = nil

    @GestureState private var dragTranslation = CGSize.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RevertMapDock {
                    if let onCloseMap {
                        RevertMapDockButton(
                            systemImage: "chevron.down",
                            label: "Close map and return home"
                        ) {
                            onCloseMap()
                        }

                        RevertMapDockDivider()
                    }

                    Menu {
                        Button {
                            onOpenSettings()
                        } label: {
                            Label("App settings", systemImage: "slider.horizontal.3")
                        }
                        Button {
                            showingMapOptions = true
                        } label: {
                            Label("Map style", systemImage: "map")
                        }
                        Button {
                            onEditLayout()
                        } label: {
                            Label("Customize layout", systemImage: "hand.draw")
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
                        systemImage: "location.north.fill",
                        label: "Center the map on my location"
                    ) {
                        onCenter()
                    }
                }

                Spacer(minLength: 0)

                Button {
                    RevertHaptics.tap()
                    onOpenRide()
                } label: {
                    Label("Ride", systemImage: "speedometer")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(RevertPrimaryButtonStyle(compact: true, stretch: false))
                // Let the label grow with Dynamic Type instead of collapsing
                // to an icon-and-ellipsis at accessibility sizes.
                .frame(minWidth: 108)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityHint("Opens the live riding screen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(
            x: controlsOffsetX + dragTranslation.width,
            y: controlsOffsetY + dragTranslation.height
        )
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    if editingLayout { state = value.translation }
                }
                .onEnded { value in
                    guard editingLayout else { return }
                    controlsOffsetX += value.translation.width
                    controlsOffsetY += value.translation.height
                }
        )
        .confirmationDialog("Map style", isPresented: $showingMapOptions, titleVisibility: .visible) {
            Button("Standard") { mapStyle = .standard(elevation: .flat) }
            Button("Satellite") { mapStyle = .imagery(elevation: .flat) }
            Button("Muted") { mapStyle = .standard(elevation: .flat, pointsOfInterest: .excludingAll) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct DirectionsBottomSheet: View {
    @Binding var destinationText: String
    @Binding var preference: DirectionPreference

    let suggestions: [AddressSearchService.Suggestion]
    let results: [PlannedRoute]
    let selected: UUID?
    let originAvailable: Bool
    let isBusy: Bool
    let isResolvingAddress: Bool
    let phase: RoutePlanner.Phase
    let addressError: String?

    let onSearchChanged: (String) -> Void
    let onSelectSuggestion: (AddressSearchService.Suggestion) -> Void
    let onClear: () -> Void
    let onPreview: () -> Void
    let onSelectRoute: (UUID) -> Void
    let onStart: (PlannedRoute) -> Void
    let onAddFuelStop: (CLLocationCoordinate2D) -> Void
    let waypoints: [CLLocationCoordinate2D]
    let addingWaypoint: Bool
    let onToggleAddWaypoint: () -> Void
    let onSavedPlace: (SavedPlace) -> Void
    let onRemoveWaypoint: (Int) -> Void
    let onOpenMenu: (CentralMenuDestination) -> Void
    let onEditLayout: () -> Void
    let recentDestinations: [RecentDestination]
    let onSelectRecent: (RecentDestination) -> Void
    let onRemoveRecent: (RecentDestination) -> Void
    let onClearRecents: () -> Void
    let editingLayout: Bool
    @Binding var menuOffsetX: Double
    @Binding var menuOffset: Double

    @State private var isExpanded = false
    @GestureState private var sheetDragTranslation = CGSize.zero
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var autoFocusExpanded = false
    @State private var keyboardHeight: CGFloat = 0

    private var showingSuggestions: Bool {
        !suggestions.isEmpty && !destinationText.isEmpty
    }

    /// Surface a failed search/route in the compact sheet too. In compact mode
    /// the error previously had nowhere to render, so a bad address looked
    /// like a dead Preview button.
    private var compactError: String? {
        if let addressError { return addressError }
        if case .failed(let message) = phase { return message }
        return nil
    }

    private var idealSheetHeight: CGFloat {
        let accessibility = dynamicTypeSize.isAccessibilitySize
        // The portrait heights total more than an iPhone's landscape height.
        // A 700 pt sheet in landscape put its header above the top of the
        // screen; compact-height sheets cap at a scrollable panel instead.
        if verticalSizeClass == .compact {
            let extra: CGFloat = accessibility ? 40 : 0
            if !results.isEmpty { return 290 + extra }
            if isExpanded { return 290 + extra }
            if showingSuggestions { return 280 + extra }
            if isBusy || isResolvingAddress || compactError != nil { return 260 + extra }
            if !waypoints.isEmpty { return 250 + extra }
            return 238 + extra
        }
        // Large type needs a taller panel or the Home/Work/Scenic row is
        // clipped off the bottom of the screen.
        if !results.isEmpty { return accessibility ? 580 : 486 }
        if isExpanded { return accessibility ? 760 : 700 }
        if showingSuggestions { return accessibility ? 560 : 468 }
        if isBusy || isResolvingAddress || compactError != nil { return accessibility ? 410 : 330 }
        if !waypoints.isEmpty { return accessibility ? 360 : 286 }
        return accessibility ? 350 : 258
    }

    /// `UIScreen.main` is deprecated in iOS 26. The keyboard frame is reported
    /// in the coordinates of the screen hosting the app, so read that screen
    /// from the active window scene instead of the global "main" screen.
    private var screenBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active.screen.bounds
        }
        return scenes.first?.screen.bounds ?? .zero
    }

    /// Keep the sheet above the keyboard and clear of the status bar. Without
    /// this cap the 700 pt search sheet slid under the notch as soon as the
    /// keyboard appeared and the field was no longer visible.
    private var sheetHeight: CGFloat {
        guard keyboardHeight > 0 else { return idealSheetHeight }
        let available = screenBounds.height - keyboardHeight - 70
        return min(idealSheetHeight, max(280, available))
    }

    private func setExpanded(_ expanded: Bool) {
        guard !editingLayout else { return }
        RevertHaptics.tap()
        withAnimation(RevertMotion.smooth) {
            isExpanded = expanded
        }
    }

    private var waypointBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MapUI.cyan)
                    .frame(width: 24, height: 24)
                    .background(MapUI.cyan.opacity(0.10), in: Circle())

                Text(waypoints.isEmpty ? "Direct route" : "\(waypoints.count) stop\(waypoints.count == 1 ? "" : "s")")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(MapUI.textSecondary)

                Spacer(minLength: 0)

                Button {
                    RevertHaptics.tap()
                    onToggleAddWaypoint()
                } label: {
                    Label(addingWaypoint ? "Done" : "Add stop",
                          systemImage: addingWaypoint ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(addingWaypoint ? .black : MapUI.cyan)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(addingWaypoint ? AnyShapeStyle(MapUI.amber) : AnyShapeStyle(MapUI.surfaceHigh), in: Capsule())
                        .overlay(Capsule().stroke(addingWaypoint ? .clear : MapUI.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            if !waypoints.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(waypoints.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 5) {
                                Text("Stop \(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                Button {
                                    RevertHaptics.tap()
                                    onRemoveWaypoint(index)
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
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                RevertGrabber()
                waypointBar
                    .allowsHitTesting(!editingLayout)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                setExpanded(!isExpanded)
            }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard !editingLayout else { return }
                        if value.translation.height < -35 { setExpanded(true) }
                        if value.translation.height > 35 { setExpanded(false) }
                    }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if results.isEmpty {
                        if isExpanded {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PLAN A RIDE")
                                        .font(RevertType.eyebrow)
                                        .tracking(1.5)
                                        .foregroundStyle(MapUI.cyan)
                                    Text("Search a destination")
                                        .font(.system(.title3, design: .rounded).weight(.bold))
                                        .foregroundStyle(MapUI.ink)
                                }
                                Spacer()
                                Button {
                                    setExpanded(false)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(RevertIconButtonStyle(tint: MapUI.textSecondary, diameter: 34))
                                .accessibilityLabel("Collapse search")
                            }

                            DirectionsSearchContent(
                                destinationText: $destinationText,
                                preference: $preference,
                                suggestions: suggestions,
                                originAvailable: originAvailable,
                                isBusy: isBusy,
                                isResolvingAddress: isResolvingAddress,
                                phase: phase,
                                addressError: addressError,
                                autoFocus: autoFocusExpanded,
                                onSearchChanged: onSearchChanged,
                                onSelectSuggestion: onSelectSuggestion,
                                onClear: onClear,
                                onPreview: onPreview,
                                onSubmit: onPreview
                            )
                            WazeQuickActions(
                                onOpenMenu: onOpenMenu,
                                onEditLayout: onEditLayout,
                                recents: recentDestinations,
                                onSelectRecent: onSelectRecent,
                                onRemoveRecent: onRemoveRecent,
                                onClearRecents: onClearRecents
                            )
                        } else {
                            DirectionsCompactSearch(
                                destinationText: $destinationText,
                                suggestions: suggestions,
                                isBusy: isBusy || isResolvingAddress,
                                errorText: compactError,
                                onSearchChanged: onSearchChanged,
                                onSelectSuggestion: onSelectSuggestion,
                                onClear: onClear,
                                onOpenMenu: onOpenMenu,
                                onSavedPlace: onSavedPlace,
                                onExpand: { setExpanded(true) },
                                onSearchFocus: { autoFocusExpanded = true },
                                onSubmit: onPreview
                            )
                        }
                    } else {
                        DirectionsResultsContent(
                            destinationText: destinationText,
                            preference: preference,
                            results: results,
                            selected: selected,
                            onClear: onClear,
                            onSelectRoute: onSelectRoute,
                            onStart: onStart,
                            onAddFuelStop: onAddFuelStop
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(editingLayout)
            // While arranging the layout a drag can pass over a control. Do
            // not let that change the ride style or open a destination.
            .allowsHitTesting(!editingLayout)
        }
        .frame(height: sheetHeight)
        .frame(maxWidth: .infinity)
        .offset(
            x: menuOffsetX + (editingLayout ? sheetDragTranslation.width : 0),
            y: menuOffset + (editingLayout ? sheetDragTranslation.height : 0)
        )
        .background {
            UnevenRoundedRectangle(topLeadingRadius: RevertMetrics.sheetRadius,
                                   topTrailingRadius: RevertMetrics.sheetRadius)
                .fill(.ultraThinMaterial)
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: RevertMetrics.sheetRadius,
                                           topTrailingRadius: RevertMetrics.sheetRadius)
                        .fill(MapUI.canvas.opacity(0.88))
                }
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: RevertMetrics.sheetRadius,
                                           topTrailingRadius: RevertMetrics.sheetRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [MapUI.cyan.opacity(0.34), .white.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.55), radius: 26, y: -10)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            if editingLayout {
                UnevenRoundedRectangle(topLeadingRadius: RevertMetrics.sheetRadius,
                                       topTrailingRadius: RevertMetrics.sheetRadius)
                    .stroke(MapUI.cyan, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    .allowsHitTesting(false)
            }
        }
        .animation(RevertMotion.smooth, value: sheetHeight)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .updating($sheetDragTranslation) { value, state, _ in
                    if editingLayout { state = value.translation }
                }
                .onEnded { value in
                    guard editingLayout else { return }
                    menuOffsetX += value.translation.width
                    menuOffset += value.translation.height
                }
        )
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-debugSearch") {
                isExpanded = true
            }
            #endif
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { autoFocusExpanded = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = max(0, screenBounds.height - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }
}

struct DirectionsCompactSearch: View {
    @Binding var destinationText: String

    let suggestions: [AddressSearchService.Suggestion]
    let isBusy: Bool
    let errorText: String?
    let onSearchChanged: (String) -> Void
    let onSelectSuggestion: (AddressSearchService.Suggestion) -> Void
    let onClear: () -> Void
    let onOpenMenu: (CentralMenuDestination) -> Void
    let onSavedPlace: (SavedPlace) -> Void
    let onExpand: () -> Void
    let onSearchFocus: () -> Void
    let onSubmit: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PLAN A RIDE")
                        .font(RevertType.eyebrow)
                        .tracking(1.5)
                        .foregroundStyle(MapUI.cyan)
                    Text("Where do you want to go?")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button {
                    onExpand()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(RevertIconButtonStyle(tint: MapUI.textSecondary, diameter: 32))
                .accessibilityLabel("Expand ride planner")
            }

            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(searchFocused ? MapUI.cyan : MapUI.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(
                        (searchFocused ? MapUI.cyan : MapUI.textTertiary).opacity(0.10),
                        in: Circle()
                    )

                TextField("Where to?", text: $destinationText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onChange(of: destinationText) { _, value in
                        onSearchChanged(value)
                    }
                    .onSubmit(onSubmit)
                    .onChange(of: searchFocused) { _, focused in
                        // The compact field sits at the bottom of a short
                        // sheet; opening the keyboard there hides it. Expand
                        // into the full search sheet before typing.
                        if focused {
                            onSearchFocus()
                            onExpand()
                        }
                    }

                if !destinationText.isEmpty {
                    Button {
                        RevertHaptics.tap()
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .accessibilityLabel("Clear destination")
                } else {
                    Button {
                        RevertHaptics.tap()
                        onOpenMenu(.plan)
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(MapUI.amber)
                            .frame(width: 36, height: 36)
                            .background(MapUI.amber.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Plan a scenic loop")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 58)
            .background(MapUI.surfaceHigh, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(searchFocused ? MapUI.cyan.opacity(0.65) : MapUI.lineStrong, lineWidth: 0.9)
            }
            .shadow(color: searchFocused ? MapUI.cyan.opacity(0.18) : .clear, radius: 12)
            .animation(RevertMotion.soft, value: searchFocused)

            if !suggestions.isEmpty && !destinationText.isEmpty {
                AddressSuggestionList(suggestions: suggestions, onSelect: onSelectSuggestion)
            }

            if isBusy {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(MapUI.cyan)
                    Text("Finding the best route…")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.textSecondary)
                    Spacer(minLength: 0)
                }
            }

            if let errorText {
                RevertInfoNote(text: errorText, systemImage: "exclamationmark.circle", tint: MapUI.coral)
            }

            HStack(spacing: 8) {
                compactPlaceButton("Home", systemImage: "house.fill", tint: MapUI.cyan) {
                    onSavedPlace(.home)
                }
                compactPlaceButton("Work", systemImage: "briefcase.fill", tint: MapUI.emerald) {
                    onSavedPlace(.work)
                }
                compactPlaceButton("Scenic", systemImage: "arrow.triangle.2.circlepath", tint: MapUI.amber) {
                    onOpenMenu(.plan)
                }
            }
        }
    }

    private func compactPlaceButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            RevertHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(MapUI.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(MapUI.surfaceHigh.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MapUI.line, lineWidth: 0.8)
            }
        }
        .buttonStyle(RevertCardButtonStyle())
    }
}

struct WazeQuickActions: View {
    let onOpenMenu: (CentralMenuDestination) -> Void
    let onEditLayout: () -> Void
    let recents: [RecentDestination]
    let onSelectRecent: (RecentDestination) -> Void
    let onRemoveRecent: (RecentDestination) -> Void
    let onClearRecents: () -> Void

    @AppStorage("centralMenuOrder") private var storedOrder = CentralMenuItem.defaultOrder.map(\.rawValue).joined(separator: ",")
    @State private var orderedItems = CentralMenuItem.defaultOrder
    @State private var showingEditor = false

    private var menuItems: [CentralMenuItem] {
        let decoded = storedOrder
            .split(separator: ",")
            .compactMap { CentralMenuItem(rawValue: String($0)) }
        let missing = CentralMenuItem.allCases.filter { !decoded.contains($0) }
        return decoded + missing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Explore")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(MapUI.ink)
                Spacer()
                Button {
                    RevertHaptics.tap()
                    onEditLayout()
                } label: {
                    Label("Layout", systemImage: "hand.draw")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(MapUI.textSecondary)
                .buttonStyle(.plain)

                Button {
                    RevertHaptics.tap()
                    showingEditor = true
                } label: {
                    Label("Arrange", systemImage: "arrow.up.arrow.down")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(MapUI.cyan)
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(orderedItems) { item in
                    Button {
                        RevertHaptics.tap()
                        onOpenMenu(item.destination)
                    } label: {
                        HStack(spacing: 9) {
                            RevertIconBadge(
                                systemImage: item.systemImage,
                                tint: item.tint,
                                size: 36,
                                radius: 11
                            )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(MapUI.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(item.subtitle)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(MapUI.surfaceHigh.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(MapUI.line, lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(RevertCardButtonStyle())
                    .accessibilityHint("Opens \(item.title)")
                }
            }

            if recents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MapUI.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(MapUI.surfaceHigh, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recent destinations")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                        Text("Places you search for will appear here.")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(MapUI.surfaceHigh.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .bold))
                        Text("Recent destinations")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Spacer(minLength: 0)
                        Menu {
                            Button(role: .destructive) {
                                onClearRecents()
                            } label: {
                                Label("Clear recents", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Recent destination actions")
                    }
                    .foregroundStyle(MapUI.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 3)

                    ForEach(recents) { recent in
                        HStack(spacing: 4) {
                            Button {
                                RevertHaptics.tap()
                                onSelectRecent(recent)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(MapUI.cyan)
                                        .frame(width: 28, height: 28)
                                        .background(MapUI.cyan.opacity(0.10), in: Circle())
                                    Text(recent.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(MapUI.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MapUI.textTertiary)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RevertCardButtonStyle())

                            Button {
                                RevertHaptics.tap()
                                onRemoveRecent(recent)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                                    .frame(width: 28, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(recent.title) from recents")
                        }
                    }
                }
                .padding(8)
                .background(MapUI.surfaceHigh.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear { orderedItems = menuItems }
        .onChange(of: orderedItems) { _, items in
            storedOrder = items.map(\.rawValue).joined(separator: ",")
        }
        .sheet(isPresented: $showingEditor) {
            MenuItemEditor(items: $orderedItems)
        }
    }
}

struct MenuItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [CentralMenuItem]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(item.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        items.move(fromOffsets: offsets, toOffset: destination)
                    }
                } header: {
                    Text("Drag to arrange your menu")
                } footer: {
                    Text("Your order is saved automatically and used the next time you open the Directions menu.")
                }
            }
            // Reordering is the only thing this screen does, so leave the
            // drag handles visible. The old screen required tapping Edit,
            // which added a second "Done" next to the dismiss button.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct LayoutEditorBanner: View {
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw.fill")
            Text("Drag menu and controls")
                .font(.caption.weight(.bold))
            Button("Reset", action: onReset)
                .font(.caption.weight(.bold))
            Button("Done", action: onDone)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MapUI.accentGradient, in: Capsule())
        .shadow(color: MapUI.shadow, radius: 12, y: 4)
    }
}

struct DirectionsSearchContent: View {
    @Binding var destinationText: String
    @Binding var preference: DirectionPreference

    let suggestions: [AddressSearchService.Suggestion]
    let originAvailable: Bool
    let isBusy: Bool
    let isResolvingAddress: Bool
    let phase: RoutePlanner.Phase
    let addressError: String?
    var autoFocus: Bool = false

    @FocusState private var searchFocused: Bool

    let onSearchChanged: (String) -> Void
    let onSelectSuggestion: (AddressSearchService.Suggestion) -> Void
    let onClear: () -> Void
    let onPreview: () -> Void
    let onSubmit: () -> Void

    private var canPreview: Bool {
        originAvailable && !destinationText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    RevertDot(tint: MapUI.emerald, size: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FROM")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(MapUI.textTertiary)
                        Text("Your location")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                    }
                    Spacer(minLength: 6)
                    if originAvailable {
                        RevertMetricPill(systemImage: "location.fill", text: "GPS ready", tint: MapUI.emerald)
                    } else {
                        RevertStatusPill(text: "Waiting for GPS", tint: MapUI.amber, pulsing: true)
                    }
                }
                .padding(.vertical, 10)

                Rectangle()
                    .fill(MapUI.line)
                    .frame(height: 0.8)
                    .padding(.leading, 20)

                HStack(spacing: 11) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MapUI.coral)
                        .frame(width: 22)

                    TextField("Search destination", text: $destinationText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onChange(of: destinationText) { _, value in
                            onSearchChanged(value)
                        }
                        .onSubmit(onSubmit)
                        .onAppear {
                            guard autoFocus else { return }
                            DispatchQueue.main.async { searchFocused = true }
                        }

                    if !destinationText.isEmpty {
                        Button {
                            RevertHaptics.tap()
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(MapUI.textTertiary)
                        }
                        .accessibilityLabel("Clear destination")
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 14)
            .background(MapUI.surfaceHigh, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(MapUI.lineStrong, lineWidth: 0.9)
            }

            if !suggestions.isEmpty && !destinationText.isEmpty {
                AddressSuggestionList(suggestions: suggestions, onSelect: onSelectSuggestion)
            }

            if let addressError {
                RevertInfoNote(text: addressError, systemImage: "exclamationmark.circle", tint: MapUI.coral)
            }

            VStack(alignment: .leading, spacing: 9) {
                RevertSectionLabel(title: "Ride style", detail: preference.title)
                RevertOptionPicker(
                    options: Array(DirectionPreference.allCases),
                    selection: $preference,
                    title: { $0.title },
                    systemImage: { $0.icon }
                )
                Text(preference.blurb)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isBusy || isResolvingAddress {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(MapUI.cyan)
                    Text(isResolvingAddress ? "Finding that destination…" : "Finding the best route…")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: RevertMetrics.primaryButtonHeight)
                .background(MapUI.surfaceHigh, in: Capsule())
                .overlay(Capsule().stroke(MapUI.line, lineWidth: 0.8))
            } else if canPreview {
                Button(action: onPreview) {
                    Label("Preview route", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .buttonStyle(RevertPrimaryButtonStyle())
            } else {
                RevertInfoNote(
                    text: "Choose a destination to preview a route.",
                    systemImage: "mappin.and.ellipse",
                    tint: MapUI.textTertiary
                )
            }

            if case .failed(let message) = phase {
                RevertInfoNote(text: message, systemImage: "exclamationmark.triangle", tint: MapUI.coral)
            }
        }
    }
}

struct DirectionsResultsContent: View {
    let destinationText: String
    let preference: DirectionPreference
    let results: [PlannedRoute]
    let selected: UUID?

    let onClear: () -> Void
    let onSelectRoute: (UUID) -> Void
    let onStart: (PlannedRoute) -> Void
    let onAddFuelStop: (CLLocationCoordinate2D) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROUTE OPTIONS")
                        .font(RevertType.eyebrow)
                        .tracking(1.5)
                        .foregroundStyle(MapUI.cyan)
                    Text(destinationText.isEmpty ? "Route preview" : destinationText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(2)
                    Text("\(results.count) motorcycle-friendly option\(results.count == 1 ? "" : "s")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
                Spacer(minLength: 6)
                Button {
                    RevertHaptics.tap()
                    onClear()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RevertIconButtonStyle(tint: MapUI.textSecondary, diameter: 34))
                .accessibilityLabel("Close route preview")
            }

            ForEach(Array(results.enumerated()), id: \.element.id) { index, route in
                DirectionsRouteCard(
                    route: route,
                    preference: preference,
                    index: index,
                    isBest: index == 0,
                    isSelected: route.id == selected,
                    onSelect: { onSelectRoute(route.id) },
                    onStart: { onStart(route) }
                )
            }

            if let route = results.first(where: { $0.id == selected }) {
                VStack(alignment: .leading, spacing: 10) {
                    RevertSectionLabel(title: "Ride details", detail: preference.title)

                    SaveRouteButton(route: route, compact: true)

                    DirectionsFuelCard(route: route, onAddStop: onAddFuelStop)

                    if !route.elevationProfile.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .firstTextBaseline) {
                                Label("Elevation", systemImage: "mountain.2")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(MapUI.ink)
                                Spacer()
                                Text("Climb \(Units.elevationText(route.climbMeters))  •  peak \(Units.elevationText(route.maxElevation))")
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(MapUI.cyan)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            RideElevationChart(values: route.elevationProfile.map(\.elevation), totalMeters: route.length)
                                .frame(height: 96)
                            if route.isMountainPassRoute {
                                RevertChip(title: "Mountain pass route", systemImage: "crown.fill", isSelected: false, tint: MapUI.amber)
                            }
                        }
                        .padding(12)
                        .background(MapUI.surfaceHigh.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(MapUI.line, lineWidth: 0.8)
                        }
                    }
                }

                RevertSectionLabel(title: "Turn-by-turn preview")
                    .padding(.top, 2)

                VStack(spacing: 0) {
                    ForEach(Array(route.steps.prefix(5).enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .center, spacing: 11) {
                            Image(systemName: step.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(MapUI.cyan)
                                .frame(width: 30, height: 30)
                                .background(MapUI.cyan.opacity(0.10), in: Circle())

                            Text(step.instruction)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(MapUI.ink)
                                .lineLimit(2)

                            Spacer(minLength: 8)

                            Text(Units.distanceText(step.distance, decimals: 1))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(MapUI.textTertiary)
                        }
                        .padding(.vertical, 9)
                        .accessibilityElement(children: .combine)

                        if index < min(route.steps.count, 5) - 1 {
                            Rectangle()
                                .fill(MapUI.line)
                                .frame(height: 0.7)
                                .padding(.leading, 41)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(MapUI.surfaceHigh.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MapUI.line, lineWidth: 0.8)
                }

                if route.steps.count > 5 {
                    RevertInfoNote(
                        text: "\(route.steps.count - 5) more turns will appear during navigation.",
                        systemImage: "arrow.turn.down.right"
                    )
                }
            }
        }
    }
}

struct DirectionsRouteCard: View {
    let route: PlannedRoute
    let preference: DirectionPreference
    let index: Int
    let isBest: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onStart: () -> Void

    private var optionLetter: String {
        let letters = ["A", "B", "C", "D", "E"]
        return letters[min(max(index, 0), letters.count - 1)]
    }

    private var timeText: String? {
        guard let time = route.expectedTravelTime else { return nil }
        return Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text("OPTION \(optionLetter)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? .black : MapUI.cyan)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(isSelected ? MapUI.cyan : MapUI.cyan.opacity(0.12), in: Capsule())

                if isBest {
                    RevertChip(title: "Best match", systemImage: "sparkles", isSelected: true, tint: MapUI.emerald)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? MapUI.cyan : MapUI.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Units.distanceText(route.length, decimals: 1))
                    .font(RevertType.number(27))
                    .foregroundStyle(MapUI.ink)

                if let timeText {
                    Text(timeText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.textSecondary)
                }

                Spacer(minLength: 4)

                RevertMetricPill(
                    systemImage: preference.icon,
                    text: preference.title,
                    tint: isSelected ? MapUI.cyan : MapUI.textTertiary
                )
            }

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Text("Curves")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { dot in
                            Circle()
                                .fill(dot < route.curviness ? MapUI.amber : MapUI.lineStrong)
                                .frame(width: 4, height: 4)
                        }
                    }
                }

                Rectangle()
                    .fill(MapUI.line)
                    .frame(width: 1, height: 11)

                RevertMetricPill(
                    systemImage: "arrow.triangle.turn.up.right.diamond",
                    text: "\(Int(route.twistPerKm.rounded()))°/km",
                    tint: MapUI.textTertiary
                )

                if route.climbMeters > 0 {
                    Rectangle()
                        .fill(MapUI.line)
                        .frame(width: 1, height: 11)
                    RevertMetricPill(
                        systemImage: "mountain.2",
                        text: Units.elevationText(route.climbMeters),
                        tint: MapUI.textTertiary
                    )
                }

                Spacer(minLength: 0)
            }

            if isSelected {
                Button {
                    RevertHaptics.rigid()
                    onStart()
                } label: {
                    Label("Start navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(RevertPrimaryButtonStyle(minHeight: 48, compact: true))
                .padding(.top, 1)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: [MapUI.cyan.opacity(0.17), MapUI.surfaceHigh],
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
                            ? [MapUI.cyan.opacity(0.75), MapUI.emerald.opacity(0.35)]
                            : [MapUI.lineStrong, MapUI.line],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.2 : 0.8
                )
        }
        .shadow(color: isSelected ? MapUI.cyan.opacity(0.18) : .clear, radius: 16, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSelected else { return }
            RevertHaptics.select()
            withAnimation(RevertMotion.snappy) {
                onSelect()
            }
        }
        .animation(RevertMotion.snappy, value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Option \(optionLetter), \(Units.distanceText(route.length, decimals: 1))\(timeText.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}


struct DirectionsFuelCard: View {
    let route: PlannedRoute
    let onAddStop: (CLLocationCoordinate2D) -> Void

    @AppStorage("fuel.rangeKm") private var rangeKm = 260.0
    @AppStorage("fuel.tankFraction") private var tankFraction = 0.8
    @Query(sort: \Bike.createdAt, order: .reverse) private var garageBikes: [Bike]
    @State private var plan: FuelPlan?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RevertCardHeader(
                icon: "fuelpump.fill",
                title: "Fuel range",
                tint: plan?.needsFuelStop == true ? MapUI.amber : MapUI.emerald,
                trailingText: loading
                    ? nil
                    : plan.map { $0.needsFuelStop ? "\($0.stopsNeeded) stop\($0.stopsNeeded == 1 ? "" : "s") needed" : "No stop needed" }
            )

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(MapUI.cyan)
                    Text("Checking stations along this route…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
            } else if let plan {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Units.distanceText(plan.routeKm * 1_000, decimals: 0)) route")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.textSecondary)
                    Spacer()
                    Text("\(Units.distanceText(plan.usableKm * 1_000, decimals: 0)) usable range")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }

                RevertProgressBar(
                    value: min(max(plan.routeKm / max(plan.usableKm, 1), 0), 1),
                    tint: plan.needsFuelStop ? MapUI.ember : MapUI.aurora,
                    height: 4
                )

                if plan.needsFuelStop {
                    ForEach(plan.suggestions) { suggestion in
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(MapUI.cyan)
                                .frame(width: 28, height: 28)
                                .background(MapUI.cyan.opacity(0.10), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.station.displayName)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(MapUI.ink)
                                    .lineLimit(1)
                                Text("at \(Units.distanceText(suggestion.distanceAlong, decimals: 0))  •  \(Units.shortDistanceText(suggestion.detourMeters)) off route")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                            }

                            Spacer(minLength: 4)

                            Button {
                                RevertHaptics.tap()
                                onAddStop(suggestion.station.coordinate)
                            } label: {
                                Text("Add")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(MapUI.cyan)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(MapUI.cyan.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().stroke(MapUI.cyan.opacity(0.28), lineWidth: 0.7))
                            }
                            .buttonStyle(RevertCardButtonStyle())
                            .accessibilityLabel("Add \(suggestion.station.displayName) as a stop")
                        }
                        .padding(8)
                        .background(MapUI.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if plan.suggestions.isEmpty {
                        RevertInfoNote(
                            text: "No fuel stations were found within \(Units.distanceText(5_000, decimals: 0)) of this route. Plan a manual stop.",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text("Check fuel stations along this route.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                    Spacer(minLength: 6)
                    Button {
                        RevertHaptics.tap()
                        Task { await load() }
                    } label: {
                        Text("Check")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(MapUI.cyan)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(MapUI.cyan.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(RevertCardButtonStyle())
                }
            }
        }
        .padding(14)
        .background(MapUI.surfaceHigh.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MapUI.line, lineWidth: 0.8)
        }
        .task(id: route.id) { await load() }
        .onChange(of: tankFraction) { _, _ in
            // The file has been open while the rider changes the tank level in
            // Settings; recompute instead of keeping the old usable range.
            plan = nil
            Task { await load() }
        }
    }

    private var effectiveRangeKm: Double {
        // An explicitly chosen primary bike wins. With a single bike the
        // Garage may not have promoted it yet, so use the first bike rather
        // than silently falling back to the profile's default range.
        garageBikes.first(where: \.isPrimary)?.fuelRangeKm
            ?? garageBikes.first?.fuelRangeKm
            ?? rangeKm
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        let routeKm = route.length / 1_000
        let usable = max(effectiveRangeKm * min(max(tankFraction, 0.1), 1), 1)
        if routeKm <= usable {
            plan = FuelService.plan(route: route, rangeKm: effectiveRangeKm, tankFraction: tankFraction, stations: [])
            loading = false
            return
        }
        let stations = await FuelService.stations(along: route)
        guard !Task.isCancelled else { loading = false; return }
        plan = FuelService.plan(route: route, rangeKm: effectiveRangeKm, tankFraction: tankFraction, stations: stations)
        loading = false
    }
}
