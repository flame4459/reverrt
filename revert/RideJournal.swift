import Foundation
import CoreLocation

/// Append-only journal for the ride currently being recorded.
///
/// Points are flushed in small batches while riding. If the app is killed,
/// iOS terminates it, or a save fails, the journal survives and can be turned
/// back into a `Ride` on the next launch. It is deleted only after the ride is
/// safely in SwiftData or the rider explicitly discards it.
final class RideJournal: @unchecked Sendable {
    static let shared = RideJournal()

    private struct Header: Codable {
        let startDate: Date
        let version: Int
    }

    private let lock = NSLock()
    private var handle: FileHandle?
    private var startDate: Date?

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RevertJournal", isDirectory: true)
    }

    private var fileURL: URL {
        directory.appendingPathComponent("active_ride.jsonl")
    }

    private init() {}

    var hasPendingRide: Bool {
        lock.withLock {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = attributes[.size] as? NSNumber else { return false }
            return size.intValue > 32
        }
    }

    func begin(startDate: Date) {
        lock.withLock {
            closeLocked(remove: true)
            self.startDate = startDate
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                handle = try FileHandle(forWritingTo: fileURL)
                let header = Header(startDate: startDate, version: 1)
                if let data = try? JSONEncoder().encode(header) {
                    handle?.write(data)
                    handle?.write(Data([0x0A]))
                }
            } catch {
                handle = nil
            }
        }
    }

    func append(_ points: [RidePoint]) {
        guard !points.isEmpty else { return }
        lock.withLock {
            guard let handle, let data = try? JSONEncoder().encode(points) else { return }
            handle.write(data)
            handle.write(Data([0x0A]))
            try? handle.synchronize()
        }
    }

    /// Deletes the in-progress journal. Call only after the ride is saved or
    /// explicitly discarded.
    func finish() {
        lock.withLock {
            closeLocked(remove: true)
            startDate = nil
        }
    }

    /// Reconstructs a ride from a journal left behind by a crash or a failed
    /// save. Returns nil when there is no usable journal.
    func recoveredRide() -> Ride? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
            let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
            guard !lines.isEmpty else { return nil }

            var headerStart: Date?
            var points: [RidePoint] = []
            for (index, line) in lines.enumerated() {
                if index == 0, let header = try? JSONDecoder().decode(Header.self, from: Data(line)) {
                    headerStart = header.startDate
                    continue
                }
                if let batch = try? JSONDecoder().decode([RidePoint].self, from: Data(line)) {
                    points.append(contentsOf: batch)
                }
            }
            guard points.count > 1 else { return nil }
            let start = headerStart ?? points.first?.time ?? Date()
            let end = points.last?.time ?? start
            return Self.makeRide(points: points, start: start, end: end)
        }
    }

    private func closeLocked(remove: Bool) {
        try? handle?.close()
        handle = nil
        if remove { try? FileManager.default.removeItem(at: fileURL) }
    }

    private static func makeRide(points: [RidePoint], start: Date, end: Date) -> Ride {
        // Same arithmetic as the live recorder, so a recovered ride reports the
        // distance the rider actually saw on the cockpit.
        let stats = RideStats.compute(points: points)
        return Ride(startDate: start, endDate: end,
                    distanceMeters: stats.distanceMeters,
                    maxSpeedMps: stats.maxSpeedMps,
                    elevationGainMeters: stats.elevationGainMeters,
                    durationSeconds: max(end.timeIntervalSince(start), 0),
                    points: points,
                    maxLeanAngleDegrees: stats.maxLeanAngleDegrees,
                    movingSeconds: stats.movingSeconds,
                    stoppedSeconds: stats.stoppedSeconds)
    }
}
