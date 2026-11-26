import Testing
import Foundation
import SwiftData
@testable import Revert

/// Regression coverage for the cleanup pass: restore must be idempotent and
/// leave one primary bike, and externally supplied links must be validated.
@MainActor
struct CleanupRegressionTests {

    private func container() throws -> ModelContainer {
        let schema = Schema([Ride.self, Bike.self, MaintenanceEntry.self, SavedRoute.self,
                             Trip.self, TripDay.self, SetupNote.self, SegmentRecord.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func writeBackup(_ backup: RevertBackup) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-\(UUID().uuidString).json")
        try encoder.encode(backup).write(to: url)
        return url
    }

    private func rideSnapshot(start: Date, meters: Double) -> RideSnapshot {
        RideSnapshot(startDate: start, endDate: start.addingTimeInterval(1_800),
                     distanceMeters: meters, maxSpeedMps: 30, elevationGainMeters: 40,
                     durationSeconds: 1_800,
                     points: [RidePoint(lat: 37.1, lon: -122.1, alt: 10, speed: 20,
                                        time: start, lean: 0),
                              RidePoint(lat: 37.11, lon: -122.11, alt: 12, speed: 25,
                                        time: start.addingTimeInterval(1_800), lean: 3)],
                     maxLeanAngleDegrees: 20, bikeName: nil, bikeID: nil, routeName: nil,
                     movingSeconds: 1_700, stoppedSeconds: 100, savedRouteID: nil,
                     laps: 1, isSprint: false, routeKey: nil, vehicleKindRaw: "motorcycle")
    }

    @Test func restoringTheSameBackupTwiceDoesNotDuplicateRides() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000.123)
        var backup = RevertBackup()
        backup.rides = [rideSnapshot(start: start, meters: 12_345)]
        let url = try writeBackup(backup)
        defer { try? FileManager.default.removeItem(at: url) }

        let context = ModelContext(try container())
        let first = try RevertBackupService.restore(from: url, context: context)
        let second = try RevertBackupService.restore(from: url, context: context)
        let rides = try context.fetch(FetchDescriptor<Ride>())

        #expect(first.added == 1)
        #expect(second.added == 0)
        #expect(second.skipped == 1)
        #expect(rides.count == 1, "a second restore must not duplicate the ride")
    }

    @Test func restoreKeepsASinglePrimaryBike() throws {
        var backup = RevertBackup()
        backup.bikes = [
            BikeSnapshot(id: UUID(), name: "First", make: "", model: "", year: 2020,
                         odometerKm: 1_000, fuelRangeKm: 250, tankLiters: 15,
                         serviceIntervalKm: 6_000, lastServiceKm: 0, notes: "",
                         isPrimary: true, createdAt: Date(),
                         kindRaw: VehicleKind.motorcycle.rawValue, isElectric: false,
                         avoidTolls: false, avoidHighways: false),
            BikeSnapshot(id: UUID(), name: "Second", make: "", model: "", year: 2021,
                         odometerKm: 500, fuelRangeKm: 200, tankLiters: 12,
                         serviceIntervalKm: 6_000, lastServiceKm: 0, notes: "",
                         isPrimary: true, createdAt: Date(),
                         kindRaw: VehicleKind.motorcycle.rawValue, isElectric: false,
                         avoidTolls: false, avoidHighways: false)
        ]
        let url = try writeBackup(backup)
        defer { try? FileManager.default.removeItem(at: url) }

        let context = ModelContext(try container())
        _ = try RevertBackupService.restore(from: url, context: context)
        let bikes = try context.fetch(FetchDescriptor<Bike>())

        #expect(bikes.count == 2)
        #expect(bikes.filter(\.isPrimary).count == 1,
                "a restore must not produce two primary vehicles")
    }

    @Test func routeLinkRejectsInvalidCoordinates() throws {
        func url(lat: Double, lon: Double, points: Int = 3, laps: Int = 1) -> URL? {
            let payload = RouteLink.Payload(
                version: RouteLink.version, name: "Bad", kind: "loop", laps: laps,
                surface: "paved", expectedTravelTime: nil,
                points: (0..<points).map { _ in RouteLink.LinkPoint(lat: lat, lon: lon, road: 0) },
                steps: [], waypoints: [], createdAt: Date())
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(payload) else { return nil }
            let token = data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return URL(string: "revert://route?d=\(token)")
        }

        #expect(RouteLink.payload(from: url(lat: 200, lon: 10)!) == nil,
                "out-of-range latitude must be rejected")
        #expect(RouteLink.payload(from: url(lat: 37.5, lon: 200)!) == nil,
                "out-of-range longitude must be rejected")
        #expect(RouteLink.payload(from: url(lat: 37.5, lon: -122.5, laps: 0)!) == nil,
                "a zero lap count must be rejected")
        #expect(RouteLink.payload(from: url(lat: 37.5, lon: -122.5)!) != nil,
                "a valid link must still decode")
    }

    @Test func rivalLinkRejectsAnOversizedToken() {
        let oversized = String(repeating: "A", count: RivalLink.maxEncodedLength + 1)
        let url = URL(string: "revert://rival?d=\(oversized)")!
        #expect(RivalLink.result(from: url) == nil)
    }

    @Test func rivalLinkRejectsImpossibleNumbers() throws {
        var result = RivalResult(rider: "Rider", routeName: "Loop",
                                 routeKey: "key", durationSeconds: 600,
                                 distanceMeters: 12_000, maxLeanDegrees: 30,
                                 maxSpeedMps: 25, date: Date())
        result.durationSeconds = 1e12
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let url = URL(string: "revert://rival?d=\(token)")!
        #expect(RivalLink.result(from: url) == nil)
    }
}
