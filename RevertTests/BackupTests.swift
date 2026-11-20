import Foundation
import SwiftData
import Testing
@testable import Revert

/// Backups are the only protection against a reinstall, so the round trip has
/// to be proven with real rows, not just an empty store.
@MainActor
struct BackupTests {
    private func container() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Ride.self, Bike.self, MaintenanceEntry.self,
                                  SavedRoute.self, Trip.self, TripDay.self,
                                  SetupNote.self, SegmentRecord.self,
                                  configurations: config)
    }

    @Test func backupRoundTripRestoresEveryKindOfRow() throws {
        let source = try container()
        let context = source.mainContext

        let bike = Bike(name: "Street Triple", make: "Triumph", model: "RS", year: 2023,
                        odometerKm: 12_400, isPrimary: true)
        context.insert(bike)
        let service = MaintenanceEntry(date: Date(timeIntervalSince1970: 1_700_000_000),
                                       odometerKm: 12_000, title: "Oil and filter",
                                       cost: 120, notes: "10W-50", bike: bike)
        context.insert(service)

        let points = [RidePoint(lat: 40.0, lon: -73.0, alt: 20, speed: 12,
                                time: Date(timeIntervalSince1970: 1_700_000_100)),
                      RidePoint(lat: 40.01, lon: -73.01, alt: 25, speed: 14,
                                time: Date(timeIntervalSince1970: 1_700_000_200))]
        let ride = Ride(startDate: points[0].time, endDate: points[1].time,
                        distanceMeters: 1_400, maxSpeedMps: 14,
                        elevationGainMeters: 5, durationSeconds: 100, points: points)
        ride.routeName = "North loop"
        context.insert(ride)

        let placeholder = PlannedRoute(points: [], roads: [:], twistPerKm: 0,
                                       retraced: 0, bearing: 0, displayName: "North loop")
        let route = SavedRoute(route: placeholder, name: "North loop")
        route.laps = 4
        context.insert(route)

        let trip = Trip(title: "Alps week", notes: "Two passes")
        context.insert(trip)
        let day = TripDay(order: 0, title: "Day 1", startLabel: "A", endLabel: "B",
                          distanceKm: 180)
        day.trip = trip
        context.insert(day)

        let setup = SetupNote(bikeID: bike.id, title: "Track day", frontPressure: 30,
                              rearPressure: 28, notes: "Cold")
        context.insert(setup)
        try context.save()

        let url = try RevertBackupService.write(context: context)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try container()
        let summary = try RevertBackupService.restore(from: url, context: destination.mainContext)

        #expect(summary.added >= 6)
        let bikes = try destination.mainContext.fetch(FetchDescriptor<Bike>())
        #expect(bikes.count == 1)
        #expect(bikes.first?.name == "Street Triple")
        #expect((bikes.first?.maintenance ?? []).count == 1)

        let rides = try destination.mainContext.fetch(FetchDescriptor<Ride>())
        #expect(rides.count == 1)
        #expect(rides.first?.points.count == 2)
        #expect(rides.first?.routeName == "North loop")

        let routes = try destination.mainContext.fetch(FetchDescriptor<SavedRoute>())
        #expect(routes.count == 1)
        #expect(routes.first?.laps == 4)

        let trips = try destination.mainContext.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
        #expect((trips.first?.days ?? []).count == 1)

        let setups = try destination.mainContext.fetch(FetchDescriptor<SetupNote>())
        #expect(setups.count == 1)

        // Restoring the same file twice must not duplicate anything.
        let second = try RevertBackupService.restore(from: url, context: destination.mainContext)
        #expect(second.added == 0)
        #expect(try destination.mainContext.fetch(FetchDescriptor<Ride>()).count == 1)
    }
}
