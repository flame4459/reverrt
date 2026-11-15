import Foundation
import MapKit

/// Motorcycles and cars share the garage, the recorder and the leaderboards.
/// Only the cockpit and a handful of metrics change with this.
nonisolated enum VehicleKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case motorcycle
    case car

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motorcycle: "Motorcycle"
        case .car: "Car"
        }
    }

    var plural: String {
        switch self {
        case .motorcycle: "Motorcycles"
        case .car: "Cars"
        }
    }

    var icon: String {
        switch self {
        case .motorcycle: "motorcycle"
        case .car: "car.fill"
        }
    }

    var isCar: Bool { self == .car }
    var isMotorcycle: Bool { self == .motorcycle }
}


/// Car routing preferences live in UserDefaults so every directions request —
/// the planner, reroutes, loop fallbacks and the CarPlay coordinator — can read
/// them without threading a vehicle object through each call site.
nonisolated enum VehiclePreferences {
    static let primaryKindKey = "vehicle.primaryKind"
    static let activeKindKey = "vehicle.activeKind"
    static let avoidTollsKey = "vehicle.car.avoidTolls"
    static let avoidHighwaysKey = "vehicle.car.avoidHighways"

    static var primaryKind: VehicleKind {
        UserDefaults.standard.string(forKey: primaryKindKey)
            .flatMap(VehicleKind.init(rawValue:)) ?? .motorcycle
    }

    /// The vehicle chosen for the route currently being started. The Garage
    /// default is only a fallback; the car/bike prompt overrides this for one
    /// navigation at a time.
    static var activeKind: VehicleKind {
        UserDefaults.standard.string(forKey: activeKindKey)
            .flatMap(VehicleKind.init(rawValue:)) ?? primaryKind
    }

    static var isCarPrimary: Bool { activeKind == .car }

    static func activate(_ kind: VehicleKind) {
        UserDefaults.standard.set(kind.rawValue, forKey: activeKindKey)
    }

    static var avoidTolls: Bool {
        UserDefaults.standard.bool(forKey: avoidTollsKey)
    }

    static var avoidHighways: Bool {
        UserDefaults.standard.bool(forKey: avoidHighwaysKey)
    }

    static func sync(primaryKind: VehicleKind, avoidTolls: Bool, avoidHighways: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(primaryKind.rawValue, forKey: primaryKindKey)
        defaults.set(primaryKind.rawValue, forKey: activeKindKey)
        // Keep the last car preferences even when a bike is primary; choosing
        // Car for one route should still use the settings saved for that car.
        if primaryKind == .car {
            defaults.set(avoidTolls, forKey: avoidTollsKey)
            defaults.set(avoidHighways, forKey: avoidHighwaysKey)
        }
    }

    static func apply(to request: MKDirections.Request) {
        guard isCarPrimary else {
            request.tollPreference = .any
            request.highwayPreference = .any
            return
        }
        request.tollPreference = avoidTolls ? .avoid : .any
        request.highwayPreference = avoidHighways ? .avoid : .any
    }
}


/// A route waiting for the "Car or bike today?" prompt.
struct PendingVehicleRoute {
    let route: PlannedRoute
    let roads: [Road]
}
