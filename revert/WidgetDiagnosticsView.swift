import SwiftUI

/// Read-only view of the Dashboard snapshot the widget consumes and
/// the provider's recent timeline/snapshot refreshes. The same data is copied
/// into the ride transcript, but this makes it inspectable without exporting.
struct WidgetDiagnosticsView: View {
    @State private var snapshot: CarWidgetSnapshot?
    @State private var logs: [String] = []
    @State private var loadedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let snapshot {
                    snapshotCard(snapshot)
                } else {
                    RevertInfoNote(
                        text: "No Dashboard snapshot has been written yet. Start a route or run the route simulator.",
                        systemImage: "rectangle.slash",
                        tint: MapUI.textTertiary
                    )
                }

                RevertSectionLabel(title: "Widget provider log", detail: "\(logs.count)")
                if logs.isEmpty {
                    Text("No widget refreshes recorded. The widget extension writes here when WidgetKit asks for a snapshot or timeline.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.reversed().enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.scaledSystem(size: 10, design: .monospaced))
                                .foregroundStyle(MapUI.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(11)
                    .background(MapUI.surfaceHigh.opacity(0.65),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                Button {
                    RevertHaptics.tap()
                    reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 46))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .pulseBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WIDGET / LIVE ACTIVITY")
                .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(MapUI.amber)
            Text("Widget diagnostics")
                .font(RevertType.display(30, weight: .heavy))
                .foregroundStyle(MapUI.ink)
            Text("The snapshot the Dashboard widget reads, plus every provider refresh. Ride transcripts also receive these entries as WIDGET-STATE and WIDGET-REFRESH.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let loadedAt {
                Text("Loaded \(loadedAt.formatted(date: .omitted, time: .standard))")
                    .font(.scaledSystem(size: 9, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
            }
        }
    }

    private func snapshotCard(_ snapshot: CarWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("DASHBOARD SNAPSHOT")
                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(MapUI.amber)
                Spacer()
                Text(snapshot.isStale ? "STALE" : snapshot.mode.rawValue.uppercased())
                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(snapshot.isStale ? MapUI.orange : MapUI.emerald)
            }

            row("Mode", snapshot.mode.rawValue)
            row("Vehicle", snapshot.isCar ? "car" : "motorcycle")
            row("Route", snapshot.routeName.isEmpty ? "—" : snapshot.routeName)
            row("Step ID", "\(snapshot.stepID)")
            row("Turn", "\(snapshot.turnSymbol) · \(snapshot.turnDistance)")
            row("Instruction", snapshot.instruction.isEmpty ? "—" : snapshot.instruction)
            row("Remaining / ETA", "\(snapshot.remaining) · \(snapshot.eta)")
            row("Speed / limit", "\(snapshot.speed) · \(snapshot.speedLimit ?? "—")")
            row("Lap", "\(snapshot.lap)/\(snapshot.totalLaps)")
            row("Hazard", snapshot.hazard ?? "—")
            row("Progress", String(format: "%.3f", snapshot.progress))
            row("Map card", snapshot.mapImage ?? "—")
            row("Updated", snapshot.updatedAt.formatted(date: .abbreviated, time: .standard))
        }
        .revertCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.scaledSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.scaledSystem(size: 11, design: .rounded))
                .foregroundStyle(MapUI.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() {
        let defaults = UserDefaults(suiteName: WidgetBridge.suiteName)
        if let data = defaults?.data(forKey: "widget.carState") {
            snapshot = try? JSONDecoder().decode(CarWidgetSnapshot.self, from: data)
        } else {
            snapshot = nil
        }
        logs = Array(WidgetDebugLog.recent().suffix(150))
        loadedAt = Date()
    }
}
