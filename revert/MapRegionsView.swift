import SwiftUI
import CoreLocation

/// Offline map regions: what is installed, what can be downloaded, and how much
/// storage the maps take. The renderer picks these archives automatically.
struct MapRegionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MapRegionStore.shared
    @State private var pendingDelete: MapRegion?
    @State private var showingDeleteAll = false

    private var currentSource: String {
        guard let coordinate = LocationHub.shared.lastLocation?.coordinate else {
            return "Waiting for a location fix"
        }
        switch store.archive(for: coordinate).source {
        case .bundledStarter:
            return "Starter map (bundled)"
        case .installedRegion(let id):
            return store.catalog.regions.first(where: { $0.id == id })?.name ?? "Downloaded region"
        case .hosted:
            return "Online only — no offline map for this area"
        }
    }

    private var currentSourceIsOnline: Bool {
        guard let coordinate = LocationHub.shared.lastLocation?.coordinate else { return false }
        return store.archive(for: coordinate).source == .hosted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RevertScreenHeader(
                    eyebrow: "OFFLINE MAPS",
                    title: "Ride without signal",
                    subtitle: "Download the areas you ride. The map uses them automatically and never switches to a streamed map without telling you.",
                    systemImage: "map"
                )

                coverageCard
                starterCard
                availableCard
                storageCard

                Text("Map data © OpenStreetMap contributors. Region files are built with the script in Scripts/maps.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Delete this region?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let region = pendingDelete { store.delete(region) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The map for that area will need a connection again.")
        }
        .confirmationDialog("Delete all downloaded maps?", isPresented: $showingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { store.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Roads and hazards you downloaded are kept.")
        }
        .onAppear { store.refresh() }
    }

    // MARK: - Cards

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            RevertCardHeader(icon: "location.circle",
                             title: "Map here",
                             subtitle: currentSource,
                             tint: currentSourceIsOnline ? MapUI.amber : MapUI.emerald)
            Text(currentSourceIsOnline
                 ? "The immersive map streams its tiles, so a blank map here means the connection dropped. Download a region or switch to the MapKit renderer in the ride menu."
                 : "The map for this position comes from storage.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(MapUI.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .pulseCard()
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RevertSectionLabel(title: "Included with Revert")
            if let starter = store.starter {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(MapUI.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(starter.name)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                        Text("Bundled · \(starter.formattedSize)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Text("Installed")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.emerald)
                }
                .padding(14)
                .pulseCard()
            } else {
                RevertInfoNote(
                    text: "This build has no starter map bundled. Add a regional archive as `region.pmtiles` in the app target, or download a region below.",
                    systemImage: "shippingbox",
                    tint: MapUI.textTertiary
                )
            }
        }
    }

    @ViewBuilder
    private var availableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RevertSectionLabel(title: "Download regions")
            if store.downloadableRegions.isEmpty {
                RevertInfoNote(
                    text: "No regions are published in this build yet. Build one with Scripts/maps/build-region.sh, then add it to MapRegions.json.",
                    systemImage: "square.and.arrow.down",
                    tint: MapUI.textTertiary
                )
            } else {
                ForEach(store.downloadableRegions) { region in
                    regionRow(region)
                }
            }
        }
    }

    private func regionRow(_ region: MapRegion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: store.isInstalled(region) ? "checkmark.circle.fill" : "map")
                    .foregroundStyle(store.isInstalled(region) ? MapUI.emerald : MapUI.cyan)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                    Text("\(region.subtitle) · \(region.formattedSize)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.secondaryInk)
                }
                Spacer(minLength: 6)
                trailingControl(region)
            }

            if let progress = store.progressByID[region.id] {
                ProgressView(value: progress)
                    .tint(MapUI.cyan)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(MapUI.secondaryInk)
            }

            if let failure = store.failureByID[region.id] {
                Text(failure)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(MapUI.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .pulseCard()
    }

    @ViewBuilder
    private func trailingControl(_ region: MapRegion) -> some View {
        if store.isInstalled(region) {
            if store.updateAvailable(region) {
                Button {
                    Task { await store.install(region) }
                } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            Button("Delete", role: .destructive) { pendingDelete = region }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        } else if store.downloadingID == region.id || store.progressByID[region.id] != nil {
            ProgressView()
        } else {
            Button {
                Task { await store.install(region) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .disabled(store.downloadingID != nil)
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RevertCardHeader(icon: "internaldrive",
                             title: "Storage",
                             subtitle: "\(ByteCountFormatter.string(fromByteCount: store.installedBytes, countStyle: .file)) of maps installed",
                             tint: MapUI.cyan)
            if let free = store.freeSpace {
                Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free on this iPhone")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.secondaryInk)
            }
            if !store.installedRegions.isEmpty {
                Button("Delete all downloaded maps", role: .destructive) {
                    showingDeleteAll = true
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .padding(14)
        .pulseCard()
    }
}
