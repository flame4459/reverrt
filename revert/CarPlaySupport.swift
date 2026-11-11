import Foundation
import CoreLocation
import SwiftData

/// Everything the car screen says, kept free of CarPlay and UIKit types so it
/// can be unit-tested without a car.
enum CarPlayText {
    static func rideTitle(_ route: PlannedRoute) -> String {
        if let name = route.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return route.kind == .loop ? "Scenic loop" : "Route"
    }

    static func rideDetail(_ route: PlannedRoute) -> String {
        var parts = [Units.distanceText(route.length, decimals: 1)]
        switch route.kind {
        case .loop:
            parts.append("\(route.curviness)/5 twist")
        case .directions:
            if let eta = route.expectedTravelTime {
                parts.append(etaText(eta))
            }
        }
        if route.climbMeters >= 30 {
            parts.append("\(Units.elevationText(route.climbMeters)) climb")
        }
        return parts.joined(separator: " · ")
    }

    static func savedRideDetail(distanceMeters: Double, climbMeters: Double) -> String {
        var parts = [Units.distanceText(distanceMeters, decimals: 1)]
        if climbMeters >= 30 {
            parts.append("\(Units.elevationText(climbMeters)) climb")
        }
        return parts.joined(separator: " · ")
    }

    /// "25 min", "1 hr 5 min", "<1 min". Nil or negative means the estimate is
    /// not known yet, which the car screen shows as a dash.
    static func etaText(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return "<1 min" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func instruction(_ step: NavStep?) -> String {
        step?.instruction ?? "Follow the route"
    }
}

/// A snapshot of the glanceable navigation state. Rebuilding CarPlay templates
/// is comparatively expensive, so the coordinator compares snapshots and only
/// replaces maneuvers when the next turn actually changes.
struct CarPlayGuidance: Equatable {
    var routeID: UUID
    var stepID: Int?
    var instruction: String
    var distanceToManeuver: Double
    var remaining: Double
    var secondsRemaining: TimeInterval?
    var arrived: Bool
}

extension NavigationManager {
    var carPlayGuidance: CarPlayGuidance? {
        guard let route else { return nil }
        return CarPlayGuidance(
            routeID: route.id,
            stepID: step?.id,
            instruction: CarPlayText.instruction(step),
            distanceToManeuver: stepDistance,
            remaining: remaining,
            secondsRemaining: estimatedTimeRemaining,
            arrived: arrived
        )
    }
}

/// One selectable row on the car screen: a saved ride (already planned) or a
/// place such as Home, Work or a recent destination (needs a MapKit route).
struct CarPlayDestination: Identifiable {
    let id: String
    let title: String
    let detail: String
    let coordinate: CLLocationCoordinate2D?
    let route: PlannedRoute?
    let roads: [Road]
}

enum CarPlayDestinations {
    static let recentsKey = "recent.destinations"

    static func recents(fromJSON json: String) -> [RecentDestination] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RecentDestination].self, from: data)) ?? []
    }

    static func savedRides(limit: Int, context: ModelContext? = nil) -> [CarPlayDestination] {
        guard limit > 0 else { return [] }
        let context = context ?? ModelContext(RevertServices.shared.modelContainer)
        let descriptor = FetchDescriptor<SavedRoute>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let saved = (try? context.fetch(descriptor)) ?? []
        return saved.prefix(limit).compactMap { savedRoute in
            guard let route = savedRoute.plannedRoute() else { return nil }
            return CarPlayDestination(
                id: "saved-\(savedRoute.id.uuidString)",
                title: savedRoute.name.isEmpty ? CarPlayText.rideTitle(route) : savedRoute.name,
                detail: CarPlayText.savedRideDetail(distanceMeters: savedRoute.distanceMeters,
                                                    climbMeters: savedRoute.climbMeters),
                coordinate: nil,
                route: route,
                roads: savedRoute.roads
            )
        }
    }

    /// Home, Work and the most recent destinations, in the order they are most
    /// likely to be useful from the car. Duplicates are dropped.
    static func places(limit: Int = 6, defaults: UserDefaults = .standard) -> [CarPlayDestination] {
        guard limit > 0 else { return [] }
        var destinations: [CarPlayDestination] = []

        let homeLat = defaults.double(forKey: "saved.home.lat")
        let homeLon = defaults.double(forKey: "saved.home.lon")
        if homeLat != 0 || homeLon != 0 {
            destinations.append(place(id: "home", title: "Home",
                                      coordinate: CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)))
        }

        let workLat = defaults.double(forKey: "saved.work.lat")
        let workLon = defaults.double(forKey: "saved.work.lon")
        if workLat != 0 || workLon != 0 {
            destinations.append(place(id: "work", title: "Work",
                                      coordinate: CLLocationCoordinate2D(latitude: workLat, longitude: workLon)))
        }

        let recents = recents(fromJSON: defaults.string(forKey: recentsKey) ?? "")
        for recent in recents where !destinations.contains(where: { $0.title == recent.title }) {
            destinations.append(place(id: "recent-\(recent.id)", title: recent.title,
                                      coordinate: recent.coordinate))
        }
        return Array(destinations.prefix(limit))
    }

    private static func place(id: String, title: String,
                              coordinate: CLLocationCoordinate2D) -> CarPlayDestination {
        CarPlayDestination(id: id, title: title, detail: "Destination", coordinate: coordinate,
                           route: nil, roads: [])
    }
}
