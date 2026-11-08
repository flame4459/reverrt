import SwiftUI
import SwiftData
import CoreLocation

/// A planned route the rider chose to keep.
@Model
final class SavedRoute {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var isLoop: Bool = true
    var pointsData: Data = Data()
    var waypointsData: Data = Data()
    var stepsData: Data = Data()
    /// Road graph captured with the loop. Keeping it makes off-route
    /// rerouting and graph-based alerts work after the ride is saved.
    var roadsData: Data = Data()
    var distanceMeters: Double = 0
    var climbMeters: Double = 0
    var maxElevation: Double = 0
    var twistPerKm: Double = 0
    var retraced: Double = 0
    var bearing: Double = 0
    var expectedTravelTime: Double = 0
    var surfaceRaw: String = LoopSurface.paved.rawValue

    init(route: PlannedRoute, name: String, roads: [Road] = []) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.isLoop = route.kind == .loop
        self.pointsData = (try? JSONEncoder().encode(route.points)) ?? Data()
        self.roadsData = (try? JSONEncoder().encode(roads)) ?? Data()
        self.waypointsData = (try? JSONEncoder().encode(route.waypoints.map {
            StoredCoordinate(lat: $0.latitude, lon: $0.longitude)
        })) ?? Data()
        self.stepsData = (try? JSONEncoder().encode(route.steps)) ?? Data()
        self.distanceMeters = route.length
        self.climbMeters = route.climbMeters
        self.maxElevation = route.maxElevation
        self.twistPerKm = route.twistPerKm
        self.retraced = route.retraced
        self.bearing = route.bearing
        self.expectedTravelTime = route.expectedTravelTime ?? 0
        self.surfaceRaw = route.surface.rawValue
    }

    var points: [RoutePoint] {
        (try? JSONDecoder().decode([RoutePoint].self, from: pointsData)) ?? []
    }

    var waypoints: [CLLocationCoordinate2D] {
        let stored = (try? JSONDecoder().decode([StoredCoordinate].self, from: waypointsData)) ?? []
        return stored.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var surface: LoopSurface {
        LoopSurface(rawValue: surfaceRaw) ?? .paved
    }

    var roads: [Road] {
        (try? JSONDecoder().decode([Road].self, from: roadsData)) ?? []
    }

    func plannedRoute() -> PlannedRoute? {
        let points = points
        guard points.count > 2 else { return nil }
        var route = PlannedRoute(
            points: points,
            roads: [:],
            twistPerKm: twistPerKm,
            retraced: retraced,
            bearing: bearing,
            displayName: name,
            expectedTravelTime: expectedTravelTime > 0 ? expectedTravelTime : nil,
            kind: isLoop ? .loop : .directions
        )
        if let steps = try? JSONDecoder().decode([NavStep].self, from: stepsData), !steps.isEmpty {
            route.steps = steps
        }
        route.waypoints = waypoints
        route.climbMeters = climbMeters
        route.maxElevation = maxElevation
        route.surface = surface
        return route
    }

    struct StoredCoordinate: Codable {
        let lat: Double
        let lon: Double
    }
}

struct SaveRouteButton: View {
    let route: PlannedRoute
    var roads: [Road] = []
    var compact = false

    @Environment(\.modelContext) private var context
    @State private var saved = false

    var body: some View {
        Button {
            let name = route.displayName ?? "Route \(Date().formatted(date: .abbreviated, time: .shortened))"
            context.insert(SavedRoute(route: route, name: name, roads: roads))
            try? context.save()
            saved = true
        } label: {
            Label(saved ? "Saved" : "Save route",
                  systemImage: saved ? "checkmark.circle.fill" : "bookmark")
        }
        .buttonStyle(SaveRouteButtonStyle(compact: compact, saved: saved))
        .disabled(saved)
        .accessibilityLabel(saved ? "Route saved" : "Save route")
    }
}

private struct SaveRouteButtonStyle: ButtonStyle {
    let compact: Bool
    let saved: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.semibold) : .headline.weight(.semibold))
            .foregroundStyle(compact ? MapUI.cyan : .white)
            .padding(.horizontal, compact ? 10 : 0)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 30 : 46)
            .background(
                compact
                    ? AnyShapeStyle(MapUI.panelElevated)
                    : AnyShapeStyle(saved ? AnyShapeStyle(MapUI.emerald.opacity(0.25)) : AnyShapeStyle(MapUI.accentGradient)),
                in: RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                    .stroke(compact ? MapUI.hairline : .clear, lineWidth: 0.8)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
