import SwiftUI
import MapKit
import CoreLocation

/// Road-to-road sprint builder. A sprint is a one-way timed run: the rider
/// picks where it starts and where it ends, the clock starts at the start line
/// and stops at the finish. It is deliberately separate from the circuit
/// planner, which is about loops and laps.
struct SprintPlannerView: View {
    var onStart: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var nav

    @State private var planner = RoutePlanner()
    @State private var startSearch = AddressSearchService()
    @State private var finishSearch = AddressSearchService()

    @State private var startText = ""
    @State private var finishText = ""
    @State private var startLabel = ""
    @State private var finishLabel = ""
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var finishCoordinate: CLLocationCoordinate2D?

    @State private var preference: DirectionPreference = .sporty
    @State private var activeField: Field = .start
    @FocusState private var focusedField: Field?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selected: UUID?
    @State private var pendingVehicleRoute: PendingVehicleRoute?
    @State private var showingVehicleChoice = false
    @State private var resolving = false
    @State private var error: String?

    private enum Field: Hashable { case start, finish }

    private var origin: CLLocationCoordinate2D? {
        nav.lastLocation?.coordinate ?? nav.currentLocation?.coordinate
    }

    private var searchRegion: MKCoordinateRegion? {
        origin.map { MKCoordinateRegion(center: $0, latitudinalMeters: 100_000, longitudinalMeters: 100_000) }
    }

    private var selectedRoute: PlannedRoute? {
        planner.results.first(where: { $0.id == selected }) ?? planner.results.first
    }

    private var suggestions: [AddressSearchService.Suggestion] {
        focusedField == nil ? [] : (activeField == .start ? startSearch.suggestions : finishSearch.suggestions)
    }

    private var isBusy: Bool { resolving || planner.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                routeFields

                if !suggestions.isEmpty {
                    AddressSuggestionList(suggestions: suggestions, onSelect: chooseSuggestion)
                        .padding(.horizontal, 2)
                }

                preferenceCard
                mapCard

                if let route = selectedRoute {
                    routeSummary(route)
                } else if !isBusy {
                    buildButton
                }

                if isBusy {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small).tint(Pulse.accent)
                        Text(planner.phase == .routing ? "Tracing the sprint…" : "Finding the roads…")
                            .font(.scaledSystem(size: 11))
                            .foregroundStyle(Pulse.muted)
                    }
                    .padding(.horizontal, 4)
                }

                if let message = error ?? phaseError {
                    PulseRouteNote(text: message, systemImage: "exclamationmark.triangle.fill", tint: Pulse.warning)
                }

                footnote
            }
            .padding(.horizontal, PulseMetrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .pulseBackground()
        .preferredColorScheme(.dark)
        .onAppear {
            centreOnOrigin()
            #if DEBUG
            if CommandLine.arguments.contains("-debugSprintDemo") {
                startText = "Golden Gate Bridge"
                startLabel = startText
                finishText = "Twin Peaks"
                finishLabel = finishText
                startCoordinate = CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783)
                finishCoordinate = CLLocationCoordinate2D(latitude: 37.7544, longitude: -122.4477)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    guard planner.results.isEmpty, !resolving else { return }
                    build()
                }
            }
            #endif
        }
        .onChange(of: startText) { _, value in
            guard activeField == .start else { return }
            if value != startLabel { startCoordinate = nil }
            startSearch.update(query: value, region: searchRegion)
        }
        .onChange(of: finishText) { _, value in
            guard activeField == .finish else { return }
            if value != finishLabel { finishCoordinate = nil }
            finishSearch.update(query: value, region: searchRegion)
        }
        .onChange(of: planner.results.first?.id) { _, _ in
            guard let route = planner.results.first else { return }
            selected = route.id
            applyNameToResults()
            camera = .region(Self.region(for: route))
            #if DEBUG
            if CommandLine.arguments.contains("-debugSprintStart") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    guard let current = selectedRoute else { return }
                    start(current)
                }
            }
            #endif
        }
        .confirmationDialog("Car or bike today?",
                            isPresented: $showingVehicleChoice,
                            titleVisibility: .visible,
                            presenting: pendingVehicleRoute) { pending in
            Button("Bike") { beginVehicleStart(pending, kind: .motorcycle) }
            Button("Car") { beginVehicleStart(pending, kind: .car) }
            Button("Cancel") { pendingVehicleRoute = nil }
        } message: { _ in
            Text("This choice changes the cockpit and the vehicle noted on the leaderboard. Garage default: \(VehiclePreferences.primaryKind.title).")
        }
    }

    // MARK: Header & fields

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ROAD TO ROAD")
                    .font(PulseType.eyebrow)
                    .tracking(1.8)
                    .foregroundStyle(Pulse.accent)
                Text("Sprint")
                    .font(PulseType.display(32))
                    .tracking(-0.6)
                    .foregroundStyle(Pulse.ink)
                Text("Pick a start and a finish. One run, timed from the start line.")
                    .font(.scaledSystem(size: 12))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                RevertHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.scaledSystem(size: 13, weight: .bold))
                    .foregroundStyle(Pulse.mutedStrong)
                    .frame(width: 38, height: 38)
                    .background(Pulse.panelHigh, in: Circle())
                    .overlay(Circle().stroke(Pulse.lineSoft, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close sprint planner")
        }
    }

    private var routeFields: some View {
        VStack(spacing: 0) {
            fieldRow(
                eyebrow: "START",
                systemImage: "circle.fill",
                tint: Pulse.emerald,
                placeholder: "Start road or place",
                text: $startText,
                field: .start
            )

            if origin != nil, startCoordinate == nil || startLabel != "My location" {
                Button {
                    RevertHaptics.tap()
                    guard let origin else { return }
                    startCoordinate = origin
                    startLabel = "My location"
                    startText = "My location"
                    startSearch.clear()
                    activeField = .finish
                    focusedField = .finish
                } label: {
                    Label("Start where I am", systemImage: "location.fill")
                        .font(.scaledSystem(size: 10, weight: .bold))
                        .foregroundStyle(Pulse.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, 45)
                .padding(.bottom, 10)
            }

            Rectangle().fill(Pulse.lineSoft).frame(height: 0.8).padding(.leading, 45)

            fieldRow(
                eyebrow: "FINISH",
                systemImage: "flag.checkered",
                tint: Pulse.warning,
                placeholder: "Finish road or place",
                text: $finishText,
                field: .finish
            )
        }
        .padding(.vertical, 2)
        .pulseCard(padding: 14)
    }

    private func fieldRow(
        eyebrow: String,
        systemImage: String,
        tint: Color,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.scaledSystem(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.scaledSystem(size: 8, weight: .heavy))
                    .tracking(1.3)
                    .foregroundStyle(Pulse.muted)
                TextField(placeholder, text: text)
                    .font(.scaledSystem(size: 14, weight: .semibold))
                    .foregroundStyle(Pulse.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: field)
                    .onTapGesture {
                        activeField = field
                    }
                    .onSubmit {
                        focusedField = field == .start ? .finish : nil
                        activeField = field == .start ? .finish : field
                    }
            }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    if field == .start {
                        startCoordinate = nil
                        startLabel = ""
                        startSearch.clear()
                    } else {
                        finishCoordinate = nil
                        finishLabel = ""
                        finishSearch.clear()
                    }
                    planner.clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaledSystem(size: 14))
                        .foregroundStyle(Pulse.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(field == .start ? "Clear start" : "Clear finish")
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            activeField = field
            focusedField = field
        }
    }

    // MARK: Preference

    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Route flavour")

            HStack(spacing: 7) {
                ForEach(DirectionPreference.allCases) { option in
                    RevertChip(
                        title: option.title,
                        isSelected: preference == option,
                        tint: Pulse.accent,
                        action: {
                            RevertHaptics.select()
                            preference = option
                            rebuildIfReady()
                        }
                    )
                }
            }

            Text(preference.blurb)
                .font(.scaledSystem(size: 10.5))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pulseCard(padding: 14)
    }

    // MARK: Map

    private var mapCard: some View {
        Map(position: $camera) {
            if let route = selectedRoute, route.coordinates.count > 1 {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Pulse.accent.opacity(0.28), lineWidth: 9)
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Pulse.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let startCoordinate {
                Annotation("Start", coordinate: startCoordinate, anchor: .center) {
                    pin(color: Pulse.emerald, systemImage: "circle.fill")
                }
            }
            if let finishCoordinate {
                Annotation("Finish", coordinate: finishCoordinate, anchor: .center) {
                    pin(color: Pulse.warning, systemImage: "flag.checkered")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .frame(height: 235)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Pulse.lineSoft, lineWidth: 0.8)
        }
        .overlay(alignment: .topLeading) {
            Text("SPRINT")
                .font(.scaledSystem(size: 8, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Pulse.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Pulse.canvas.opacity(0.82), in: Capsule())
                .padding(10)
        }
    }

    private func pin(color: Color, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.scaledSystem(size: 12, weight: .bold))
            .foregroundStyle(Pulse.canvas)
            .frame(width: 26, height: 26)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 2))
            .shadow(color: color.opacity(0.5), radius: 7)
    }

    // MARK: Result

    private var buildButton: some View {
        Button {
            RevertHaptics.rigid()
            build()
        } label: {
            Label("Build sprint", systemImage: "flag.checkered")
        }
        .buttonStyle(PulsePrimaryButtonStyle())
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
    }

    private func routeSummary(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Units.distanceText(route.length, decimals: 1))
                    .font(PulseType.number(32))
                    .tracking(-1)
                    .foregroundStyle(Pulse.ink)
                if let time = route.expectedTravelTime {
                    Text(Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .font(.scaledSystem(size: 11, weight: .semibold))
                        .foregroundStyle(Pulse.mutedStrong)
                }
                Spacer(minLength: 0)
                PulseTag(text: "Sprint", tint: Pulse.warning)
            }

            Text(route.displayName ?? "Start to finish")
                .font(.scaledSystem(size: 12, weight: .semibold))
                .foregroundStyle(Pulse.mutedStrong)
                .lineLimit(2)

            HStack(spacing: 9) {
                Button {
                    RevertHaptics.success()
                    start(route)
                } label: {
                    Label("Start sprint", systemImage: "flag.checkered")
                }
                .buttonStyle(PulsePrimaryButtonStyle())

                SaveRouteButton(route: route, roads: planner.roads, compact: true)
                    .frame(height: 50)
            }

            Button {
                RevertHaptics.tap()
                planner.clearResults()
                build()
            } label: {
                Label("Rebuild with these settings", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PulseGhostButtonStyle(minHeight: 42))
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

    private var footnote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "timer")
                .font(.scaledSystem(size: 10, weight: .bold))
                .padding(.top, 2)
            Text("The clock starts when you reach the start line and stops at the finish. The ride from home to the start is guided but not timed.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaledSystem(size: 10))
        .foregroundStyle(Pulse.muted)
        .padding(.top, 2)
    }

    // MARK: Actions

    private func build() {
        focusedField = nil
        error = nil
        let startQuery = startText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finishQuery = finishText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !startQuery.isEmpty, !finishQuery.isEmpty else {
            error = "Pick a start road and a finish road first."
            return
        }
        guard !resolving else { return }
        resolving = true

        Task { @MainActor in
            defer { resolving = false }
            do {
                let from: CLLocationCoordinate2D
                if let startCoordinate {
                    from = startCoordinate
                } else {
                    from = try await startSearch.coordinate(forQuery: startQuery, region: searchRegion)
                }

                let to: CLLocationCoordinate2D
                if let finishCoordinate {
                    to = finishCoordinate
                } else {
                    to = try await finishSearch.coordinate(forQuery: finishQuery, region: searchRegion)
                }

                let metres = CLLocation(latitude: from.latitude, longitude: from.longitude)
                    .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
                guard metres > 50 else {
                    error = "The start and finish are in the same place. Pick roads further apart."
                    return
                }

                startCoordinate = from
                finishCoordinate = to
                startLabel = startQuery
                finishLabel = finishQuery
                startSearch.clear()
                finishSearch.clear()
                camera = .region(MKCoordinateRegion(center: from,
                                                    latitudinalMeters: max(metres * 1.6, 1_500),
                                                    longitudinalMeters: max(metres * 1.6, 1_500)))
                planner.directions(from: from, to: to, via: [], preference: preference, kind: .sprint)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func rebuildIfReady() {
        guard startCoordinate != nil, finishCoordinate != nil else { return }
        planner.clearResults()
        build()
    }

    private func chooseSuggestion(_ suggestion: AddressSearchService.Suggestion) {
        let isStart = activeField == .start
        Task { @MainActor in
            do {
                let coordinate = try await (isStart ? startSearch : finishSearch).coordinate(for: suggestion)
                let label = suggestion.title.isEmpty ? suggestion.subtitle : suggestion.title
                if isStart {
                    startCoordinate = coordinate
                    startLabel = label
                    startText = label
                    startSearch.clear()
                    activeField = .finish
                    focusedField = .finish
                } else {
                    finishCoordinate = coordinate
                    finishLabel = label
                    finishText = label
                    finishSearch.clear()
                    focusedField = nil
                }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func start(_ route: PlannedRoute) {
        pendingVehicleRoute = PendingVehicleRoute(route: route, roads: planner.roads)
        showingVehicleChoice = true
    }

    private func beginVehicleStart(_ pending: PendingVehicleRoute, kind: VehicleKind) {
        var route = pending.route
        if route.displayName == nil {
            route.displayName = displayName
        }
        nav.start(route, roads: pending.roads, vehicleKind: kind)
        pendingVehicleRoute = nil
        onStart()
        dismiss()
    }

    private var displayName: String {
        let start = startLabel.isEmpty ? startText : startLabel
        let finish = finishLabel.isEmpty ? finishText : finishLabel
        return "\(start) → \(finish)"
    }

    private func applyNameToResults() {
        guard !planner.results.isEmpty else { return }
        let name = displayName
        guard planner.results.contains(where: { $0.displayName != name }) else { return }
        planner.results = planner.results.map { route in
            var route = route
            route.displayName = name
            return route
        }
    }

    private func centreOnOrigin() {
        if let origin {
            camera = .region(MKCoordinateRegion(center: origin,
                                                latitudinalMeters: 6_000,
                                                longitudinalMeters: 6_000))
        }
    }

    private var phaseError: String? {
        if case .failed(let message) = planner.phase { return message }
        return nil
    }

    private static func region(for route: PlannedRoute) -> MKCoordinateRegion {
        guard let first = route.points.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                      latitudinalMeters: 1_000, longitudinalMeters: 1_000)
        }
        var minLat = first.lat, maxLat = first.lat
        var minLon = first.lon, maxLon = first.lon
        for point in route.points {
            minLat = min(minLat, point.lat)
            maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon)
            maxLon = max(maxLon, point.lon)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.35, 0.01),
                                   longitudeDelta: max((maxLon - minLon) * 1.35, 0.01))
        )
    }
}
