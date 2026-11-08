import SwiftUI
import SwiftData
import MapKit
import Charts

struct HistoryView: View {
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
                || ride.startDate.formatted(date: .abbreviated, time: .omitted)
                    .localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RiderScreenHeader(
                        eyebrow: "YOUR GARAGE LOG",
                        title: "Ride history",
                        subtitle: "Every route, distance and climb in one place.",
                        systemImage: "clock.arrow.circlepath"
                    )

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
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(MapUI.textTertiary)
                            TextField("Search rides, bikes or dates", text: $query)
                                .font(.system(.subheadline, design: .rounded))
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
                        RiderEmptyState(
                            systemImage: "road.lanes",
                            title: "No rides yet",
                            message: "Import a GPX file to build your history, or start recording from the map.",
                            primaryTitle: "Import a GPX ride",
                            primarySystemImage: "square.and.arrow.down",
                            primaryAction: { importing = true }
                        )
                        .riderCard()
                    } else if filteredRides.isEmpty {
                        RiderInfoNote(
                            text: "No ride matches “\(query)”.",
                            systemImage: "magnifyingglass",
                            tint: MapUI.textTertiary
                        )
                    } else {
                        RideHistorySummary(rides: filteredRides)
                        RideInsightsView(rides: filteredRides)

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
                                        RideHistoryRow(ride: ride)
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
                                            .font(.system(size: 13, weight: .bold))
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
            .background(MapUI.groupedBackground)
            .scrollIndicators(.hidden)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import GPX")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close history")
                }
            }
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
                    RiderDiagnostics.log("GPX import failed for \(failed.count) file(s)")
                    importError = "Couldn't read: " + failed.joined(separator: ", ")
                }
            }
        }
    }
}

struct RideHistoryRow: View {
    let ride: Ride

    var body: some View {
        MapCard {
            HStack(spacing: 14) {
                VStack(spacing: 4) {
                    Image(systemName: "motorcycle")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(MapUI.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(ride.startDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MapUI.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(ride.startDate.formatted(
                        .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                    ))
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
                        Label("\(Int(ride.maxLeanAngleDegrees.rounded()))° lean", systemImage: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(MapUI.magenta)
                    }
                    .font(.caption.weight(.semibold))
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MapUI.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RideInsightsView: View {
    let rides: [Ride]

    private var recent: [Ride] {
        Array(rides.prefix(12).reversed())
    }

    private var bestDistance: Double { rides.map(\.distanceMeters).max() ?? 0 }
    private var bestAverage: Double {
        rides.map { ride in
            ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
        }.max() ?? 0
    }
    private var bestLean: Double { rides.map(\.maxLeanAngleDegrees).max() ?? 0 }
    private var totalTime: Double { rides.reduce(0) { $0 + $1.durationSeconds } }

    var body: some View {
        MapCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Personal bests", systemImage: "trophy.fill")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(rides.count == 1 ? "1 ride" : "All \(rides.count) rides")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MapUI.secondaryInk)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    bestValue("Longest", Units.distanceText(bestDistance, decimals: 1), tint: MapUI.cyan)
                    bestValue("Fastest avg", Units.speedText(bestAverage), tint: MapUI.emerald)
                    bestValue("Max lean", "\(Int(bestLean.rounded()))°", tint: MapUI.magenta)
                    bestValue("Total time", Units.clock(totalTime), tint: MapUI.orange)
                }

                if recent.count > 1 {
                    Chart(recent) { ride in
                        BarMark(
                            x: .value("Date", ride.startDate, unit: .day),
                            y: .value("Distance", Units.distanceValue(ride.distanceMeters))
                        )
                        .foregroundStyle(MapUI.cyan.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4))
                    }
                    .chartYAxisLabel(Units.distanceUnit)
                    .frame(height: 110)
                    .accessibilityLabel("Recent ride distances")
                }
            }
        }
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

struct RideHistorySummary: View {
    let rides: [Ride]

    private var totalDistance: Double { rides.reduce(0) { $0 + $1.distanceMeters } }
    private var totalElevation: Double { rides.reduce(0) { $0 + $1.elevationGainMeters } }
    private var averageDistance: Double { totalDistance / Double(max(rides.count, 1)) }
    private var maxLean: Double { rides.map(\.maxLeanAngleDegrees).max() ?? 0 }

    var body: some View {
        MapCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("All-time snapshot", systemImage: "chart.bar.xaxis")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text("\(rides.count) ride\(rides.count == 1 ? "" : "s")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MapUI.accent)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    summaryValue("Distance", Units.distanceText(totalDistance, decimals: 1), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    summaryValue("Avg distance", Units.distanceText(averageDistance, decimals: 1), systemImage: "chart.line.uptrend.xyaxis")
                    summaryValue("Climbed", Units.elevationText(totalElevation), systemImage: "mountain.2")
                    summaryValue("Top speed", Units.speedText(rides.map(\.maxSpeedMps).max() ?? 0), systemImage: "speedometer")
                }

                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .foregroundStyle(MapUI.magenta)
                    Text("Max lean")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MapUI.secondaryInk)
                    Spacer()
                    Text("\(Int(maxLean.rounded()))°")
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(MapUI.magenta)
                }
                .padding(.top, 2)
            }
        }
    }

    private func summaryValue(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(MapUI.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(MapUI.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }
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
                                        .font(.system(size: 14, weight: .bold))
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

                RiderScreenHeader(
                    eyebrow: "POST-RIDE REVIEW",
                    title: ride.startDate.formatted(date: .abbreviated, time: .omitted),
                    subtitle: "Replay the ride, then study every corner.",
                    systemImage: "flag.checkered"
                )

                heatmapControls

                replayCard

                MapCard {
                    VStack(alignment: .leading, spacing: 12) {
                        RiderSectionLabel(title: "Telemetry", detail: "\(points.count) samples")
                        HStack(spacing: 0) {
                            RiderStatTile(label: "Max lean", value: "\(Int(RideAnalysis.maxLean(points).rounded()))°", tint: MapUI.magenta)
                            Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                            RiderStatTile(label: "Corners", value: "\(turns.count)", tint: MapUI.cyan)
                            Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                            RiderStatTile(label: "Avg speed", value: Units.speedText(RideAnalysis.averageSpeed(points)), tint: MapUI.emerald)
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
                        RiderSectionLabel(title: "Ride data")
                        let averageSpeed = ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
                        RiderKeyValueRow(label: "Distance", value: Units.distanceText(ride.distanceMeters, decimals: 1))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RiderKeyValueRow(label: "Time", value: Units.clock(ride.durationSeconds))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RiderKeyValueRow(label: "Top speed", value: Units.speedText(ride.maxSpeedMps))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RiderKeyValueRow(label: "Average speed", value: Units.speedText(averageSpeed, decimals: 1))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RiderKeyValueRow(label: "Elevation gain", value: Units.elevationText(ride.elevationGainMeters))
                        Rectangle().fill(MapUI.line).frame(height: 0.7)
                        RiderKeyValueRow(label: "Max lean", value: "\(Int(max(ride.maxLeanAngleDegrees, RideAnalysis.maxLean(points)).rounded()))°", tint: MapUI.magenta)
                    }
                }

                turnReview
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(MapUI.groupedBackground)
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
    }

    // MARK: Heat controls

    private var heatmapControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            RiderOptionPicker(
                options: RideHeatMetric.allCases,
                selection: $metric,
                title: { $0.title },
                tint: metric == .speed ? MapUI.cyan : MapUI.magenta
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
                                .foregroundStyle(MapUI.magenta)
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
