import Foundation

/// Files Revert hands to a car-screen app.
///
/// They live in `Documents/CarHandoff`, which `UIFileSharingEnabled` exposes in
/// the Files app, so the rider can import them from Organic Maps or any other
/// GPX importer. They are disposable: anything not touched for a day is removed
/// on the next launch, so the folder never grows into a pile of old routes.
nonisolated enum CarHandoffStore {
    static let folderName = "CarHandoff"
    static let maximumAge: TimeInterval = 24 * 60 * 60

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Every exported GPX, newest first.
    static func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    /// Delete exports that have not been used for `maximumAge`. Called at launch
    /// and after every write; a re-export of the same route refreshes the file's
    /// modification date, so an active route never disappears mid-trip.
    @discardableResult
    static func cleanupExpired(now: Date = Date()) -> [URL] {
        var removed: [URL] = []
        for url in files() {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > maximumAge {
                try? FileManager.default.removeItem(at: url)
                removed.append(url)
            }
        }
        if !removed.isEmpty {
            RevertDiagnostics.log("handoff.cleanup removed=\(removed.count)")
        }
        return removed
    }
}
