import SwiftUI
import SwiftData
import Foundation

// MARK: - SwiftData models

@Model
final class Bike {
    var id: UUID = UUID()
    var name: String = ""
    var make: String = ""
    var model: String = ""
    var year: Int = 0
    var odometerKm: Double = 0
    var fuelRangeKm: Double = 260
    var tankLiters: Double = 15
    var serviceIntervalKm: Double = 6_000
    var lastServiceKm: Double = 0
    var notes: String = ""
    var isPrimary: Bool = false
    var createdAt: Date = Date()
    /// Added after the first release. Existing rows migrate as motorcycles.
    var kindRaw: String = VehicleKind.motorcycle.rawValue
    var isElectric: Bool = false
    var avoidTolls: Bool = false
    var avoidHighways: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceEntry.bike)
    var maintenance: [MaintenanceEntry]? = []

    init(name: String, make: String = "", model: String = "", year: Int = 0,
         odometerKm: Double = 0, fuelRangeKm: Double = 260, tankLiters: Double = 15,
         serviceIntervalKm: Double = 6_000, lastServiceKm: Double = 0,
         notes: String = "", isPrimary: Bool = false,
         kind: VehicleKind = .motorcycle,
         isElectric: Bool = false, avoidTolls: Bool = false, avoidHighways: Bool = false) {
        self.id = UUID()
        self.name = name
        self.make = make
        self.model = model
        self.year = year
        self.odometerKm = odometerKm
        self.fuelRangeKm = fuelRangeKm
        self.tankLiters = tankLiters
        self.serviceIntervalKm = serviceIntervalKm
        self.lastServiceKm = lastServiceKm
        self.notes = notes
        self.isPrimary = isPrimary
        self.createdAt = Date()
        self.kindRaw = kind.rawValue
        self.isElectric = isElectric
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
    }

    var kind: VehicleKind {
        get { VehicleKind(rawValue: kindRaw) ?? .motorcycle }
        set { kindRaw = newValue.rawValue }
    }

    var isCar: Bool { kind.isCar }

    /// "Yamaha MT-07" for a bike with make/model filled in.
    var makeModelName: String {
        [make, model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Riders name their bikes; the nickname must win over the catalog name,
    /// otherwise typing "Baby" into the editor has no visible effect.
    var displayName: String {
        let nickname = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }
        return makeModelName.isEmpty ? "Unnamed vehicle" : makeModelName
    }

    var distanceToServiceKm: Double {
        max(lastServiceKm + serviceIntervalKm - odometerKm, 0)
    }

    var isServiceDue: Bool { odometerKm - lastServiceKm >= serviceIntervalKm }
}

@Model
final class MaintenanceEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var odometerKm: Double = 0
    var title: String = ""
    var cost: Double = 0
    var notes: String = ""
    var bike: Bike?

    init(date: Date = Date(), odometerKm: Double, title: String, cost: Double = 0,
         notes: String = "", bike: Bike? = nil) {
        self.id = UUID()
        self.date = date
        self.odometerKm = odometerKm
        self.title = title
        self.cost = cost
        self.notes = notes
        self.bike = bike
    }
}

// MARK: - Garage

struct GarageView: View {
    /// The tab shell shows its own in-content header, so the native title is
    /// only useful when Garage is pushed inside another stack.
    var showsNavigationTitle = true

    @Environment(\.modelContext) private var context
    @Query(sort: \Bike.createdAt, order: .reverse) private var bikes: [Bike]
    @Query(sort: \MaintenanceEntry.date, order: .reverse) private var allEntries: [MaintenanceEntry]
    @State private var addingBike = false
    @State private var editingBike: Bike?
    @State private var bikePendingDelete: Bike?
    @State private var query = ""

    private var primaryBike: Bike? {
        bikes.first(where: \.isPrimary) ?? bikes.first
    }

    private var primaryEntries: [MaintenanceEntry] {
        guard let id = primaryBike?.id else { return [] }
        return allEntries.filter { $0.bike?.id == id }
    }

    private var filteredBikes: [Bike] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return bikes }
        return bikes.filter {
            $0.displayName.localizedCaseInsensitiveContains(needle)
                || $0.make.localizedCaseInsensitiveContains(needle)
                || $0.model.localizedCaseInsensitiveContains(needle)
                || $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        eyebrow: "",
                        title: "Garage",
                        variant: .compact,
                        identifier: AccessibilityID.Garage.title
                    )

                    if bikes.count >= 3 {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                                .font(.scaledSystem(size: 13, weight: .bold))
                                .foregroundStyle(MapUI.textTertiary)
                            TextField("Search the garage", text: $query)
                                .font(.system(.subheadline, design: .rounded))
                                .accessibilityIdentifier(AccessibilityID.Garage.search)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !query.isEmpty {
                                Button {
                                    query = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(MapUI.textTertiary)
                                }
                                .accessibilityLabel("Clear garage search")
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

                    if bikes.isEmpty {
                        RevertEmptyState(
                            systemImage: "car.2.fill",
                            title: "No vehicles yet",
                            message: "Add a bike or a car to track range, service intervals and maintenance.",
                            primaryTitle: "Add a vehicle",
                            primarySystemImage: "plus",
                            primaryAction: { addingBike = true }
                        )
                        .revertCard()
                    } else if filteredBikes.isEmpty {
                        RevertInfoNote(
                            text: "No bike matches “\(query)”.",
                            systemImage: "magnifyingglass",
                            tint: MapUI.textTertiary
                        )
                    } else {
                        ForEach(filteredBikes) { bike in
                            NavigationLink {
                                BikeDetailView(bike: bike)
                            } label: {
                                bikeCard(bike)
                            }
                            .buttonStyle(RevertCardButtonStyle())
                            .contextMenu {
                                Button {
                                    editingBike = bike
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    for other in bikes { other.isPrimary = false }
                                    bike.isPrimary = true
                                    try? context.save()
                                    WidgetBridge.updateBike(name: bike.displayName, odometerKm: bike.odometerKm, kind: bike.kind)
                                    VehiclePreferences.sync(primaryKind: bike.kind,
                                                            avoidTolls: bike.avoidTolls,
                                                            avoidHighways: bike.avoidHighways)
                                    RevertHaptics.select()
                                } label: {
                                    Label(bike.isPrimary ? "Primary bike" : "Set as primary",
                                          systemImage: bike.isPrimary ? "star.fill" : "star")
                                }
                                .disabled(bike.isPrimary)
                                Button(role: .destructive) {
                                    bikePendingDelete = bike
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }

                        Button {
                            RevertHaptics.tap()
                            addingBike = true
                        } label: {
                            Label("Add another vehicle", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(RevertSecondaryButtonStyle())
                        .accessibilityIdentifier(AccessibilityID.Garage.add)

                        maintenanceSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle(showsNavigationTitle ? "Garage" : "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingBike) {
            BikeEditorView(bike: nil)
        }
        .sheet(item: $editingBike) { bike in
            BikeEditorView(bike: bike)
        }
        .alert("Delete this vehicle?", isPresented: Binding(
            get: { bikePendingDelete != nil },
            set: { if !$0 { bikePendingDelete = nil } }
        )) {
            Button("Delete vehicle", role: .destructive) {
                if let bike = bikePendingDelete { deleteBike(bike) }
                bikePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { bikePendingDelete = nil }
        } message: {
            Text("The vehicle and its maintenance log will be removed from this iPhone.")
        }
        .onAppear {
            syncPrimaryPreferences()
            #if DEBUG
            if CommandLine.arguments.contains("-debugGarageSeed"), bikes.isEmpty {
                let sample = Bike(
                    name: "Street Triple 765 RS",
                    make: "Triumph",
                    model: "Street Triple 765 RS",
                    year: 2025,
                    odometerKm: 12_480,
                    fuelRangeKm: 240,
                    tankLiters: 15,
                    serviceIntervalKm: 8_000,
                    lastServiceKm: 8_000,
                    isPrimary: true
                )
                context.insert(sample)
                try? context.save()
            }
            if CommandLine.arguments.contains("-debugGarageCar"), bikes.isEmpty {
                let car = Bike(name: "Friends' car", make: "Volkswagen",
                               model: "Golf GTI", year: 2024, odometerKm: 18_400,
                               fuelRangeKm: 520, serviceIntervalKm: 15_000,
                               isPrimary: true, kind: .car)
                context.insert(car)
                try? context.save()
            }
            #endif
        }
        .tint(MapUI.accent)
    }

    private func distanceText(km: Double, decimals: Int = 0) -> String {
        Units.distanceText(km * 1_000, decimals: decimals)
    }

    private func deleteBike(_ bike: Bike) {
        let wasPrimary = bike.isPrimary
        context.delete(bike)
        if wasPrimary, let next = bikes.first(where: { $0.id != bike.id }) {
            next.isPrimary = true
        }
        try? context.save()
        syncPrimaryPreferences()
        // A deleted vehicle must not stay on the widget. Point it at whatever
        // became primary, or clear it when the garage is empty.
        if wasPrimary {
            if let replacement = bikes.first(where: { $0.id != bike.id }) {
                WidgetBridge.updateBike(name: replacement.displayName,
                                        odometerKm: replacement.odometerKm,
                                        kind: replacement.kind)
            } else {
                WidgetBridge.clearBike()
            }
        }
    }

    private func syncPrimaryPreferences() {
        guard let primary = bikes.first(where: \.isPrimary) ?? bikes.first else { return }
        VehiclePreferences.sync(primaryKind: primary.kind,
                                avoidTolls: primary.avoidTolls,
                                avoidHighways: primary.avoidHighways)
    }

    @ViewBuilder
    private var maintenanceSection: some View {
        if let bike = primaryBike {
            VStack(alignment: .leading, spacing: 9) {
                NavigationLink {
                    BikeDetailView(bike: bike)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MAINTENANCE")
                                .font(PulseType.section)
                                .tracking(1.6)
                                .foregroundStyle(Pulse.ink)
                            Text(bike.displayName)
                                .font(.scaledSystem(size: 10))
                                .foregroundStyle(Pulse.muted)
                        }
                        Spacer()
                        Text("VIEW LOG")
                            .font(.scaledSystem(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Pulse.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    if primaryEntries.isEmpty {
                        Text("Nothing logged yet. Open the vehicle to add the first service.")
                            .font(.scaledSystem(size: 11))
                            .foregroundStyle(Pulse.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                    } else {
                        ForEach(Array(primaryEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.scaledSystem(size: 12, weight: .semibold))
                                    .foregroundStyle(Pulse.accent)
                                    .frame(width: 28, height: 28)
                                    .background(Pulse.accentWell, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.scaledSystem(size: 12, weight: .semibold))
                                        .foregroundStyle(Pulse.ink)
                                    Text(RevertFormat.mediumDate(entry.date))
                                        .font(.scaledSystem(size: 9.5))
                                        .foregroundStyle(Pulse.muted)
                                }

                                Spacer(minLength: 4)

                                Text(distanceText(km: entry.odometerKm))
                                    .font(.scaledSystem(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Pulse.mutedStrong)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)

                            if index < min(primaryEntries.count, 3) - 1 {
                                Rectangle()
                                    .fill(Pulse.lineSoft)
                                    .frame(height: 0.8)
                                    .padding(.leading, 51)
                            }
                        }
                    }
                }
                .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Pulse.line, lineWidth: 0.8)
                }
            }
        }
    }

    private func bikeCard(_ bike: Bike) -> some View {
        let used = max(bike.odometerKm - bike.lastServiceKm, 0)
        let progress = bike.serviceIntervalKm > 0
            ? min(max(used / bike.serviceIntervalKm, 0), 1)
            : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                RevertIconBadge(
                    systemImage: bike.kind.icon,
                    tint: bike.isPrimary ? MapUI.cyan : MapUI.textSecondary,
                    size: 42,
                    radius: 13
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bike.displayName.isEmpty ? "Unnamed vehicle" : bike.displayName)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(MapUI.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        if bike.isPrimary {
                            Image(systemName: "star.fill")
                                .font(.scaledSystem(size: 10, weight: .bold))
                                .foregroundStyle(Pulse.accent)
                                .accessibilityLabel("Primary vehicle")
                        }
                    }
                    Text([bike.makeModelName == bike.displayName ? nil : bike.makeModelName,
                          bike.year > 0 ? String(bike.year) : nil,
                          distanceText(km: bike.odometerKm)]
                            .compactMap { $0 }
                            .joined(separator: "  •  "))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 6)
            }

            HStack(spacing: 0) {
                RevertStatTile(
                    label: "Odometer",
                    value: distanceText(km: bike.odometerKm)
                )
                Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                RevertStatTile(
                    label: bike.isCar ? "Range" : "Fuel range",
                    value: distanceText(km: bike.fuelRangeKm)
                )
            }

            HStack(spacing: 6) {
                Image(systemName: bike.isServiceDue
                      ? "exclamationmark.triangle.fill"
                      : "checkmark.seal.fill")
                Text(bike.isServiceDue
                     ? "Service due now"
                     : "Next service in \(distanceText(km: bike.distanceToServiceKm))")
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.scaledSystem(size: 9, weight: .bold))
                    .foregroundStyle(MapUI.textTertiary)
            }
            .font(.scaledSystem(size: 10.5, weight: .semibold))
            .foregroundStyle(bike.isServiceDue ? Pulse.caution : Pulse.positive)

            RevertProgressBar(
                value: progress,
                tint: bike.isServiceDue ? MapUI.ember : MapUI.aurora,
                height: 4
            )
        }
        .revertCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bike.displayName), \(distanceText(km: bike.odometerKm)) on the clock, \(distanceText(km: bike.fuelRangeKm)) range\(bike.isServiceDue ? ", service due" : "")")
    }
}

struct BikeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Bike.createdAt, order: .reverse) private var garageBikes: [Bike]
    let bike: Bike?

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year = 0
    @State private var odometerKm = 0.0
    @State private var fuelRangeKm = 260.0
    @State private var tankLiters = 15.0

    private var tankDisplay: Binding<Double> {
        Binding(get: { Units.volumeValue(tankLiters) },
                set: { tankLiters = Units.volumeToLiters($0) })
    }
    @State private var serviceIntervalKm = 6_000.0
    @State private var lastServiceKm = 0.0
    @State private var notes = ""
    @State private var kind: VehicleKind = .motorcycle
    @State private var isElectric = false
    @State private var avoidTolls = false
    @State private var avoidHighways = false

    /// Vehicle values are stored in kilometres. Show and accept them in the
    /// rider's chosen unit so the Garage agrees with the rest of the app.
    private func displayDistance(_ binding: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { Units.isMetric ? binding.wrappedValue : binding.wrappedValue * 0.621371192 },
            set: { binding.wrappedValue = Units.isMetric ? $0 : $0 / 0.621371192 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    Picker("Type", selection: $kind) {
                        ForEach(VehicleKind.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField(kind.isCar ? "Nickname (e.g. daily)" : "Nickname", text: $name)
                    TextField("Make", text: $make)
                    TextField("Model", text: $model)
                    // A stepper starting at year 0 needed two thousand taps to
                    // reach a modern model year.
                    Picker("Year", selection: $year) {
                        Text("—").tag(0)
                        ForEach(Array((1970...(Calendar.current.component(.year, from: Date()) + 1)).reversed()), id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if kind.isCar {
                    Section("Car routing") {
                        Toggle("Electric vehicle", isOn: $isElectric)
                        Toggle("Avoid tolls", isOn: $avoidTolls)
                        Toggle("Avoid highways", isOn: $avoidHighways)
                        Text("Toll and highway preferences are applied to live MapKit directions while this car is the primary vehicle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(kind.isCar ? "Range & service" : "Fuel & service") {
                    HStack {
                        Text(kind.isCar ? "Range" : "Fuel range")
                        Spacer()
                        TextField(Units.distanceUnit, value: displayDistance($fuelRangeKm), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Units.distanceUnit).foregroundStyle(.secondary)
                    }
                    if !kind.isCar {
                        HStack {
                            Text("Tank")
                            Spacer()
                            TextField(Units.volumeUnit, value: tankDisplay, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("L").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Service every")
                        Spacer()
                        TextField(Units.distanceUnit, value: displayDistance($serviceIntervalKm), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Units.distanceUnit).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Odometer at last service")
                        Spacer()
                        TextField(Units.distanceUnit, value: displayDistance($lastServiceKm), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Units.distanceUnit).foregroundStyle(.secondary)
                    }
                }
                Section("Odometer") {
                    HStack {
                        Text("Current")
                        Spacer()
                        TextField(Units.distanceUnit, value: displayDistance($odometerKm), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Units.distanceUnit).foregroundStyle(.secondary)
                    }
                }
                Section("Notes") {
                    TextField("Mods, tyres, oil…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .pulseBackground()
            .navigationTitle(bike == nil ? "Add vehicle" : "Edit vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && make.isEmpty && model.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard let bike else { return }
        name = bike.name
        make = bike.make
        model = bike.model
        year = bike.year
        odometerKm = bike.odometerKm
        fuelRangeKm = bike.fuelRangeKm
        tankLiters = bike.tankLiters
        serviceIntervalKm = bike.serviceIntervalKm
        lastServiceKm = bike.lastServiceKm
        notes = bike.notes
        kind = bike.kind
        isElectric = bike.isElectric
        avoidTolls = bike.avoidTolls
        avoidHighways = bike.avoidHighways
    }

    private func save() {
        let target = bike ?? Bike(name: name, kind: kind)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.make = make.trimmingCharacters(in: .whitespaces)
        target.model = model.trimmingCharacters(in: .whitespaces)
        target.year = min(max(year, 0), 2100)
        target.odometerKm = odometerKm
        target.fuelRangeKm = max(fuelRangeKm, 50)
        target.tankLiters = max(tankLiters, 1)
        target.serviceIntervalKm = max(serviceIntervalKm, 500)
        target.lastServiceKm = lastServiceKm
        target.notes = notes
        target.kind = kind
        target.isElectric = kind.isCar ? isElectric : false
        target.avoidTolls = kind.isCar ? avoidTolls : false
        target.avoidHighways = kind.isCar ? avoidHighways : false
        if bike == nil {
            // The first machine becomes the primary automatically; otherwise
            // fuel range and ride attribution fall back to defaults even
            // though the rider just entered a real bike.
            if garageBikes.isEmpty { target.isPrimary = true }
            context.insert(target)
        }
        try? context.save()
        // Only the primary vehicle may overwrite the widget snapshot; editing a
        // second bike used to replace the widget's name, odometer and kind.
        if target.isPrimary {
            WidgetBridge.updateBike(name: target.displayName, odometerKm: target.odometerKm, kind: target.kind)
        }
        if target.isPrimary || garageBikes.isEmpty {
            VehiclePreferences.sync(primaryKind: target.kind,
                                    avoidTolls: target.avoidTolls,
                                    avoidHighways: target.avoidHighways)
        }
        dismiss()
    }
}

struct BikeDetailView: View {
    @Query(sort: \SetupNote.createdAt, order: .reverse) private var setupNotes: [SetupNote]
    @Bindable var bike: Bike
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MaintenanceEntry.date, order: .reverse) private var allEntries: [MaintenanceEntry]
    @State private var addingEntry = false
    @State private var editingBike = false
    @State private var confirmingDelete = false

    private var entries: [MaintenanceEntry] {
        allEntries.filter { $0.bike?.id == bike.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MapCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: bike.kind.icon)
                                .font(.scaledSystem(size: 13, weight: .bold))
                                .foregroundStyle(MapUI.cyan)
                            Text(bike.displayName.isEmpty ? "Unnamed vehicle" : bike.displayName)
                        }
                            .font(.title2.weight(.bold))
                            .foregroundStyle(MapUI.ink)
                        if bike.makeModelName != bike.displayName, !bike.makeModelName.isEmpty {
                            Text([bike.year > 0 ? String(bike.year) : nil, bike.makeModelName]
                                .compactMap { $0 }
                                .joined(separator: "  •  "))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MapUI.secondaryInk)
                        }
                        Label(Units.distanceText(bike.odometerKm * 1_000, decimals: 0), systemImage: "gauge.with.dots.needle.67percent")
                        Label(bike.isCar
                              ? "\(Units.distanceText(bike.fuelRangeKm * 1_000, decimals: 0)) range"
                              : "\(Units.distanceText(bike.fuelRangeKm * 1_000, decimals: 0)) range  •  \(Units.volumeText(bike.tankLiters)) tank",
                              systemImage: bike.isCar ? "bolt.car.fill" : "fuelpump.fill")
                        Label(bike.isServiceDue ? "Service due" : "Next service in \(Units.distanceText(bike.distanceToServiceKm * 1_000, decimals: 0))",
                              systemImage: bike.isServiceDue ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .foregroundStyle(bike.isServiceDue ? MapUI.orange : MapUI.emerald)
                        if bike.isCar {
                            Label(bike.isElectric ? "Electric" : "Combustion",
                                  systemImage: bike.isElectric ? "bolt.car.fill" : "fuelpump.fill")
                                .foregroundStyle(bike.isElectric ? MapUI.emerald : MapUI.textSecondary)
                        }
                        if !bike.notes.isEmpty {
                            Text(bike.notes)
                                .font(.footnote)
                                .foregroundStyle(MapUI.secondaryInk)
                        }
                    }
                    // Keep the info card the same width as the log cards
                    // below it; without this it shrinks to its longest label.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink {
                    SetupNotesDetailView(bike: bike)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.scaledSystem(size: 14, weight: .bold))
                            .foregroundStyle(MapUI.cyan)
                            .frame(width: 30, height: 30)
                            .background(MapUI.cyan.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Setup notes & tyre log")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                            Text("Pressures, suspension and changes worth remembering")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(MapUI.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.scaledSystem(size: 10, weight: .bold))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .padding(12)
                    .background(MapUI.surfaceHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack {
                    Text("Maintenance log")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Button {
                        addingEntry = true
                    } label: {
                        Label("Log", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(MapUI.accent)
                }

                if entries.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.footnote)
                        .foregroundStyle(MapUI.secondaryInk)
                } else {
                    ForEach(entries) { entry in
                        MapCard {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.headline)
                                    Text("\(entry.date.formatted(date: .abbreviated, time: .omitted))  •  \(Units.distanceText(entry.odometerKm * 1_000, decimals: 0))")
                                        .font(.caption)
                                        .foregroundStyle(MapUI.secondaryInk)
                                    if !entry.notes.isEmpty {
                                        Text(entry.notes).font(.footnote)
                                    }
                                }
                                Spacer()
                                Text(entry.cost > 0
                                     ? entry.cost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                                     : "")
                                    .font(.subheadline.weight(.semibold))
                                Menu {
                                    Button(role: .destructive) {
                                        context.delete(entry)
                                        try? context.save()
                                    } label: {
                                        Label("Delete entry", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.scaledSystem(size: 12, weight: .bold))
                                        .foregroundStyle(MapUI.textTertiary)
                                        .frame(width: 26, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Maintenance entry actions")
                            }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                context.delete(entry)
                                try? context.save()
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .pulseBackground()
        .navigationTitle(bike.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingBike = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete vehicle", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Bike actions")
            }
        }
        .sheet(isPresented: $addingEntry) {
            MaintenanceEditorView(bike: bike)
        }
        .sheet(isPresented: $editingBike) {
            BikeEditorView(bike: bike)
        }
        .alert("Delete this vehicle?", isPresented: $confirmingDelete) {
            Button("Delete vehicle", role: .destructive) {
                for note in setupNotes where note.bikeID == bike.id {
                    context.delete(note)
                }
                context.delete(bike)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The vehicle and its maintenance log will be removed from this iPhone.")
        }
    }
}

struct MaintenanceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let bike: Bike
    @State private var title = ""
    @State private var date = Date()
    @State private var odometerKm = 0.0
    @State private var cost = 0.0
    @State private var notes = ""

    private func displayDistance(_ binding: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { Units.isMetric ? binding.wrappedValue : binding.wrappedValue * 0.621371192 },
            set: { binding.wrappedValue = Units.isMetric ? $0 : $0 / 0.621371192 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you do? (oil, tyres, chain…)", text: $title)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                HStack {
                    Text("Odometer")
                    Spacer()
                    TextField(Units.distanceUnit, value: displayDistance($odometerKm), format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(Units.distanceUnit).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Cost")
                    Spacer()
                    TextField("0", value: $cost, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .scrollContentBackground(.hidden)
            .pulseBackground()
            .navigationTitle("Log service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = MaintenanceEntry(date: date, odometerKm: odometerKm,
                                                     title: title.isEmpty ? "Service" : title,
                                                     cost: cost, notes: notes, bike: bike)
                        context.insert(entry)
                        bike.lastServiceKm = max(bike.lastServiceKm, odometerKm)
                        bike.odometerKm = max(bike.odometerKm, odometerKm)
                        try? context.save()
                        if bike.isPrimary {
                            WidgetBridge.updateBike(name: bike.displayName, odometerKm: bike.odometerKm, kind: bike.kind)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                odometerKm = bike.odometerKm
            }
        }
        .preferredColorScheme(.dark)
    }
}
