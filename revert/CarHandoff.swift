import SwiftUI
import UIKit
import Foundation
import CoreLocation
import UniformTypeIdentifiers

// MARK: - Route data

nonisolated struct CarHandoffPoint: Sendable {
    let lat: Double
    let lon: Double
    let elevation: Double?
    let isOriginal: Bool
}

nonisolated struct CarHandoffRoute: Sendable {
    var name: String
    /// True when the name is the rider's own (a saved route). A generated name
    /// is replaced by "Start to destination" once the places are known.
    var isSavedName: Bool = false
    let points: [CarHandoffPoint]
    var expectedTravelTime: TimeInterval?
    let createdAt: Date

    init(route: PlannedRoute) {
        let generated = route.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if generated.isEmpty {
            self.name = route.kind.isLoop ? "Scenic loop" : "Point to point"
        } else {
            self.name = generated
        }
        self.isSavedName = false
        self.expectedTravelTime = route.expectedTravelTime
        self.createdAt = Date()
        let profile = route.elevationProfile
        let cumulative = route.cumulative
        var base: [CarHandoffPoint] = route.points.enumerated().map { index, point in
            let elevation: Double?
            if profile.isEmpty {
                elevation = nil
            } else {
                let distance = index < cumulative.count ? cumulative[index] : 0
                elevation = Self.elevation(at: distance, profile: profile)
            }
            return CarHandoffPoint(lat: point.lat, lon: point.lon,
                                   elevation: elevation, isOriginal: true)
        }

        // A loop with laps set should arrive in the car app as one track that
        // covers every lap, not a single circuit. Repeat the vertices and drop
        // the seam point so the line does not stall at the start/finish.
        let laps = route.kind.isLoop ? max(route.laps, 1) : 1
        if laps > 1, base.count > 2 {
            var repeated: [CarHandoffPoint] = []
            repeated.reserveCapacity(base.count * laps)
            for lap in 0..<laps {
                let segment = lap == 0 ? base[...] : base.dropFirst()
                repeated.append(contentsOf: segment)
            }
            base = repeated
            if let travel = route.expectedTravelTime, travel > 0 {
                self.expectedTravelTime = travel * Double(laps)
            }
        }
        self.points = base
    }

    @MainActor
    init(saved: SavedRoute) {
        self.name = saved.name
        self.isSavedName = true
        self.expectedTravelTime = saved.expectedTravelTime > 0 ? saved.expectedTravelTime : nil
        self.createdAt = saved.createdAt
        self.points = saved.points.map {
            CarHandoffPoint(lat: $0.lat, lon: $0.lon, elevation: nil, isOriginal: true)
        }
    }

    private static func elevation(at distance: Double, profile: [ElevationSample]) -> Double? {
        guard let first = profile.first else { return nil }
        if distance <= first.distance { return first.elevation }
        for index in 1..<profile.count {
            let a = profile[index - 1], b = profile[index]
            if distance <= b.distance {
                let span = max(b.distance - a.distance, 0.001)
                let t = (distance - a.distance) / span
                return a.elevation + (b.elevation - a.elevation) * t
            }
        }
        return profile.last?.elevation
    }

    var totalMeters: Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { result, pair in
            result + CLLocation(latitude: pair.0.lat, longitude: pair.0.lon)
                .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lon))
        }
    }
}

// MARK: - GPX handoff exporter

nonisolated enum CarHandoffExportTarget: String, CaseIterable, Identifiable, Sendable {
    case organicMaps
    case planner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .organicMaps: "Organic Maps (car)"
        case .planner: "Kurviger / Scenic"
        }
    }

    var detail: String {
        switch self {
        case .organicMaps: "Track only, so the car app follows Revert's line."
        case .planner: "Track plus a densified route for planning importers."
        }
    }
}

nonisolated enum CarHandoffExporter {
    static let maximumPoints = 20_000
    static let preferredGapMeters = 50.0

    static func trackOnlyURL(for route: CarHandoffRoute, named name: String? = nil) -> URL? {
        write(route: route, includeRoute: false, suffix: "", name: name)
    }

    static func routeAndTrackURL(for route: CarHandoffRoute, named name: String? = nil) -> URL? {
        write(route: route, includeRoute: true, suffix: " route", name: name)
    }

    private static func write(route: CarHandoffRoute, includeRoute: Bool, suffix: String,
                              name: String? = nil) -> URL? {
        guard route.points.count > 1 else { return nil }
        let points = resampled(route.points)
        guard points.count > 1 else { return nil }
        let xml = makeXML(route: route, points: points, includeRoute: includeRoute)
        GPX.removeOldTempFiles()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let cleanName = sanitize(name ?? route.name)
        let directory = CarHandoffStore.directory
        CarHandoffStore.ensureDirectory()
        let url = directory
            .appendingPathComponent("\(cleanName) - \(df.string(from: route.createdAt))\(suffix).gpx")
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            CarHandoffStore.cleanupExpired()
            return url
        } catch {
            RevertDiagnostics.log("car handoff GPX write failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func makeXML(route: CarHandoffRoute, points: [CarHandoffPoint],
                        includeRoute: Bool) -> String {
        let iso = ISO8601DateFormatter()
        let duration = route.expectedTravelTime ?? max(route.totalMeters / (20 / 3.6), 1)
        let start = route.createdAt
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        lines.append("<gpx version=\"1.1\" creator=\"RevertApp\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n")
        lines.append("  <metadata><name>\(escape(route.name))</name><time>\(iso.string(from: start))</time></metadata>\n")
        if includeRoute {
            lines.append("  <rte>\n    <name>\(escape(route.name))</name>\n")
            for point in points {
                var line = "    <rtept lat=\"\(point.lat)\" lon=\"\(point.lon)\">"
                if let elevation = point.elevation {
                    line += "<ele>\(String(format: "%.1f", elevation))</ele>"
                }
                line += "</rtept>\n"
                lines.append(line)
            }
            lines.append("  </rte>\n")
        }
        lines.append("  <trk>\n    <name>\(escape(route.name))</name>\n    <trkseg>\n")
        for (index, point) in points.enumerated() {
            let t = duration * Double(index) / Double(max(points.count - 1, 1))
            var line = "      <trkpt lat=\"\(point.lat)\" lon=\"\(point.lon)\">"
            if let elevation = point.elevation {
                line += "<ele>\(String(format: "%.1f", elevation))</ele>"
            }
            line += "<time>\(iso.string(from: start.addingTimeInterval(t)))</time></trkpt>\n"
            lines.append(line)
        }
        lines.append("    </trkseg>\n  </trk>\n</gpx>\n")
        return lines.joined()
    }

    /// Keep every original vertex, insert points on gaps over 50 m, and only
    /// widen those gaps if an unusually long route would exceed 20k points.
    static func resampled(_ points: [CarHandoffPoint]) -> [CarHandoffPoint] {
        guard points.count > 1 else { return points }
        for gap in [50.0, 75.0, 100.0, 150.0, 200.0, 300.0, 400.0, 600.0, 800.0] {
            let result = interpolate(points, gap: gap)
            if result.count <= maximumPoints { return result }
        }
        return capped(points)
    }

    private static func interpolate(_ points: [CarHandoffPoint], gap: Double) -> [CarHandoffPoint] {
        var result: [CarHandoffPoint] = [points[0]]
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let distance = CLLocation(latitude: previous.lat, longitude: previous.lon)
                .distance(from: CLLocation(latitude: current.lat, longitude: current.lon))
            if distance > gap {
                let steps = Int(ceil(distance / gap))
                for step in 1..<steps {
                    let t = Double(step) / Double(steps)
                    result.append(CarHandoffPoint(
                        lat: previous.lat + (current.lat - previous.lat) * t,
                        lon: previous.lon + (current.lon - previous.lon) * t,
                        elevation: interpolateElevation(previous.elevation, current.elevation, t),
                        isOriginal: false
                    ))
                }
            }
            result.append(current)
        }
        return result
    }

    private static func capped(_ points: [CarHandoffPoint]) -> [CarHandoffPoint] {
        guard points.count > maximumPoints else { return points }
        let originals = points.indices.filter { points[$0].isOriginal }
        var keep = Set<Int>()
        if originals.count <= maximumPoints {
            keep.formUnion(originals)
            let step = max(1, points.count / maximumPoints)
            var index = 0
            while keep.count < maximumPoints, index < points.count {
                keep.insert(index)
                index += step
            }
        } else {
            let step = Int(ceil(Double(originals.count) / Double(maximumPoints)))
            for (position, index) in originals.enumerated() where position % step == 0 {
                keep.insert(index)
            }
        }
        return points.enumerated().filter { keep.contains($0.offset) }.map(\.element)
    }

    private static func interpolateElevation(_ a: Double?, _ b: Double?, _ t: Double) -> Double? {
        guard let a, let b else { return nil }
        return a + (b - a) * t
    }

    static func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Route" : String(cleaned.prefix(80))
    }

    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Automatic delivery

/// Tries to hand the GPX straight to a document handler before any UI appears.
/// `open` on a file URL launches the app that owns the type — Organic Maps, when it
/// registered GPX — which is the fastest path and needs no share sheet. It is
/// retried because a cold app can refuse the first request while it launches.
@MainActor
enum CarHandoffAutoSender {
    /// Kept alive: `UIDocumentInteractionController` is invalidated the moment
    /// it is deallocated, and the menu would vanish with it.
    private static var openInController: UIDocumentInteractionController?

    static func open(_ url: URL, attempts: Int = 3) async -> Bool {
        for attempt in 1...max(attempts, 1) {
            let opened = await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
            RevertDiagnostics.log("handoff.auto attempt=\(attempt) opened=\(opened)")
            if opened { return true }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        return false
    }

    /// The sanctioned way to hand a document to another app: the "Open in" menu
    /// grants the receiver access to the file. `open` on a file URL does not,
    /// which is why every attempt can fail even when the app is installed.
    @discardableResult
    static func presentOpenInMenu(_ url: URL) -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            RevertDiagnostics.log("handoff.openin no window")
            return false
        }
        let controller = UIDocumentInteractionController(url: url)
        openInController = controller
        let presented = controller.presentOpenInMenu(from: root.view.bounds,
                                                     in: root.view,
                                                     animated: true)
        RevertDiagnostics.log("handoff.openin presented=\(presented)")
        return presented
    }
}

// MARK: - Files export

/// A GPX file wrapped for SwiftUI's file exporter. Saving through the exporter
/// is the reliable bridge to apps that import from Files rather than the share
/// sheet (Organic Maps is one of them).
struct GPXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [gpxType] }
    static var gpxType: UTType { UTType(filenameExtension: "gpx") ?? .xml }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - UI

struct CarHandoffButton: View {
    let route: CarHandoffRoute
    var compact = false
    @State private var showing = false

    var body: some View {
        Button {
            RevertHaptics.tap()
            showing = true
        } label: {
            Label(compact ? "Car screen" : "Send to car screen",
                  systemImage: "car.side.fill")
        }
        .buttonStyle(RevertSecondaryButtonStyle(minHeight: compact ? 44 : 48))
        .accessibilityLabel("Send to car screen")
        .accessibilityHint("Shares a GPX track with a car display app")
        .sheet(isPresented: $showing) {
            CarHandoffSheet(route: route)
        }
    }
}

@MainActor
enum CarAppLauncher {
    /// iOS has no API to list installed apps. `canOpenURL` is the supported
    /// best-effort check, and only works when Organic Maps declares one of these
    /// schemes. A false result means "not detected", not proof it is absent.
    static let candidateSchemes = [
        "om", "organicmaps"
    ]
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id1567437057")!

    static var isInstalled: Bool { launchURL != nil }

    /// The first scheme the device actually answers for — used by the
    /// "Open Organic Maps" button after a track has been shared.
    static var launchURL: URL? {
        for scheme in candidateSchemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            if UIApplication.shared.canOpenURL(url) { return url }
        }
        return nil
    }
}

private enum CarHandoffAlert: Int, Identifiable {
    case organicMapsRequired
    case muteHelp

    var id: Int { rawValue }
}

struct CarHandoffSheet: View {
    let route: CarHandoffRoute
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("carHandoff.seen") private var seen = false
    @AppStorage("carHandoff.mutedCarApp") private var mutedCarApp = false
    @AppStorage("carHandoff.organicMapsNoticeSeen") private var carAppNoticeSeen = false
    @AppStorage("carHandoff.organicMapsConfirmed") private var carAppConfirmed = false
    @State private var target: CarHandoffExportTarget = .organicMaps
    @State private var sharing = false
    @State private var shareURL: URL?
    @State private var didShare = false
    @State private var exportDocument: GPXDocument?
    @State private var exportName = "Revert route"
    @State private var showingExporter = false
    @State private var savedToFiles = false
    @State private var sending = false
    @State private var resolvedName: String?
    @State private var autoSendFailed = false
    @State private var activeAlert: CarHandoffAlert?
    @State private var carAppDetected: Bool?

    private static let carAppStoreURL = CarAppLauncher.appStoreURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if target == .organicMaps {
                        carAppRequirement
                    }
                    if seen {
                        compactSteps
                    } else {
                        steps
                    }
                    targetPicker
                    sendButton
                    Button {
                        saveToFiles()
                    } label: {
                        Label("Save to Files instead", systemImage: "folder")
                    }
                    .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                    .disabled(route.points.count < 2)
                    if target == .organicMaps, !didShare, !savedToFiles, autoSendFailed {
                        RevertInfoNote(
                            text: "If Organic Maps isn't listed in the share sheet, tap Save to Files. The track is also kept under On My iPhone → Revert → CarHandoff for its importer.",
                            systemImage: "info.circle",
                            tint: Pulse.muted
                        )
                    }
                    if didShare || savedToFiles {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Pulse.emerald)
                            Text(savedToFiles
                                 ? "Saved to On My iPhone → Revert → CarHandoff. Import it from Organic Maps' bookmarks screen."
                                 : (target == .organicMaps
                                    ? "Shared. The track is in Organic Maps' bookmarks — open it on the car screen."
                                    : "Sent. Import it in your planner before riding."))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                        }
                        .padding(.vertical, 3)
                    }
                    if didShare || savedToFiles, target == .organicMaps, carAppDetected == true {
                        Button {
                            if let url = CarAppLauncher.launchURL { openURL(url) }
                        } label: {
                            Label("Open Organic Maps", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                    }
                    if didShare, target == .organicMaps, !mutedCarApp {
                        muteReminder
                    }
                    fallback
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .pulseBackground()
            .navigationTitle("Drive this route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $sharing) {
                if let shareURL {
                    CarHandoffShareSheet(url: shareURL) { completed in
                        sharing = false
                        if completed {
                            didShare = true
                            seen = true
                            RevertHaptics.success()
                        } else {
                            autoSendFailed = true
                        }
                    }
                }
            }
            .fileExporter(isPresented: $showingExporter,
                          document: exportDocument,
                          contentType: GPXDocument.gpxType,
                          defaultFilename: exportName) { result in
                switch result {
                case .success:
                    savedToFiles = true
                    seen = true
                    RevertHaptics.success()
                case .failure(let error):
                    RevertDiagnostics.log("handoff.export failed: \(error.localizedDescription)")
                }
                exportDocument = nil
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .organicMapsRequired:
                    Alert(
                        title: Text("Organic Maps on the car screen"),
                        message: Text("Revert cannot draw on CarPlay without Apple's entitlement. Organic Maps can: it is free, works offline, and imports the GPX you save here. Save the GPX, import it in Organic Maps, open the track on the car display, and turn its voice off. Revert keeps navigating and stays the only voice."),
                        primaryButton: .default(Text("Open Organic Maps")) {
                            carAppNoticeSeen = true
                            if let url = CarAppLauncher.launchURL { openURL(url) }
                        },
                        secondaryButton: .default(Text("Not installed")) {
                            carAppNoticeSeen = true
                            openURL(Self.carAppStoreURL)
                        }
                    )
                case .muteHelp:
                    Alert(
                        title: Text("Organic Maps voice off?"),
                        message: Text("Open Organic Maps on the car screen and turn its navigation voice off. Revert is the only voice that should be speaking."),
                        primaryButton: .default(Text("Done")) { mutedCarApp = true },
                        secondaryButton: .cancel(Text("Cancel"))
                    )
                }
            }
            .task { await resolvePlaceName() }
            .onAppear {
                RevertDiagnostics.log("handoff.sheet opened target=\(target.rawValue)")
                detectCarAppAndMaybePrompt()
                #if DEBUG
                // Device check: `-debugCarHandoff -debugAutoHandoff` opens this
                // sheet and immediately runs the delivery chain, so the whole
                // path can be exercised without tapping the phone.
                if CommandLine.arguments.contains("-debugAutoHandoff") {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        send()
                    }
                }
                #endif
            }
            .onDisappear { seen = true }
            .onChange(of: target) { _, newTarget in
                didShare = false
                if newTarget == .organicMaps {
                    detectCarAppAndMaybePrompt()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, target == .organicMaps {
                    detectCarAppAndMaybePrompt()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CAR HANDOFF")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(Pulse.accent)
            Text(target == .organicMaps
                 ? "Revert navigates. Organic Maps draws."
                 : "Take the waypoints to your planner.")
                .font(PulseType.display(26))
                .foregroundStyle(Pulse.ink)
            Text(target == .organicMaps
                 ? "Save the GPX, import it in Organic Maps, and the car screen shows the line. Revert keeps the route, position, ETA, alerts and the only voice."
                 : "This export is for Kurviger, Scenic or calimoto. It includes a route with waypoints and the matching track; those apps may calculate their own guidance.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var carAppRequirement: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: carAppDetected == true ? "checkmark.circle.fill" : "car.side.fill")
                .foregroundStyle(carAppDetected == true ? Pulse.emerald : Pulse.warning)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(carAppRequirementTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Pulse.ink)
                Text("Revert cannot draw on CarPlay without Apple's entitlement. Organic Maps is the display app: free, offline, and it imports GPX.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 2)
            Button("Why?") {
                activeAlert = .organicMapsRequired
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Pulse.accent)
        }
        .padding(11)
        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var carAppRequirementTitle: String {
        switch carAppDetected {
        case true?: "Organic Maps detected on this iPhone"
        case false?: "Organic Maps was not detected"
        case nil: "Checking for Organic Maps…"
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 9) {
            if target == .organicMaps {
                step(1, "Share the track", "Tap Share GPX and pick Organic Maps in the share sheet. It takes the file directly.")
                step(2, "It lands in your bookmarks", "Organic Maps imports the track into Bookmarks and Tracks. Nothing else to set up.")
                step(3, "Open it on the car screen", "Open the track in Organic Maps on CarPlay and turn its voice off. Revert stays the navigator.")
            } else {
                step(1, "Send route + track", "Share the file with Kurviger, Scenic or calimoto.")
                step(2, "Import as a route", "The densified waypoints keep the planned line; the track matches the geometry.")
                step(3, "Review before riding", "These planners may re-calculate. Check the line before you trust it.")
            }
        }
        .pulseCard()
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Pulse.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Pulse.ink)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compactSteps: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(Pulse.accent)
            Text(target == .organicMaps
                 ? "Save the GPX, import it in Organic Maps, then open it on the car screen. Revert stays the only navigator."
                 : "Send route + track to your planner, import it as a route, and check the line before riding.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pulseCard()
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Target", selection: $target) {
                ForEach(CarHandoffExportTarget.allCases) { target in
                    Text(target.title).tag(target)
                }
            }
            .pickerStyle(.segmented)
            Text(target.detail)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Pulse.muted)
        }
    }

    private var sendButton: some View {
        Button {
            RevertHaptics.tap()
            send()
        } label: {
            HStack(spacing: 8) {
                if sending { ProgressView().controlSize(.small) }
                Label(sending
                      ? "Opening share sheet…"
                      : (target == .organicMaps ? "Share GPX to Organic Maps" : "Share route + track"),
                      systemImage: "square.and.arrow.up")
            }
        }
        .buttonStyle(RevertPrimaryButtonStyle(minHeight: 48))
        .disabled(route.points.count < 2 || sending)
    }

    private func send() {
        let generated = target == .organicMaps
            ? CarHandoffExporter.trackOnlyURL(for: route, named: resolvedName)
            : CarHandoffExporter.routeAndTrackURL(for: route, named: resolvedName)
        guard let generated else {
            RevertDiagnostics.log("handoff.write failed target=\(target.rawValue)")
            return
        }
        let bytes = (try? Data(contentsOf: generated).count) ?? 0
        let resolved = UTType(filenameExtension: "gpx")
        RevertDiagnostics.log("handoff.share target=\(target.rawValue)"
                              + " file=\(generated.lastPathComponent)"
                              + " bytes=\(bytes)"
                              + " uti=\(CarHandoffShareSheet.typeIdentifier)"
                              + " dynamic=\(resolved?.isDynamic ?? true)"
                              + " resolved=\(resolved?.identifier ?? "none")")

        guard target == .organicMaps else {
            shareURL = generated
            sharing = true
            return
        }

        // iOS has no API that hands a file to another app without one user
        // action: `open` on a file URL is not document sharing, which is why
        // every silent attempt failed. Go straight to the share sheet, where
        // document handlers and share extensions both appear.
        sending = true
        autoSendFailed = false
        shareURL = generated
        sharing = true
        RevertDiagnostics.log("handoff.share.presented")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            sending = false
        }
    }

    /// Export through the Files app. Organic Maps imports from Files even when it is
    /// not offered in the share sheet, so this is the dependable path.
    private func saveToFiles() {
        let url = target == .organicMaps
            ? CarHandoffExporter.trackOnlyURL(for: route, named: resolvedName)
            : CarHandoffExporter.routeAndTrackURL(for: route, named: resolvedName)
        guard let url, let data = try? Data(contentsOf: url) else {
            RevertDiagnostics.log("handoff.export failed: no file")
            return
        }
        exportName = url.deletingPathExtension().lastPathComponent
        exportDocument = GPXDocument(data: data)
        showingExporter = true
        RevertDiagnostics.log("handoff.export file=\(url.lastPathComponent) bytes=\(data.count)")
    }

    /// Point-to-point routes get "Start to destination" from the two ends.
    /// Saved routes and named loops keep the rider's name untouched.
    private func resolvePlaceName() async {
        guard resolvedName == nil, !route.isSavedName, route.name == "Point to point" else { return }
        guard let start = route.points.first, let end = route.points.last else { return }
        let geocoder = CLGeocoder()
        let startPlace = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: start.lat, longitude: start.lon)
        ).first
        let endPlace = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: end.lat, longitude: end.lon)
        ).first
        func label(_ place: CLPlacemark?) -> String? {
            guard let place else { return nil }
            return place.locality ?? place.subAdministrativeArea ?? place.name
        }
        guard let from = label(startPlace), let to = label(endPlace), from != to else { return }
        resolvedName = "\(from) to \(to)"
        RevertDiagnostics.log("handoff.name resolved=\(resolvedName ?? "")")
    }

    private func detectCarAppAndMaybePrompt() {
        // Log what the phone answers for every candidate scheme: this is the
        // only signal available about whether Organic Maps is installed and reachable.
        for scheme in CarAppLauncher.candidateSchemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            RevertDiagnostics.log("handoff.detect scheme=\(scheme) canOpen=\(UIApplication.shared.canOpenURL(url))")
        }
        let installed = CarAppLauncher.isInstalled || carAppConfirmed
        carAppDetected = installed
        if !installed, !carAppNoticeSeen {
            activeAlert = .organicMapsRequired
        }
    }

    private var muteReminder: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(Pulse.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Organic Maps's voice off?")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Pulse.ink)
                Text("There is no API to mute it; this is a rider step.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pulse.muted)
            }
            Spacer(minLength: 4)
            Button("Done") { mutedCarApp = true }
                .font(.system(size: 10, weight: .bold))
            Button {
                activeAlert = .muteHelp
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Show mute instructions")
        }
        .padding(11)
        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fallback: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Organic Maps?")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Pulse.ink)
            Text(target == .organicMaps
                 ? "Any GPX handler works; the track-only file is the portable fallback. Organic Maps follows the line without re-routing."
                 : "Use this export for planning apps. For the car screen, switch back to Organic Maps and keep its voice off.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
            if target == .organicMaps {
                Link("Get Organic Maps", destination: Self.carAppStoreURL)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Pulse.accent)
            }
        }
        .pulseCard()
    }
}

/// Shares a GPX file as GPX.
///
/// Handing a bare file URL to the share sheet lets the system classify it by
/// extension alone, which on a device with no GPX handler produces a dynamic
/// UTI (`dyn.*`). Apps that register `com.topografix.gpx` then never appear in
/// the sheet — which is exactly how a track "never made it" to the car app.
final class GPXActivityItem: NSObject, UIActivityItemSource {
    let url: URL

    init(url: URL) { self.url = url }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Advertise the payload as XML as well as GPX. GPX *is* XML, and the share
    /// extensions that accept route files are split between apps that declare
    /// `com.topografix.gpx` and apps that only declare `public.xml`. Saying XML
    /// widens the sheet without changing the file, which still arrives as .gpx.
    func activityViewController(_ controller: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.xml.identifier
    }
}

struct CarHandoffShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Bool) -> Void

    /// Prefer the system's own GPX type when something on the device declares
    /// it; otherwise hand out the standard identifier rather than a dynamic one.
    static var typeIdentifier: String {
        if let type = UTType(filenameExtension: "gpx"), !type.isDynamic {
            return type.identifier
        }
        return "com.topografix.gpx"
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = GPXActivityItem(url: url)
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, error in
            RevertDiagnostics.log("handoff.share completed=\(completed)"
                                  + " activity=\(activity?.rawValue ?? "none")"
                                  + " error=\(error?.localizedDescription ?? "none")")
            DispatchQueue.main.async { onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
