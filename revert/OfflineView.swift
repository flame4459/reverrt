import SwiftUI
import CoreLocation
public import Combine

struct OfflineView: View {
    @Environment(NavigationManager.self) private var nav
    @State private var radiusKm = 16.0
    @State private var total = 0
    @State private var remaining = 0
    @State private var bytes: Int64 = 0
    @State private var message: String?
    @State private var heldAwake = false
    @State private var roadDownloading = false
    @State private var hazardDownloading = false
    @State private var regionTotal = 0
    @State private var regionDone = 0
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
                    text: "This saves routing and alert data. Map imagery with no signal comes from Offline map regions below.",
                    systemImage: "map",
                    tint: MapUI.textTertiary
                )

                NavigationLink {
                    MapRegionsView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RevertCardHeader(
                            icon: "map.fill",
                            title: "Offline map regions",
                            subtitle: "Download map areas, not just roads",
                            tint: MapUI.cyan
                        )
                        Text("The immersive map streams its tiles by default. A downloaded region removes that dependency for the area you ride.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .pulseCard()
                }
                .buttonStyle(.plain)

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
                options: [8.0, 16.0, 20.0, 32.0],
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
                .font(.scaledSystem(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.scaledSystem(size: 11, weight: .semibold, design: .rounded))
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
        let radius = radiusKm
        downloadTask?.cancel()
        roadDownloading = false
        hazardDownloading = false
        roadFailed = false
        message = nil

        downloadTask = Task { @MainActor in
            let token = BackgroundWork.begin("Revert region download")
            defer { BackgroundWork.end(token) }
            let started = Date()
            // Only the parts that are actually missing get fetched.
            let needsRoads = await Task.detached(priority: .userInitiated) {
                RoadStore.cachedArea(center: c, radiusKm: radius) == nil
            }.value
            guard !Task.isCancelled else { return }
            let needsHazards = HazardAreas.needsDownload(center: c, radiusKm: radius)

            // A region bigger than one request is downloaded cell by cell.
            if radius > RegionPrep.maxCellRadiusKm {
                await downloadRegion(center: c, radiusKm: radius, started: started)
                downloadTask = nil
                return
            }

            guard needsRoads || needsHazards else {
                total = 0
                remaining = 0
                message = "This area is already saved."
                roadFailed = false
                refresh()
                downloadTask = nil
                return
            }

            total = (needsRoads ? 1 : 0) + (needsHazards ? 1 : 0)
            roadDownloading = needsRoads
            hazardDownloading = needsHazards
            refresh()

            // Roads and hazards are different Overpass features over the same
            // bounding box, so there is no reason to queue one behind the other.
            let hazardTask: Task<Bool, Never>? = needsHazards
                ? Task { @MainActor in await downloadHazards(center: c, radius: radius, started: started) }
                : nil
            let roadsOK = needsRoads
                ? await downloadRoads(center: c, radius: radius, started: started)
                : true
            let hazardsOK = await hazardTask?.value ?? true
            guard !Task.isCancelled else { return }

            roadDownloading = false
            hazardDownloading = false
            roadFailed = !roadsOK || !hazardsOK
            if roadFailed {
                if !roadsOK && !hazardsOK {
                    message = "Map data didn't finish downloading. Try again, or choose a smaller area."
                } else if !roadsOK {
                    message = "Road data didn't finish downloading. Try again, or choose a smaller area."
                } else {
                    message = "Hazard data didn't finish downloading. Try again, or choose a smaller area."
                }
            } else {
                message = "Saved for offline riding."
                RevertHaptics.success()
            }
            RevertDiagnostics.log("offline.done \(Int(Date().timeIntervalSince(started) * 1_000))ms"
                                  + " roads=\(roadsOK) hazards=\(hazardsOK)")
            refresh()
            downloadTask = nil
        }
    }

    private func downloadRegion(center: CLLocationCoordinate2D, radiusKm: Double, started: Date) async {
        let cells = RegionPrep.cells(center: center, radiusKm: radiusKm)
        regionTotal = cells.count
        regionDone = 0
        total = cells.count
        message = nil
        refresh()

        var failures = 0
        for (index, cell) in cells.enumerated() {
            guard !Task.isCancelled else { return }
            if RoadStore.cachedArea(center: cell.center, radiusKm: cell.radiusKm) == nil {
                do {
                    _ = try await RoadStore.downloadArea(center: cell.center, radiusKm: cell.radiusKm, timeout: 60)
                } catch {
                    failures += 1
                    RevertDiagnostics.log("region cell \(index + 1) roads failed: \(error.localizedDescription)")
                }
            }
            if HazardAreas.needsDownload(center: cell.center, radiusKm: cell.radiusKm) {
                do {
                    _ = try await HazardAreas.download(center: cell.center, radiusKm: cell.radiusKm, timeout: 60)
                } catch {
                    failures += 1
                    RevertDiagnostics.log("region cell \(index + 1) hazards failed: \(error.localizedDescription)")
                }
            }
            regionDone = index + 1
            refresh()
        }

        regionTotal = 0
        regionDone = 0
        roadFailed = failures > 0
        if failures > 0 {
            message = "Part of the region didn't download (\(failures) of \(cells.count * 2) requests). Try again to fill the gaps."
        } else {
            message = "Region saved for offline riding."
            RevertHaptics.success()
        }
        RevertDiagnostics.log("region.done \(Int(Date().timeIntervalSince(started) * 1_000))ms"
                              + " cells=\(cells.count) failures=\(failures)")
        refresh()
    }

    private func downloadRoads(center: CLLocationCoordinate2D, radius: Double, started: Date) async -> Bool {
        do {
            _ = try await RoadStore.downloadArea(center: center, radiusKm: radius, timeout: 90)
            RevertDiagnostics.log("offline.roads \(Int(Date().timeIntervalSince(started) * 1_000))ms ok")
            roadDownloading = false
            refresh()
            return true
        } catch {
            RevertDiagnostics.log("offline.roads failed after \(Int(Date().timeIntervalSince(started) * 1_000))ms: \(error.localizedDescription)")
            roadDownloading = false
            refresh()
            return false
        }
    }

    private func downloadHazards(center: CLLocationCoordinate2D, radius: Double, started: Date) async -> Bool {
        do {
            _ = try await HazardAreas.download(center: center, radiusKm: radius, timeout: 90)
            RevertDiagnostics.log("offline.hazards \(Int(Date().timeIntervalSince(started) * 1_000))ms ok")
            hazardDownloading = false
            refresh()
            return true
        } catch {
            RevertDiagnostics.log("offline.hazards failed after \(Int(Date().timeIntervalSince(started) * 1_000))ms: \(error.localizedDescription)")
            hazardDownloading = false
            refresh()
            return false
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        HazardStore.shared.cancelPending()
        roadDownloading = false
        hazardDownloading = false
        roadFailed = false
        total = 0
        remaining = 0
        regionTotal = 0
        regionDone = 0
        if heldAwake {
            IdleTimer.release("offline")
            heldAwake = false
        }
        message = "Download canceled."
        updateDiskBytes()
    }

    private func clear() {
        HazardStore.shared.clear()
        HazardAreas.clear()
        GraphCache.clear()
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
            let total = HazardStore.shared.diskBytes() + HazardAreas.diskBytes() + GraphCache.diskBytes()
                + RoadStore.shared.diskBytes()
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
        let newRemaining: Int
        if regionTotal > 0 {
            newRemaining = max(regionTotal - regionDone, 0)
        } else {
            newRemaining = (roadDownloading ? 1 : 0) + (hazardDownloading ? 1 : 0)
        }
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
