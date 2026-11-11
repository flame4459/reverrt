import Foundation

/// Privacy-preserving, on-device diagnostics. Only coarse events and error
/// messages are recorded; coordinates, place names and ride tracks never are.
enum RevertDiagnostics {
    private static let lock = NSLock()
    private static let directoryName = "RevertDiagnostics"
    private static let maxBytes = 256 * 1024

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static var logURL: URL {
        directory.appendingPathComponent("diagnostics.log")
    }

    static func log(_ message: String) {
        lock.withLock {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date())
                let line = "[\(stamp)] \(message)\n"
                if let data = line.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logURL.path) {
                        let handle = try FileHandle(forWritingTo: logURL)
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                        try handle.close()
                    } else {
                        try data.write(to: logURL, options: .atomic)
                    }
                }
                rotateIfNeeded()
            } catch {
                // Diagnostics must never affect the ride.
            }
        }
    }

    static func text() -> String {
        lock.withLock {
            (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        }
    }

    static func clear() {
        lock.withLock {
            try? FileManager.default.removeItem(at: logURL)
        }
    }

    static func exportURL() -> URL? {
        let body = text()
        guard !body.isEmpty else { return nil }
        let header = """
        Revert diagnostics
        App \(appVersion) (\(appBuild))
        iOS \(UIDeviceInfo.systemVersion)
        Generated \(Date().formatted(date: .abbreviated, time: .shortened))

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Revert diagnostics.txt")
        do {
            try (header + body).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxBytes else { return }
        // Do not call text() here: the caller already holds the lock and
        // NSLock is not recursive.
        guard let body = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let lines = body.split(separator: "\n").suffix(150)
        try? lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }
}

private enum UIDeviceInfo {
    static var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
