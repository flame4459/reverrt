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
            Text("Ride Lab")
                .font(PulseType.display(32))
                .foregroundStyle(Pulse.ink)
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
                FeatureRow(title: "Conditions", subtitle: "Sunset, daylight and finish-in-the-dark warnings",
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
        .navigationTitle("Conditions")
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
                            Text("\(Units.distanceText(base.rangeKm * 1_000, decimals: 0)) range")
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                                .foregroundStyle(Pulse.ink)
                            Text("Comfortable turn-back at \(Units.distanceText(base.comfortableKm * 1_000, decimals: 0))")
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
    }

    private func totalDistance(_ trip: Trip) -> String {
        Units.distanceText(trip.sortedDays.reduce(0) { $0 + $1.distanceKm * 1_000 }, decimals: 1)
    }
}

struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var notes = ""

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
            .navigationTitle("New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        context.insert(Trip(title: title.trimmingCharacters(in: .whitespaces), notes: notes))
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
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Environment(NavigationManager.self) private var nav
    @State private var showingAddDay = false

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
                            Button(role: .destructive) {
                                context.delete(day)
                                try? context.save()
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
        .sheet(isPresented: $showingAddDay) {
            TripDayEditorView(trip: trip, savedRoutes: savedRoutes)
        }
    }

    private func savedRoute(for day: TripDay) -> SavedRoute? {
        guard let id = day.savedRouteID else { return nil }
        return savedRoutes.first { $0.id == id }
    }
}

struct TripDayEditorView: View {
    let trip: Trip
    let savedRoutes: [SavedRoute]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var start = ""
    @State private var end = ""
    @State private var distance = 0.0
    @State private var notes = ""
    @State private var savedRouteID: UUID?

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
            .navigationTitle("Add day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let next = (trip.days ?? []).count
                        let day = TripDay(order: next,
                                          title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "Day \(next + 1)" : title,
                                          startLabel: start, endLabel: end,
                                          distanceKm: distance, notes: notes, savedRouteID: savedRouteID)
                        day.trip = trip
                        context.insert(day)
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
            Text("Keep swiping. One route at a time, no list to scan at speed.")
                .font(.scaledSystem(size: 10, design: .rounded))
                .foregroundStyle(Pulse.muted)
        }
        .padding(.vertical, 18)
        .pulseBackground()
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
                        Button {
                            replan(route)
                        } label: {
                            Label(replanning ? "Re-planning…" : "Re-plan with roads", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                        .disabled(replanning)

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
        Task {
            if let newRoute = await RouteReplanner.replan(track: track, name: importedName) {
                self.route = newRoute
                error = nil
                RevertHaptics.success()
            } else {
                error = "MapKit could not re-plan this track."
            }
            replanning = false
        }
    }

}

// MARK: - A6 Route links

struct RouteLinkFeatureView: View {
    let savedRoutes: [SavedRoute]
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var nav
    @State private var pasted = ""
    @State private var incoming: PlannedRoute?
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
                            packRow("Road graph", "\(roadCount) cached ways", ok: roadCount > 0)
                            packRow("Hazards", "\(hazardCount) cached devices", ok: hazardCount > 0)
                            packRow("Route geometry", "\(route.points.count) points on disk", ok: true)
                            packRow("Elevation", "Fetched on demand", ok: false)
                            Text("A corridor pack downloads a \(Units.distanceText(12_000, decimals: 0)) area around the start. Use the full Offline screen for a larger radius.")
                                .font(.scaledSystem(size: 10, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .pulseCard()

                        Button {
                            pack(center: center, route: route)
                        } label: {
                            Label(packing ? "Packing…" : "Pack this area", systemImage: "arrow.down.circle.fill")
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
        packing = true
        message = nil
        Task {
            let roads = await RoadStore.store(for: route.surface).loadArea(center: center, radiusKm: 12)
            let hazards = await HazardStore.shared.loadArea(center: center, radiusKm: 12)
            packing = false
            message = "Packed \(roads.count) roads and \(hazards.count) hazards around the start."
            RevertHaptics.success()
        }
    }
}
