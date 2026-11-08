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

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceEntry.bike)
    var maintenance: [MaintenanceEntry]? = []

    init(name: String, make: String = "", model: String = "", year: Int = 0,
         odometerKm: Double = 0, fuelRangeKm: Double = 260, tankLiters: Double = 15,
         serviceIntervalKm: Double = 6_000, lastServiceKm: Double = 0,
         notes: String = "", isPrimary: Bool = false) {
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
    }

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
        return makeModelName.isEmpty ? "Unnamed bike" : makeModelName
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
    @Environment(\.modelContext) private var context
    @Query(sort: \Bike.createdAt, order: .reverse) private var bikes: [Bike]
    @State private var addingBike = false
    @State private var editingBike: Bike?
    @State private var bikePendingDelete: Bike?
    @State private var query = ""

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
                    RiderScreenHeader(
                        eyebrow: "YOUR GARAGE",
                        title: "Your machines",
                        subtitle: "Bikes, service intervals and the log that keeps them honest.",
                        systemImage: "wrench.and.screwdriver.fill"
                    )

                    if !bikes.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(MapUI.textTertiary)
                            TextField("Search the garage", text: $query)
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
                        RiderEmptyState(
                            systemImage: "motorcycle",
                            title: "No bikes yet",
                            message: "Add your bike to track fuel range, service intervals and maintenance.",
                            primaryTitle: "Add a bike",
                            primarySystemImage: "plus",
                            primaryAction: { addingBike = true }
                        )
                        .riderCard()
                    } else if filteredBikes.isEmpty {
                        RiderInfoNote(
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
                            .buttonStyle(RiderCardButtonStyle())
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
                                    RiderHaptics.select()
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
                            RiderHaptics.tap()
                            addingBike = true
                        } label: {
                            Label("Add another bike", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(RiderSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
        }
        .background(MapUI.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("Garage")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingBike) {
            BikeEditorView(bike: nil)
        }
        .sheet(item: $editingBike) { bike in
            BikeEditorView(bike: bike)
        }
        .alert("Delete this bike?", isPresented: Binding(
            get: { bikePendingDelete != nil },
            set: { if !$0 { bikePendingDelete = nil } }
        )) {
            Button("Delete bike", role: .destructive) {
                if let bike = bikePendingDelete { deleteBike(bike) }
                bikePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { bikePendingDelete = nil }
        } message: {
            Text("The bike and its maintenance log will be removed from this iPhone.")
        }
        .onAppear {
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
    }

    private func bikeCard(_ bike: Bike) -> some View {
        let used = max(bike.odometerKm - bike.lastServiceKm, 0)
        let progress = bike.serviceIntervalKm > 0
            ? min(max(used / bike.serviceIntervalKm, 0), 1)
            : 0
        let nextService = bike.lastServiceKm + bike.serviceIntervalKm

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                RiderIconBadge(
                    systemImage: "motorcycle",
                    tint: bike.isPrimary ? MapUI.cyan : MapUI.textSecondary,
                    size: 42,
                    radius: 13
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(bike.displayName.isEmpty ? "Unnamed bike" : bike.displayName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
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

                VStack(alignment: .trailing, spacing: 5) {
                    if bike.isPrimary {
                        RiderChip(title: "Primary", systemImage: "star.fill", isSelected: true, tint: MapUI.cyan)
                    }
                    if bike.isServiceDue {
                        RiderChip(title: "Service due", systemImage: "wrench.and.screwdriver.fill", isSelected: true, tint: MapUI.coral)
                    }
                }
            }

            HStack(spacing: 0) {
                RiderStatTile(
                    label: "Odometer",
                    value: distanceText(km: bike.odometerKm)
                )
                Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                RiderStatTile(
                    label: "Fuel range",
                    value: distanceText(km: bike.fuelRangeKm)
                )
                Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                RiderStatTile(
                    label: bike.isServiceDue ? "Service" : "Next service",
                    value: bike.isServiceDue
                        ? "Due now"
                        : distanceText(km: bike.distanceToServiceKm),
                    tint: bike.isServiceDue ? MapUI.coral : MapUI.emerald
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                RiderProgressBar(
                    value: progress,
                    tint: bike.isServiceDue ? MapUI.ember : MapUI.aurora,
                    height: 4
                )
                HStack {
                    Text(bike.isServiceDue
                         ? "Service interval reached"
                         : "Next service at \(distanceText(km: nextService))")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
            }
        }
        .riderCard()
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
    @State private var serviceIntervalKm = 6_000.0
    @State private var lastServiceKm = 0.0
    @State private var notes = ""

    /// Bike values are stored in kilometres. Show and accept them in the
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
                Section("Bike") {
                    TextField("Nickname", text: $name)
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
                Section("Fuel & service") {
                    HStack {
                        Text("Fuel range")
                        Spacer()
                        TextField(Units.distanceUnit, value: displayDistance($fuelRangeKm), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Units.distanceUnit).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Tank")
                        Spacer()
                        TextField("L", value: $tankLiters, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("L").foregroundStyle(.secondary)
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
            .background(MapUI.groupedBackground)
            .navigationTitle(bike == nil ? "Add bike" : "Edit bike")
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
    }

    private func save() {
        let target = bike ?? Bike(name: name)
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
        if bike == nil {
            // The first machine becomes the primary automatically; otherwise
            // fuel range and ride attribution fall back to defaults even
            // though the rider just entered a real bike.
            if garageBikes.isEmpty { target.isPrimary = true }
            context.insert(target)
        }
        try? context.save()
        WidgetBridge.updateBike(name: target.displayName, odometerKm: target.odometerKm)
        dismiss()
    }
}

struct BikeDetailView: View {
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
                        Text(bike.displayName.isEmpty ? "Unnamed bike" : bike.displayName)
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
                        Label("\(Units.distanceText(bike.fuelRangeKm * 1_000, decimals: 0)) range  •  \(String(format: "%.1f", bike.tankLiters)) L tank", systemImage: "fuelpump.fill")
                        Label(bike.isServiceDue ? "Service due" : "Next service in \(Units.distanceText(bike.distanceToServiceKm * 1_000, decimals: 0))",
                              systemImage: bike.isServiceDue ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .foregroundStyle(bike.isServiceDue ? MapUI.orange : MapUI.emerald)
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
                                        .font(.system(size: 12, weight: .bold))
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
        .background(MapUI.groupedBackground)
        .navigationTitle("Bike")
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
                        Label("Delete bike", systemImage: "trash")
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
        .alert("Delete this bike?", isPresented: $confirmingDelete) {
            Button("Delete bike", role: .destructive) {
                context.delete(bike)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The bike and its maintenance log will be removed from this iPhone.")
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
            .background(MapUI.groupedBackground)
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
                        WidgetBridge.updateBike(name: bike.displayName, odometerKm: bike.odometerKm)
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
