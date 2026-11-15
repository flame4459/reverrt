import SwiftUI

/// Settings → Ride debug. Lists the per-ride transcripts so they can be read,
/// shared or deleted without a Mac.
struct RideDebugView: View {
    @AppStorage("debug.rideLogging") private var enabled = true
    @State private var entries: [RideDebug.Entry] = []
    @State private var reportCount = 0
    @State private var showingSimulator = false

    var body: some View {
        List {
            Section {
                Toggle("Record ride debug files", isOn: $enabled)
            } footer: {
                Text("One text file per recorded ride: the settings it ran under, every alert with the rider and device positions, every device that was skipped and why, and a position trace every 15 seconds. Files stay on this iPhone unless you share one.")
            }

            Section {
                NavigationLink {
                    DebugReportsView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.scaledSystem(size: 14, weight: .bold))
                            .foregroundStyle(MapUI.amber)
                            .frame(width: 30, height: 30)
                            .background(MapUI.amber.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Crashes & loop failures")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                            Text("Exact reasons, plus per-day compiled exports")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(MapUI.secondaryInk)
                        }
                        Spacer(minLength: 4)
                        Text("\(reportCount)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Reports")
            } footer: {
                Text("Crash reports and loop-generation failures are written automatically beside the ride transcripts. Compile every log by date inside.")
            }

            Section {
                NavigationLink {
                    WidgetDiagnosticsView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.scaledSystem(size: 14, weight: .bold))
                            .foregroundStyle(MapUI.amber)
                            .frame(width: 30, height: 30)
                            .background(MapUI.amber.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CarPlay diagnostics")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                            Text("Widget snapshot and provider refresh log")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(MapUI.secondaryInk)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Widget")
            } footer: {
                Text("Inspect the Dashboard snapshot the CarPlay widget reads and the latest WidgetKit timeline/snapshot refreshes.")
            }

            Section {
                Button {
                    RevertHaptics.tap()
                    showingSimulator = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.scaledSystem(size: 14, weight: .bold))
                            .foregroundStyle(MapUI.cyan)
                            .frame(width: 30, height: 30)
                            .background(MapUI.cyan.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Route simulator")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                            Text("Drive the active route without leaving home")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(MapUI.secondaryInk)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.scaledSystem(size: 10, weight: .bold))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Simulator")
            } footer: {
                Text("Start navigation first, then move the app's location along the route at 1×–10×. Simulated transcripts and reports are marked SIMULATION.")
            }

            Section {
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No rides logged yet")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                        Text("The next ride you record will appear here.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.secondaryInk)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            RideDebugDetailView(entry: entry)
                        } label: {
                            row(entry)
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                HStack {
                    Text("Rides")
                    Spacer()
                    Text("\(entries.count)")
                        .foregroundStyle(MapUI.textTertiary)
                }
            } footer: {
                Text("The newest 40 files are kept; older ones are removed automatically.")
            }
        }
        .scrollContentBackground(.hidden)
        .pulseBackground()
        .navigationTitle("Ride debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete all files", role: .destructive) {
                            RideDebug.shared.deleteAll()
                            reload()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSimulator) {
            RouteSimulatorView(holdAtStart: 3.4)
        }
        .onAppear(perform: reload)
    }

    private func row(_ entry: RideDebug.Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(entry.started.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? entry.url.deletingPathExtension().lastPathComponent)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.textTertiary)
            }
            HStack(spacing: 5) {
                if entry.isSimulation {
                    Text("SIM")
                        .font(.scaledSystem(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(MapUI.amber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MapUI.amber.opacity(0.12), in: Capsule())
                }
                Text(entry.routeName ?? "Free ride")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        entries = RideDebug.shared.files()
        reportCount = DebugReports.files().count
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets where entries.indices.contains(index) {
            RideDebug.shared.delete(entries[index])
        }
        reload()
    }
}

struct RideDebugDetailView: View {
    let entry: RideDebug.Entry

    @Environment(\.dismiss) private var dismiss
    @State private var text = "Loading…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.scaledSystem(size: 10, design: .monospaced))
                .foregroundStyle(MapUI.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .scrollContentBackground(.hidden)
        .pulseBackground()
        .navigationTitle(entry.routeName ?? "Ride debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: entry.url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    RideDebug.shared.delete(entry)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete this file")
            }
        }
        .task {
            text = RideDebug.shared.text(for: entry)
        }
    }
}
