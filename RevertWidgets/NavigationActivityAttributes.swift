import ActivityKit
import Foundation
import UIKit

/// Shared by the app and the Live Activity extension. Keep this type name and
/// shape identical in both targets; ActivityKit uses it as the activity key.
nonisolated struct NavigationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var distance: String
        var speed: String
        var offRoute: Bool
        var updatedAt: Date
        /// SF Symbol for the upcoming maneuver (`NavStep.symbol`). The CarPlay
        /// dashboard card leads with it, so the shape of the turn lands before
        /// the words do.
        var turnSymbol: String
        /// Distance left on the whole route, already formatted. The app formats
        /// it because `Units` does not exist in this target.
        var remaining: String
        /// Clock time the rider is expected to finish, already formatted.
        var eta: String
        /// Current speed limit in the rider's units, or nil when unknown.
        var speedLimit: String? = nil
        /// Current circuit lap. 0 when this is a point-to-point drive/ride.
        var lap: Int = 0
        var totalLaps: Int = 0
        /// Short hazard/alert label to show on the car card.
        var hazard: String? = nil
        var isSimulation: Bool = false
        /// "car" or "motorcycle"; the widget picks the right glyph.
        var vehicleKind: String = "motorcycle"
        /// File name of the rendered map card in the app group, if one exists.
        /// Only the name travels in the state: the image is far too big for an
        /// activity payload.
        var mapImage: String? = nil
        /// 0...1 along the route, for the progress strip.
        var progress: Double = 0
        /// Current maneuver id, for correlating Live Activity updates with the
        /// navigation step log.
        var stepID: Int = -1
    }

    var startedAt: Date
}

/// iOS 17 variant of the Live Activity.
///
/// The adaptive layout and the small activity family (CarPlay Dashboard, Watch
/// Smart Stack) only exist on iOS 18, so the two generations must not claim the
/// same activity type: ActivityKit expects exactly one widget per type. This
/// type reuses the same payload and differs only in its type name, which is
/// what ActivityKit uses as the activity key.
nonisolated struct LegacyNavigationActivityAttributes: ActivityAttributes {
    typealias ContentState = NavigationActivityAttributes.ContentState

    var startedAt: Date
}

/// Snapshot shared with the widget extension. `NavigationActivityAttributes`
/// is the live channel; this is the tickable widget's view of the same drive.
nonisolated struct CarWidgetSnapshot: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable {
        case parked
        case driving
        case paused
        case arrived
        case simulation
    }

    var mode: Mode = .parked
    var vehicleKind: String = "motorcycle"
    var routeName: String = ""
    var turnSymbol: String = "location.north.fill"
    var turnDistance: String = "—"
    var instruction: String = ""
    var remaining: String = "—"
    var eta: String = "—"
    var speed: String = "—"
    var speedLimit: String? = nil
    var lap: Int = 0
    var totalLaps: Int = 0
    var hazard: String? = nil
    var isSimulation: Bool = false
    var mapImage: String? = nil
    var progress: Double = 0
    /// Current maneuver id, for correlating Dashboard snapshots with the
    /// navigation step log.
    var stepID: Int = -1
    var updatedAt: Date = .distantPast

    var isCar: Bool { vehicleKind == "car" }
    /// Matches the widget's own refresh cadence: five minutes without an
    /// update is a stopped app, not a quiet stretch of road.
    var isStale: Bool { Date().timeIntervalSince(updatedAt) > 300 }
    var isLive: Bool {
        mode == .driving || mode == .paused || mode == .simulation
    }

    static let parked = CarWidgetSnapshot()
}


/// The map card shared between the app (which draws it) and the extensions
/// (which display it). An app group is the only way to hand a bitmap to a
/// widget: activity payloads are kilobytes, images are not.
nonisolated enum LiveMapImage {
    static let appGroup = "group.com.davidmolina.Revert"
    static let folder = "live-map"

    static func folderURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(folder, isDirectory: true)
    }

    static func url(for name: String) -> URL? {
        folderURL()?.appendingPathComponent(name)
    }

    static func load(_ name: String) -> UIImage? {
        guard let url = url(for: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}


/// Cross-process telemetry for the Dashboard widget. The widget extension
/// appends a line each time WidgetKit asks for a snapshot or timeline; the app
/// drains the buffer into the active ride transcript. No coordinates or ride
/// content beyond the snapshot fields are written here.
nonisolated enum WidgetDebugLog {
    static let appGroup = "group.com.davidmolina.Revert"
    static let key = "widget.debugLog"
    static let recentKey = "widget.debugLog.recent"
    static let maxLines = 300
    static let maxRecent = 150

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func log(_ event: String, _ fields: [String: String] = [:]) {
        guard let defaults else { return }
        var line = "\(Date().ISO8601Format()) \(event)"
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            line += " \(key)=\(value.replacingOccurrences(of: "\n", with: " "))"
        }
        var entries = defaults.stringArray(forKey: key) ?? []
        entries.append(line)
        if entries.count > maxLines {
            entries.removeFirst(entries.count - maxLines)
        }
        defaults.set(entries, forKey: key)

        var recent = defaults.stringArray(forKey: recentKey) ?? []
        recent.append(line)
        if recent.count > maxRecent {
            recent.removeFirst(recent.count - maxRecent)
        }
        defaults.set(recent, forKey: recentKey)
    }

    /// The retained history for the CarPlay diagnostics screen. Unlike
    /// `drain()`, this is never removed by the ride transcript flush.
    static func recent() -> [String] {
        defaults?.stringArray(forKey: recentKey) ?? []
    }

    /// Reads and clears the buffer. Called from the app's ride transcript.
    static func drain() -> [String] {
        guard let defaults else { return [] }
        let entries = defaults.stringArray(forKey: key) ?? []
        if !entries.isEmpty {
            defaults.removeObject(forKey: key)
        }
        return entries
    }

    static func peek() -> [String] {
        defaults?.stringArray(forKey: key) ?? []
    }
}
