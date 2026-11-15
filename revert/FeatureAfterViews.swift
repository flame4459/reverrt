import SwiftUI
import MapKit
import SwiftData
import CoreLocation

// MARK: - B1 Voice marks

struct UserMarksFeatureView: View {
    @State private var store = UserMarksStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RevertInfoNote(
                    text: "In the cockpit say “mark hazard” to drop a note at the current position, or “avoid this road” to keep it out of future planning. Marks stay on this iPhone.",
                    systemImage: "mic.fill",
                    tint: Pulse.accent
                )

                RevertSectionLabel(title: "Marked hazards", detail: "\(store.hazards.count)")
                if store.hazards.isEmpty {
                    Text("No marks yet.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                } else {
                    ForEach(store.hazards) { mark in
                        HStack(spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Pulse.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mark.kind)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Pulse.ink)
                                Text("\(mark.createdAt.formatted(date: .abbreviated, time: .shortened))\(mark.road.map { " · \($0)" } ?? "")")
                                    .font(.scaledSystem(size: 9.5, design: .rounded))
                                    .foregroundStyle(Pulse.muted)
                            }
                            Spacer()
                            Button {
                                store.delete(mark)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Pulse.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                RevertSectionLabel(title: "Avoided roads", detail: "\(store.avoidedRoads.count)")
                if store.avoidedRoads.isEmpty {
                    Text("No avoided roads.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                } else {
                    ForEach(store.avoidedRoads, id: \.self) { road in
                        HStack {
                            Text(road)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Pulse.ink)
                            Spacer()
                            Button("Allow") { store.stopAvoiding(road) }
                                .font(.scaledSystem(size: 10, weight: .bold))
                                .foregroundStyle(Pulse.accent)
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
        .navigationTitle("Voice marks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - B2 Ghost

struct GhostFeatureView: View {
    let rides: [Ride]
    @AppStorage("ride.ghostEnabled") private var ghostEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $ghostEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ghost on the next ride")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Pulse.ink)
                        Text("Shows your best previous run on the same route as a ghost marker.")
                            .font(.scaledSystem(size: 10, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                    }
                }
                .tint(Pulse.accent)
                .pulseCard()

                if rides.isEmpty {
                    RevertInfoNote(text: "Record a ride first. The ghost uses a previous ride with the same route fingerprint.",
                                   systemImage: "figure.run", tint: Pulse.accent)
                } else {
                    RevertSectionLabel(title: "Previous runs", detail: "\(rides.count)")
                    ForEach(rides.prefix(12)) { ride in
                        HStack(spacing: 9) {
                            Image(systemName: "figure.run")
                                .foregroundStyle(Pulse.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.routeName ?? "Recorded ride")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                                Text("\(ride.startDate.formatted(date: .abbreviated, time: .omitted)) · \(Units.distanceText(ride.distanceMeters, decimals: 1)) · \(Units.clock(ride.durationSeconds))")
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Ghost chase")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - B3 Battery

struct BatteryFeatureView: View {
    @AppStorage("ride.longRideMode") private var longRideMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $longRideMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Long-ride battery mode")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Pulse.ink)
                        Text("After ten seconds at speed the cockpit dims to a near-black screen; tap to wake.")
                            .font(.scaledSystem(size: 10, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                    }
                }
                .tint(Pulse.accent)
                .pulseCard()

                Text("The ride keeps recording and navigating while dimmed. The dimmer is in the cockpit only; it never stops GPS or voice prompts.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Long-ride battery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - B4 Ride again

struct RideAgainFeatureView: View {
    let rides: [Ride]
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var savedRoutes: [SavedRoute]
    @Environment(NavigationManager.self) private var nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if rides.isEmpty {
                    RevertInfoNote(text: "No rides to repeat yet.",
                                   systemImage: "arrow.clockwise", tint: Pulse.accent)
                } else {
                    ForEach(rides.prefix(20)) { ride in
                        HStack(spacing: 9) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.routeName ?? "Recorded ride")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                                Text("\(ride.startDate.formatted(date: .abbreviated, time: .shortened)) · \(Units.distanceText(ride.distanceMeters, decimals: 1))")
                                    .font(.scaledSystem(size: 9.5, design: .rounded))
                                    .foregroundStyle(Pulse.muted)
                            }
                            Spacer()
                            Button {
                                again(ride)
                            } label: {
                                Label("Ride again", systemImage: "play.fill")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Pulse.accent)
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
        .navigationTitle("Ride it again")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func again(_ ride: Ride) {
        let saved = ride.savedRouteID.flatMap { id in savedRoutes.first { $0.id == id } }
            ?? (ride.routeKey.flatMap { key in savedRoutes.first { $0.fingerprintKey == key } })
        guard let route = RideAgainRoute.make(ride: ride, saved: saved) else { return }
        RevertHaptics.success()
        FeatureRideLauncher.start(route: route, roads: saved?.roads ?? [], nav: nav)
    }
}

// MARK: - C1 Corner report

struct CornerFeatureView: View {
    let rides: [Ride]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if rides.isEmpty {
                    RevertInfoNote(text: "Record a ride to see corner entry, apex and exit speeds.",
                                   systemImage: "point.topleft.down.curvedto.point.bottomright.up", tint: Pulse.accent)
                } else {
                    ForEach(rides.prefix(20)) { ride in
                        NavigationLink {
                            CornerReportDetailView(ride: ride)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ride.routeName ?? "Recorded ride")
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Pulse.ink)
                                    Text(ride.startDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.scaledSystem(size: 9.5, design: .rounded))
                                        .foregroundStyle(Pulse.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 9, weight: .bold))
                                    .foregroundStyle(Pulse.muted)
                            }
                            .padding(10)
                            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Corner report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CornerReportDetailView: View {
    let ride: Ride
    @State private var points: [RidePoint] = []
    @State private var report: CornerReport?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let report {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.summary)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Pulse.ink)
                        if !report.corners.isEmpty {
                            Text("Smoothness \(report.score)/100")
                                .font(.scaledSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Pulse.accent)
                        }
                    }
                    .pulseCard()
                }

                if points.count > 1 {
                    Map(position: $camera) {
                        MapPolyline(coordinates: points.map(\.coordinate))
                            .stroke(Pulse.accent.opacity(0.55), lineWidth: 4)
                        if let report {
                            ForEach(report.corners) { corner in
                                Annotation("", coordinate: corner.apex) {
                                    Circle()
                                        .fill(corner.label == "Right" ? Pulse.accent : Pulse.emerald)
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let report {
                    RevertSectionLabel(title: "Corners", detail: "\(report.corners.count)")
                    ForEach(report.corners) { corner in
                        HStack(spacing: 9) {
                            Text("\(corner.id + 1)")
                                .font(.scaledSystem(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                                .frame(width: 18)
                            Text(corner.label)
                                .font(.scaledSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(corner.label == "Right" ? Pulse.accent : Pulse.emerald)
                                .frame(width: 42, alignment: .leading)
                            Text("\(Units.speedText(corner.entrySpeed)) → \(Units.speedText(corner.apexSpeed)) → \(Units.speedText(corner.exitSpeed))")
                                .font(.scaledSystem(size: 9.5, design: .rounded))
                                .foregroundStyle(Pulse.mutedStrong)
                            Spacer()
                            Text("\(Int(corner.lean.rounded()))°")
                                .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                        }
                        .padding(9)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Corner report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            points = ride.points
            report = CornerReport(ride: ride)
            camera = .region(MKCoordinateRegion(center: points.first?.coordinate ?? CLLocationCoordinate2D(),
                                                latitudinalMeters: 2_000, longitudinalMeters: 2_000))
        }
    }
}

// MARK: - C2 Monthly poster

struct MonthlyFeatureView: View {
    let rides: [Ride]
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var posterURL: URL?
    @State private var rendering = false

    private var recap: MonthlyRecap { MonthlyRecap(month: month, rides: rides) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button {
                        month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Pulse.accent)
                    Spacer()
                    Text(recap.title)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Pulse.ink)
                    Spacer()
                    Button {
                        month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Pulse.accent)
                }

                MonthlyPoster(recap: recap)

                if let posterURL {
                    ShareLink(item: posterURL) {
                        Label("Share poster image", systemImage: "photo.artframe")
                    }
                    .buttonStyle(RevertPrimaryButtonStyle(minHeight: 46))
                } else {
                    Button {
                        renderPoster()
                    } label: {
                        Label(rendering ? "Rendering…" : "Render poster image", systemImage: "photo.artframe")
                    }
                    .buttonStyle(RevertPrimaryButtonStyle(minHeight: 46))
                    .disabled(rendering || recap.rides.isEmpty)
                }

                if recap.rides.isEmpty {
                    RevertInfoNote(text: "No recorded rides in this month.",
                                   systemImage: "calendar", tint: Pulse.accent)
                } else {
                    ShareLink(item: shareText) {
                        Label("Share recap", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(RevertSecondaryButtonStyle(minHeight: 46))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Monthly recap")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: month) { _, _ in
            posterURL = nil
        }
    }

    private func renderPoster() {
        rendering = true
        let content = MonthlyPoster(recap: recap)
            .frame(width: 1080, height: 1350)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else {
            rendering = false
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RevertMonthly-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            posterURL = url
            RevertHaptics.success()
        } catch {
            RevertDiagnostics.log("monthly poster write failed: \(error.localizedDescription)")
        }
        rendering = false
    }

    private var shareText: String {
        """
        \(recap.title) — Revert
        \(recap.rides.count) rides · \(Units.distanceText(recap.distanceMeters, decimals: 1)) · \(Units.clock(recap.durationSeconds)) · \(Units.elevationText(recap.climbMeters)) climbed
        Longest: \(recap.longestRide.map { Units.distanceText($0.distanceMeters, decimals: 1) } ?? "—")
        Top speed: \(Units.speedText(recap.topSpeedMps))
        """
    }
}

struct MonthlyPoster: View {
    let recap: MonthlyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REVERT / MONTH")
                    .font(.scaledSystem(size: 9, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(Pulse.accent)
                Spacer()
                Text(recap.month.formatted(.dateTime.year()))
                    .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(recap.month.formatted(.dateTime.month(.wide)).uppercased())
                .font(.scaledSystem(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            HStack(spacing: 0) {
                posterMetric("\(recap.rides.count)", "RIDES")
                posterMetric(Units.distanceText(recap.distanceMeters, decimals: 0), "DISTANCE")
                posterMetric(Units.clock(recap.durationSeconds), "TIME")
            }
            HStack(spacing: 0) {
                posterMetric(Units.elevationText(recap.climbMeters), "CLIMBED")
                posterMetric(recap.longestRide.map { Units.distanceText($0.distanceMeters, decimals: 1) } ?? "—", "LONGEST")
                posterMetric(Units.speedText(recap.topSpeedMps), "TOP SPEED")
            }
            Text("KEEP MOVING · KEEP EXPLORING")
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Pulse.accent.opacity(0.85))
        }
        .padding(20)
        .background(Pulse.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Pulse.lineBright, lineWidth: 1)
        }
    }

    private func posterMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.scaledSystem(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - C3 Setup & service

struct SetupFeatureView: View {
    let bikes: [Bike]
    @Query(sort: \SetupNote.createdAt, order: .reverse) private var notes: [SetupNote]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                if bikes.isEmpty {
                    RevertInfoNote(text: "Add a bike in the Garage to keep setup notes.",
                                   systemImage: "wrench.and.screwdriver", tint: Pulse.accent)
                } else {
                    ForEach(bikes) { bike in
                        NavigationLink {
                            SetupNotesDetailView(bike: bike)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundStyle(Pulse.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bike.displayName)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Pulse.ink)
                                    Text("\(notes.filter { $0.bikeID == bike.id }.count) setup notes · service \(bike.isServiceDue ? "due" : "in \(Units.distanceText(bike.distanceToServiceKm * 1_000, decimals: 0))")")
                                        .font(.scaledSystem(size: 9.5, design: .rounded))
                                        .foregroundStyle(bike.isServiceDue ? Pulse.warning : Pulse.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 9, weight: .bold))
                                    .foregroundStyle(Pulse.muted)
                            }
                            .padding(11)
                            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Setup & service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SetupNotesDetailView: View {
    let bike: Bike
    @Environment(\.modelContext) private var context
    @Query(sort: \SetupNote.createdAt, order: .reverse) private var notes: [SetupNote]
    @State private var showingAdd = false

    private var bikeNotes: [SetupNote] {
        notes.filter { $0.bikeID == bike.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(bike.displayName)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Pulse.ink)
                    Text("\(Units.distanceText(bike.odometerKm * 1_000, decimals: 0)) odometer")
                        .font(.scaledSystem(size: 10, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                    if bike.isServiceDue {
                        Text("Service interval reached")
                            .font(.scaledSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Pulse.warning)
                    } else {
                        Text("Next service in \(Units.distanceText(bike.distanceToServiceKm * 1_000, decimals: 0))")
                            .font(.scaledSystem(size: 10, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                    }
                }
                .pulseCard()

                Button {
                    RevertHaptics.tap()
                    showingAdd = true
                } label: {
                    Label("Add setup note", systemImage: "plus.circle.fill")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))

                if bikeNotes.isEmpty {
                    RevertInfoNote(text: "No setup notes for this bike yet. Add tyre pressures, suspension changes or anything you want to remember for the next ride.",
                                   systemImage: "note.text", tint: Pulse.accent)
                } else {
                    ForEach(bikeNotes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Pulse.ink)
                            Text("\(note.createdAt.formatted(date: .abbreviated, time: .omitted)) · F \(RevertFormat.number(note.frontPressure, decimals: 1)) / R \(RevertFormat.number(note.rearPressure, decimals: 1)) psi")
                                .font(.scaledSystem(size: 9.5, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                            if !note.notes.isEmpty {
                                Text(note.notes)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Pulse.mutedStrong)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(note)
                                try? context.save()
                            } label: {
                                Label("Delete note", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Setup notes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            SetupNoteEditorView(bikeID: bike.id)
        }
    }
}

struct SetupNoteEditorView: View {
    let bikeID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var front = 32.0
    @State private var rear = 36.0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    TextField("Title (e.g. Soft rear, 3 clicks)", text: $title)
                    HStack {
                        Text("Front psi")
                        Spacer()
                        TextField("32", value: $front, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Rear psi")
                        Spacer()
                        TextField("36", value: $rear, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .pulseBackground()
            .navigationTitle("Setup note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let note = SetupNote(bikeID: bikeID,
                                             title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "Setup" : title,
                                             frontPressure: front, rearPressure: rear, notes: notes)
                        context.insert(note)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - C4 Segment hunt

struct SegmentFeatureView: View {
    let rides: [Ride]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if rides.isEmpty {
                    RevertInfoNote(text: "Record a ride; segments are found from your own track, never uploaded.",
                                   systemImage: "scissors", tint: Pulse.accent)
                } else {
                    ForEach(rides.prefix(20)) { ride in
                        NavigationLink {
                            SegmentDetailView(ride: ride)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ride.routeName ?? "Recorded ride")
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Pulse.ink)
                                    Text("\(ride.startDate.formatted(date: .abbreviated, time: .omitted)) · \(Units.distanceText(ride.distanceMeters, decimals: 1))")
                                        .font(.scaledSystem(size: 9.5, design: .rounded))
                                        .foregroundStyle(Pulse.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 9, weight: .bold))
                                    .foregroundStyle(Pulse.muted)
                            }
                            .padding(10)
                            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Segment hunt")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SegmentDetailView: View {
    let ride: Ride
    @State private var segments: [SegmentCandidate] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if segments.isEmpty {
                    RevertInfoNote(text: "No twisty stretch was found in this ride.",
                                   systemImage: "scissors", tint: Pulse.accent)
                } else {
                    ForEach(segments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.name)
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Pulse.ink)
                            Text("\(Units.distanceText(segment.lengthMeters, decimals: 1)) · \(segment.cornerCount) corners · best \(Units.speedText(segment.bestSpeed))")
                                .font(.scaledSystem(size: 10, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Local-only first pass: segments are detected from your track and not uploaded or shared.")
                        .font(.scaledSystem(size: 9.5, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Segments")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { segments = SegmentDetector.detect(points: ride.points) }
    }
}

// MARK: - D1 Platform

struct PlatformFeatureView: View {
    @AppStorage("ride.focusMode") private var focusMode = false
    @AppStorage("ride.ghostEnabled") private var ghostEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $focusMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ride-only chrome")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Pulse.ink)
                        Text("Hide the secondary map dock and keep the cockpit to the next turn, speed and controls.")
                            .font(.scaledSystem(size: 10, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                    }
                }
                .tint(Pulse.accent)
                .pulseCard()

                VStack(alignment: .leading, spacing: 5) {
                    RevertSectionLabel(title: "Siri & Shortcuts", detail: "Usual loop")
                    Text("Ask Siri “Start my usual loop with Revert” once the usual-loop shortcut is installed. The shortcut starts the saved loop with the most completed rides and opens the cockpit.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                        .font(.scaledSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Pulse.accent)
                }
                .pulseCard()

                VStack(alignment: .leading, spacing: 5) {
                    RevertSectionLabel(title: "Widget", detail: "Dashboard")
                    Text("The Revert widget shows the active Dashboard drive, or “Start a loop” when parked. Add it from the CarPlay Dashboard widget strip or the iPhone Home Screen.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .pulseCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .pulseBackground()
        .navigationTitle("Siri, Focus & widget")
        .navigationBarTitleDisplayMode(.inline)
    }
}
