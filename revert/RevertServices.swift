import Foundation
import SwiftData

/// The long-lived objects shared by the iPhone scene and the widget bridge.
///
/// The phone and the car must look at the *same* navigation session: starting a
/// ride on the phone has to show up on the car screen, and ending it on the car
/// has to stop the phone. A second `NavigationManager` would quietly diverge.
@MainActor
final class RevertServices {
    static let shared = RevertServices()

    let navigation = NavigationManager()

    /// One store for the whole app. The widget bridge needs to read saved rides,
    /// and two containers pointed at the same SQLite file would not see each
    /// other's writes reliably.
    let modelContainer: ModelContainer

    /// Keeps the routing/profile defaults aligned with the garage primary even
    /// when the rider has not opened the Garage this launch. The car/bike
    /// prompt can still override the active vehicle for one route.
    func syncVehiclePreferences() {
        let context = ModelContext(modelContainer)
        let bikes = (try? context.fetch(FetchDescriptor<Bike>())) ?? []
        guard let primary = bikes.first(where: \.isPrimary) ?? bikes.first else {
            VehiclePreferences.sync(primaryKind: .motorcycle,
                                    avoidTolls: false, avoidHighways: false)
            return
        }
        VehiclePreferences.sync(primaryKind: primary.kind,
                                avoidTolls: primary.avoidTolls,
                                avoidHighways: primary.avoidHighways)
    }

    /// True when the on-disk store could not be opened and the app is running on
    /// a throwaway in-memory store. Rides cannot be saved in this state, and the
    /// UI says so instead of reporting a successful save.
    private(set) var isUsingTransientStore = false
    /// The broken store that was moved aside, if recovery had to quarantine one.
    private(set) var quarantinedStoreURL: URL?

    /// Callers that must not lose data check this before saving.
    var canPersist: Bool { !isUsingTransientStore }

    private init() {
        let schema = Schema([Ride.self, Bike.self, MaintenanceEntry.self, SavedRoute.self,
                             Trip.self, TripDay.self, SetupNote.self, SegmentRecord.self])

        // 1. The normal path.
        if let container = try? ModelContainer(for: schema) {
            modelContainer = container
            return
        }

        // 2. The store is unreadable. Keep it for recovery and try a fresh file
        //    rather than silently switching to memory and losing the session.
        RevertDiagnostics.log("store.open failed — quarantining and retrying")
        let broken = Self.quarantineStore()
        if let container = try? ModelContainer(for: schema) {
            modelContainer = container
            quarantinedStoreURL = broken
            if let broken {
                RevertDiagnostics.log("store.recovered quarantined=\(broken.lastPathComponent)")
            }
            return
        }

        // 3. Still failing: run in memory, but never pretend saves work.
        RevertDiagnostics.log("store.transient — persistent storage unavailable")
        isUsingTransientStore = true
        guard let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            fatalError("Revert could not open any data store")
        }
        modelContainer = container
    }

    /// Moves the default store and its sidecars into `Application Support/StoreRecovery`.
    /// The files are kept, never deleted, so a rider can recover them.
    private static func quarantineStore() -> URL? {
        let fileManager = FileManager.default
        let support = URL.applicationSupportDirectory
        guard let entries = try? fileManager.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil
        ) else { return nil }
        let storeFiles = entries.filter { $0.lastPathComponent.hasPrefix("default.store") }
        guard !storeFiles.isEmpty else { return nil }

        let stamp = Int(Date().timeIntervalSince1970)
        let folder = support.appending(path: "StoreRecovery", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var main: URL?
        for file in storeFiles {
            let destination = folder.appending(path: "\(file.lastPathComponent).\(stamp)")
            do {
                try fileManager.moveItem(at: file, to: destination)
                if file.lastPathComponent == "default.store" { main = destination }
            } catch {
                RevertDiagnostics.log("store.quarantine failed for \(file.lastPathComponent)")
            }
        }
        return main
    }
}
