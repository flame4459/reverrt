import Foundation
import WidgetKit

/// Shares a tiny, non-identifying snapshot with the widget extension. Only the
/// bike name, odometer, units and the last ride's distance/date are written;
/// no coordinates or tracks cross the app-group boundary.
enum WidgetBridge {
    static let suiteName = "group.com.davidmolina.Revert"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func updateBike(name: String, odometerKm: Double, kind: VehicleKind = .motorcycle) {
        guard let defaults else { return }
        defaults.set(name, forKey: "widget.bikeName")
        defaults.set(odometerKm, forKey: "widget.odometerKm")
        defaults.set(kind.rawValue, forKey: "widget.vehicleKind")
        defaults.set(Units.isMetric, forKey: "widget.metric")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Writes the car/bike snapshot the Dashboard widget reads. The snapshot
    /// itself is cheap to write on every live update; reloading the widget on
    /// every 25 m step would burn the timeline budget, so the reload is
    /// throttled unless the caller asks for a force (start, pause, stop,
    /// arrival, lap, hazard).
    nonisolated(unsafe) private static var lastWidgetReload = Date.distantPast

    @MainActor
    private static var lastWidgetWrite = Date.distantPast
    static func updateCarState(_ snapshot: CarWidgetSnapshot, force: Bool = false,
                               reason: String = "state") {
        guard let defaults else { return }
        let writeNow = Date()
        if !force, writeNow.timeIntervalSince(lastWidgetWrite) < 5 { return }
        lastWidgetWrite = writeNow
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: "widget.carState")
        }
        defaults.set(snapshot.vehicleKind, forKey: "widget.vehicleKind")
        defaults.set(snapshot.isSimulation, forKey: "widget.isSimulation")
        defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: "widget.carUpdatedAt")

        let now = Date()
        let since = now.timeIntervalSince(lastWidgetReload)
        let reload = force || since > 60
        if reload { lastWidgetReload = now }

        let fields: [(String, String)] = [
            ("mode", snapshot.mode.rawValue),
            ("vehicle", snapshot.vehicleKind),
            ("route", snapshot.routeName),
            ("turnSymbol", snapshot.turnSymbol),
            ("turnDistance", snapshot.turnDistance),
            ("instruction", snapshot.instruction),
            ("remaining", snapshot.remaining),
            ("eta", snapshot.eta),
            ("speed", snapshot.speed),
            ("limit", snapshot.speedLimit ?? "—"),
            ("lap", "\(snapshot.lap)/\(snapshot.totalLaps)"),
            ("hazard", snapshot.hazard ?? "—"),
            ("sim", snapshot.isSimulation ? "yes" : "no"),
            ("progress", String(format: "%.3f", snapshot.progress)),
            ("stepID", "\(snapshot.stepID)"),
            ("mapImage", snapshot.mapImage ?? "—"),
            ("updated", String(format: "%.1f", snapshot.updatedAt.timeIntervalSince1970)),
            ("force", force ? "yes" : "no"),
            ("reason", reason),
            ("reload", reload ? "yes" : "no"),
            ("sinceReload", String(format: "%.1fs", since))
        ]
        RideDebug.shared.event("WIDGET-STATE", fields)

        if reload {
            WidgetCenter.shared.reloadTimelines(ofKind: "RevertQuickWidget")
        }
        flushWidgetDebug()
    }

    /// Moves entries the widget extension wrote (timeline/snapshot refreshes)
    /// into the active ride transcript.
    @MainActor
    static func flushWidgetDebug() {
        for entry in WidgetDebugLog.drain() {
            RideDebug.shared.event("WIDGET-REFRESH", [("log", entry)])
        }
    }

    static func updateRide(distanceMeters: Double, date: Date, routeName: String?, bikeName: String?) {
        guard let defaults else { return }
        defaults.set(distanceMeters, forKey: "widget.lastRideMeters")
        defaults.set(date.timeIntervalSince1970, forKey: "widget.lastRideDate")
        if let routeName { defaults.set(routeName, forKey: "widget.lastRideName") }
        else { defaults.removeObject(forKey: "widget.lastRideName") }
        if let bikeName { defaults.set(bikeName, forKey: "widget.bikeName") }
        defaults.set(Units.isMetric, forKey: "widget.metric")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func updateUnits() {
        guard let defaults else { return }
        defaults.set(Units.isMetric, forKey: "widget.metric")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Tells the widget whether a ride is live, so its one button can say
    /// "Start a loop" when parked and "Ride in progress" when it isn't.
    /// Written on ride start/end only, so it costs two timeline reloads a ride.
    @MainActor
    static func setRideActive(_ active: Bool, routeName: String? = nil) {
        guard let defaults else { return }
        RideDebug.shared.event("WIDGET-ACTIVE", [
            ("active", active ? "yes" : "no"),
            ("route", routeName ?? "—")
        ])
        defaults.set(active, forKey: "widget.rideActive")
        if active, let routeName, !routeName.isEmpty {
            defaults.set(routeName, forKey: "widget.activeRouteName")
        } else if !active {
            defaults.removeObject(forKey: "widget.activeRouteName")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
