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

    private init() {
        let schema = Schema([Ride.self, Bike.self, MaintenanceEntry.self, SavedRoute.self,
                             Trip.self, TripDay.self, SetupNote.self])
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
