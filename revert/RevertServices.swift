import Foundation
import SwiftData

/// The long-lived objects shared by the iPhone scene and the CarPlay scene.
///
/// The phone and the car must look at the *same* navigation session: starting a
/// ride on the phone has to show up on the car screen, and ending it on the car
/// has to stop the phone. A second `NavigationManager` would quietly diverge.
@MainActor
final class RevertServices {
    static let shared = RevertServices()

    let navigation = NavigationManager()

    /// One store for both scenes. The CarPlay scene needs to read saved rides,
    /// and two containers pointed at the same SQLite file would not see each
    /// other's writes reliably.
    let modelContainer: ModelContainer

    private init() {
        let schema = Schema([Ride.self, Bike.self, MaintenanceEntry.self, SavedRoute.self])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            RevertDiagnostics.log("SwiftData store failed to open: \(error.localizedDescription)")
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                // Without a store the app can still navigate; losing local
                // history is bad, but refusing to launch is worse.
                fatalError("Revert could not open its data store: \(error)")
            }
        }
    }
}
