import Foundation

/// Combines every debug file for a calendar day into one text export.
///
/// Ride transcripts and crash/loop-failure reports live in different
/// subfolders, but a rider sending a problem to a developer wants one file per
/// day, not a pile of attachments.
@MainActor
enum DebugArchive {
    private struct Source {
        let url: URL
        let date: Date
        let label: String
    }

    static func compileByDate() -> [URL] {
        var sources: [Source] = []

        for entry in RideDebug.shared.files() {
            sources.append(Source(url: entry.url,
                                  date: entry.started ?? Date.distantPast,
                                  label: entry.routeName ?? "Ride"))
        }
        for entry in DebugReports.files() {
            sources.append(Source(url: entry.url,
                                  date: entry.date,
                                  label: "\(entry.kind) — \(entry.title)"))
        }

        guard !sources.isEmpty else { return [] }

        var byDay: [Date: [Source]] = [:]
        for source in sources {
            let day = Calendar.current.startOfDay(for: source.date)
            byDay[day, default: []].append(source)
        }

        do {
            try FileManager.default.createDirectory(at: DebugReports.compiledDirectory,
                                                    withIntermediateDirectories: true)
        } catch {
            return []
        }

        var outputs: [URL] = []
        for (day, daySources) in byDay.sorted(by: { $0.key > $1.key }) {
            let dayStamp = DebugReports.dayStamp(day)
            var text = """
            REVERT DEBUG EXPORT
            App \(RevertDiagnostics.appVersion) (\(RevertDiagnostics.appBuild))  iOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            Day \(day.formatted(date: .complete, time: .omitted))
            Files \(daySources.count)
            Compiled \(Date().formatted(date: .complete, time: .standard))

            This file combines every Revert debug log and report for the day.
            Files are separated by the ===== markers.

            """

            for source in daySources.sorted(by: { $0.date < $1.date }) {
                let body = (try? String(contentsOf: source.url, encoding: .utf8)) ?? "(unreadable file)"
                text += "\n\n===== \(source.label) — \(source.date.formatted(date: .abbreviated, time: .standard)) =====\n"
                text += body
            }

            let url = DebugReports.compiledDirectory
                .appendingPathComponent("Revert debug \(dayStamp).txt")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                outputs.append(url)
            } catch {
                continue
            }
        }
        return outputs
    }

    static func compiledFiles() -> [URL] {
        DebugReports.compiledFiles()
    }
}
