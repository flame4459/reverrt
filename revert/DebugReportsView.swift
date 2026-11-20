import SwiftUI

/// Crash reports, loop-generation failures and per-day compiled exports.
/// Reached from Settings → Ride debug.
struct DebugReportsView: View {
    @State private var reports: [DebugReports.Entry] = []
    @State private var compiled: [URL] = []
    @State private var compiling = false
    @State private var handoffFiles: [URL] = []

    var body: some View {
        List {
            Section {
                EmptyView()
            } footer: {
                Text("Crash reports and loop-generation failures are written here automatically. They sit beside the ride transcripts in the Revert debug folder, and anything nobody has opened for three days is deleted automatically.")
            }

            Section {
                if reports.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No crash or failure reports")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                        Text("A crash, or a loop that could not be built, will appear here with the exact reason.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.secondaryInk)
                    }
                    .padding(.vertical, 5)
                } else {
                    ForEach(reports) { entry in
                        NavigationLink {
                            DebugReportDetailView(entry: entry)
                        } label: {
                            row(entry)
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                HStack {
                    Text("Failure & crash reports")
                    Spacer()
                    Text("\(reports.count)")
                        .foregroundStyle(MapUI.textTertiary)
                }
            }

            Section {
                Button {
                    compile()
                } label: {
                    Label(compiling ? "Compiling…" : "Compile every log by date",
                          systemImage: "calendar.badge.clock")
                        .foregroundStyle(MapUI.cyan)
                }
                .disabled(compiling)

                if compiled.isEmpty {
                    Text("No compiled exports yet. Compile to get one text file per day, combining ride transcripts and reports.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.secondaryInk)
                } else {
                    ForEach(compiled, id: \.self) { url in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dayLabel(url))
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(MapUI.ink)
                                Text(sizeLabel(url))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                            Spacer(minLength: 4)
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.scaledSystem(size: 13, weight: .bold))
                                    .foregroundStyle(MapUI.cyan)
                                    .frame(width: 34, height: 34)
                                    .background(MapUI.cyan.opacity(0.10), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Share \(dayLabel(url))")
                        }
                    }
                    .onDelete(perform: deleteCompiled)
                }
            } header: {
                Text("Compiled by date")
            } footer: {
                Text("One text file per calendar day, containing every ride transcript and report from that day. Compiled files are written to the debug folder, can be shared from here, and are deleted after three days without being opened.")
            }

            Section {
                if handoffFiles.isEmpty {
                    Text("No GPX handoff files. Save one from a route's \"Send to car screen\" action and it appears here and in Files under Revert/CarHandoff.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.secondaryInk)
                } else {
                    ForEach(handoffFiles, id: \.self) { url in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(MapUI.ink)
                                    .lineLimit(2)
                                Text("\(sizeLabel(url)) · removed after 24 h unused")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                            Spacer(minLength: 4)
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.scaledSystem(size: 13, weight: .bold))
                                    .foregroundStyle(MapUI.cyan)
                                    .frame(width: 34, height: 34)
                                    .background(MapUI.cyan.opacity(0.10), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Share \(url.lastPathComponent)")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Car handoff GPX")
                    Spacer()
                    Text("\(handoffFiles.count)")
                        .foregroundStyle(MapUI.textTertiary)
                }
            } footer: {
                Text("Files shared with Organic Maps. Delete sweeps anything older than a day; the same cleanup runs on every launch.")
            }
        }
        .scrollContentBackground(.hidden)
        .pulseBackground()
        .navigationTitle("Debug reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !reports.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete all reports", role: .destructive) {
                            DebugReports.deleteAll()
                            reload()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            handoffFiles = CarHandoffStore.files()
            DebugHousekeeping.cleanupExpired()
            reload()
            #if DEBUG
            if CommandLine.arguments.contains("-debugSeedReports") {
                if DebugReports.files().isEmpty {
                    DebugReports.write(
                        kind: "Loop failure",
                        title: "No loop could be built",
                        body: """
                        REQUEST
                        start: 37.77490, -122.41940
                        target: 40.0 mi (64374 m)
                        style: twisty  mode: extended  surface: paved
                        radius: 9.2 km
                        shaping pins: 0
                        preferred roads: —
                        prefers passes: no

                        OUTCOME
                        reason: No loop could be built
                        road count: 0
                        nearest road: —
                        graph failure: no mapped roads are loaded around this start
                        mapkit candidates: 0
                        message: Couldn't build a 40 mi loop from this start. No mapped roads are loaded around this start. Try a different start or a shorter distance.

                        DIAGNOSTICS TAIL
                        plan.roads 1204ms count=0 cached=false
                        plan.search pass=1 4102ms routes=0 roads=0 failure=no mapped roads are loaded around this start
                        plan.mapkit candidates=0 routes=0 quick=0
                        """
                    )
                    DebugReports.write(
                        kind: "Crash",
                        title: "Exception NSInternalInconsistencyException",
                        body: """
                        Exception: NSInternalInconsistencyException
                        Reason: A map camera was asked to fit an empty coordinate list.
                        Stack:
                        0   Revert   0x0000000102a4f3c0 CockpitCamera.fit(_:) + 128
                        1   Revert   0x0000000102a4f110 RideView.body.getter + 992
                        2   SwiftUI  0x00000001a2a4f3c0 ...
                        """
                    )
                }
            }
            #endif
            reload()
            #if DEBUG
            if CommandLine.arguments.contains("-debugCompile") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    compile()
                }
            }
            #endif
        }
    }

    private func row(_ entry: DebugReports.Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(entry.kind.uppercased())
                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(entry.kind.localizedCaseInsensitiveContains("crash")
                                     ? MapUI.danger : MapUI.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((entry.kind.localizedCaseInsensitiveContains("crash")
                                 ? MapUI.danger : MapUI.amber).opacity(0.12), in: Capsule())
                Spacer(minLength: 6)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
            }
            Text(entry.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(MapUI.ink)
                .lineLimit(2)
            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
        }
        .padding(.vertical, 3)
    }

    private func sizeLabel(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func dayLabel(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func reload() {
        reports = DebugReports.files()
        compiled = DebugArchive.compiledFiles()
    }

    private func compile() {
        guard !compiling else { return }
        compiling = true
        Task { @MainActor in
            let urls = DebugArchive.compileByDate()
            compiled = urls.sorted { $0.lastPathComponent > $1.lastPathComponent }
            compiling = false
            if !urls.isEmpty { RevertHaptics.success() }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets where reports.indices.contains(index) {
            DebugReports.delete(reports[index])
        }
        reload()
    }

    private func deleteCompiled(_ offsets: IndexSet) {
        for index in offsets where compiled.indices.contains(index) {
            try? FileManager.default.removeItem(at: compiled[index])
        }
        reload()
    }
}

struct DebugReportDetailView: View {
    let entry: DebugReports.Entry

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
        .navigationTitle(entry.kind)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: entry.url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    DebugReports.delete(entry)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete this report")
            }
        }
        .task {
            text = DebugReports.text(for: entry)
        }
    }
}
