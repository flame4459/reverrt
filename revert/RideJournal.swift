import Foundation
import CoreLocation

/// Append-only journal for the ride currently being recorded.
///
/// Points are flushed in small batches while riding. If the app is killed,
/// iOS terminates it, or a save fails, the journal survives and can be turned
/// back into a `Ride` on the next launch. It is deleted only after the ride is
/// safely in SwiftData or the rider explicitly discards it.
///
/// A ride that is never saved is archived as `pending-<stamp>.jsonl` instead of
/// being deleted by the next start, and `recoveredRide()` will offer the newest
/// usable journal — active or archived — on the next launch.
final class RideJournal: @unchecked Sendable {
    static let shared = RideJournal()

    private struct Header: Codable {
        let startDate: Date
        let version: Int
    }

    private let lock = NSLock()
    private var handle: FileHandle?
    private var startDate: Date?
    /// The file `recoveredRide()` handed out, so the recovery prompt deletes
    /// exactly that ride when the rider saves or discards it.
    private var recoveredURL: URL?

    /// How many unsaved rides are kept before the oldest is dropped.
    private let maximumArchivedRides = 3

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RevertJournal", isDirectory: true)
    }

    private var fileURL: URL {
        directory.appendingPathComponent("active_ride.jsonl")
    }

    /// Archived journals, newest first.
    private func archivedURLs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("pending-") && $0.pathExtension == "jsonl" }
            .sorted { left, right in
                let a = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    private func hasContent(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.intValue > 32
    }

    private init() {}

    var hasPendingRide: Bool {
        lock.withLock {
            if hasContent(fileURL) { return true }
            return archivedURLs().contains(where: hasContent)
        }
    }

    func begin(startDate: Date) {
        lock.withLock {
            archiveExistingLocked()
            self.startDate = startDate
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    handle = nil
                    RevertDiagnostics.log("journal.begin: could not create \(fileURL.lastPathComponent)")
                    return
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                self.handle = handle
                let header = Header(startDate: startDate, version: 1)
                if let data = try? JSONEncoder().encode(header) {
                    try handle.write(contentsOf: data)
                    try handle.write(contentsOf: Data([0x0A]))
                }
            } catch {
                handle = nil
                RevertDiagnostics.log("journal.begin failed: \(error.localizedDescription)")
            }
        }
    }

    func append(_ points: [RidePoint]) {
        guard !points.isEmpty else { return }
        lock.withLock {
            guard let handle, let data = try? JSONEncoder().encode(points) else { return }
            do {
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data([0x0A]))
                try handle.synchronize()
            } catch {
                // A journal that cannot be written must never take the ride
                // down with it: stop journaling and let recording continue.
                self.handle = nil
                RevertDiagnostics.log("journal.append failed: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes the in-progress journal. Call only after the current ride is
    /// saved or explicitly discarded.
    func finish() {
        lock.withLock {
            closeLocked(remove: true)
            startDate = nil
        }
    }

    /// Deletes the journal handed out by `recoveredRide()`, plus an unusable
    /// active journal left over from a launch that could not recover it.
    func finishRecovery() {
        lock.withLock {
            if let recoveredURL {
                try? FileManager.default.removeItem(at: recoveredURL)
            }
            recoveredURL = nil
            startDate = nil
            if handle == nil {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// Reconstructs a ride from a journal left behind by a crash or a failed
    /// save. Prefers the active journal, then the newest archived one. Returns
    /// nil when there is no usable journal.
    func recoveredRide() -> Ride? {
        lock.withLock {
            recoveredURL = nil
            for url in [fileURL] + archivedURLs() {
                guard let data = try? Data(contentsOf: url), !data.isEmpty,
                      let ride = Self.decode(data), ride.points.count > 1 else { continue }
                recoveredURL = url
                return ride
            }
            return nil
        }
    }

    private static func decode(_ data: Data) -> Ride? {
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
        return makeRide(points: points, start: start, end: end)
    }

    /// Moves a journal that was never saved out of the way before a new ride
    /// starts. Deleting it here is how an unsaved ride used to disappear.
    private func archiveExistingLocked() {
        try? handle?.close()
        handle = nil
        guard hasContent(fileURL) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let destination = directory.appendingPathComponent("pending-\(Int(Date().timeIntervalSince1970)).jsonl")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
        } catch {
            RevertDiagnostics.log("journal.begin: could not archive unsaved ride: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        for stale in archivedURLs().dropFirst(maximumArchivedRides) {
            try? FileManager.default.removeItem(at: stale)
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
