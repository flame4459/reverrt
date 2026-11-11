import SwiftUI
import CoreLocation
public import Combine

struct OfflineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var nav
    @State private var radiusKm = 16.0
    @State private var total = 0
    @State private var remaining = 0
    @State private var bytes: Int64 = 0
    @State private var message: String?
    @State private var heldAwake = false
    @State private var roadDownloading = false
    @State private var roadFailed = false
    @State private var isCalculatingBytes = false
    @State private var showingDeleteConfirmation = false
    @State private var downloadTask: Task<Void, Never>?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var completed: Int {
        max(total - remaining, 0)
    }

    private var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    private var savedSizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var messageTint: Color {
        if roadFailed { return MapUI.coral }
        if remaining > 0 { return MapUI.cyan }
        return MapUI.emerald
    }

    /// Radii are stored in kilometres but the picker must speak the rider's
    /// unit. The old picker showed "10 / 15 / 16 km" to everyone.
    private func radiusLabel(_ km: Double) -> String {
        Units.isMetric
            ? "\(Int(km.rounded())) km"
            : "\(Int((km / 1.609344).rounded())) mi"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RevertScreenHeader(
                    eyebrow: "OFFLINE RIDING",
                    title: "No-signal ready",
                    subtitle: "Save the roads, hazards, limits and surfaces around you before the signal disappears.",
                    systemImage: "arrow.down.circle"
                )

                RevertInfoNote(
                    text: "This saves routing and alert data, not map imagery. The map background may still need a signal.",
                    systemImage: "map",
                    tint: MapUI.textTertiary
                )

                downloadCard

                if remaining > 0 {
                    progressCard
                }

                coverageCard

                storageCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MapUI.cyan)
        .onAppear {
            refresh()
            updateDiskBytes()
        }
        .onReceive(timer) { _ in
            guard remaining > 0 || roadDownloading else { return }
            refresh()
        }
        .onDisappear {
            if heldAwake { IdleTimer.release("offline"); heldAwake = false }
        }
        .confirmationDialog(
            "Delete downloaded data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                RevertHaptics.warning()
                clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Roads, hazards, elevation and fuel data saved on this iPhone will be removed. You can download this area again later.")
        }
    }

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RevertCardHeader(
                icon: "square.and.arrow.down",
                title: "Download an area",
                subtitle: "Keep riding when the bars drop",
                tint: MapUI.cyan
            )

            RevertSectionLabel(title: "Area radius", detail: "\(radiusLabel(radiusKm)) around you")

            RevertOptionPicker(
                options: [8.0, 16.0, 20.0],
                selection: $radiusKm,
                title: radiusLabel
            )
            .disabled(remaining > 0)
            .opacity(remaining > 0 ? 0.5 : 1)

            Button {
                start()
            } label: {
                Label(
                    remaining > 0
                        ? "Downloading…"
                        : (roadFailed ? "Try again" : "Download around my location"),
                    systemImage: remaining > 0
                        ? "arrow.down.circle"
                        : (roadFailed ? "arrow.clockwise" : "location.fill")
                )
            }
            .buttonStyle(RevertPrimaryButtonStyle())
            .disabled(remaining > 0)
            .opacity(remaining > 0 ? 0.55 : 1)

            if let message {
                RevertInfoNote(
                    text: message,
                    systemImage: roadFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    tint: messageTint
                )
            }
        }
        .revertCard()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                RevertIconBadge(systemImage: "arrow.down.circle", tint: MapUI.cyan, size: 34, radius: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Downloading offline data")
                        .font(RevertType.headline)
                        .foregroundStyle(MapUI.ink)
                    Text("Keep Revert open until this finishes.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                }
                Spacer(minLength: 6)
                Text("\(Int(progress * 100))%")
                    .font(RevertType.number(15))
                    .foregroundStyle(MapUI.cyan)
            }

            RevertProgressBar(value: progress, tint: MapUI.aurora, height: 6)

            Text("\(completed) of \(max(total, 1)) downloads")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(MapUI.textTertiary)

            Button {
                cancelDownload()
            } label: {
                Label("Cancel download", systemImage: "xmark.circle")
            }
            .buttonStyle(RevertSecondaryButtonStyle(tint: MapUI.coral, minHeight: 44))
        }
        .revertCard()
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RevertCardHeader(
                icon: "map",
                title: "What gets saved",
                subtitle: "Everything stays on this iPhone",
                tint: MapUI.emerald
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                savedItem("Roads", "road.lanes", MapUI.cyan)
                savedItem("Hazards", "exclamationmark.triangle", MapUI.amber)
                savedItem("Speed limits", "speedometer", MapUI.orange)
                savedItem("Surfaces", "car.rear.road.lane", MapUI.violet)
                savedItem("Elevation", "mountain.2", MapUI.emerald)
                savedItem("Fuel stops", "fuelpump", MapUI.coral)
            }

            RevertInfoNote(
                text: "Existing areas are reused automatically for up to 90 days. Downloads pause if the phone locks.",
                systemImage: "lock.shield",
                tint: MapUI.textTertiary
            )
        }
        .revertCard()
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            RevertCardHeader(
                icon: "externaldrive",
                title: "Storage",
                subtitle: "On-device map data",
                tint: MapUI.violet
            )

            HStack(alignment: .firstTextBaseline) {
                Text(savedSizeText)
                    .font(RevertType.display(30, weight: .heavy))
                    .foregroundStyle(MapUI.ink)
                Text("saved")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.textTertiary)
                Spacer()
                if isCalculatingBytes {
                    ProgressView().controlSize(.small).tint(MapUI.cyan)
                }
            }

            Button {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete downloaded data", systemImage: "trash")
            }
            .buttonStyle(RevertSecondaryButtonStyle(tint: MapUI.coral, minHeight: 48))
            .disabled(remaining > 0)
            .opacity(remaining > 0 ? 0.5 : 1)
        }
        .revertCard()
    }

    private func savedItem(_ title: String, _ systemImage: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(MapUI.surfaceHigh.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func start() {
        guard let c = nav.currentLocation?.coordinate else {
            message = "Couldn't get your location. Allow location access, then try again."
            roadFailed = true
            return
        }
        RevertHaptics.rigid()
        // Hazards remain tiled, but road geometry is fetched as one bulk
        // request. That avoids turning an offline download into dozens of
        // separate road-network requests.
        let hazardTiles = HazardStore.shared.prefetch(center: c, radiusKm: radiusKm)
        let radius = radiusKm
        total = hazardTiles + 1
        roadDownloading = true
        roadFailed = false
        message = nil
        refresh()

        downloadTask = Task { @MainActor in
            // Decoding the bulk cache is real work; never do it on the main thread.
            let needsRoads = await Task.detached(priority: .userInitiated) {
                RoadStore.cachedArea(center: c, radiusKm: radius) == nil
            }.value
            guard !Task.isCancelled else { return }
            guard needsRoads else {
                roadDownloading = false
                total = hazardTiles
                if hazardTiles == 0 {
                    message = "This area is already saved."
                    roadFailed = false
                }
                refresh()
                downloadTask = nil
                return
            }
            do {
                // An explicit offline download is not an interactive route
                // request: the rider has asked for a large area and is watching
                // progress, so give the mirrors a real chance instead of the
                // planner's 14-second budget.
                _ = try await RoadStore.downloadArea(center: c, radiusKm: radiusKm, timeout: 90)
                guard !Task.isCancelled else { return }
                roadDownloading = false
                RevertHaptics.success()
                refresh()
            } catch {
                guard !Task.isCancelled else { return }
                RevertDiagnostics.log("offline download failed: \(error.localizedDescription)")
                roadDownloading = false
                roadFailed = true
                message = "Road data didn't finish downloading. Try again, or choose a smaller area."
                refresh()
            }
            downloadTask = nil
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        HazardStore.shared.cancelPending()
        roadDownloading = false
        roadFailed = false
        total = 0
        remaining = 0
        if heldAwake {
            IdleTimer.release("offline")
            heldAwake = false
        }
        message = "Download canceled."
        updateDiskBytes()
    }

    private func clear() {
        HazardStore.shared.clear()
        RoadStore.shared.clear()
        RoadStore.advShared.clear()
        RoadStore.clearBulkCache()
        ElevationService.clearDiskCache()
        FuelService.clearDiskCache()
        total = 0
        roadFailed = false
        message = "Downloaded data deleted."
        refresh()
        updateDiskBytes()
    }

    private func updateDiskBytes() {
        guard !isCalculatingBytes else { return }
        isCalculatingBytes = true
        Task.detached(priority: .utility) {
            let total = HazardStore.shared.diskBytes() + RoadStore.shared.diskBytes()
                + RoadStore.advShared.diskBytes() + RoadStore.bulkDiskBytes()
                + ElevationService.diskBytes() + FuelService.diskBytes()
            await MainActor.run {
                self.bytes = total
                self.isCalculatingBytes = false
            }
        }
    }

    private func refresh() {
        let prevRemaining = remaining
        let newRemaining = HazardStore.shared.pendingCount + (roadDownloading ? 1 : 0)
        remaining = newRemaining

        // Only calculate bytes when transitioning from downloading to done
        if prevRemaining > 0 && newRemaining == 0 {
            updateDiskBytes()
        }

        if remaining > 0, !heldAwake {
            IdleTimer.acquire("offline")   // downloads pause if the phone locks
            heldAwake = true
        }
        if remaining == 0, heldAwake {
            IdleTimer.release("offline")
            heldAwake = false
            // Don't clobber the failure message that was just written.
            if total > 0, !roadFailed { message = "Done. This area now works offline." }
        }
    }
}
