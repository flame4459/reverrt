import Foundation
import CoreFoundation
import CoreLocation
import UIKit

/// One plain-text transcript per recorded ride, written to
/// `Application Support/RideDebug/` and listed under Settings → Ride debug.
///
/// The point is to explain *why* the bike did or did not say something, so a
/// file carries the settings the ride ran under, every alert with the rider and
/// device positions, every device the engine deliberately skipped and why, and a
/// position sample every 5 seconds.
///
/// This is the one place in Revert that stores coordinates on purpose. The file
/// never leaves the phone unless the rider shares it from the debug screen.
@MainActor
final class RideDebug {
    static let shared = RideDebug()

    static let folderName = "RideDebug"
    /// Keep the folder small enough that listing it stays instant.
    private static let maxFiles = 40

    struct Entry: Identifiable, Hashable {
        let url: URL
        let started: Date?
        let routeName: String?
        let bytes: Int

        var id: URL { url }
    }

    private let overrideDirectory: URL?
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var startedAt: Date?
    private var lastSample = Date.distantPast
    private var counts: [String: Int] = [:]
    private var loggedSkips = Set<String>()

    private(set) var isActive = false
    private(set) var fileURL: URL?

    init(directory: URL? = nil) {
        overrideDirectory = directory
    }

    /// On unless the rider turns it off on the Ride debug screen.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "debug.rideLogging") as? Bool ?? true
    }

    var directory: URL {
        overrideDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.folderName, isDirectory: true)
    }

    // MARK: Ride lifecycle

    /// Called when the recorder starts. A no-op mid-ride or when logging is off.
    func begin(route: PlannedRoute?, bike: String?, force: Bool = false) {
        guard !isActive, force || isEnabled else { return }
        let now = Date()
        startedAt = now
        counts.removeAll()
        loggedSkips.removeAll()
        lastSample = .distantPast

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            prune()
            let url = directory.appendingPathComponent(Self.fileName(for: now, route: route?.displayName))
            bytesWritten = 0
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            fileURL = url
            isActive = true
            write(header(now: now, route: route, bike: bike))
            write(settingsBlock())
            write(routeBlock(route))
            write("--- EVENTS ---")
            write(line("BEGIN", [
                ("route", route.map { $0.displayName ?? "(unnamed)" } ?? "none"),
                ("bike", bike ?? "—"),
                ("kind", route.map { "\($0.kind)" } ?? "—"),
                ("mode", "ride")
            ]))
        } catch {
            // Debug logging must never break a ride.
            close()
        }
    }

    func finish(distanceMeters: Double, duration: TimeInterval, maxLean: Double, endedAt: Date? = nil) {
        guard isActive else { return }
        write("--- SUMMARY ---")
        write("ended \(Clock.stamp(endedAt ?? Date()))  duration=\(Clock.duration(duration))"
              + "  distance=\(Metric.distance(distanceMeters))  maxLean=\(Int(maxLean.rounded()))°")
        let alertCounts = counts.filter { $0.key.hasPrefix("hazard.") }
            .sorted { $0.key < $1.key }
            .map { "\($0.key.dropFirst("hazard.".count))=\($0.value)" }
        let curveCounts = counts.filter { $0.key.hasPrefix("curve.") }
            .sorted { $0.key < $1.key }
            .map { "\($0.key.dropFirst("curve.".count))=\($0.value)" }
        let skipCounts = counts.filter { $0.key.hasPrefix("skip.") }
            .sorted { $0.key < $1.key }
            .map { "\($0.key.dropFirst("skip.".count))=\($0.value)" }
        write("alerts hazard=\(alertCounts.isEmpty ? "—" : alertCounts.joined(separator: ","))"
              + " curve=\(curveCounts.isEmpty ? "—" : curveCounts.joined(separator: ","))"
              + " surface=\(counts["surface", default: 0])"
              + " overLimit=\(counts["overLimit", default: 0])"
              + " speedLimitChanges=\(counts["speedLimit", default: 0])")
        write("skipped \(skipCounts.isEmpty ? "—" : skipCounts.joined(separator: ","))")
        let diagnosticNames = ["NAV-JOIN", "NAV-STEP", "NAV-CUE", "NAV-STRAIGHT",
                               "WIDGET-STATE", "WIDGET-REFRESH", "WIDGET-ACTIVE",
                               "LIVE-START", "LIVE-STARTED", "LIVE-UPDATE", "LIVE-END", "SAMPLE"]
        let diagnostics = diagnosticNames
            .compactMap { name in counts[name].map { "\(name)=\($0)" } }
            .joined(separator: ",")
        write("diagnostics \(diagnostics.isEmpty ? "—" : diagnostics)")
        close()
    }

    /// Writes a summary for a ride that ended without a clean finish (the
    /// cockpit was closed while the recorder was still running).
    func finishIfActive() {
        guard isActive else { return }
        write("--- SUMMARY ---")
        write("ended \(Clock.stamp(Date()))  (cockpit closed before the ride was saved)")
        close()
    }

    private func close() {
        try? handle?.close()
        handle = nil
        isActive = false
        fileURL = nil
    }

    // MARK: Events

    func event(_ name: String, _ fields: [(String, String)] = []) {
        guard isActive else { return }
        count(name)
        write(line(name, fields))
    }

    /// What the alert engine actually had to work with. Logged once a minute;
    /// answers "did it stay quiet because there was no data".
    func data(_ fields: [(String, String)]) {
        guard isActive else { return }
        write(line("DATA", fields))
    }

    /// An important line that only makes sense once per ride: a skipped device,
    /// or why the alert engine had no route context.
    func note(_ name: String, key: String, _ fields: [(String, String)] = []) {
        guard isActive else { return }
        guard loggedSkips.insert("\(name)|\(key)").inserted else { return }
        write(line(name, fields))
    }

    /// The road the rider is actually matched to. Logged on every road change,
    /// which is what tells a real speed-limit bug from missing road data.
    func road(_ road: Road, limit: Int?, unpaved: Bool, location: CLLocation) {
        guard isActive else { return }
        event("ROAD", [
            ("id", "\(road.id)"),
            ("name", road.name ?? road.ref ?? "—"),
            ("limit", limit.map { "\($0) mph" } ?? "none"),
            ("surface", road.surface ?? (unpaved ? "unpaved" : "—")),
            ("rider", Metric.coordinate(location.coordinate))
        ])
    }

    /// A traffic device the rider was told about.
    func hazard(_ hazard: Hazard,
                ahead: Double,
                lateral: Double,
                location: CLLocation,
                progress: Double,
                lookahead: Double,
                spoken: String?) {
        guard isActive else { return }
        count("hazard.\(hazard.kind.rawValue)")
        event("HAZARD", [
            ("kind", hazard.kind.rawValue),
            ("id", "\(hazard.id)"),
            ("ahead", Metric.meters(ahead)),
            ("lateral", Metric.meters(lateral)),
            ("speed", Metric.speedPhrase(location.speed)),
            ("progress", Metric.meters(progress)),
            ("lookahead", Metric.meters(lookahead)),
            ("rider", Metric.coordinate(location.coordinate)),
            ("device", Metric.coordinate(hazard.coordinate)),
            ("spoken", spoken ?? "—")
        ])
    }

    /// A device that was on the route and close, but was withheld. Logged once
    /// per device and reason so a long ride cannot fill the file with repeats.
    func skip(_ hazard: Hazard, reason: String, ahead: Double?) {
        guard isActive else { return }
        let key = "\(hazard.id)|\(reason)"
        guard loggedSkips.insert(key).inserted else { return }
        count("skip.\(reason)")
        event("SKIP", [
            ("kind", hazard.kind.rawValue),
            ("id", "\(hazard.id)"),
            ("reason", reason),
            ("ahead", ahead.map(Metric.meters) ?? "—")
        ])
    }

    func curve(_ warning: CurveWarning, location: CLLocation) {
        guard isActive else { return }
        count("curve.\(warning.level)")
        event("CURVE", [
            ("dir", warning.dir == .left ? "left" : "right"),
            ("level", "\(warning.level)"),
            ("tightening", warning.tightening ? "yes" : "no"),
            ("radius", Metric.meters(warning.radius)),
            ("advisory", Metric.speedPhraseFromMph(Double(warning.advisoryMph))),
            ("ahead", Metric.meters(warning.distance)),
            ("speed", Metric.speedPhrase(location.speed)),
            ("apex", Metric.coordinate(CLLocationCoordinate2D(latitude: warning.apexLat, longitude: warning.apexLon))),
            ("rider", Metric.coordinate(location.coordinate))
        ])
    }

    func surface(_ text: String, location: CLLocation) {
        guard isActive else { return }
        count("surface")
        event("SURFACE", [
            ("text", text),
            ("rider", Metric.coordinate(location.coordinate))
        ])
    }

    func overLimit(mph: Double, limit: Int, location: CLLocation) {
        guard isActive else { return }
        count("overLimit")
        event("OVERLIMIT", [
            ("speed", Metric.speedPhrase(location.speed)),
            ("limit", "\(limit) mph"),
            ("over", "\(Int(mph.rounded()) - limit) mph"),
            ("rider", Metric.coordinate(location.coordinate))
        ])
    }

    func speedLimit(_ limit: Int?, road: String?, location: CLLocation) {
        guard isActive else { return }
        count("speedLimit")
        event("LIMIT", [
            ("limit", limit.map { "\($0) mph" } ?? "none"),
            ("road", road ?? "—"),
            ("rider", Metric.coordinate(location.coordinate))
        ])
    }

    /// A position trace, throttled to one line every 5 seconds. The extra
    /// cadence is deliberate: it makes a widget/step mismatch visible even on
    /// a fast road.
    func sample(_ location: CLLocation, progress: Double, remaining: Double,
                step: String? = nil, stepDistance: Double? = nil,
                turn: String? = nil, lap: Int? = nil, totalLaps: Int? = nil,
                speedLimit: Int? = nil, offRoute: Bool = false) {
        guard isActive, Date().timeIntervalSince(lastSample) >= 5 else { return }
        lastSample = Date()
        var fields: [(String, String)] = [
            ("rider", Metric.coordinate(location.coordinate)),
            ("speed", Metric.speedPhrase(location.speed)),
            // CoreLocation reports -1 for "not known yet" on course and
            // accuracy. Printing the sentinel made a clean export look broken.
            ("course", location.course >= 0 ? String(format: "%.0f°", location.course) : "—"),
            ("progress", Metric.meters(progress)),
            ("remaining", Metric.meters(remaining)),
            ("accuracy", location.horizontalAccuracy >= 0 ? Metric.meters(location.horizontalAccuracy) : "—"),
            ("offRoute", offRoute ? "yes" : "no")
        ]
        if let step { fields.append(("step", step)) }
        if let stepDistance { fields.append(("toTurn", Metric.meters(stepDistance))) }
        if let turn { fields.append(("turn", turn)) }
        if let lap { fields.append(("lap", "\(lap)/\(totalLaps ?? 0)")) }
        if let speedLimit { fields.append(("limit", "\(speedLimit) mph")) }
        event("SAMPLE", fields)
    }

    /// The complete step table is written once at the start of a ride so the
    /// turn/widget state can be compared against what navigation actually had.
    private func routeBlock(_ route: PlannedRoute?) -> String {
        guard let route else { return "--- ROUTE DETAIL ---\nnone (free ride)" }
        var lines = ["--- ROUTE DETAIL ---"]
        lines.append("kind=\(route.kind) length=\(Int(route.length))m laps=\(route.laps)"
                     + " surface=\(route.surface.title) expected=\(route.expectedTravelTime.map { Int($0) } ?? -1)s")
        lines.append("points=\(route.points.count) coordinates=\(route.coordinates.count)"
                     + " waypoints=\(route.waypoints.count) climb=\(Int(route.climbMeters))m"
                     + " maxElev=\(Int(route.maxElevation))m twist=\(String(format: "%.1f", route.twistPerKm))/km"
                     + " retraced=\(String(format: "%.3f", route.retraced)) bearing=\(Int(route.bearing))")
        lines.append("steps=\(route.steps.count)")
        for step in route.steps.prefix(250) {
            let road = step.road?.replacingOccurrences(of: "\n", with: " ") ?? "—"
            let text = step.text?.replacingOccurrences(of: "\n", with: " ") ?? "—"
            lines.append("  [\(step.id)] \(step.turn) at=\(Int(step.distance))m"
                         + " road=\(road) text=\(text)")
        }
        if route.steps.count > 250 {
            lines.append("  … \(route.steps.count - 250) more steps omitted")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: File access for the Settings screen

    func files() -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { $0.pathExtension == "txt" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Entry(url: url,
                             started: values?.creationDate ?? values?.contentModificationDate,
                             routeName: routeName(of: url),
                             bytes: values?.fileSize ?? 0)
            }
            .sorted { ($0.started ?? .distantPast) > ($1.started ?? .distantPast) }
    }

    func text(for entry: Entry) -> String {
        (try? String(contentsOf: entry.url, encoding: .utf8)) ?? "Could not read this file."
    }

    func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }

    func deleteAll() {
        for entry in files() { delete(entry) }
    }

    // MARK: Writing

    /// A cap per file: a long day of riding produced transcripts big enough to
    /// be awkward to share, and the debug export is meant to be attached to a
    /// message. Once the cap is reached the ride keeps running; it just stops
    /// adding lines.
    private static let maxFileBytes = 8 * 1024 * 1024

    private func write(_ text: String) {
        guard let handle, let data = (text + "\n").data(using: .utf8) else { return }
        guard bytesWritten + data.count <= Self.maxFileBytes else { return }
        do {
            try handle.write(contentsOf: data)
            bytesWritten += data.count
        } catch {
            close()
        }
    }

    private func line(_ name: String, _ fields: [(String, String)]) -> String {
        var out = "\(Clock.stamp(Date())) \(name)"
        for (key, value) in fields {
            out += " \(key)=\(Metric.field(value))"
        }
        return out
    }

    private func count(_ key: String) {
        counts[key, default: 0] += 1
    }

    private func header(now: Date, route: PlannedRoute?, bike: String?) -> String {
        var lines = [
            "REVERT RIDE DEBUG",
            "App \(RevertDiagnostics.appVersion) (\(RevertDiagnostics.appBuild))"
                + "  iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
                + "  \(UIDevice.current.model)",
            "Started \(Clock.stamp(now))"
        ]
        if let route {
            lines.append("Route: \(route.displayName ?? "(unnamed)")")
            lines.append("  kind=\(route.kind)  length=\(Metric.meters(route.length))"
                         + "  steps=\(route.steps.count)"
                         + "  expected=\(route.expectedTravelTime.map(Clock.duration) ?? "—")"
                         + "  twist≈\(Int(route.twistPerKm.rounded()))/km")
        } else {
            lines.append("Route: none (free ride)")
        }
        if let bike, !bike.isEmpty { lines.append("Bike: \(bike)") }
        lines.append("Vehicle: active=\(VehiclePreferences.activeKind) primary=\(VehiclePreferences.primaryKind)")
        return lines.joined(separator: "\n")
    }

    private func settingsBlock() -> String {
        let defaults = UserDefaults.standard
        var lines = ["--- SETTINGS ---"]
        let process = ProcessInfo.processInfo
        let thermal = ["nominal", "fair", "serious", "critical"][min(process.thermalState.rawValue, 3)]
        lines.append("device.thermal = \(thermal)")
        lines.append("device.lowPower = \(process.isLowPowerModeEnabled)")
        var seen = Set<String>()
        for (key, label, fallback) in Self.curatedSettings {
            seen.insert(key)
            let stored = defaults.object(forKey: key)
            lines.append("\(label) [\(key)] = \(Metric.setting(stored ?? fallback))\(stored == nil ? " (default)" : "")")
        }
        // Anything added under these prefixes later still shows up, so a new
        // alert toggle never silently goes unrecorded.
        let extra = defaults.dictionaryRepresentation().keys
            .filter { key in Self.watchedPrefixes.contains { key.hasPrefix($0) } && !seen.contains(key) }
            .sorted()
        for key in extra {
            lines.append("\(key) = \(Metric.setting(defaults.object(forKey: key)))")
        }
        return lines.joined(separator: "\n")
    }

    private static let watchedPrefixes = ["alert.", "ride.", "navigation.", "helmet.", "voice.", "units.", "vehicle."]

    private static let curatedSettings: [(key: String, label: String, fallback: Any)] = [
        ("units.system", "Units system", "automatic"),
        ("units.metric", "Units metric", false),
        ("rider.selectedBike", "Selected bike", BikeCatalog.defaultBike),
        ("ride.cameraMode", "Camera", "cockpit"),
        ("ride.autoPause", "Auto-pause", true),
        ("ride.launchCountdown", "Launch countdown", true),
        ("alert.stop", "Stop signs", true),
        ("alert.signal", "Traffic lights", true),
        ("alert.cameras", "Cameras", true),
        ("alert.rail", "Rail crossings", true),
        ("alert.school", "Schools", true),
        ("alert.roundabout", "Roundabouts", true),
        ("alert.curves", "Curve warnings", true),
        ("alert.curveAccel", "Curve aggressiveness", 3.5),
        ("alert.surface", "Unpaved warnings", true),
        ("alert.overLimit", "Over-limit warning", true),
        ("alert.limitTolerance", "Over-limit tolerance", 5),
        ("alert.hazardSpeedThreshold", "Hazard speed gate", 0),
        ("alert.reactionTime", "Reaction time", 1.5),
        ("alert.haptics", "Haptics", true),
        ("alert.voice", "Hazard voice", true),
        ("navigation.voice", "Navigation voice", true),
        ("helmet.binaural", "Helmet cues", true),
    ]

    private func prune() {
        let entries = files()
        guard entries.count >= Self.maxFiles else { return }
        for entry in entries.suffix(from: Self.maxFiles - 1) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    private func routeName(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 800), let head = String(data: data, encoding: .utf8) else {
            return nil
        }
        return head.split(separator: "\n")
            .first { $0.hasPrefix("Route: ") }
            .map { String($0.dropFirst("Route: ".count)) }
    }

    private static func fileName(for date: Date, route: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        var name = formatter.string(from: date)
        if let route, !route.isEmpty {
            let cleaned = route
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(48)
            name += " — \(cleaned)"
        }
        return name + ".txt"
    }
}

// MARK: - Formatting

private enum Clock {
    static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

private enum Metric {
    static func meters(_ value: Double) -> String {
        String(format: "%.0fm", value)
    }

    static func distance(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1_000)
    }

    static func speedPhrase(_ mps: Double) -> String {
        // CLLocation.speed is -1 until the first valid fix; the recorder
        // already clamps it, so the log must not show a negative speed.
        String(format: "%.0fkm/h", max(mps, 0) * 3.6)
    }

    static func speedPhraseFromMph(_ mph: Double) -> String {
        String(format: "%.0fkm/h", mph * 1.60934)
    }

    static func coordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    /// Bare values are fine; anything with a space is quoted so a line stays
    /// readable and greppable.
    static func field(_ value: String) -> String {
        if value.isEmpty { return "\"\"" }
        return value.contains(" ") || value.contains("=") ? "\"\(value)\"" : value
    }

    static func setting(_ value: Any?) -> String {
        switch value {
        case nil: return "unset"
        case let number as NSNumber:
            // Every Bool arrives as NSNumber; only CFBoolean is actually a flag,
            // otherwise a tolerance of 1 would be reported as "on".
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "on" : "off"
            }
            return number.stringValue
        case let string as String: return string.isEmpty ? "(empty)" : string
        default: return String(describing: value!)
        }
    }
}
