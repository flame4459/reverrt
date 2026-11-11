import Foundation
import CoreLocation
import MapKit
import Observation

/// A lightweight, equatable camera sample. Publishing this (instead of the raw
/// `CLLocation`) keeps the map from being invalidated on every GPS fix while
/// still giving the cockpit camera enough resolution to feel live.
nonisolated struct RideCameraPose: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var heading: Double
    var speed: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Follows a planned route: tracks progress, speaks directions, and finds a way back if you leave it.
@MainActor
@Observable
final class NavigationManager {
    var route: PlannedRoute?
    var step: NavStep?              // the next maneuver
    var nextStep: NavStep?          // the maneuver after that
    var stepDistance = 0.0          // meters to it
    var remaining = 0.0             // meters left on the route
    var joined = false              // false until the rider reaches the route
    var distanceToStart = 0.0
    var currentSpeedMps = 0.0
    var offRoute = false
    var rerouting = false
    var arrived = false
    var userCoordinate: CLLocationCoordinate2D?
    var userHeading = 0.0
    var cameraPose: RideCameraPose?

    /// Updated on every GPS fix (the Plan tab uses it as the default start)
    var lastLocation: CLLocation?
    /// Flips once and stays true. Views observe this instead of `lastLocation`
    /// so they are not invalidated on every GPS fix.
    var hasLocation = false
    /// True when the rider has explicitly denied location access. The map
    /// screens use this to offer a way to Settings instead of spinning on
    /// "Waiting for GPS" forever.
    var locationDenied = false
    /// Permission has not been answered yet. Used for an explicit Enable
    /// banner when the rider skipped onboarding.
    var locationUndetermined = false
    /// Uses a cached Core Location fix when the hub has not published one yet.
    var currentLocation: CLLocation? { lastLocation ?? LocationHub.shared.lastLocation }
    @ObservationIgnored private let hub = LocationHub.shared
    @ObservationIgnored private var hubToken: UUID?
    @ObservationIgnored private var authToken: UUID?

    init() {
        // The hub owns the single CLLocationManager for the whole app.
        hubToken = hub.addSubscriber { [weak self] location in
            self?.handle(location)
        }
        locationDenied = hub.authorizationStatus == .denied || hub.authorizationStatus == .restricted
        locationUndetermined = hub.authorizationStatus == .notDetermined
        authToken = hub.addAuthorizationSubscriber { [weak self] status in
            self?.locationDenied = status == .denied || status == .restricted
            self?.locationUndetermined = status == .notDetermined
        }
    }
    @ObservationIgnored private var roads: [Road] = []
    @ObservationIgnored private var seg = 0            // index of the route segment the rider is on
    @ObservationIgnored private var along = 0.0        // meters along the route
    @ObservationIgnored private var stepIdx = 1
    @ObservationIgnored private var announced = Set<Int>()
    @ObservationIgnored private var offSince: Date?
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var normalDestination: CLLocationCoordinate2D?
    @ObservationIgnored private var lastPoseAt = Date.distantPast
    @ObservationIgnored private var lastPoseHeading = 0.0
    @ObservationIgnored private var preciseLease: LocationHub.Lease?
    /// Navigation must keep receiving fixes while the phone is locked in a
    /// pocket or mounted out of sight, so a live route holds this claim for its
    /// whole lifetime rather than only while the ride screen is open.
    @ObservationIgnored private var backgroundLease: LocationHub.Lease?
    /// Bumped whenever the active route changes. In-flight reroutes capture it
    /// and refuse to install their result if it has moved on.
    @ObservationIgnored private(set) var routeGeneration = 0

    var startCoordinate: CLLocationCoordinate2D? { route?.points.first?.coordinate }

    /// Meters along the route where the rider currently is. Used by the alert
    /// engine to decide which traffic devices are actually on this ride.
    var routeProgress: Double { along }
    var isOnRoute: Bool { route != nil && joined && !offRoute && !arrived && !rerouting }

    var estimatedTimeRemaining: TimeInterval? {
        guard remaining > 0 else { return 0 }
        if currentSpeedMps > 3 {
            return remaining / currentSpeedMps
        }
        guard let expected = route?.expectedTravelTime, let length = route?.length, length > 0 else {
            return nil
        }
        return expected * remaining / length
    }

    // MARK: Control
    func start(_ r: PlannedRoute, roads: [Road]) {
        routeGeneration += 1
        route = r
        self.roads = roads
        // A loop finishes where it starts. Treating that as a point-to-point
        // destination is what sent riders back to the trailhead instead of
        // rejoining the loop; only MapKit directions have a real destination.
        normalDestination = r.kind == .directions ? r.destination : nil
        if preciseLease == nil {
            preciseLease = hub.acquirePrecise()
        }
        if backgroundLease == nil {
            backgroundLease = hub.acquireBackground()
            hub.requestAlwaysIfNeeded()
        }
        reset()
        stepIdx = r.kind == .directions ? 0 : min(1, max(r.steps.count - 1, 0))
        remaining = r.length
        step = r.steps.indices.contains(stepIdx) ? r.steps[stepIdx] : nil
        nextStep = r.steps.indices.contains(stepIdx + 1) ? r.steps[stepIdx + 1] : nil
        if let loc = lastLocation { handle(loc) }
    }

    func stop() {
        routeGeneration += 1
        route = nil
        step = nil
        nextStep = nil
        roads = []
        normalDestination = nil
        preciseLease?.release()
        preciseLease = nil
        backgroundLease?.release()
        backgroundLease = nil
        reset()
        arrived = false
    }

    private func reset() {
        seg = 0
        along = 0
        stepIdx = 0
        announced = []
        offSince = nil
        joined = false
        offRoute = false
        rerouting = false
        arrived = false
        stepDistance = 0
        distanceToStart = 0
        currentSpeedMps = 0
        lastReroute = Date.distantPast
        nextStep = nil
    }

    // MARK: Location updates
    func handle(_ loc: CLLocation) {
        lastLocation = loc
        if !hasLocation { hasLocation = true }
        currentSpeedMps = max(loc.speed, 0)
        userCoordinate = loc.coordinate
        if loc.course >= 0 {
            userHeading = loc.course
        }
        publishCameraPose(loc)

        guard let r = route, !arrived, r.points.count > 1 else { return }

        // Not on the route yet: wait until the rider reaches it
        if !joined {
            if let first = r.points.first {
                distanceToStart = loc.distance(from: CLLocation(latitude: first.lat, longitude: first.lon))
            }
            guard let m = project(loc.coordinate, onto: r, from: 0, to: r.points.count - 1, firstWithin: 50) else { return }
            joined = true
            seg = m.seg
            along = m.along
            Speaker.shared.say(
                Narrator.routeStarted(road: r.steps.first?.road),
                kind: .navigation
            )
        }

        // Search just around where we last were so overlapping stretches don't confuse the match
        let lo = max(seg - 2, 0)
        var hi = seg
        while hi < r.points.count - 2, r.cumulative[hi + 1] - r.cumulative[seg] < 1000 { hi += 1 }
        guard let m = project(loc.coordinate, onto: r, from: lo, to: hi + 1) else { return }

        if m.dist >= 50 {
            if offSince == nil { offSince = Date() }
            if let o = offSince, Date().timeIntervalSince(o) > 8, loc.speed > 2, !rerouting,
               Date().timeIntervalSince(lastReroute) > 20 {
                if !offRoute { offRoute = true }
                reroute(from: loc)
            }
            return
        }
        offSince = nil
        if offRoute { offRoute = false }

        seg = m.seg
        along = m.along
        remaining = max(r.length - along, 0)

        if remaining < 30, along > r.length * 0.5 {
            arrived = true
            remaining = 0
            step = r.steps.last
            nextStep = nil
            stepDistance = 0
            Speaker.shared.say(Narrator.arrival, kind: .navigation)
            return
        }

        while stepIdx < r.steps.count - 1, r.steps[stepIdx].distance <= along + 5 { stepIdx += 1 }
        guard !r.steps.isEmpty else { return }
        let next = r.steps[min(stepIdx, r.steps.count - 1)]
        step = next
        nextStep = r.steps.indices.contains(stepIdx + 1) ? r.steps[stepIdx + 1] : nil
        stepDistance = max(next.distance - along, 0)
        speakIfNeeded(next, speed: max(loc.speed, 0))
    }

    private func publishCameraPose(_ loc: CLLocation) {
        let now = Date()
        let heading = loc.course >= 0 ? loc.course : userHeading
        let headingMoved = abs(heading - lastPoseHeading) >= 4
        guard now.timeIntervalSince(lastPoseAt) >= 0.12 || headingMoved else { return }
        lastPoseAt = now
        lastPoseHeading = heading
        cameraPose = RideCameraPose(latitude: loc.coordinate.latitude,
                                    longitude: loc.coordinate.longitude,
                                    heading: heading,
                                    speed: max(loc.speed, 0))
    }

    private func speakIfNeeded(_ s: NavStep, speed: Double) {
        guard !s.instruction.isEmpty else { return }
        let far = max(speed * 18, 350)
        let near = max(speed * 5, 70)
        let farKey = stepIdx * 2, nearKey = stepIdx * 2 + 1
        if stepDistance <= near {
            if !announced.contains(nearKey) {
                announced.insert(nearKey)
                announced.insert(farKey)
                Speaker.shared.say(Narrator.instruction(s, distance: nil), kind: .navigation)
            }
        } else if stepDistance <= far, !announced.contains(farKey) {
            announced.insert(farKey)
            Speaker.shared.say(Narrator.instruction(s, distance: stepDistance), kind: .navigation)
        }
    }

    static func spoken(_ meters: Double) -> String {
        Units.spokenDistance(meters)
    }

    // MARK: Geometry
    /// Closest point on the route between segments lo..<hi. Earlier segments win near-ties.
    private func project(_ c: CLLocationCoordinate2D, onto r: PlannedRoute, from lo: Int, to hi: Int, firstWithin: Double? = nil)
        -> (seg: Int, dist: Double, along: Double)? {
        guard lo < hi, hi < r.points.count else { return nil }
        let kx = 111_320.0 * cos(c.latitude * .pi / 180)
        let ky = 110_540.0
        var best: (seg: Int, dist: Double, along: Double)?
        for i in lo..<hi {
            let a = r.points[i], b = r.points[i + 1]
            let ax = (a.lon - c.longitude) * kx, ay = (a.lat - c.latitude) * ky
            let bx = (b.lon - c.longitude) * kx, by = (b.lat - c.latitude) * ky
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? -(ax * dx + ay * dy) / len2 : 0
            t = min(max(t, 0), 1)
            let px = ax + t * dx, py = ay + t * dy
            let d = (px * px + py * py).squareRoot()
            let here = r.cumulative[i] + t * (r.cumulative[i + 1] - r.cumulative[i])
            if let w = firstWithin {
                if d < w { return (i, d, here) }      // join at the earliest point on the route
                continue
            }
            if best == nil || d < best!.dist - 5 {
                best = (i, d, here)
            }
        }
        return best
    }

    // MARK: Rerouting
    private func reroute(from loc: CLLocation) {
        guard let r = route else { return }
        let generation = routeGeneration
        rerouting = true
        lastReroute = Date()
        Speaker.shared.say("Off route. Finding a way back", kind: .navigation)

        // Point-to-point directions genuinely end at the destination. Loops do
        // not: their destination is the start, so send them through the graph
        // rejoin below instead.
        if r.kind == .directions, let destination = normalDestination {
            rerouteDirections(from: loc.coordinate, to: destination, generation: generation)
            return
        }

        guard !roads.isEmpty else {
            rerouting = false
            // No offline graph is available. As a last resort, guide the rider
            // back to the route's end so they can restart from the trailhead.
            if let destination = r.destination {
                rerouteDirections(from: loc.coordinate, to: destination, generation: generation)
            }
            return
        }

        // Rejoin the route about 500 m further along
        var j = min(seg + 1, r.points.count - 2)
        while j < r.points.count - 2, r.cumulative[j] - along < 500 { j += 1 }
        let target = max(j, 1)
        let coord = loc.coordinate
        let allRoads = roads
        Task.detached(priority: .userInitiated) {
            // Graph construction and Dijkstra are pure work; keep them off the
            // main actor so navigation stays responsive while rerouting.
            let new = RouteBuilder.reroute(roads: allRoads, route: r, from: coord, rejoinAt: target)
            await MainActor.run { self.finishReroute(new, generation: generation) }
        }
    }

    private func rerouteDirections(from source: CLLocationCoordinate2D,
                                  to destination: CLLocationCoordinate2D,
                                  generation: Int) {
        Task {
            let request = MKDirections.Request()
            request.source = MKMapItem(location: CLLocation(latitude: source.latitude, longitude: source.longitude), address: nil)
            request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
            request.transportType = .automobile

            do {
                let response = try await MKDirections(request: request).calculate()
                let updated = response.routes.first.map(PlannedRoute.init(mapRoute:))
                finishReroute(updated, generation: generation)
            } catch {
                finishReroute(nil, generation: generation)
            }
        }
    }

    /// Installs a reroute result, but only if it belongs to the route that is
    /// still active. Without this guard, a reroute requested on one route could
    /// land after the rider ended navigation or started another route and
    /// replace it with a stale way back.
    func finishReroute(_ new: PlannedRoute?, generation: Int) {
        guard generation == routeGeneration else { return }
        rerouting = false
        guard route != nil else { return }
        guard let new else {
            Speaker.shared.say("Couldn't find a way back. Head toward the route", kind: .navigation)
            return
        }
        route = new
        normalDestination = new.kind == .directions ? new.destination : nil
        seg = 0
        along = 0
        announced = []
        offSince = nil
        offRoute = false
        // A rejoin route starts under the rider, so we are joined immediately.
        joined = true
        distanceToStart = 0
        arrived = false
        remaining = new.length
        stepIdx = new.kind == .directions ? 0 : min(1, max(new.steps.count - 1, 0))
        step = new.steps.indices.contains(stepIdx) ? new.steps[stepIdx] : nil
        nextStep = new.steps.indices.contains(stepIdx + 1) ? new.steps[stepIdx + 1] : nil
        stepDistance = 0
        Speaker.shared.say(Narrator.routeUpdated, kind: .navigation)
    }
}
