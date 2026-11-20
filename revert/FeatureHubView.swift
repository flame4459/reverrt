import SwiftUI
import MapKit
import SwiftData
import CoreLocation

extension Notification.Name {
    static let revertFeatureRideStarted = Notification.Name("revert.feature.ride.started")
}

@MainActor
enum FeatureRideLauncher {
    static func start(route: PlannedRoute, roads: [Road], nav: NavigationManager) {
        nav.start(route, roads: roads, vehicleKind: VehiclePreferences.activeKind)
        UserDefaults.standard.set(true, forKey: "intent.openRide")
        NotificationCenter.default.post(name: .revertOpenIntent, object: nil)
        NotificationCenter.default.post(name: .revertFeatureRideStarted, object: nil)
    }
}

struct FeatureHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @Query(sort: \Bike.createdAt, order: .reverse) private var bikes: [Bike]

    private var savedPlanned: [(SavedRoute, PlannedRoute)] {
        savedRoutes.compactMap { saved in saved.plannedRoute().map { (saved, $0) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    planningSection
                    rideSection
                    afterSection
                    platformSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .pulseBackground()
            .navigationTitle("Ride Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        RevertHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close Ride Lab")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .revertFeatureRideStarted)) { _ in
            dismiss()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SIXTEEN FEATURES · ONE LAB")
                .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(Pulse.accent)
            // The navigation bar already says "Ride Lab"; a second 32 pt copy
            // right underneath just pushes the first section off screen.
            Text("Planning conditions, touring, route links, hands-free marks, ghost runs, corner and segment reports, monthly posters and setup notes — all on this iPhone.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planningSection: some View {
        labSection(title: "A · Planning", detail: "Before the ride") {
            NavigationLink {
                ConditionsFeatureView(routes: savedRoutes, rides: rides, bikes: bikes)
            } label: {
                FeatureRow(title: "Conditions (light)", subtitle: "Sunset, daylight and finish-in-the-dark warnings",
                           systemImage: "sun.horizon.fill", tint: Pulse.warning)
            }
            NavigationLink {
                RangeFeatureView(bikes: bikes, routes: savedRoutes)
            } label: {
                FeatureRow(title: "Range ring", subtitle: "Does this loop fit the bike’s tank?",
                           systemImage: "gauge.with.dots.needle.50percent", tint: Pulse.accent)
            }
            NavigationLink {
                TripListView()
            } label: {
                FeatureRow(title: "Touring", subtitle: "Multi-day trips, one card per day",
                           systemImage: "suitcase.rolling.fill", tint: Pulse.accent)
            }
            NavigationLink {
                SavedLoopDeckView(items: savedPlanned)
            } label: {
                FeatureRow(title: "Loop deck", subtitle: "Swipe saved loops; keep one to ride",
                           systemImage: "rectangle.stack.fill", tint: Pulse.accent)
            }
            NavigationLink {
                RouteImportView()
            } label: {
                FeatureRow(title: "Import a route", subtitle: "GPX track → rideable route",
                           systemImage: "square.and.arrow.down", tint: Pulse.accent)
            }
            NavigationLink {
                RouteLinkFeatureView(savedRoutes: savedRoutes)
            } label: {
                FeatureRow(title: "Route links", subtitle: "Share or open a route with no server",
                           systemImage: "link", tint: Pulse.accent)
            }
            NavigationLink {
                RidePackFeatureView(savedRoutes: savedRoutes)
            } label: {
                FeatureRow(title: "Offline preflight", subtitle: "Roads, hazards and a corridor pack",
                           systemImage: "arrow.down.circle.fill", tint: Pulse.warning)
            }
        }
    }

    private var rideSection: some View {
        labSection(title: "B · In the ride", detail: "Hands-free") {
            NavigationLink {
                UserMarksFeatureView()
            } label: {
                FeatureRow(title: "Voice marks", subtitle: "Mark hazards and avoid roads by voice",
                           systemImage: "mic.fill", tint: Pulse.accent)
            }
            NavigationLink {
                GhostFeatureView(rides: rides)
            } label: {
                FeatureRow(title: "Ghost chase", subtitle: "Race the best previous run on this route",
                           systemImage: "figure.run", tint: Pulse.accent)
            }
            NavigationLink {
                BatteryFeatureView()
            } label: {
                FeatureRow(title: "Long-ride battery", subtitle: "Dim the cockpit after a quiet stretch",
                           systemImage: "battery.25percent", tint: Pulse.warning)
            }
        }
    }

    private var afterSection: some View {
        labSection(title: "C · After the ride", detail: "What the data means") {
            NavigationLink {
                RideAgainFeatureView(rides: rides)
            } label: {
                FeatureRow(title: "Ride it again", subtitle: "Replay the exact track or the saved route",
                           systemImage: "arrow.clockwise", tint: Pulse.accent)
            }
            NavigationLink {
                CornerFeatureView(rides: rides)
            } label: {
                FeatureRow(title: "Corner report", subtitle: "Entry, apex and exit speed for every bend",
                           systemImage: "point.topleft.down.curvedto.point.bottomright.up", tint: Pulse.accent)
            }
            NavigationLink {
                MonthlyFeatureView(rides: rides)
            } label: {
                FeatureRow(title: "Monthly recap", subtitle: "A poster for the month’s riding",
                           systemImage: "calendar", tint: Pulse.accent)
            }
            NavigationLink {
                SetupFeatureView(bikes: bikes)
            } label: {
                FeatureRow(title: "Setup & service", subtitle: "Tyres, pressures, notes and intervals",
                           systemImage: "wrench.and.screwdriver.fill", tint: Pulse.accent)
            }
            NavigationLink {
                SegmentFeatureView(rides: rides)
            } label: {
                FeatureRow(title: "Segment hunt", subtitle: "Find the twisty stretches worth repeating",
                           systemImage: "scissors", tint: Pulse.accent)
            }
        }
    }

    private var platformSection: some View {
        labSection(title: "D · Platform", detail: "Glanceable") {
            NavigationLink {
                PlatformFeatureView()
            } label: {
                FeatureRow(title: "Siri, Focus & widget", subtitle: "Start the usual loop without unlocking",
                           systemImage: "sparkles", tint: Pulse.warning)
            }
        }
    }

    private func labSection<Content: View>(title: String, detail: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RevertSectionLabel(title: title, detail: detail)
            content()
        }
    }
}

struct FeatureRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.scaledSystem(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Pulse.ink)
                Text(subtitle)
                    .font(.scaledSystem(size: 10, design: .rounded))
                    .foregroundStyle(Pulse.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.scaledSystem(size: 9, weight: .bold))
                .foregroundStyle(Pulse.muted)
        }
        .padding(11)
        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Pulse.line, lineWidth: 0.8)
        }
    }
}

// MARK: - A1 Conditions

struct ConditionsFeatureView: View {
    let routes: [SavedRoute]
    let rides: [Ride]
    let bikes: [Bike]
    @State private var selectedRouteID: UUID?

    private var selectedSaved: SavedRoute? {
        if let selectedRouteID { return routes.first(where: { $0.id == selectedRouteID }) }
        return routes.first
    }

    private var route: PlannedRoute? {
        if let selectedSaved { return selectedSaved.plannedRoute() }
        if let ride = rides.first { return RideAgainRoute.make(ride: ride, saved: nil) }
        return nil
    }

    private var bike: Bike? {
        bikes.first(where: \.isPrimary) ?? bikes.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !routes.isEmpty {
                    Picker("Route", selection: $selectedRouteID) {
                        ForEach(routes) { saved in
                            Text(saved.name).tag(Optional(saved.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Pulse.accent)
                }

                let snapshot = ConditionsService.snapshot(route: route, bike: bike)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sun.horizon.fill")
                            .font(.scaledSystem(size: 25, weight: .bold))
                            .foregroundStyle(Pulse.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.headline)
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                                .foregroundStyle(Pulse.ink)
                            Text(route?.displayName ?? selectedSaved?.name ?? "Latest ride")
                                .font(.scaledSystem(size: 10, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                        }
                    }

                    HStack(spacing: 9) {
                        conditionFact("Sunrise", snapshot.sunrise?.formatted(date: .omitted, time: .shortened) ?? "—")
                        conditionFact("Sunset", snapshot.sunset?.formatted(date: .omitted, time: .shortened) ?? "—")
                        conditionFact("Ride", Units.clock(snapshot.rideDuration))
                    }

                    ForEach(snapshot.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.scaledSystem(size: 10, weight: .bold))
                                .foregroundStyle(Pulse.warning)
                            Text(warning)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Pulse.mutedStrong)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .pulseCard()

                Text(snapshot.weatherNote)
                    .font(.scaledSystem(size: 10, design: .rounded))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Conditions (light)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func conditionFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Pulse.muted)
            Text(value)
                .font(.scaledSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Pulse.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A2 Range

struct RangeFeatureView: View {
    let bikes: [Bike]
    let routes: [SavedRoute]
    @State private var selectedBikeID: UUID?

    private var bike: Bike? {
        if let selectedBikeID { return bikes.first(where: { $0.id == selectedBikeID }) }
        return bikes.first(where: \.isPrimary) ?? bikes.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !bikes.isEmpty {
                    Picker("Bike", selection: $selectedBikeID) {
                        ForEach(bikes) { bike in
                            Text(bike.displayName).tag(Optional(bike.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Pulse.accent)
                }

                let base = RangePolicy.summary(for: bike, routeLengthMeters: 0)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: "fuelpump.fill")
                            .font(.scaledSystem(size: 24, weight: .bold))
                            .foregroundStyle(Pulse.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Units.distanceText(base.usableKm * 1_000, decimals: 0)) usable range")
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                                .foregroundStyle(Pulse.ink)
                            Text("At \(Int(base.tankFraction * 100))% tank · comfortable turn-back \(Units.distanceText(base.comfortableKm * 1_000, decimals: 0))")
                                .font(.scaledSystem(size: 10, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                        }
                    }
                    Text("Leave a 10% reserve. If a loop is longer than the comfortable range, plan fuel before the turn-back point.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.mutedStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .pulseCard()

                RevertSectionLabel(title: "Saved routes", detail: "\(routes.count)")
                if routes.isEmpty {
                    Text("Save a route from the planner to see its range verdict.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                } else {
                    ForEach(routes) { saved in
                        let summary = RangePolicy.summary(for: bike, routeLengthMeters: saved.distanceMeters)
                        HStack(spacing: 10) {
                            Text(summary.verdict.rawValue.uppercased())
                                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                                .foregroundStyle(verdictColor(summary.verdict))
                                .frame(width: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                                Text("\(Units.distanceText(saved.distanceMeters, decimals: 1)) · \(summary.note)")
                                    .font(.scaledSystem(size: 9.5, design: .rounded))
                                    .foregroundStyle(Pulse.muted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Range ring")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func verdictColor(_ verdict: RangeSummary.Verdict) -> Color {
        switch verdict {
        case .fits: Pulse.emerald
        case .tight: Pulse.warning
        case .exceeds: Pulse.danger
        case .unknown: Pulse.muted
        }
    }
}

// MARK: - A3 Touring

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var showingAdd = false
    @State private var editingTrip: Trip?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    RevertHaptics.tap()
                    showingAdd = true
                } label: {
                    Label("New trip", systemImage: "plus.circle.fill")
                }
                .buttonStyle(RevertPrimaryButtonStyle())

                if trips.isEmpty {
                    RevertInfoNote(text: "Build a multi-day trip here. Each day can link to a saved route so the riding order is already decided.",
                                   systemImage: "suitcase.rolling", tint: Pulse.accent)
                } else {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.title)
                                    .font(.system(.headline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Pulse.ink)
                                Text("\(trip.sortedDays.count) day\(trip.sortedDays.count == 1 ? "" : "s") · \(totalDistance(trip))")
                                    .font(.scaledSystem(size: 10, design: .rounded))
                                    .foregroundStyle(Pulse.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingTrip = trip
                            } label: {
                                Label("Edit trip", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                context.delete(trip)
                                try? context.save()
                            } label: {
                                Label("Delete trip", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Touring")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            TripEditorView()
        }
        .sheet(item: $editingTrip) { trip in
            TripEditorView(trip: trip)
        }
    }

    private func totalDistance(_ trip: Trip) -> String {
        Units.distanceText(trip.sortedDays.reduce(0) { $0 + $1.distanceKm * 1_000 }, decimals: 1)
    }
}

struct TripEditorView: View {
    var trip: Trip? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var notes = ""

    init(trip: Trip? = nil) {
        self.trip = trip
        _title = State(initialValue: trip?.title ?? "")
        _notes = State(initialValue: trip?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Title (e.g. Alps week)", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .pulseBackground()
            .navigationTitle(trip == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        if let trip {
                            trip.title = trimmed
                            trip.notes = notes
                        } else {
                            context.insert(Trip(title: trimmed, notes: notes))
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TripDetailView: View {
    let trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Environment(NavigationManager.self) private var nav
    @State private var showingAddDay = false
    @State private var editingTrip = false
    @State private var editingDay: TripDay?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !trip.notes.isEmpty {
                    Text(trip.notes)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.mutedStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    RevertHaptics.tap()
                    showingAddDay = true
                } label: {
                    Label("Add a day", systemImage: "plus.circle.fill")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))

                if trip.sortedDays.isEmpty {
                    RevertInfoNote(text: "Add each day and, optionally, the saved route it follows.",
                                   systemImage: "calendar", tint: Pulse.accent)
                } else {
                    ForEach(trip.sortedDays) { day in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("DAY \(day.order + 1)")
                                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                                    .tracking(1)
                                    .foregroundStyle(Pulse.accent)
                                Spacer()
                                if let saved = savedRoute(for: day) {
                                    Button {
                                        guard let route = saved.plannedRoute() else { return }
                                        FeatureRideLauncher.start(route: route, roads: saved.roads, nav: nav)
                                    } label: {
                                        Label("Ride day", systemImage: "play.fill")
                                            .font(.scaledSystem(size: 10, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Pulse.accent)
                                }
                            }
                            Text(day.title)
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Pulse.ink)
                            if !day.startLabel.isEmpty || !day.endLabel.isEmpty {
                                Text("\(day.startLabel) → \(day.endLabel)")
                                    .font(.scaledSystem(size: 10, design: .rounded))
                                    .foregroundStyle(Pulse.muted)
                            }
                            Text("\(Units.distanceText(day.distanceKm * 1_000, decimals: 1))\(day.notes.isEmpty ? "" : " · \(day.notes)")")
                                .font(.scaledSystem(size: 9.5, design: .rounded))
                                .foregroundStyle(Pulse.mutedStrong)
                                .lineLimit(3)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .contextMenu {
                            Button {
                                editingDay = day
                            } label: {
                                Label("Edit day", systemImage: "pencil")
                            }
                            if let saved = savedRoute(for: day), let url = RouteLink.url(for: saved) {
                                ShareLink(item: url) {
                                    Label("Share day link", systemImage: "link")
                                }
                            }
                            if let saved = savedRoute(for: day), let gpx = saved.gpxExportURL {
                                ShareLink(item: gpx) {
                                    Label("Share day GPX", systemImage: "doc.badge.arrow.up")
                                }
                            }
                            Button {
                                moveDay(day, by: -1)
                            } label: {
                                Label("Move up", systemImage: "arrow.up")
                            }
                            Button {
                                moveDay(day, by: 1)
                            } label: {
                                Label("Move down", systemImage: "arrow.down")
                            }
                            Button(role: .destructive) {
                                context.delete(day)
                                try? context.save()
                                renumberDays()
                            } label: {
                                Label("Delete day", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingTrip = true
                    } label: {
                        Label("Edit trip", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        context.delete(trip)
                        try? context.save()
                        dismiss()
                    } label: {
                        Label("Delete trip", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Trip actions")
            }
        }
        .sheet(isPresented: $showingAddDay) {
            TripDayEditorView(trip: trip, savedRoutes: savedRoutes)
        }
        .sheet(isPresented: $editingTrip) {
            TripEditorView(trip: trip)
        }
        .sheet(item: $editingDay) { day in
            TripDayEditorView(trip: trip, savedRoutes: savedRoutes, day: day)
        }
    }

    private func moveDay(_ day: TripDay, by offset: Int) {
        var days = trip.sortedDays
        guard let index = days.firstIndex(where: { $0.id == day.id }) else { return }
        let target = index + offset
        guard days.indices.contains(target) else { return }
        days.swapAt(index, target)
        for (order, item) in days.enumerated() { item.order = order }
        trip.days = days
        try? context.save()
    }

    private func renumberDays() {
        for (order, day) in trip.sortedDays.enumerated() { day.order = order }
        try? context.save()
    }

    private func savedRoute(for day: TripDay) -> SavedRoute? {
        guard let id = day.savedRouteID else { return nil }
        return savedRoutes.first { $0.id == id }
    }
}

struct TripDayEditorView: View {
    let trip: Trip
    let savedRoutes: [SavedRoute]
    var day: TripDay? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var start = ""
    @State private var end = ""
    @State private var distance = 0.0
    @State private var notes = ""
    @State private var savedRouteID: UUID?

    init(trip: Trip, savedRoutes: [SavedRoute], day: TripDay? = nil) {
        self.trip = trip
        self.savedRoutes = savedRoutes
        self.day = day
        _title = State(initialValue: day?.title ?? "")
        _start = State(initialValue: day?.startLabel ?? "")
        _end = State(initialValue: day?.endLabel ?? "")
        _distance = State(initialValue: day?.distanceKm ?? 0)
        _notes = State(initialValue: day?.notes ?? "")
        _savedRouteID = State(initialValue: day?.savedRouteID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    TextField("Title", text: $title)
                    TextField("Start", text: $start)
                    TextField("Finish", text: $end)
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("0", value: $distance, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("km").foregroundStyle(.secondary)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("Saved route") {
                    Picker("Route", selection: $savedRouteID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(savedRoutes) { saved in
                            Text(saved.name).tag(Optional(saved.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .scrollContentBackground(.hidden)
            .pulseBackground()
            .navigationTitle(day == nil ? "Add day" : "Edit day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        if let day {
                            day.title = trimmed.isEmpty ? day.title : trimmed
                            day.startLabel = start
                            day.endLabel = end
                            day.distanceKm = distance
                            day.notes = notes
                            day.savedRouteID = savedRouteID
                        } else {
                            let next = (trip.days ?? []).count
                            let newDay = TripDay(order: next,
                                                 title: trimmed.isEmpty ? "Day \(next + 1)" : trimmed,
                                                 startLabel: start, endLabel: end,
                                                 distanceKm: distance, notes: notes,
                                                 savedRouteID: savedRouteID)
                            newDay.trip = trip
                            context.insert(newDay)
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - A4 Loop deck

struct SavedLoopDeckView: View {
    let items: [(SavedRoute, PlannedRoute)]
    @Environment(NavigationManager.self) private var nav

    var body: some View {
        if items.isEmpty {
            RevertInfoNote(text: "Save a loop first, then the deck can deal them one by one.",
                           systemImage: "rectangle.stack", tint: Pulse.accent)
                .padding(16)
                .pulseBackground()
                .navigationTitle("Loop deck")
        } else {
            LoopDeckView(routes: items.map(\.1)) { route in
                FeatureRideLauncher.start(route: route, roads: [], nav: nav)
            }
            .navigationTitle("Loop deck")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct LoopDeckView: View {
    let routes: [PlannedRoute]
    let onRide: (PlannedRoute) -> Void
    @State private var index = 0

    private var route: PlannedRoute? {
        routes.indices.contains(index) ? routes[index] : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            if let route {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("OPTION \(index + 1) OF \(routes.count)")
                            .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Pulse.accent)
                        Spacer()
                        Text(route.heading)
                            .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                    }
                    Text(route.displayName ?? "Untitled loop")
                        .font(PulseType.display(30))
                        .foregroundStyle(Pulse.ink)
                        .lineLimit(2)
                    HStack(spacing: 0) {
                        deckStat("DISTANCE", Units.distanceText(route.length, decimals: 1))
                        deckStat("CLIMB", Units.elevationText(route.climbMeters))
                        deckStat("CURVES", "\(route.curviness)/5")
                    }
                    if let comparison = comparison(for: route) {
                        Text(comparison)
                            .font(.scaledSystem(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(comparison)
                    }
                    HStack(spacing: 9) {
                        Button {
                            RevertHaptics.tap()
                            if index + 1 < routes.count { index += 1 } else { index = 0 }
                        } label: {
                            Label("Skip", systemImage: "arrow.right")
                        }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 48))

                        Button {
                            RevertHaptics.success()
                            onRide(route)
                        } label: {
                            Label("Ride this", systemImage: "play.fill")
                        }
                        .buttonStyle(RevertPrimaryButtonStyle(minHeight: 48))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Pulse.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Pulse.lineBright, lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            if routes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Pulse.muted)
                    Text("No loops yet")
                        .font(PulseType.display(22))
                        .foregroundStyle(Pulse.ink)
                    Text("Widen the distance or move the start point, then plan again.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
            Text("Keep swiping. One route at a time, no list to scan at speed.")
                .font(.scaledSystem(size: 10, design: .rounded))
                .foregroundStyle(Pulse.muted)
        }
        .padding(.vertical, 18)
        .pulseBackground()
    }

    /// The pitch is that a loop can be longer but far more interesting. Say it
    /// in the deck instead of making the rider compare numbers by memory.
    private func comparison(for route: PlannedRoute) -> String? {
        guard routes.count > 1,
              let shortest = routes.min(by: { $0.length < $1.length }),
              shortest.id != route.id else { return nil }
        let distance = (route.length - shortest.length) / max(shortest.length, 1) * 100
        let curves = (route.twistPerKm - shortest.twistPerKm) / max(shortest.twistPerKm, 1) * 100
        var parts: [String] = []
        if abs(distance) >= 5 {
            parts.append(distance > 0
                         ? "\(Int(distance.rounded()))% longer than the shortest option"
                         : "\(Int(-distance.rounded()))% shorter than the shortest option")
        }
        if abs(curves) >= 10 {
            parts.append(curves > 0
                         ? "\(Int(curves.rounded()))% more curves"
                         : "\(Int(-curves.rounded()))% fewer curves")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func deckStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.scaledSystem(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Pulse.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Pulse.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A5 Import

struct RouteImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @State private var importing = false
    @State private var route: PlannedRoute?
    @State private var error: String?
    @State private var importedName = "Imported route"
    @State private var track: [CLLocationCoordinate2D] = []
    @State private var replanning = false
    @State private var replanTask: Task<Void, Never>?
    @State private var replanProgress: (done: Int, total: Int)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    RevertHaptics.tap()
                    importing = true
                } label: {
                    Label("Choose a GPX file", systemImage: "doc.badge.plus")
                }
                .buttonStyle(RevertPrimaryButtonStyle())

                Text("Imports the recorded track as-is, or re-plans it through MapKit in \(Units.distanceText(15_000, decimals: 0)) legs. The original file never leaves the phone.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let error {
                    RevertInfoNote(text: error, systemImage: "exclamationmark.triangle.fill", tint: Pulse.warning)
                }

                if let route {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(route.displayName ?? importedName)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Pulse.ink)
                        Text("\(Units.distanceText(route.length, decimals: 1)) · \(route.points.count) points")
                            .font(.scaledSystem(size: 10, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                        if replanning {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text(replanProgress.map { "Routing \($0.done)/\($0.total) legs…" } ?? "Preparing route…")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Pulse.muted)
                                Spacer()
                                Button("Cancel") { cancelReplan() }
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Pulse.warning)
                            }
                        } else {
                            Button {
                                replan(route)
                            } label: {
                                Label("Re-plan with roads", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            }
                            .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                        }

                        HStack(spacing: 9) {
                            Button {
                                RevertHaptics.success()
                                FeatureRideLauncher.start(route: route, roads: [], nav: nav)
                            } label: {
                                Label("Ride it", systemImage: "play.fill")
                            }
                            .buttonStyle(RevertPrimaryButtonStyle(minHeight: 46))

                            Button {
                                context.insert(SavedRoute(route: route, name: importedName, roads: []))
                                try? context.save()
                                RevertHaptics.success()
                            } label: {
                                Label("Save route", systemImage: "bookmark")
                            }
                            .buttonStyle(RevertSecondaryButtonStyle(minHeight: 46))
                        }
                    }
                    .pulseCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Import route")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { replanTask?.cancel() }
        .fileImporter(isPresented: $importing, allowedContentTypes: GPX.contentTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let track = GPX.parseTrack(from: data) else {
                    error = "That GPX file did not contain a track."
                    return
                }
                importedName = url.deletingPathExtension().lastPathComponent
                self.track = track.points.map(\.coordinate)
                if let made = RideAgainRoute.make(ride: track.makeRide(), saved: nil) {
                    route = made
                    error = nil
                } else {
                    error = "The track needs at least three points."
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    private func replan(_ route: PlannedRoute) {
        guard !track.isEmpty else { return }
        replanning = true
        replanProgress = nil
        replanTask?.cancel()
        replanTask = Task {
            let result = await RouteReplanner.replan(track: track, name: importedName) { done, total in
                replanProgress = (done, total)
            }
            guard !Task.isCancelled else {
                replanning = false
                return
            }
            if let newRoute = result {
                self.route = newRoute
                error = nil
                RevertHaptics.success()
            } else {
                error = "MapKit could not re-plan this track."
            }
            replanning = false
            replanProgress = nil
        }
    }

    private func cancelReplan() {
        replanTask?.cancel()
        replanTask = nil
        replanning = false
        replanProgress = nil
    }

}

// MARK: - A6 Route links

struct RouteLinkFeatureView: View {
    let savedRoutes: [SavedRoute]
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @State private var pasted = ""
    @State private var incoming: PlannedRoute?
    @State private var qrItem: RouteQRCodeItem?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if savedRoutes.isEmpty {
                    RevertInfoNote(text: "Save a route to create a link.",
                                   systemImage: "link", tint: Pulse.accent)
                } else {
                    ForEach(savedRoutes) { saved in
                        if let url = RouteLink.url(for: saved) {
                            ShareLink(item: url) {
                                HStack(spacing: 9) {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Pulse.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.name)
                                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            .foregroundStyle(Pulse.ink)
                                        Text("Share route link")
                                            .font(.scaledSystem(size: 9.5, design: .rounded))
                                            .foregroundStyle(Pulse.muted)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .contextMenu {
                                Button {
                                    qrItem = RouteQRCodeItem(url: url, name: saved.name)
                                } label: {
                                    Label("Show QR code", systemImage: "qrcode")
                                }
                            }
                        } else {
                            HStack(spacing: 9) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Pulse.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.name)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Pulse.ink)
                                    Text("Route is too large for a single link; use a GPX export or split it.")
                                        .font(.scaledSystem(size: 9.5, design: .rounded))
                                        .foregroundStyle(Pulse.muted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    RevertSectionLabel(title: "Open a link", detail: "No server")
                    TextField("Paste a revert://route link", text: $pasted)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(11)
                        .background(Pulse.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        openPasted()
                    } label: {
                        Label("Open link", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                }

                if let error {
                    RevertInfoNote(text: error, systemImage: "exclamationmark.triangle.fill", tint: Pulse.warning)
                }

                if let incoming {
                    RouteLinkPreview(route: incoming)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Route links")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $qrItem) { item in
            RouteQRCodeView(item: item)
        }
    }

    private func openPasted() {
        guard let url = URL(string: pasted.trimmingCharacters(in: .whitespacesAndNewlines)),
              let payload = RouteLink.payload(from: url),
              let route = RouteLink.route(from: payload) else {
            error = "That is not a Revert route link."
            return
        }
        incoming = route
        error = nil
    }
}

struct RouteLinkPreview: View {
    let route: PlannedRoute
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route.displayName ?? "Shared route")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Pulse.ink)
            Text("\(Units.distanceText(route.length, decimals: 1)) · \(route.laps) lap\(route.laps == 1 ? "" : "s") · \(Int(route.points.count)) points")
                .font(.scaledSystem(size: 10, design: .rounded))
                .foregroundStyle(Pulse.muted)
            HStack(spacing: 9) {
                Button {
                    FeatureRideLauncher.start(route: route, roads: [], nav: nav)
                } label: {
                    Label("Ride it", systemImage: "play.fill")
                }
                .buttonStyle(RevertPrimaryButtonStyle(minHeight: 44))

                Button {
                    context.insert(SavedRoute(route: route, name: route.displayName ?? "Shared route", roads: []))
                    try? context.save()
                    saved = true
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "bookmark")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                .disabled(saved)
            }
        }
        .pulseCard()
    }
}

/// Used by the app-level route-link URL import as a sheet.
struct IncomingRouteLinkView: View {
    let route: PlannedRoute
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RouteLinkPreview(route: route)
                    Button {
                        FeatureRideLauncher.start(route: route, roads: [], nav: nav)
                        dismiss()
                    } label: {
                        Label("Ride this route", systemImage: "play.fill")
                    }
                    .buttonStyle(RevertPrimaryButtonStyle())
                }
                .padding(16)
            }
            .pulseBackground()
            .navigationTitle("Shared route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

// MARK: - A7 Offline preflight

struct RidePackFeatureView: View {
    let savedRoutes: [SavedRoute]
    @Environment(NavigationManager.self) private var nav
    @State private var selectedID: UUID?
    @State private var packing = false
    @State private var message: String?
    @State private var packingText: String?
    @State private var packedRoads = 0
    @State private var packedHazards = 0
    @State private var packedChunks = 0

    private var saved: SavedRoute? {
        if let selectedID { return savedRoutes.first { $0.id == selectedID } }
        return savedRoutes.first
    }

    private var route: PlannedRoute? { saved?.plannedRoute() }
    private var center: CLLocationCoordinate2D? { route?.points.first?.coordinate }

    private var roadCount: Int {
        guard let center, let route else { return 0 }
        return RoadStore.store(for: route.surface).items(near: center).count
    }

    private var hazardCount: Int {
        guard let center else { return 0 }
        return HazardStore.items(near: center).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if savedRoutes.isEmpty {
                    RevertInfoNote(text: "Save a route first; the preflight checks the area around its start.",
                                   systemImage: "arrow.down.circle", tint: Pulse.accent)
                } else {
                    Picker("Route", selection: $selectedID) {
                        ForEach(savedRoutes) { saved in
                            Text(saved.name).tag(Optional(saved.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Pulse.accent)

                    if let route, let center {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(route.displayName ?? "Route")
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                                .foregroundStyle(Pulse.ink)
                            packRow("Road graph", packedRoads > 0 ? "\(packedRoads) corridor ways" : "\(roadCount) cached ways", ok: packedRoads > 0 || roadCount > 0)
                            packRow("Hazards", packedHazards > 0 ? "\(packedHazards) corridor devices" : "\(hazardCount) cached devices", ok: packedHazards > 0 || hazardCount > 0)
                            packRow("Route geometry", "\(route.points.count) points on disk", ok: true)
                            packRow("Corridor", packedChunks > 0 ? "\(packedChunks) chunks packed" : "Not packed", ok: packedChunks > 0)
                            packRow("Elevation", "Fetched on demand", ok: false)
                            Text("Pack the whole route, not just the start: each \(Units.distanceText(8_000, decimals: 0)) of the route gets an overlapping \(Units.distanceText(8_000, decimals: 0)) area of roads and hazards. Elevation remains on demand.")
                                .font(.scaledSystem(size: 10, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .pulseCard()

                        Button {
                            pack(center: center, route: route)
                        } label: {
                            Label(packing ? (packingText ?? "Packing…") : "Pack route corridor", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(RevertPrimaryButtonStyle())
                        .disabled(packing)

                        if let message {
                            RevertInfoNote(text: message, systemImage: "checkmark.circle.fill", tint: Pulse.emerald)
                        }

                        NavigationLink {
                            OfflineView()
                        } label: {
                            Label("Open full offline downloads", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Offline preflight")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func packRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Pulse.emerald : Pulse.muted)
            Text(label)
                .font(.scaledSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Pulse.ink)
            Spacer()
            Text(value)
                .font(.scaledSystem(size: 9.5, design: .rounded))
                .foregroundStyle(Pulse.muted)
        }
    }

    private func pack(center: CLLocationCoordinate2D, route: PlannedRoute) {
        let chunks = corridorSamples(route)
        packing = true
        message = nil
        packingText = "Preparing corridor…"
        packedRoads = 0
        packedHazards = 0
        packedChunks = 0
        Task {
            var roads = 0
            var hazards = 0
            for (index, chunk) in chunks.enumerated() {
                packingText = "Packing \(index + 1)/\(chunks.count)…"
                let loadedRoads = await RoadStore.store(for: route.surface)
                    .loadArea(center: chunk, radiusKm: 8)
                let loadedHazards = await HazardStore.shared
                    .loadArea(center: chunk, radiusKm: 8)
                roads += loadedRoads.count
                hazards += loadedHazards.count
                packedChunks = index + 1
                packedRoads = roads
                packedHazards = hazards
            }
            packing = false
            packingText = nil
            message = "Packed \(roads) roads and \(hazards) hazards across \(chunks.count) route chunks."
            RevertHaptics.success()
        }
    }

    /// One overlapping 8 km area every ~8 km along the actual route geometry.
    private func corridorSamples(_ route: PlannedRoute) -> [CLLocationCoordinate2D] {
        let points = route.points
        guard let first = points.first?.coordinate else { return [center].compactMap { $0 } }
        var samples: [CLLocationCoordinate2D] = [first]
        var last = first
        var accumulated = 0.0
        for point in points.dropFirst() {
            accumulated += CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: point.lat, longitude: point.lon))
            last = point.coordinate
            if accumulated >= 8_000 {
                samples.append(point.coordinate)
                accumulated = 0
            }
            if samples.count >= 12 { break }
        }
        if let final = points.last?.coordinate,
           CLLocation(latitude: final.latitude, longitude: final.longitude)
            .distance(from: CLLocation(latitude: samples.last!.latitude,
                                       longitude: samples.last!.longitude)) > 100 {
            samples.append(final)
        }
        return samples
    }
}
