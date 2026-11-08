import Foundation
import WidgetKit

/// Shares a tiny, non-identifying snapshot with the widget extension. Only the
/// bike name, odometer, units and the last ride's distance/date are written;
/// no coordinates or tracks cross the app-group boundary.
enum WidgetBridge {
    static let suiteName = "group.com.davidmolina.MyApp"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func updateBike(name: String, odometerKm: Double) {
        guard let defaults else { return }
        defaults.set(name, forKey: "widget.bikeName")
        defaults.set(odometerKm, forKey: "widget.odometerKm")
        defaults.set(Units.isMetric, forKey: "widget.metric")
        WidgetCenter.shared.reloadAllTimelines()
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
}
