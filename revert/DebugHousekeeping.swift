import Foundation

/// Keeps the on-device debug folder from growing forever.
///
/// Every file under `Application Support/RideDebug` — ride transcripts, crash
/// and failure reports, and compiled daily exports — is disposable once nobody
/// has looked at it for a few days. The sweep runs at launch and whenever the
/// debug screen opens, and it treats "last opened" as the newer of the file's
/// access and modification dates, because opening or sharing a report reads it.
nonisolated enum DebugHousekeeping {
    static let maximumAge: TimeInterval = 3 * 24 * 60 * 60

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RideDebug", isDirectory: true)
    }

    @discardableResult
    static func cleanupExpired(now: Date = Date()) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .contentAccessDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var removed = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .contentAccessDateKey, .contentModificationDateKey
            ])
            guard values?.isRegularFile == true else { continue }
            let accessed = values?.contentAccessDate ?? .distantPast
            let modified = values?.contentModificationDate ?? .distantPast
            let lastTouched = max(accessed, modified)
            if now.timeIntervalSince(lastTouched) > maximumAge {
                try? fileManager.removeItem(at: url)
                removed += 1
            }
        }
        if removed > 0 {
            RevertDiagnostics.log("debug.cleanup removed=\(removed)")
        }
        return removed
    }
}
