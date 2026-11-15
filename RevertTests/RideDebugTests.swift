import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct RideDebugTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RideDebugTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func transcriptRecordsSettingsAlertsAndSummary() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = RideDebug(directory: directory)
        log.begin(route: nil, bike: "Test bike", force: true)
        #expect(log.isActive)

        let hazard = Hazard(id: 42, kind: .stop, lat: 37.775, lon: -122.419)
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        log.hazard(hazard,
                   ahead: 120,
                   lateral: 3.2,
                   location: location,
                   progress: 400,
                   lookahead: 210,
                   spoken: "Stop sign in 400 feet")
        log.skip(hazard, reason: "already-announced", ahead: 120)
        log.skip(hazard, reason: "already-announced", ahead: 120) // deduped
        // Two fixes in the same tick: the trace is throttled to one per 5 s.
        log.sample(location, progress: 400, remaining: 5_200)
        log.sample(location, progress: 410, remaining: 5_190)
        log.finish(distanceMeters: 18_200, duration: 1_872, maxLean: 41)

        let files = log.files()
        #expect(files.count == 1)
        let text = try #require(files.first.map(log.text(for:)))

        #expect(text.contains("REVERT RIDE DEBUG"))
        #expect(text.contains("Bike: Test bike"))
        #expect(text.contains("--- SETTINGS ---"))
        #expect(text.contains("[alert.stop]"))
        #expect(text.contains("HAZARD kind=stop id=42 ahead=120m lateral=3m"))
        #expect(text.contains("device=37.77500,-122.41900"))
        #expect(text.contains("spoken=\"Stop sign in 400 feet\""))
        #expect(text.contains("--- SUMMARY ---"))
        #expect(text.contains("distance=18.2 km"))
        // The same withheld device is only reported once.
        #expect(text.components(separatedBy: "SKIP kind=stop").count - 1 == 1)
        #expect(text.components(separatedBy: "SAMPLE rider=37.77490,-122.41940").count - 1 == 1)
        #expect(text.contains("BEGIN route=none bike=\"Test bike\""))
    }

    @Test func loggingOffWritesNothing() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let previous = UserDefaults.standard.object(forKey: "debug.rideLogging")
        UserDefaults.standard.set(false, forKey: "debug.rideLogging")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "debug.rideLogging") }
            else { UserDefaults.standard.removeObject(forKey: "debug.rideLogging") }
        }

        let log = RideDebug(directory: directory)
        log.begin(route: nil, bike: nil)
        #expect(!log.isActive)
        #expect(log.files().isEmpty)
    }

    @Test func oldFilesArePruned() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 41 existing transcripts, then one more ride.
        for index in 0..<41 {
            let url = directory.appendingPathComponent("old-\(index).txt")
            try "stub".write(to: url, atomically: true, encoding: .utf8)
        }
        let log = RideDebug(directory: directory)
        log.begin(route: nil, bike: nil, force: true)
        log.finish(distanceMeters: 1, duration: 1, maxLean: 0)

        #expect(log.files().count <= 40)
    }
}
