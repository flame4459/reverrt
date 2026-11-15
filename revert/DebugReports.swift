import Foundation

/// Text reports that belong in the same on-device debug folder as the ride
/// transcripts: crashes, loop-generation failures and anything else the rider
/// may need to send back.
///
/// They live under `Application Support/RideDebug/Reports/`, next to the ride
/// logs, so one screen can list, share and compile the whole debug folder.
nonisolated enum DebugReports {
    static let reportsFolderName = "Reports"
    static let compiledFolderName = "Compiled"

    private static let lock = NSLock()
    private static let maxReports = 80

    struct Entry: Identifiable, Hashable {
        let url: URL
        let kind: String
        let title: String
        let date: Date
        let bytes: Int

        var id: URL { url }
    }

    static var debugFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RideDebug", isDirectory: true)
    }

    static var reportsDirectory: URL {
        debugFolder.appendingPathComponent(reportsFolderName, isDirectory: true)
    }

    static var compiledDirectory: URL {
        debugFolder.appendingPathComponent(compiledFolderName, isDirectory: true)
    }

    @discardableResult
    static func write(kind: String, title: String, body: String) -> URL? {
        lock.withLock {
            do {
                try FileManager.default.createDirectory(at: reportsDirectory,
                                                        withIntermediateDirectories: true)
                let now = Date()
                let name = "\(fileStamp(now)) \(kind) — \(sanitize(title)).txt"
                let url = reportsDirectory.appendingPathComponent(name)
                let text = header(kind: kind, title: title, date: now) + "\n" + body + "\n"
                try text.write(to: url, atomically: true, encoding: .utf8)
                prune()
                return url
            } catch {
                return nil
            }
        }
    }

    static func files() -> [Entry] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: keys
        )) ?? []

        return urls
            .filter { $0.pathExtension == "txt" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                let bytes = values?.fileSize ?? 0
                let name = url.deletingPathExtension().lastPathComponent
                let kind = kind(from: name)
                let title = title(from: name)
                return Entry(url: url, kind: kind, title: title, date: date, bytes: bytes)
            }
            .sorted { $0.date > $1.date }
    }

    static func text(for entry: Entry) -> String {
        (try? String(contentsOf: entry.url, encoding: .utf8)) ?? "Could not read this report."
    }

    static func delete(_ entry: Entry) {
        lock.withLock {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    static func deleteAll() {
        lock.withLock {
            for entry in files() {
                try? FileManager.default.removeItem(at: entry.url)
            }
        }
    }

    static func compiledFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: compiledDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Naming

    static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }

    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func header(kind: String, title: String, date: Date) -> String {
        """
        REVERT DEBUG REPORT
        App \(RevertDiagnostics.appVersion) (\(RevertDiagnostics.appBuild))  iOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Device \(deviceModel)
        Generated \(date.formatted(date: .complete, time: .standard))
        Kind \(kind)
        Title \(title)

        """
    }

    private static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
        }
        return identifier.isEmpty ? "iPhone" : identifier
    }

    private static func sanitize(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(64)).isEmpty ? "Report" : String(cleaned.prefix(64))
    }

    private static func kind(from name: String) -> String {
        // "2026-11-12 07.53.02 Crash — ..."
        let parts = name.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { return "Report" }
        let rest = String(parts[2])
        return rest.components(separatedBy: " — ").first ?? "Report"
    }

    private static func title(from name: String) -> String {
        guard let range = name.range(of: " — ") else { return name }
        return String(name[range.upperBound...])
    }

    private static func prune() {
        let entries = files()
        guard entries.count > maxReports else { return }
        for entry in entries.suffix(from: maxReports) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }
}
