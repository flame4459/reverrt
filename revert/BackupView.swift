import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications
import UIKit

/// One screen for the two things that protect months of data: write everything
/// to a file the rider keeps, and bring it back after a reset or a new phone.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Query private var rides: [Ride]
    @Query private var bikes: [Bike]
    @Query private var routes: [SavedRoute]
    @Query private var trips: [Trip]

    @State private var exportURL: URL?
    @State private var sharingExport = false
    @State private var importing = false
    @State private var result: Result<(added: Int, skipped: Int), Error>?
    @State private var busy = false
    @AppStorage(BackupReminder.enabledKey) private var remindersEnabled = true
    @State private var notificationsDenied = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    stat("Rides", rides.count, "bicycle")
                    stat("Routes", routes.count, "point.topleft.down.to.point.bottomright.curvepath")
                    stat("Vehicles", bikes.count, "motorcycle")
                }
                .padding(.vertical, 4)
            } header: {
                Text("What will be saved")
            } footer: {
                Text("Rides, saved routes, vehicles and their service history, trips, setup notes, and the preferences that shape the app. Places and hazard markers are not included yet.")
            }

            Section {
                Button {
                    export()
                } label: {
                    Label(busy ? "Writing backup…" : "Back up everything", systemImage: "externaldrive.badge.plus")
                        .foregroundStyle(MapUI.cyan)
                }
                .disabled(busy)

                if let exportURL {
                    Button {
                        sharingExport = true
                    } label: {
                        Label("Share the backup file", systemImage: "square.and.arrow.up")
                            .foregroundStyle(MapUI.cyan)
                    }
                    Text(filename(exportURL))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("The file is written to Revert/Backups in Files, so it survives a delete and redownload. Keep a copy in iCloud Drive or on your Mac.")
            }

            Section {
                Toggle(isOn: $remindersEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me every 6 days")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                        Text("A notification reports how long this install has gone without a backup, before a revocation can take it.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(MapUI.secondaryInk)
                    }
                }
                .onChange(of: remindersEnabled) { _, _ in
                    Task { await BackupReminder.schedule() }
                }
                if notificationsDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Notifications are off — open Settings", systemImage: "bell.slash")
                            .foregroundStyle(Pulse.warning)
                    }
                }
            } header: {
                Text("Reminders")
            }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsDenied = settings.authorizationStatus == .denied
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Restore from a backup", systemImage: "arrow.down.doc")
                        .foregroundStyle(MapUI.cyan)
                }
                .disabled(busy)
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring adds anything that isn't already on this phone. Existing rides and routes are never overwritten, so restoring the same file twice is safe.")
            }
        }
        .scrollContentBackground(.hidden)
        .pulseBackground()
        .navigationTitle("Backup & restore")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $sharingExport) {
            if let exportURL {
                CarHandoffShareSheet(url: exportURL, onFinish: { _ in sharingExport = false })
                    .presentationDetents([.medium, .large])
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json, .data],
                      allowsMultipleSelection: false) { outcome in
            restore(outcome)
        }
        .alert("Backup", isPresented: Binding(
            get: { result != nil },
            set: { if !$0 { result = nil } }
        )) {
            Button("OK", role: .cancel) { result = nil }
        } message: {
            switch result {
            case .success(let summary):
                Text("Restored \(summary.added) items. Skipped \(summary.skipped) that were already here.")
            case .failure(let error):
                Text("The backup could not be restored: \(error.localizedDescription)")
            case nil:
                Text("")
            }
        }
    }

    private func stat(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(MapUI.cyan)
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(MapUI.ink)
            Text(title)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func export() {
        busy = true
        defer { busy = false }
        do {
            exportURL = try RevertBackupService.write(context: context)
            RevertHaptics.success()
            sharingExport = true
        } catch {
            result = .failure(error)
        }
    }

    private func restore(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                result = .success(try RevertBackupService.restore(from: url, context: context))
                RevertHaptics.success()
            } catch {
                result = .failure(error)
            }
        case .failure(let error):
            result = .failure(error)
        }
    }

    private func filename(_ url: URL) -> String {
        url.lastPathComponent
    }
}
