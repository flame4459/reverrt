import SwiftUI
import SwiftData
import MapKit
import Charts

struct HistoryView: View {
    /// Hidden when History is a tab instead of a presented sheet.
    var showsCloseButton = true
    /// Hidden on the History tab; the in-content header carries the title.
    var showsNavigationTitle = true

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @Environment(\.modelContext) private var context
    @State private var importing = false
    @State private var importError: String?
    @State private var importProgress: String?
    @State private var ridePendingDelete: Ride?
    @State private var query = ""

    private var filteredRides: [Ride] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return rides }
        return rides.filter { ride in
            ride.bikeDisplayName.localizedCaseInsensitiveContains(needle)
                || (ride.routeName?.localizedCaseInsensitiveContains(needle) ?? false)
                || RevertFormat.mediumDate(ride.startDate)
                    .localizedCaseInsensitiveContains(needle)
        }
    }

    private var maxFilteredDistance: Double {
        filteredRides.map(\.distanceMeters).max() ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        eyebrow: "",
                        title: "Ride history",
                        variant: .compact,
                        identifier: AccessibilityID.History.title
                    ) {
                        HStack(spacing: 8) {
                            PulseCircleButton(
                                systemImage: "square.and.arrow.down",
                                label: "Import GPX",
                                identifier: AccessibilityID.History.importGPX
                            ) {
                                importing = true
                            }
                            if showsCloseButton {
                                PulseCircleButton(
                                    systemImage: "xmark",
                                    tint: Pulse.mutedStrong,
                                    label: "Close history",
                                    identifier: AccessibilityID.History.close
                                ) {
                                    dismiss()
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        NavigationLink {
                            MonthlyFeatureView(rides: rides)
                        } label: {
                            historyFeatureChip("Monthly recap", icon: "calendar")
                        }
                        NavigationLink {
                            CornerFeatureView(rides: rides)
                        } label: {
                            historyFeatureChip("Corners", icon: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        NavigationLink {
                            SegmentFeatureView(rides: rides)
                        } label: {
                            historyFeatureChip("Segments", icon: "scissors")
                        }
                    }

                    if let importProgress {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(MapUI.cyan)
                            Text(importProgress)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(MapUI.surfaceHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !rides.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                                .font(.scaledSystem(size: 13, weight: .bold))
                                .foregroundStyle(MapUI.textTertiary)
                            TextField("Search rides, bikes or dates", text: $query)
                                .font(.system(.subheadline, design: .rounded))
                                .accessibilityIdentifier(AccessibilityID.History.search)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !query.isEmpty {
                                Button {
                                    query = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(MapUI.textTertiary)
                                }
                                .accessibilityLabel("Clear ride search")
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(MapUI.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(MapUI.line, lineWidth: 0.8)
                        }
                    }

                    if rides.isEmpty {
                        RevertEmptyState(
                            systemImage: "road.lanes",
                            title: "No rides yet",
                            message: "Import a GPX file to build your history, or start recording from the Ride tab.",
                            primaryTitle: "Import a GPX ride",
                            primarySystemImage: "square.and.arrow.down",
                            primaryAction: { importing = true }
                        )
                        .revertCard()
                    } else if filteredRides.isEmpty {
                        RevertInfoNote(
                            text: "No ride matches “\(query)”.",
                            systemImage: "magnifyingglass",
                            tint: MapUI.textTertiary
                        )
                    } else {
                        RideStatsOverview(rides: filteredRides)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Recent rides")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundStyle(MapUI.ink)
                                Spacer()
                                Text("\(filteredRides.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                            .padding(.horizontal, 2)

                            ForEach(filteredRides) { ride in
                                HStack(spacing: 8) {
                                    NavigationLink {
                                        RideDetailView(ride: ride)
                                    } label: {
                                        RideHistoryRow(ride: ride, maxDistance: maxFilteredDistance)
                                    }
                                    .buttonStyle(.plain)

                                    Menu {
                                        Button(role: .destructive) {
                                            ridePendingDelete = ride
                                        } label: {
                                            Label("Delete ride", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.scaledSystem(size: 13, weight: .bold))
                                            .foregroundStyle(MapUI.textTertiary)
                                            .frame(width: 32, height: 40)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("Ride actions")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .pulseBackground()
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: GPX.contentTypes,
                allowsMultipleSelection: true
            ) { handleImport($0) }
            .alert("Import problem", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Delete this ride?", isPresented: Binding(
                get: { ridePendingDelete != nil },
                set: { if !$0 { ridePendingDelete = nil } }
            )) {
                Button("Delete ride", role: .destructive) {
                    if let ride = ridePendingDelete { deleteRide(ride) }
                    ridePendingDelete = nil
                }
                Button("Cancel", role: .cancel) { ridePendingDelete = nil }
            } message: {
                Text("The track will be removed from History. This cannot be undone.")
            }
        }
    }

    private func deleteRide(_ ride: Ride) {
        context.delete(ride)
        try? context.save()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importProgress = urls.count == 1
                ? "Importing \(urls[0].lastPathComponent)…"
                : "Importing \(urls.count) files…"
            Task { @MainActor in
                var failed: [String] = []
                for (index, url) in urls.enumerated() {
                    importProgress = "Reading \(index + 1) of \(urls.count)…"
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }

                    let track: GPX.ImportedTrack? = await Task.detached(priority: .userInitiated) {
                        () -> GPX.ImportedTrack? in
                        guard let data = try? Data(contentsOf: url) else { return nil }
                        return GPX.parseTrack(from: data)
                    }.value

                    if let track {
                        context.insert(track.makeRide())
                    } else {
                        failed.append(url.lastPathComponent)
                    }
                }
                try? context.save()
                importProgress = nil
                if !failed.isEmpty {
                    RevertDiagnostics.log("GPX import failed for \(failed.count) file(s)")
                    importError = "Couldn't read: " + failed.joined(separator: ", ")
                }
            }
        }
    }
}

struct RideHistoryRow: View {
    let ride: Ride
    let maxDistance: Double

    var body: some View {
        MapCard {
            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Image(systemName: ride.vehicleKind.icon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(MapUI.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(RevertFormat.shortDate(ride.startDate))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MapUI.secondaryInk)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(RevertFormat.rowDateTime(ride.startDate))
                            .font(.headline)
                            .foregroundStyle(MapUI.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("\(Units.distanceText(ride.distanceMeters, decimals: 1))  •  \(Units.clock(ride.durationSeconds))")
                            .font(.subheadline)
                            .foregroundStyle(MapUI.secondaryInk)
                        HStack(spacing: 10) {
                            Label("Top \(Units.speedText(ride.maxSpeedMps))", systemImage: "speedometer")
                                .foregroundStyle(MapUI.accent)
                            if ride.isCar {
                                Label(ride.vehicleKind.title, systemImage: ride.vehicleKind.icon)
                                    .foregroundStyle(MapUI.emerald)
                            } else {
                                Label("\(Int(ride.maxLeanAngleDegrees.rounded()))° lean", systemImage: "gauge.with.dots.needle.67percent")
                                    .foregroundStyle(Pulse.lean)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MapUI.secondaryInk)
                }

                if maxDistance > 0 {
                    RevertProgressBar(
                        value: min(max(ride.distanceMeters / maxDistance, 0), 1),
                        tint: MapUI.accentGradient,
                        height: 3
                    )
                    .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RideStatsOverview: View {
    let rides: [Ride]

    private var totalDistance: Double { rides.reduce(0) { $0 + $1.distanceMeters } }
    private var totalElevation: Double { rides.reduce(0) { $0 + $1.elevationGainMeters } }
    private var totalTime: Double { rides.reduce(0) { $0 + $1.durationSeconds } }
    private var averageDistance: Double { totalDistance / Double(max(rides.count, 1)) }
    private var longest: Double { rides.map(\.distanceMeters).max() ?? 0 }
    private var topSpeed: Double { rides.map(\.maxSpeedMps).max() ?? 0 }
    private var maxLean: Double { rides.map(\.maxLeanAngleDegrees).max() ?? 0 }
    private var hasMotorcycle: Bool { rides.contains { $0.vehicleKind == .motorcycle } }
    private var bestAverageSpeed: Double {
        rides.map { ride in
            ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
        }.max() ?? 0
    }

    var body: some View {
        MapCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Ride stats", systemImage: "chart.bar.xaxis")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(rides.count == 1 ? "1 ride" : "\(rides.count) rides")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MapUI.accent)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Units.distanceText(totalDistance, decimals: 1))
                        .font(.scaledSystem(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MapUI.accent)
                    Text("total distance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MapUI.secondaryInk)
                }

                HStack(spacing: 0) {
                    miniStat("Avg ride", Units.distanceText(averageDistance, decimals: 1))
                    miniDivider
                    miniStat("Time", RevertFormat.duration(totalTime))
                    miniDivider
                    miniStat("Climbed", Units.elevationText(totalElevation))
                }

                Rectangle()
                    .fill(MapUI.line)
                    .frame(height: 0.8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    bestValue("Longest", Units.distanceText(longest, decimals: 1), tint: MapUI.accent)
                    bestValue("Fastest avg", Units.speedText(bestAverageSpeed), tint: MapUI.emerald)
                    if hasMotorcycle {
                        bestValue("Max lean", "\(Int(maxLean.rounded()))°", tint: Pulse.lean)
                    } else {
                        bestValue("Cars", "\(rides.filter(\.isCar).count)", tint: MapUI.emerald)
                    }
                    bestValue("Top speed", Units.speedText(topSpeed), tint: MapUI.accent)
                }
            }
        }
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.scaledSystem(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MapUI.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MapUI.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var miniDivider: some View {
        Rectangle()
            .fill(MapUI.line)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }

    private func bestValue(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MapUI.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func historyFeatureChip(_ title: String, icon: String) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon)
            .font(.scaledSystem(size: 9, weight: .bold))
        Text(title)
            .font(.scaledSystem(size: 9.5, weight: .semibold, design: .rounded))
    }
    .foregroundStyle(MapUI.cyan)
    .padding(.horizontal, 9)
    .frame(height: 28)
    .background(MapUI.cyan.opacity(0.10), in: Capsule())
}

struct RideDetailView: View {
    let ride: Ride
    @State private var points: [RidePoint] = []
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var heatSegments: [RideHeatSegment] = []
    @State private var turns: [RideTurn] = []
    @State private var elevation: [Double] = []
    @State private var metric: RideHeatMetric = .speed
    @State private var camera: MapCameraPosition = .automatic
    @State private var replayIndex = 0
    @State private var isReplaying = false
    @State private var replayTask: Task<Void, Never>?
    @State private var gpxURL: URL?
    @State private var showingPoster = false
    @State private var showingRivals = false
    @Environment(NavigationManager.self) private var nav
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]

    private var currentPoint: RidePoint? {
        guard points.indices.contains(replayIndex) else { return nil }
        return points[replayIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MapCard {
                    Map(position: $camera) {
                        if routeCoordinates.count > 1 {
                            MapPolyline(coordinates: routeCoordinates)
                                .stroke(MapUI.cyan.opacity(0.28), lineWidth: 8)
                        }
                        ForEach(heatSegments) { segment in
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(segment.color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        }
                        ForEach(turns) { turn in
                            Annotation("", coordinate: turn.coordinate, anchor: .center) {
                                Circle()
                                    .fill(turn.direction > 0 ? MapUI.cyan : MapUI.emerald)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1))
                            }
                        }
                        if let currentPoint {
                            Annotation("Replay", coordinate: currentPoint.coordinate, anchor: .center) {
                                ZStack {
                                    Circle().fill(MapUI.pitchBlack).frame(width: 30, height: 30)
                                    Image(systemName: "motorcycle.fill")
                                        .font(.scaledSystem(size: 14, weight: .bold))
                                        .foregroundStyle(MapUI.cyan)
                                    Circle().stroke(MapUI.cyan, lineWidth: 1.5).frame(width: 30, height: 30)
                                }
                                .shadow(color: MapUI.cyan.opacity(0.6), radius: 8)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                RevertScreenHeader(
                    eyebrow: "POST-RIDE REVIEW",
                    title: RevertFormat.mediumDate(ride.startDate),
                    subtitle: "Replay the ride, then study every corner.",
                    systemImage: "flag.checkered"
                )

                heatmapControls

                replayCard

                MapCard {
                    VStack(alignment: .leading, spacing: 12) {
                        RevertSectionLabel(title: "Telemetry", detail: "\(points.count) samples")
                        HStack(spacing: 0) {
                            if ride.isCar {
                                RevertStatTile(label: "Vehicle", value: ride.vehicleKind.title, tint: MapUI.emerald)
                            } else {
                                RevertStatTile(label: "Max lean", value: "\(Int(RideAnalysis.maxLean(points).rounded()))°", tint: Pulse.lean)
                            }
                            Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                            RevertStatTile(label: "Corners", value: "\(turns.count)", tint: MapUI.cyan)
                            Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                            RevertStatTile(label: "Avg speed", value: Units.speedText(RideAnalysis.averageSpeed(points)), tint: MapUI.emerald)
                        }
                        if !elevation.isEmpty {
                            Rectangle().fill(MapUI.line).frame(height: 0.8)
                            RideElevationChart(values: elevation, totalMeters: ride.distanceMeters)
                                .frame(height: 130)
                        }
                    }
                }

                MapCard {
                    VStack(alignment: .leading, spacing: 10) {
                        RevertSectionLabel(title: "Ride data")
                        let averageSpeed = ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
                        RevertKeyValueRow(label: "Distance", value: Units.distanceText(ride.distanceMeters, decimals: 1))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RevertKeyValueRow(label: "Time", value: Units.clock(ride.durationSeconds))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RevertKeyValueRow(label: "Top speed", value: Units.speedText(ride.maxSpeedMps))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RevertKeyValueRow(label: "Average speed", value: Units.speedText(averageSpeed, decimals: 1))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RevertKeyValueRow(label: "Elevation gain", value: Units.elevationText(ride.elevationGainMeters))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        if ride.isCar {
                            RevertKeyValueRow(label: "Vehicle", value: ride.vehicleKind.title, tint: MapUI.emerald)
                        } else {
                            RevertKeyValueRow(label: "Max lean", value: "\(Int(max(ride.maxLeanAngleDegrees, RideAnalysis.maxLean(points)).rounded()))°", tint: Pulse.lean)
                        }
                    }
                }

                turnReview
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle("Ride")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-debugPoster") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showingPoster = true
                }
            }
            #endif
        }
        .onDisappear {
            replayTask?.cancel()
            replayTask = nil
            isReplaying = false
        }
        .toolbar {
            if let gpxURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: gpxURL)
                }
            }
            if ride.routeKey != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingRivals = true
                    } label: {
                        Image(systemName: "trophy")
                    }
                    .accessibilityLabel("Rivals for this ride")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        rideAgain()
                    } label: {
                        Label("Ride it again", systemImage: "arrow.clockwise")
                    }
                    NavigationLink {
                        CornerReportDetailView(ride: ride)
                    } label: {
                        Label("Corner report", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                    NavigationLink {
                        SegmentDetailView(ride: ride)
                    } label: {
                        Label("Segment hunt", systemImage: "scissors")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Ride data actions")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPoster = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .accessibilityLabel("Create a story poster")
                // Poster rendering needs the decoded track; tapping before
                // load() finishes used to open a blank poster.
                .disabled(points.isEmpty)
            }
        }
        .sheet(isPresented: $showingPoster) {
            StoryPosterStudio(ride: ride, points: points, turns: turns)
        }
        .sheet(isPresented: $showingRivals) {
            RouteLeaderboardView(
                title: ride.routeName ?? "This loop",
                routeKey: ride.routeKey ?? "",
                savedRouteID: ride.savedRouteID,
                routeName: ride.routeName,
                laps: max(ride.laps, 1),
                isSprint: ride.isSprint
            )
        }
    }

    private func rideAgain() {
        let saved = ride.savedRouteID.flatMap { id in savedRoutes.first { $0.id == id } }
            ?? (ride.routeKey.flatMap { key in savedRoutes.first { $0.fingerprintKey == key } })
        guard let route = RideAgainRoute.make(ride: ride, saved: saved) else { return }
        RevertHaptics.success()
        FeatureRideLauncher.start(route: route, roads: saved?.roads ?? [], nav: nav)
    }

    // MARK: Heat controls

    private var heatmapControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            RevertOptionPicker(
                options: RideHeatMetric.allCases,
                selection: $metric,
                title: { $0.title },
                tint: metric == .speed ? MapUI.cyan : Pulse.lean
            )
            .onChange(of: metric) { _, newValue in
                heatSegments = RideAnalysis.heatSegments(from: points, metric: newValue)
            }

            HStack(spacing: 12) {
                legendDot("Low", color: metric == .speed ? Color(red: 0.18, green: 0.55, blue: 1.0) : MapUI.cyan)
                legendDot("Pace", color: MapUI.emerald)
                legendDot("Fast", color: MapUI.orange)
                legendDot("Peak", color: MapUI.magenta)
                Spacer()
                Text(metric == .speed ? "Speed along the track" : "Signed lean along the track")
                    .font(.caption2)
                    .foregroundStyle(MapUI.secondaryInk)
            }
        }
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2.weight(.semibold))
        }
    }

    // MARK: Replay

    private var replayCard: some View {
        MapCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        toggleReplay()
                    } label: {
                        Image(systemName: isReplaying ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(MapUI.pitchBlack, in: Circle())
                            .overlay(Circle().stroke(MapUI.fiberOpticBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(points.isEmpty)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ride replay")
                            .font(.headline.weight(.bold))
                        Text(currentPoint.map {
                            "\(Units.speedText($0.speed))  •  \(Int(abs($0.lean ?? 0).rounded()))° lean  •  \(Units.elevationText($0.alt))"
                        } ?? "No track data")
                            .font(.caption)
                            .foregroundStyle(MapUI.secondaryInk)
                    }
                    Spacer()
                    Text("\(min(replayIndex + 1, max(points.count, 1)))/\(points.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MapUI.secondaryInk)
                }

                Slider(
                    value: Binding(
                        get: { Double(replayIndex) },
                        set: { value in
                            replayIndex = min(max(Int(value), 0), max(points.count - 1, 0))
                            followReplay()
                        }
                    ),
                    in: 0...Double(max(points.count - 1, 1))
                )
                .tint(MapUI.cyan)
                .disabled(points.isEmpty)
            }
        }
    }

    private func toggleReplay() {
        if isReplaying {
            isReplaying = false
            replayTask?.cancel()
            replayTask = nil
            return
        }
        guard points.count > 1 else { return }
        if replayIndex >= points.count - 2 { replayIndex = 0 }
        isReplaying = true
        replayTask?.cancel()
        replayTask = Task { @MainActor in
            while !Task.isCancelled, isReplaying {
                if replayIndex >= points.count - 1 {
                    isReplaying = false
                    break
                }
                // Faster than real time, but slow enough to read the corner.
                let speed = max(points[replayIndex].speed, 6)
                let step = Int(max(1, speed / 5))
                replayIndex = min(replayIndex + step, points.count - 1)
                followReplay()
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }
    }

    private func followReplay() {
        guard points.indices.contains(replayIndex) else { return }
        camera = .camera(MapCamera(
            centerCoordinate: points[replayIndex].coordinate,
            distance: 900,
            heading: 0,
            pitch: 45
        ))
    }

    // MARK: Turn review

    private var turnReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Turn-by-turn review")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(turns.count) corners")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MapUI.secondaryInk)
            }

            if turns.isEmpty {
                Text("Not enough track data to detect corners.")
                    .font(.footnote)
                    .foregroundStyle(MapUI.secondaryInk)
            } else {
                ForEach(turns) { turn in
                    Button {
                        replayIndex = turn.apexIndex
                        followReplay()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: turn.direction > 0 ? "arrow.turn.up.right" : "arrow.turn.up.left")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(turn.direction > 0 ? MapUI.cyan : MapUI.emerald)
                                .frame(width: 34, height: 34)
                                .background(MapUI.panelElevated, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(turn.label) · \(Int(abs(points[turn.apexIndex].lean ?? 0).rounded()))° lean")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MapUI.ink)
                                Text("\(Units.speedText(turn.speed)) at apex")
                                    .font(.caption)
                                    .foregroundStyle(MapUI.secondaryInk)
                            }
                            Spacer()
                            Text("\(Int(turn.peakLean.rounded()))°")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Pulse.lean)
                        }
                        .padding(10)
                        .background(MapUI.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(MapUI.hairline, lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        let data = ride.pointsData
        let decoded = await Task.detached(priority: .userInitiated) {
            (try? JSONDecoder().decode([RidePoint].self, from: data)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        points = decoded
        routeCoordinates = decoded.map(\.coordinate)
        turns = RideAnalysis.turns(from: decoded)
        elevation = RideAnalysis.elevationProfile(decoded)
        heatSegments = RideAnalysis.heatSegments(from: decoded, metric: metric)
        replayIndex = 0

        if let first = decoded.first {
            var minLat = first.lat
            var maxLat = first.lat
            var minLon = first.lon
            var maxLon = first.lon
            for point in decoded {
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLon = min(minLon, point.lon)
                maxLon = max(maxLon, point.lon)
            }
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            camera = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: max((maxLat - minLat) * 1.35, 0.01),
                    longitudeDelta: max((maxLon - minLon) * 1.35, 0.01)
                )
            ))
        }
        let start = ride.startDate
        gpxURL = await Task.detached(priority: .utility) {
            GPX.writeTempFile(points: decoded, startDate: start)
        }.value
    }
}

struct RideElevationChart: View {
    let values: [Double]
    let totalMeters: Double

    private var distanceDivisor: Double {
        Units.isMetric ? 1_000 : 1_609.344
    }

    private var elevationScale: Double {
        Units.isMetric ? 1 : 3.28084
    }

    private var samples: [(distance: Double, elevation: Double)] {
        guard values.count > 1 else { return [] }
        let step = max(1, values.count / 220)
        var output: [(Double, Double)] = []
        for index in stride(from: 0, to: values.count, by: step) {
            let fraction = Double(index) / Double(values.count - 1)
            // Stored samples are metres; convert them with the axis label so
            // the imperial chart is not plotting metres under a "ft" label.
            output.append((fraction * totalMeters / distanceDivisor, values[index] * elevationScale))
        }
        return output
    }

    var body: some View {
        Chart(samples, id: \.distance) { sample in
            AreaMark(x: .value("Distance", sample.distance), y: .value("Elevation", sample.elevation))
                .foregroundStyle(LinearGradient(colors: [MapUI.cyan.opacity(0.35), .clear],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Distance", sample.distance), y: .value("Elevation", sample.elevation))
                .foregroundStyle(MapUI.cyan)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxisLabel(Units.distanceUnit)
        .chartYAxisLabel(Units.elevationUnit)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
    }
}
