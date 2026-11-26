import Foundation
import SwiftData

/// A complete, portable copy of what the rider has created: vehicles and their
/// service history, every recorded ride, saved routes, trips, setup notes and
/// the preferences that shape the app.
///
/// The point is recovery. A phone can be wiped, a container can be reset by a
/// reinstall, and none of that should cost months of rides. The file is plain
/// JSON so it can be inspected, kept in Files or iCloud Drive, and restored on
/// the same phone or a new one.
nonisolated struct RevertBackup: Codable {
    static let currentVersion = 1

    var version: Int = RevertBackup.currentVersion
    var exportedAt: Date = Date()
    var appVersion: String = ""
    var bikes: [BikeSnapshot] = []
    var maintenance: [MaintenanceSnapshot] = []
    var rides: [RideSnapshot] = []
    var savedRoutes: [SavedRouteSnapshot] = []
    var trips: [TripSnapshot] = []
    var setups: [SetupSnapshot] = []
    /// Filtered UserDefaults, stored as a plist blob so every value type survives.
    var preferences: Data?
}

nonisolated struct BikeSnapshot: Codable {
    var id: UUID
    var name: String
    var make: String
    var model: String
    var year: Int
    var odometerKm: Double
    var fuelRangeKm: Double
    var tankLiters: Double
    var serviceIntervalKm: Double
    var lastServiceKm: Double
    var notes: String
    var isPrimary: Bool
    var createdAt: Date
    var kindRaw: String
    var isElectric: Bool
    var avoidTolls: Bool
    var avoidHighways: Bool
}

nonisolated struct MaintenanceSnapshot: Codable {
    var id: UUID
    var bikeID: UUID?
    var date: Date
    var odometerKm: Double
    var title: String
    var cost: Double
    var notes: String
}

nonisolated struct RideSnapshot: Codable {
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double
    var maxSpeedMps: Double
    var elevationGainMeters: Double
    var durationSeconds: Double
    var points: [RidePoint]
    var maxLeanAngleDegrees: Double
    var bikeName: String?
    var bikeID: UUID?
    var routeName: String?
    var movingSeconds: Double
    var stoppedSeconds: Double
    var savedRouteID: UUID?
    var laps: Int
    var isSprint: Bool
    var routeKey: String?
    var vehicleKindRaw: String
}

nonisolated struct SavedRouteSnapshot: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var isLoop: Bool
    var isSprint: Bool
    var pointsData: Data
    var waypointsData: Data
    var stepsData: Data
    var roadsData: Data
    var distanceMeters: Double
    var climbMeters: Double
    var maxElevation: Double
    var twistPerKm: Double
    var retraced: Double
    var bearing: Double
    var expectedTravelTime: Double
    var surfaceRaw: String
    var laps: Int
}

nonisolated struct TripSnapshot: Codable {
    var id: UUID
    var title: String
    var notes: String
    var createdAt: Date
    var days: [TripDaySnapshot]
}

nonisolated struct TripDaySnapshot: Codable {
    var id: UUID
    var order: Int
    var title: String
    var startLabel: String
    var endLabel: String
    var distanceKm: Double
    var notes: String
    var savedRouteID: UUID?
}

nonisolated struct SetupSnapshot: Codable {
    var id: UUID
    var bikeID: UUID?
    var createdAt: Date
    var title: String
    var frontPressure: Double
    var rearPressure: Double
    var notes: String
}

// MARK: - Export / restore

@MainActor
enum RevertBackupService {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private static let preferencePrefixes = ["units.", "alert.", "map.", "voice.",
                                             "companion.", "nav.", "ride."]

    static var newestBackupURL: URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l < r
            }
    }

    static func makeBackup(context: ModelContext) throws -> RevertBackup {
        var backup = RevertBackup()
        backup.appVersion = RevertDiagnostics.appVersion

        let bikes = try context.fetch(FetchDescriptor<Bike>())
        backup.bikes = bikes.map { bike in
            BikeSnapshot(id: bike.id, name: bike.name, make: bike.make, model: bike.model,
                         year: bike.year, odometerKm: bike.odometerKm, fuelRangeKm: bike.fuelRangeKm,
                         tankLiters: bike.tankLiters, serviceIntervalKm: bike.serviceIntervalKm,
                         lastServiceKm: bike.lastServiceKm, notes: bike.notes,
                         isPrimary: bike.isPrimary, createdAt: bike.createdAt,
                         kindRaw: bike.kindRaw, isElectric: bike.isElectric,
                         avoidTolls: bike.avoidTolls, avoidHighways: bike.avoidHighways)
        }
        backup.maintenance = bikes.flatMap { bike in
            (bike.maintenance ?? []).map { entry in
                MaintenanceSnapshot(id: entry.id, bikeID: bike.id, date: entry.date,
                                    odometerKm: entry.odometerKm, title: entry.title,
                                    cost: entry.cost, notes: entry.notes)
            }
        }

        let rides = try context.fetch(FetchDescriptor<Ride>())
        backup.rides = rides.map { ride in
            RideSnapshot(startDate: ride.startDate, endDate: ride.endDate,
                         distanceMeters: ride.distanceMeters, maxSpeedMps: ride.maxSpeedMps,
                         elevationGainMeters: ride.elevationGainMeters,
                         durationSeconds: ride.durationSeconds, points: ride.points,
                         maxLeanAngleDegrees: ride.maxLeanAngleDegrees, bikeName: ride.bikeName,
                         bikeID: ride.bikeID, routeName: ride.routeName,
                         movingSeconds: ride.movingSeconds, stoppedSeconds: ride.stoppedSeconds,
                         savedRouteID: ride.savedRouteID, laps: ride.laps,
                         isSprint: ride.isSprint, routeKey: ride.routeKey,
                         vehicleKindRaw: ride.vehicleKindRaw)
        }

        let routes = try context.fetch(FetchDescriptor<SavedRoute>())
        backup.savedRoutes = routes.map { route in
            SavedRouteSnapshot(id: route.id, name: route.name, createdAt: route.createdAt,
                               isLoop: route.isLoop, isSprint: route.isSprint,
                               pointsData: route.pointsData, waypointsData: route.waypointsData,
                               stepsData: route.stepsData, roadsData: route.roadsData,
                               distanceMeters: route.distanceMeters, climbMeters: route.climbMeters,
                               maxElevation: route.maxElevation, twistPerKm: route.twistPerKm,
                               retraced: route.retraced, bearing: route.bearing,
                               expectedTravelTime: route.expectedTravelTime,
                               surfaceRaw: route.surfaceRaw, laps: route.laps)
        }

        let trips = try context.fetch(FetchDescriptor<Trip>())
        backup.trips = trips.map { trip in
            TripSnapshot(id: trip.id, title: trip.title, notes: trip.notes,
                         createdAt: trip.createdAt,
                         days: (trip.days ?? [])
                            .sorted { $0.order < $1.order }
                            .map { day in
                                TripDaySnapshot(id: day.id, order: day.order, title: day.title,
                                                startLabel: day.startLabel, endLabel: day.endLabel,
                                                distanceKm: day.distanceKm, notes: day.notes,
                                                savedRouteID: day.savedRouteID)
                            })
        }

        let setups = try context.fetch(FetchDescriptor<SetupNote>())
        backup.setups = setups.map { note in
            SetupSnapshot(id: note.id, bikeID: note.bikeID, createdAt: note.createdAt,
                          title: note.title, frontPressure: note.frontPressure,
                          rearPressure: note.rearPressure, notes: note.notes)
        }

        backup.preferences = snapshotPreferences()
        return backup
    }

    /// Writes the backup beside the handoff exports, where file sharing exposes
    /// it in the Files app, and returns the URL for the share sheet.
    @discardableResult
    static func write(context: ModelContext) throws -> URL {
        let backup = try makeBackup(context: context)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let url = directory.appendingPathComponent("Revert backup - \(formatter.string(from: Date())).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                               ofItemAtPath: url.path)
        RevertDiagnostics.log("backup.write rides=\(backup.rides.count) routes=\(backup.savedRoutes.count) bikes=\(backup.bikes.count)")
        return url
    }

    static func restore(from url: URL, context: ModelContext) throws -> (added: Int, skipped: Int) {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(RevertBackup.self, from: data)
        var added = 0
        var skipped = 0

        let existingBikes = try context.fetch(FetchDescriptor<Bike>())
        let existingBikeIDs = Set(existingBikes.map(\.id))
        // A restore must never leave two bikes starred: ride attribution keys
        // off a single primary.
        var primaryTaken = existingBikes.contains(where: \.isPrimary)
        for snapshot in backup.bikes where !existingBikeIDs.contains(snapshot.id) {
            let shouldBePrimary = snapshot.isPrimary && !primaryTaken
            if shouldBePrimary { primaryTaken = true }
            let bike = Bike(name: snapshot.name, make: snapshot.make, model: snapshot.model,
                            year: snapshot.year, odometerKm: snapshot.odometerKm,
                            fuelRangeKm: snapshot.fuelRangeKm, tankLiters: snapshot.tankLiters,
                            serviceIntervalKm: snapshot.serviceIntervalKm,
                            lastServiceKm: snapshot.lastServiceKm, notes: snapshot.notes,
                            isPrimary: shouldBePrimary,
                            kind: VehicleKind(rawValue: snapshot.kindRaw) ?? .motorcycle,
                            isElectric: snapshot.isElectric, avoidTolls: snapshot.avoidTolls,
                            avoidHighways: snapshot.avoidHighways)
            bike.id = snapshot.id
            bike.createdAt = snapshot.createdAt
            context.insert(bike)
            added += 1
        }
        let existingMaintenanceIDs = Set((try context.fetch(FetchDescriptor<MaintenanceEntry>())).map(\.id))
        for entry in backup.maintenance where !existingMaintenanceIDs.contains(entry.id) {
            guard let bike = try? context.fetch(FetchDescriptor<Bike>()).first(where: { $0.id == entry.bikeID }) else {
                skipped += 1
                continue
            }
            let item = MaintenanceEntry(date: entry.date, odometerKm: entry.odometerKm,
                                        title: entry.title, cost: entry.cost,
                                        notes: entry.notes, bike: bike)
            item.id = entry.id
            context.insert(item)
            added += 1
        }

        // Export encodes dates as ISO-8601, which drops sub-second precision, so
        // an exact timestamp key duplicated every ride on a second restore.
        // Match with a one-second tolerance instead.
        var seenRides: [(date: Date, meters: Double)] = try context.fetch(FetchDescriptor<Ride>())
            .map { ($0.startDate, $0.distanceMeters) }
        for snapshot in backup.rides {
            let isDuplicate = seenRides.contains { existing in
                abs(existing.date.timeIntervalSince(snapshot.startDate)) < 1
                    && abs(existing.meters - snapshot.distanceMeters) < 1
            }
            if isDuplicate { skipped += 1; continue }
            seenRides.append((snapshot.startDate, snapshot.distanceMeters))
            let ride = Ride(startDate: snapshot.startDate, endDate: snapshot.endDate,
                            distanceMeters: snapshot.distanceMeters, maxSpeedMps: snapshot.maxSpeedMps,
                            elevationGainMeters: snapshot.elevationGainMeters,
                            durationSeconds: snapshot.durationSeconds, points: snapshot.points,
                            maxLeanAngleDegrees: snapshot.maxLeanAngleDegrees,
                            bikeName: snapshot.bikeName, bikeID: snapshot.bikeID,
                            routeName: snapshot.routeName, movingSeconds: snapshot.movingSeconds,
                            stoppedSeconds: snapshot.stoppedSeconds,
                            savedRouteID: snapshot.savedRouteID)
            ride.laps = snapshot.laps
            ride.isSprint = snapshot.isSprint
            ride.routeKey = snapshot.routeKey
            ride.vehicleKindRaw = snapshot.vehicleKindRaw
            context.insert(ride)
            added += 1
        }

        let existingRouteIDs = Set((try context.fetch(FetchDescriptor<SavedRoute>())).map(\.id))
        for snapshot in backup.savedRoutes where !existingRouteIDs.contains(snapshot.id) {
            // SavedRoute has no empty initialiser (SwiftData needs its backing
            // storage), so start from a placeholder route and overwrite every
            // stored field with the backed-up one.
            let placeholder = PlannedRoute(points: [], roads: [:], twistPerKm: 0,
                                           retraced: 0, bearing: 0, displayName: snapshot.name)
            let route = SavedRoute(route: placeholder, name: snapshot.name)
            route.id = snapshot.id
            route.name = snapshot.name
            route.createdAt = snapshot.createdAt
            route.isLoop = snapshot.isLoop
            route.isSprint = snapshot.isSprint
            route.pointsData = snapshot.pointsData
            route.waypointsData = snapshot.waypointsData
            route.stepsData = snapshot.stepsData
            route.roadsData = snapshot.roadsData
            route.distanceMeters = snapshot.distanceMeters
            route.climbMeters = snapshot.climbMeters
            route.maxElevation = snapshot.maxElevation
            route.twistPerKm = snapshot.twistPerKm
            route.retraced = snapshot.retraced
            route.bearing = snapshot.bearing
            route.expectedTravelTime = snapshot.expectedTravelTime
            route.surfaceRaw = snapshot.surfaceRaw
            route.laps = snapshot.laps
            context.insert(route)
            added += 1
        }

        let existingTripIDs = Set((try context.fetch(FetchDescriptor<Trip>())).map(\.id))
        for snapshot in backup.trips where !existingTripIDs.contains(snapshot.id) {
            let trip = Trip(title: snapshot.title, notes: snapshot.notes)
            trip.id = snapshot.id
            trip.createdAt = snapshot.createdAt
            context.insert(trip)
            for daySnapshot in snapshot.days {
                let day = TripDay(order: daySnapshot.order, title: daySnapshot.title,
                                  startLabel: daySnapshot.startLabel, endLabel: daySnapshot.endLabel,
                                  distanceKm: daySnapshot.distanceKm, notes: daySnapshot.notes,
                                  savedRouteID: daySnapshot.savedRouteID)
                day.id = daySnapshot.id
                day.trip = trip
                context.insert(day)
            }
            added += 1
        }

        let existingSetupIDs = Set((try context.fetch(FetchDescriptor<SetupNote>())).map(\.id))
        for snapshot in backup.setups where !existingSetupIDs.contains(snapshot.id) {
            let note = SetupNote(bikeID: snapshot.bikeID, title: snapshot.title,
                                 frontPressure: snapshot.frontPressure,
                                 rearPressure: snapshot.rearPressure, notes: snapshot.notes)
            note.id = snapshot.id
            note.createdAt = snapshot.createdAt
            context.insert(note)
            added += 1
        }

        if let preferences = backup.preferences { restorePreferences(preferences) }
        do {
            try context.save()
        } catch {
            // Nothing from a failed restore may stay in the autosaving context.
            context.rollback()
            throw error
        }
        RevertDiagnostics.log("backup.restore added=\(added) skipped=\(skipped)")
        return (added, skipped)
    }

    // MARK: - Preferences

    private static func snapshotPreferences() -> Data? {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let filtered = domain.filter { key, _ in
            preferencePrefixes.contains { key.hasPrefix($0) }
        }
        return try? PropertyListSerialization.data(fromPropertyList: filtered,
                                                   format: .binary, options: 0)
    }

    private static func restorePreferences(_ data: Data) {
        guard let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        let defaults = UserDefaults.standard
        for (key, value) in dictionary {
            defaults.set(value, forKey: key)
        }
    }
}
