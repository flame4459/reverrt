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

/// One maneuver on the road to the loop start.
nonisolated struct ApproachStep: Identifiable {
    let id: Int
    let instruction: String
    let symbol: String
    /// Meters from the beginning of the approach where this maneuver happens.
    let at: Double
}

/// A MapKit route from the rider's current position to the loop start. It is a
/// guide, not the ride: once the rider reaches the first route point the real
/// PlannedRoute takes over and this is thrown away.
nonisolated struct ApproachGuide {
    var steps: [ApproachStep]
    var distance: Double
    var expectedTravelTime: TimeInterval?
    var coordinates: [CLLocationCoordinate2D]
}

/// Follows a planned route: tracks progress, speaks directions, and finds a way back if you leave it.
@MainActor
@Observable
final class NavigationManager {
    var route: PlannedRoute?
    /// Vehicle chosen for this navigation. It drives the car/bike cockpit,
    /// labels, recording and the CarPlay snapshot.
    private(set) var vehicleKind: VehicleKind = .motorcycle
    var step: NavStep?              // the next maneuver
    var nextStep: NavStep?          // the maneuver after that
    var stepDistance = 0.0          // meters to it
    var remaining = 0.0             // meters left on the route
    var joined = false              // false until the rider reaches the route
    var distanceToStart = 0.0
    /// Turn-by-turn directions to the loop start, fetched with MapKit while
    /// the rider is still on the way. nil until the first request finishes.
    var approachInstruction: String?
    var approachSymbol = "location.north.line"
    var approachStepDistance = 0.0
    var approachRemaining = 0.0
    var approachETA: TimeInterval?
    var approachCoordinates: [CLLocationCoordinate2D] = []
    var approachActive: Bool { route != nil && !joined && !approachCoordinates.isEmpty }
    /// Current lap (1-based) and the number configured on the route. Point to
    /// point routes always report 1 / 1.
    var lap = 1
    var lastLapDuration: TimeInterval?
    var totalLaps: Int {
        guard let route, route.kind.isLoop else { return 1 }
        return max(route.laps, 1)
    }
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
    /// Previous raw match, used to see the loop line pass from ~length to ~0.
    @ObservationIgnored private var lastMatchedAlong: Double?
    /// Metres ridden since the last counted lap.
    @ObservationIgnored private var distanceSinceLap = 0.0
    /// A real loop returns to its start; an open "lap" route does not.
    @ObservationIgnored private var loopIsClosed = false
    @ObservationIgnored private var stepIdx = 1
    /// Which distance rungs have already been spoken, per step id.
    @ObservationIgnored private var announcedCallouts: [Int: Set<Int>] = [:]
    /// Consecutive fixes whose course disagrees with the route's own tangent.
    @ObservationIgnored private var reversedFixes = 0
    @ObservationIgnored private var straightAnnounced = Set<Int>()
    @ObservationIgnored private var offSince: Date?
    @ObservationIgnored private var lastReroute = Date.distantPast
    /// Low-passed course, so the heading-up map does not twitch with GPS noise.
    @ObservationIgnored private var smoothedHeading: Double = 0
    /// Where the last reroute attempt started, so a failed attempt is only
    /// retried once the rider has actually moved.
    @ObservationIgnored private var lastReroutePoint: CLLocationCoordinate2D?
    @ObservationIgnored private var normalDestination: CLLocationCoordinate2D?
    @ObservationIgnored private var lastPoseAt = Date.distantPast
    @ObservationIgnored private var lastPoseHeading = 0.0
    @ObservationIgnored private var approach: ApproachGuide?
    @ObservationIgnored private var approachTask: Task<Void, Never>?
    @ObservationIgnored private var approachFetching = false
    @ObservationIgnored private var approachLastFetch = Date.distantPast
    @ObservationIgnored private var approachLastOrigin: CLLocation?
    @ObservationIgnored private var approachAnnounced = Set<Int>()
    @ObservationIgnored private var lapStartedAt = Date()
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
        guard let route, remaining > 0 else { return 0 }
        let lapsLeft = max(totalLaps - lap, 0)
        let totalRemaining = remaining + Double(lapsLeft) * route.length
        if currentSpeedMps > 3 {
            return totalRemaining / currentSpeedMps
        }
        guard let expected = route.expectedTravelTime, route.length > 0 else {
            return nil
        }
        return expected * totalRemaining / route.length
    }

    // MARK: Control
    func start(_ r: PlannedRoute, roads: [Road], vehicleKind: VehicleKind? = nil) {
        let kind = vehicleKind ?? VehiclePreferences.activeKind
        self.vehicleKind = kind
        VehiclePreferences.activate(kind)
        routeGeneration += 1
        route = r
        self.roads = roads
        // A loop finishes where it starts. Treating that as a point-to-point
        // destination is what sent riders back to the trailhead instead of
        // rejoining the loop; only MapKit directions have a real destination.
        normalDestination = r.kind.isPointToPoint ? r.destination : nil
        if preciseLease == nil {
            preciseLease = hub.acquirePrecise()
        }
        if backgroundLease == nil {
            backgroundLease = hub.acquireBackground()
            hub.requestAlwaysIfNeeded()
        }
        reset()
        // After reset(), which clears it: a loop that ends where it began
        // banks laps at the line; a route that does not close finishes by
        // reaching its end.
        if let first = r.points.first, let last = r.points.last {
            loopIsClosed = r.kind.isTimed
                && CLLocation(latitude: first.lat, longitude: first.lon)
                    .distance(from: CLLocation(latitude: last.lat, longitude: last.lon)) < 60
        }
        stepIdx = r.kind.isPointToPoint ? 0 : min(1, max(r.steps.count - 1, 0))
        remaining = r.length
        step = r.steps.indices.contains(stepIdx) ? r.steps[stepIdx] : nil
        nextStep = r.steps.indices.contains(stepIdx + 1) ? r.steps[stepIdx + 1] : nil
        if let loc = lastLocation { handle(loc) }
        refreshApproachIfNeeded()
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
        clearApproach()
        reset()
        arrived = false
    }

    private func reset() {
        seg = 0
        along = 0
        lastMatchedAlong = nil
        distanceSinceLap = 0
        loopIsClosed = false
        stepIdx = 0
        announcedCallouts = [:]
        straightAnnounced = []
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
        lap = 1
        lastLapDuration = nil
        lapStartedAt = Date()
        clearApproach()
    }

    // MARK: Location updates

    /// How far ahead of the raw fix the HUD is allowed to dead-reckon.
    ///
    /// A fix describes the moment it was taken, not the moment it arrives. The
    /// main actor is shared with map drawing, tile loads and speech, so a fix
    /// is routinely a few hundred milliseconds old when `handle` sees it, and
    /// seconds old during a redraw stall. At 25 m/s that is tens of metres of
    /// road the turn counter was silently ignoring.
    private static let maxFixAge = 2.0
    /// At or beyond this age a fix re-anchors the route match but is not
    /// trusted to speak a maneuver from — it may describe a road the rider has
    /// already left.
    private static let staleFixAge = 5.0
    /// Lateral offset (m) at which the fix stops being "on the route".
    private static let offRouteEnter = 65.0
    /// Offset (m) it has to come back inside before the route is trusted
    /// again. The band between the two stops a drifting fix on a junction from
    /// flapping the banner and the alerts.
    private static let offRouteClear = 30.0

    /// Age of a fix, never negative (device clock corrections can push it
    /// below zero for a moment).
    static func fixAge(of location: CLLocation, now: Date = Date()) -> TimeInterval {
        max(now.timeIntervalSince(location.timestamp), 0)
    }

    func handle(_ loc: CLLocation) {
        lastLocation = loc
        if !hasLocation { hasLocation = true }
        let speed = max(loc.speed, 0)
        let age = Self.fixAge(of: loc)
        currentSpeedMps = speed

        // The raw fix is the truth until the route match below has something
        // better to say about it.
        userCoordinate = loc.coordinate
        if loc.course >= 0 {
            userHeading = loc.course
        }
        publishCameraPose(at: loc.coordinate, heading: userHeading, speed: speed)

        // A 60 m fix cannot prove the rider left the route. Matching on it is
        // how a street canyon installed a reroute that replaced a perfectly
        // good route; wait for a fix that can be trusted. Unknown accuracy
        // (negative, as in scripted fixes) is not evidence of a bad fix.
        guard loc.horizontalAccuracy <= 30 else { return }

        guard let r = route, !arrived, r.points.count > 1 else { return }

        // Not on the route yet: wait until the rider reaches the start area.
        // Projecting onto the whole loop would join at any overlapping stretch
        // near the house and start the loop clock early; the timer belongs at
        // the official start, not wherever the route happens to pass.
        if !joined {
            if let first = r.points.first {
                distanceToStart = loc.distance(from: CLLocation(latitude: first.lat, longitude: first.lon))
            }
            if r.kind.isTimed {
                // A timed loop starts where its template says. The approach
                // guidance exists so the rider can find that point, and the
                // 75 m gate was too tight for a GPS fix taken a few metres
                // past the line — which left the ride un-joinable and the
                // recording locked behind it.
                updateApproach(with: loc)
                let nearStart = project(loc.coordinate, onto: r,
                                        from: 0, to: r.points.count - 1,
                                        firstWithin: 80)
                if distanceToStart < 300, let m = nearStart {
                    join(r, m, at: loc, speed: speed)
                } else {
                    // Joining anywhere along the loop looked convenient, but a
                    // saved loop often passes near home: it joined there,
                    // skipped the approach and started the clock mid-lap. The
                    // rider gets directions to the start line instead.
                    return
                }
            } else {
                // Point-to-point is not a loop with a start line: the rider is
                // already on it wherever they are. Join at the nearest point on
                // the route and let the normal off-route logic reroute if they
                // are nowhere near it. Running "directions to the start" here
                // was what announced Glen Cove Avenue and Walnut Road while the
                // banner still showed the first turn of a route they had never
                // joined.
                guard let m = project(loc.coordinate, onto: r,
                                      from: 0, to: r.points.count - 1) else { return }
                join(r, m, at: loc, speed: speed)
            }
        }

        // Search around where we last were so overlapping stretches don't
        // confuse the match. The window reaches ~20 m back as well: a fix that
        // lands a few metres behind the last one used to be clamped to the
        // front of the window, which read as sudden extra progress.
        var lo = seg
        while lo > 0, r.cumulative[seg] - r.cumulative[lo] < 20 { lo -= 1 }
        var hi = seg
        while hi < r.points.count - 2, r.cumulative[hi + 1] - r.cumulative[seg] < 1000 { hi += 1 }
        guard var m = project(loc.coordinate, onto: r, from: lo, to: hi + 1) else { return }

        // The line has no segment: the closing point is also the start. Once
        // the rider is in the second half of a loop, also offer the first few
        // hundred metres as a candidate, so crossing the line matches `along 0`
        // instead of the run-out at the end of the loop.
        if r.kind.isTimed, along > r.length * 0.5 {
            var wrapHi = 0
            while wrapHi < r.points.count - 2, r.cumulative[wrapHi + 1] < 200 { wrapHi += 1 }
            if let wrapped = project(loc.coordinate, onto: r, from: 0, to: wrapHi + 1),
               wrapped.dist < m.dist - 1 {
                m = wrapped
            }
        }

        if m.dist >= Self.offRouteEnter {
            if offSince == nil { offSince = Date() }
            // Say so now. Leaving the last good turn distance on screen left
            // "350 ft to the turn" pointing at a junction the rider was not at.
            if !offRoute {
                offRoute = true
                RideDebug.shared.event("NAV-OFFROUTE", [
                    ("offset", "\(Int(m.dist))"),
                    ("along", "\(Int(m.along))"),
                    ("speed", "\(Int(speed))")
                ])
            }
            // A GPS bias of 50 m beside a road used to sit right on the old
            // 50 m line, so every fix flipped in and out and re-routed. The
            // band is wider now and a re-route cannot repeat for 40 seconds.
            if let o = offSince, Date().timeIntervalSince(o) > 10, speed > 2, !rerouting,
               Date().timeIntervalSince(lastReroute) > 40,
               movedSinceReroute(loc.coordinate) {
                reroute(from: loc)
            }
            return
        }
        if m.dist <= Self.offRouteClear {
            offSince = nil
            if offRoute {
                offRoute = false
                RideDebug.shared.event("NAV-ONROUTE", [
                    ("offset", "\(Int(m.dist))"),
                    ("along", "\(Int(m.along))")
                ])
            }
        }
        guard !offRoute else {
            // Still inside the hysteresis band after being off route: keep the
            // banner honest until the fix clearly rejoins the line.
            return
        }

        // Riding against the route mirrors every instruction: the right-hand
        // road gets announced as a left. If the course keeps disagreeing with
        // the route's tangent, the banner cannot be trusted — reroute the rider
        // instead of talking them into the wrong turn.
        if speed > 3, loc.course >= 0, loc.courseAccuracy <= 30 {
            let tangent = heading(on: r, at: m.along)
            if Geo.angleDiff(loc.course, tangent) > 110 {
                reversedFixes += 1
            } else {
                reversedFixes = 0
            }
            if reversedFixes >= 2, r.kind.isTimed {
                reversedFixes = 0
                RideDebug.shared.event("NAV-REVERSED", [
                    ("course", "\(Int(loc.course))"),
                    ("route", "\(Int(tangent))"),
                    ("along", "\(Int(along))")
                ])
                flipRoute(at: loc, speed: speed)
                return
            }
            if reversedFixes >= 3, !rerouting, Date().timeIntervalSince(lastReroute) > 20 {
                reversedFixes = 0
                RideDebug.shared.event("NAV-REVERSED", [
                    ("course", "\(Int(loc.course))"),
                    ("route", "\(Int(tangent))"),
                    ("along", "\(Int(along))")
                ])
                reroute(from: loc)
                return
            }
        } else {
            reversedFixes = 0
        }

        seg = m.seg
        along = predictedAlong(from: m.along, previous: along, age: age, speed: speed,
                               speedAccuracy: loc.speedAccuracy, route: r)
        // A lap is a crossing of the line, not "within 30 m of the end". The
        // old test fired while the rider was still 30 m short, reset the match
        // to zero, and the next fix matched the end of the loop again — two
        // laps in two seconds, then an early finish.
        if let previous = lastMatchedAlong, m.along > previous {
            distanceSinceLap += m.along - previous
        }
        let crossedLine = (lastMatchedAlong.map {
            $0 > r.length * 0.6 && m.along < r.length * 0.25
        } ?? false) && distanceSinceLap > r.length * 0.5
        lastMatchedAlong = m.along

        if crossedLine, r.kind.isTimed, loopIsClosed {
            if lap < totalLaps {
                lastLapDuration = Date().timeIntervalSince(lapStartedAt)
                lap += 1
                lapStartedAt = Date()
                distanceSinceLap = 0
                seg = m.seg
                along = m.along
                stepIdx = 0
                announcedCallouts = [:]
                straightAnnounced = []
                offRoute = false
                offSince = nil
                step = r.steps.indices.contains(0) ? r.steps[0] : nil
                nextStep = r.steps.indices.contains(1) ? r.steps[1] : nil
                stepDistance = 0
                RideDebug.shared.event("NAV-LAP", [
                    ("lap", "\(lap)/\(totalLaps)"),
                    ("last", "\(Int((lastLapDuration ?? 0).rounded()))"),
                    ("length", "\(Int(r.length))"),
                    ("speed", "\(Int(speed))")
                ])
                Speaker.shared.say("Lap \(lap) of \(totalLaps)", kind: .navigation)
            } else {
                arrived = true
                remaining = 0
                step = r.steps.last
                nextStep = nil
                stepDistance = 0
                lastLapDuration = Date().timeIntervalSince(lapStartedAt)
                RideDebug.shared.event("NAV-ARRIVE", [
                    ("along", "\(Int(m.along))"),
                    ("length", "\(Int(r.length))"),
                    ("lap", "\(lap)/\(totalLaps)"),
                    ("last", "\(Int((lastLapDuration ?? 0).rounded()))")
                ])
                Speaker.shared.say(Narrator.arrival, kind: .navigation)
                return
            }
        } else if r.kind.isTimed, !loopIsClosed,
                  r.length - m.along < 30, m.along > r.length * 0.5 {
            if lap < totalLaps {
                lastLapDuration = Date().timeIntervalSince(lapStartedAt)
                lap += 1
                lapStartedAt = Date()
                seg = 0
                along = 0
                remaining = r.length
                stepIdx = 0
                announcedCallouts = [:]
                straightAnnounced = []
                offRoute = false
                offSince = nil
                step = r.steps.indices.contains(0) ? r.steps[0] : nil
                nextStep = r.steps.indices.contains(1) ? r.steps[1] : nil
                stepDistance = 0
                RideDebug.shared.event("NAV-LAP", [
                    ("lap", "\(lap)/\(totalLaps)"),
                    ("last", "\(Int((lastLapDuration ?? 0).rounded()))"),
                    ("length", "\(Int(r.length))"),
                    ("speed", "\(Int(speed))")
                ])
                Speaker.shared.say("Lap \(lap) of \(totalLaps)", kind: .navigation)
                return
            }
            arrived = true
            remaining = 0
            step = r.steps.last
            nextStep = nil
            stepDistance = 0
            lastLapDuration = Date().timeIntervalSince(lapStartedAt)
            RideDebug.shared.event("NAV-ARRIVE", [
                ("along", "\(Int(m.along))"),
                ("length", "\(Int(r.length))"),
                ("lap", "\(lap)/\(totalLaps)"),
                ("last", "\(Int((lastLapDuration ?? 0).rounded()))")
            ])
            Speaker.shared.say(Narrator.arrival, kind: .navigation)
            return
        } else if !r.kind.isTimed, r.length - m.along < 30, m.along > r.length * 0.5 {
            // Point-to-point still ends by proximity; there is no line to cross.
            arrived = true
            remaining = 0
            step = r.steps.last
            nextStep = nil
            stepDistance = 0
            lastLapDuration = Date().timeIntervalSince(lapStartedAt)
            RideDebug.shared.event("NAV-ARRIVE", [
                ("along", "\(Int(m.along))"),
                ("length", "\(Int(r.length))"),
                ("lap", "\(lap)/\(totalLaps)"),
                ("last", "\(Int((lastLapDuration ?? 0).rounded()))")
            ])
            Speaker.shared.say(Narrator.arrival, kind: .navigation)
            return
        }

        remaining = max(r.length - along, 0)

        // A maneuver is retired when a fix proves the rider has passed it. The
        // predicted distance may count it down to zero, but prediction must not
        // skip the turn the rider is looking at.
        let previousStepIdx = stepIdx
        while stepIdx < r.steps.count - 1, r.steps[stepIdx].distance <= m.along + 5 { stepIdx += 1 }
        guard !r.steps.isEmpty else { return }
        var next = r.steps[min(stepIdx, r.steps.count - 1)]
        if next.turn == .arrive, lap < totalLaps {
            // "You have arrived" is wrong until the last lap. Show the line.
            next = NavStep(id: next.id, turn: .arrive, road: nil, at: next.at,
                           distance: next.distance, text: "Lap \(lap) of \(totalLaps)")
        }
        step = next
        nextStep = r.steps.indices.contains(stepIdx + 1) ? r.steps[stepIdx + 1] : nil
        stepDistance = max(next.distance - along, 0)
        if previousStepIdx != stepIdx {
            RideDebug.shared.event("NAV-STEP", [
                ("from", "\(previousStepIdx)"),
                ("to", "\(stepIdx)"),
                ("id", "\(next.id)"),
                ("turn", "\(next.turn)"),
                ("road", next.road ?? "—"),
                ("instruction", next.instruction),
                ("at", "\(Int(next.distance))"),
                ("along", "\(Int(along))"),
                ("toTurn", "\(Int(stepDistance))"),
                ("remaining", "\(Int(remaining))"),
                ("next", nextStep?.instruction ?? "—"),
                ("lap", "\(lap)/\(totalLaps)"),
                ("speed", "\(Int(speed))")
            ])
        }
        // A fix that may describe a road left minutes ago must not announce a
        // maneuver out of the blue.
        if age <= Self.staleFixAge {
            speakStraightIfNeeded(route: r)
            speakIfNeeded(next, speed: speed)
        }

        // Ride the puck and the camera on the route at the predicted distance:
        // the arrow sits on the drawn line, and it is where the rider is now
        // rather than where the last fix left off.
        let position = pointOn(r, at: along)
        userCoordinate = position
        if speed < 1.5 || loc.course < 0 || loc.courseAccuracy > 30 {
            // GPS course means nothing at a standstill and flickers there, so
            // the map spins at every light. The route's own tangent does not.
            userHeading = heading(on: r, at: along)
        }
        // Same fix as the raw pose published on the way in, so bypass the
        // throttle: the projected point is the one the camera should follow.
        publishCameraPose(at: position, heading: userHeading, speed: speed, force: true)
    }

    /// Dead-reckons the route distance to cover the age of the fix.
    ///
    /// Clamped so it can never claim the rider has passed a maneuver before a
    /// fix proves it, and never so far that a bad speed reading flings the
    /// puck down the road.
    private func predictedAlong(from matched: Double, previous: Double, age: TimeInterval,
                                speed: Double, speedAccuracy: Double,
                                route r: PlannedRoute) -> Double {
        var along = matched
        let speedIsUsable = speedAccuracy <= 0 || speedAccuracy <= 5
        if age > 0.05, speed > 1, speedIsUsable {
            let lead = min(min(age, Self.maxFixAge) * speed, 120)
            // Do not predict past the maneuver the rider is heading for.
            along = min(matched + lead, nextManeuverDistance(after: matched, in: r))
        }
        // A fix a few metres behind the last one is GPS noise, not a rider
        // going backwards: hold the counter instead of ticking it up again.
        if along < previous - 0.5, along > previous - 15, speed > 2 {
            along = previous
        }
        return min(max(along, 0), r.length)
    }

    private func nextManeuverDistance(after distance: Double, in r: PlannedRoute) -> Double {
        for s in r.steps where s.distance > distance + 0.5 {
            return s.distance
        }
        return r.length
    }

    /// The point on the route `distance` metres from its start.
    private func pointOn(_ r: PlannedRoute, at distance: Double) -> CLLocationCoordinate2D {
        guard r.points.count > 1 else { return r.coordinates.first ?? kCLLocationCoordinate2DInvalid }
        let d = min(max(distance, 0), r.length)
        let index = Self.segmentIndex(r, at: d)
        let a = r.points[index], b = r.points[index + 1]
        let span = r.cumulative[index + 1] - r.cumulative[index]
        let t = span > 0 ? min(max((d - r.cumulative[index]) / span, 0), 1) : 0
        return CLLocationCoordinate2D(latitude: a.lat + (b.lat - a.lat) * t,
                                      longitude: a.lon + (b.lon - a.lon) * t)
    }

    /// Index of the route segment that contains `distance`, by binary search:
    /// prediction can put the point several vertices ahead of `seg`.
    private static func segmentIndex(_ r: PlannedRoute, at distance: Double) -> Int {
        var low = 0
        var high = r.points.count - 2
        while low < high {
            let mid = (low + high + 1) / 2
            if r.cumulative[mid] <= distance { low = mid } else { high = mid - 1 }
        }
        return min(max(low, 0), r.points.count - 2)
    }

    /// Direction of the route around `distance`, measured over a short window
    /// so one sharp vertex does not spin the camera.
    private func heading(on r: PlannedRoute, at distance: Double) -> Double {
        let back = pointOn(r, at: distance - 12)
        let ahead = pointOn(r, at: distance + 18)
        return RoadGraph.flat(back.latitude, back.longitude, ahead.latitude, ahead.longitude).heading
    }

    private func publishCameraPose(at coordinate: CLLocationCoordinate2D,
                                   heading: Double, speed: Double, force: Bool = false) {
        let now = Date()
        let headingMoved = abs(heading - lastPoseHeading) >= 4
        // A hot phone or Low Power Mode should not be asked for twelve map
        // updates a second. Halving the rate is invisible at speed and buys
        // back battery and thermals on a long ride.
        let throttled = ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        let minimumInterval = throttled ? 0.25 : 0.08
        guard force || now.timeIntervalSince(lastPoseAt) >= minimumInterval || headingMoved && !throttled else { return }
        lastPoseAt = now
        lastPoseHeading = heading

        // Course from CoreLocation jitters by several degrees per fix. The map
        // rotates with this value, so feeding it raw makes the whole world
        // shiver. A circular low-pass over successive fixes is what makes the
        // rotation feel like Apple Maps instead of a compass in a paint shaker.
        var delta = heading - smoothedHeading
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        smoothedHeading = smoothedHeading + delta * 0.22
        smoothedHeading = smoothedHeading.truncatingRemainder(dividingBy: 360)
        if smoothedHeading < 0 { smoothedHeading += 360 }

        cameraPose = RideCameraPose(latitude: coordinate.latitude,
                                    longitude: coordinate.longitude,
                                    heading: smoothedHeading,
                                    speed: speed)
    }

    /// Waze's approach bands. The faster the rider, the earlier the first
    /// turn/exit prompt. The table is deliberately speed-banded rather than a
    /// continuous formula: it gives a stable, predictable prompt distance.
    nonisolated static func approachDistance(forSpeed speed: Double) -> Double {
        let kmh = max(speed, 0) * 3.6
        if kmh < 70 { return 305 }       // 1,000 ft
        if kmh < 90 { return 805 }       // 0.5 mi
        if kmh < 150 { return 3_218 }    // 2 mi
        return 4_828                     // 3 mi
    }

    /// Three decreasing rungs: the approach band, half of it, then the close
    /// prompt. All are in metres and independent of the unit setting.
    nonisolated static func calloutRungs(forSpeed speed: Double) -> [Double] {
        let approach = approachDistance(forSpeed: speed)
        return [approach, approach * 0.5, max(150, approach * 0.18)]
    }

    /// The final no-distance prompt must also scale; 25 m at 80 mph is under
    /// a second of warning.
    nonisolated static func finalPromptDistance(forSpeed speed: Double) -> Double {
        min(max(speed * 3.0, 35), 150)
    }

    private func speakIfNeeded(_ s: NavStep, speed: Double) {
        guard !s.instruction.isEmpty else { return }
        // The lap line is not the destination; the lap announcement covers it.
        if s.turn == .arrive, lap < totalLaps { return }
        var spoken = announcedCallouts[s.id, default: []]
        let rungs = Self.calloutRungs(forSpeed: speed)

        // A step can become current already inside several rungs — the next
        // manoeuvre after a turn is often 40 m away. Announce once, with the
        // live distance, and mark every rung already passed so the following
        // fixes do not fire a burst of duplicates.
        let crossed = rungs.enumerated()
            .filter { stepDistance <= $0.element && !spoken.contains($0.offset) }
        if let first = crossed.first {
            for rung in crossed { spoken.insert(rung.offset) }
            announcedCallouts[s.id] = spoken
            RideDebug.shared.event("NAV-CUE", [
                ("stage", "rung\(first.offset + 1)"),
                ("turn", "\(s.turn)"),
                ("road", s.road ?? "—"),
                ("instruction", s.instruction),
                ("distance", "\(Int(stepDistance))"),
                ("speed", "\(Int(speed))"),
                ("band", "\(Int(speed * 3.6)) km/h"),
                ("lookahead", "\(Int(first.element)) m")
            ])
            if UserDefaults.standard.bool(forKey: "voice.muted"), first.offset == rungs.count - 1 {
                TurnCue.approach()
            }
            Speaker.shared.say(Narrator.instruction(s, distance: stepDistance), kind: .navigation)
            return
        }

        // On the junction: "Turn left onto X", no distance. Scale this too.
        let final = Self.finalPromptDistance(forSpeed: speed)
        if stepDistance <= final, !spoken.contains(99) {
            spoken.insert(99)
            announcedCallouts[s.id] = spoken
            RideDebug.shared.event("NAV-CUE", [
                ("stage", "now"),
                ("turn", "\(s.turn)"),
                ("road", s.road ?? "—"),
                ("instruction", s.instruction),
                ("distance", "\(Int(stepDistance))"),
                ("speed", "\(Int(speed))"),
                ("finalBand", "\(Int(final)) m")
            ])
            Speaker.shared.say(Narrator.instruction(s, distance: nil), kind: .navigation)
        }
    }

    /// Google-style "stay on this road" callout at the top of a long segment.
    /// It fires once per segment (between maneuvers), not once per fix.
    private func speakStraightIfNeeded(route: PlannedRoute) {
        guard stepDistance >= 1_200, !straightAnnounced.contains(stepIdx) else { return }
        straightAnnounced.insert(stepIdx)
        let road = currentRoad(for: route)
        RideDebug.shared.event("NAV-STRAIGHT", [
            ("step", "\(stepIdx)"),
            ("toTurn", "\(Int(stepDistance))"),
            ("road", road ?? "—")
        ])
        Speaker.shared.say(
            Narrator.straight(road: road, distance: stepDistance),
            kind: .navigation
        )
    }

    private func currentRoad(for route: PlannedRoute) -> String? {
        guard !route.steps.isEmpty else { return nil }
        let index = min(max(stepIdx - 1, 0), route.steps.count - 1)
        let previous = route.steps[index]
        // At a point-to-point start, step zero may itself be the first turn.
        // Only trust its road when it is the start/straight step.
        if stepIdx == 0, previous.turn != .start, previous.turn != .straight {
            return nil
        }
        if let road = previous.road, !road.isEmpty {
            return StreetNames.road(road)
        }
        if let text = previous.text, let road = StreetNames.roadName(from: text) {
            return road
        }
        return nil
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
    /// True when the rider has moved far enough that another reroute attempt
    /// is worth speaking; a failed attempt used to repeat every 20 seconds.
    private func movedSinceReroute(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let previous = lastReroutePoint else { return true }
        return CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) > 300
    }

    /// A timed route can be ridden either way round. When the rider is clearly
    /// going the opposite direction, guide them along it in the direction they
    /// are actually travelling instead of counting down a route behind them.
    private func flipRoute(at loc: CLLocation, speed: Double) {
        guard let r = route else { return }
        let reversed = Self.flippedRoute(r)
        RideDebug.shared.event("NAV-FLIP", [
            ("from", "\(Int(along))"),
            ("length", "\(Int(r.length))"),
            ("speed", "\(Int(speed))")
        ])
        Speaker.shared.say("You're going the other way. Guiding you in this direction.",
                           kind: .navigation)
        start(reversed, roads: roads, vehicleKind: vehicleKind)
        if let m = project(loc.coordinate, onto: reversed,
                           from: 0, to: reversed.points.count - 1) {
            join(reversed, m, at: loc, speed: speed)
        }
    }

    private static func flippedRoute(_ r: PlannedRoute) -> PlannedRoute {
        let n = r.points.count
        var copy = PlannedRoute(points: Array(r.points.reversed()), roads: [:],
                                twistPerKm: r.twistPerKm, retraced: r.retraced,
                                bearing: r.bearing, displayName: r.displayName,
                                expectedTravelTime: r.expectedTravelTime, kind: r.kind)
        copy.laps = r.laps

        var steps: [NavStep] = [
            NavStep(id: 0, turn: .start, road: r.steps.first?.road, at: 0, distance: 0)
        ]
        for step in r.steps where step.turn != .start && step.turn != .arrive {
            steps.append(NavStep(id: 0,
                                 turn: step.turn.flipped,
                                 road: step.road,
                                 at: max(0, n - 1 - step.at),
                                 distance: max(0, r.length - step.distance),
                                 text: step.text))
        }
        steps.sort { $0.distance < $1.distance }
        steps = steps.enumerated().map { index, step in
            NavStep(id: index, turn: step.turn, road: step.road, at: step.at,
                    distance: step.distance, text: step.text)
        }
        steps.append(NavStep(id: steps.count, turn: .arrive, road: nil,
                             at: n - 1, distance: copy.length))
        copy.steps = steps
        return copy
    }

    private func reroute(from loc: CLLocation) {
        guard let r = route else { return }
        let generation = routeGeneration
        rerouting = true
        lastReroute = Date()
        lastReroutePoint = loc.coordinate
        RideDebug.shared.event("NAV-REROUTE", [
            ("roads", "\(roads.count)"),
            ("along", "\(Int(along))"),
            ("remaining", "\(Int(remaining))"),
            ("point", String(format: "%.5f,%.5f", loc.coordinate.latitude, loc.coordinate.longitude))
        ])
        Speaker.shared.say("Off route. Finding a way back", kind: .navigation)

        // Point-to-point directions genuinely end at the destination. Loops do
        // not: their destination is the start, so send them through the graph
        // rejoin below instead.
        if r.kind.isPointToPoint, let destination = normalDestination {
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
            request.source = MKMapItem.revert(location: CLLocation(latitude: source.latitude, longitude: source.longitude))
            request.destination = MKMapItem.revert(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
            request.transportType = .automobile
            VehiclePreferences.apply(to: request)

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
        normalDestination = new.kind.isPointToPoint ? new.destination : nil
        seg = 0
        along = 0
        announcedCallouts = [:]
        straightAnnounced = []
        offSince = nil
        offRoute = false
        // A rejoin route starts under the rider, so we are joined immediately.
        joined = true
        distanceToStart = 0
        arrived = false
        remaining = new.length
        stepIdx = new.kind.isPointToPoint ? 0 : min(1, max(new.steps.count - 1, 0))
        step = new.steps.indices.contains(stepIdx) ? new.steps[stepIdx] : nil
        nextStep = new.steps.indices.contains(stepIdx + 1) ? new.steps[stepIdx + 1] : nil
        stepDistance = 0
        Speaker.shared.say(Narrator.routeUpdated, kind: .navigation)
    }

    // MARK: - Approach to the start

    /// The loop starts where the rider is not. Rather than telling them to
    /// "head to the start" and leaving it at that, ask MapKit for driving
    /// directions to the first route point and turn those into the same kind
    /// of maneuver HUD the loop itself uses.
    private func refreshApproachIfNeeded() {
        guard let route, !joined, route.points.count > 1 else { return }
        guard let loc = lastLocation ?? hub.lastLocation else { return }
        guard let first = route.points.first else { return }
        let start = CLLocation(latitude: first.lat, longitude: first.lon)
        guard loc.distance(from: start) > 40 else { return }
        fetchApproach(from: loc, to: start)
    }

    private func join(_ r: PlannedRoute,
                      _ m: (seg: Int, dist: Double, along: Double),
                      at loc: CLLocation,
                      speed: Double) {
        joined = true
        lap = 1
        lastLapDuration = nil
        lapStartedAt = Date()
        clearApproach()
        seg = m.seg
        along = m.along
        RideDebug.shared.event("NAV-JOIN", [
            ("route", r.displayName ?? "—"),
            ("kind", "\(r.kind)"),
            ("along", "\(Int(m.along))"),
            ("seg", "\(m.seg)"),
            ("steps", "\(r.steps.count)"),
            ("speed", "\(Int(speed))"),
            ("point", String(format: "%.5f,%.5f", loc.coordinate.latitude, loc.coordinate.longitude))
        ])
        Speaker.shared.say(
            Narrator.routeStarted(road: r.steps.first?.road
                                  ?? r.steps.first?.text.flatMap(StreetNames.roadName)),
            kind: .navigation
        )
    }

    private func updateApproach(with loc: CLLocation) {
        guard let route, route.kind.isTimed, !joined else { clearApproach(); return }
        if approach != nil {
            advanceApproach(with: loc)
            let drift = approachLastOrigin.map { loc.distance(from: $0) } ?? .greatestFiniteMagnitude
            // Directions depend on where you are now. Re-ask after a couple of
            // hundred meters, not on every GPS fix.
            if drift > 200, !approachFetching,
               Date().timeIntervalSince(approachLastFetch) > 20 {
                refreshApproachIfNeeded()
            }
        } else {
            refreshApproachIfNeeded()
        }
    }

    private func fetchApproach(from origin: CLLocation, to destination: CLLocation) {
        guard !approachFetching else { return }
        approachFetching = true
        approachLastFetch = Date()
        approachLastOrigin = origin
        let startCoordinate = destination.coordinate

        approachTask?.cancel()
        approachTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let request = MKDirections.Request()
            request.source = MKMapItem.revert(location: origin)
            request.destination = MKMapItem.revert(location: CLLocation(latitude: startCoordinate.latitude,
                                     longitude: startCoordinate.longitude))
            request.transportType = .automobile
            VehiclePreferences.apply(to: request)
            request.requestsAlternateRoutes = false
            defer { self.approachFetching = false }
            do {
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled, self.route != nil, !self.joined else { return }
                guard let mapRoute = response.routes.first else { return }
                self.installApproach(mapRoute)
            } catch {
                // Keep the straight-line distance as the fallback. A later fix
                // retries the request, so a tunnel or dead spot is not final.
            }
        }
    }

    private func installApproach(_ mapRoute: MKRoute) {
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: mapRoute.polyline.pointCount
        )
        mapRoute.polyline.getCoordinates(&coordinates,
                                         range: NSRange(location: 0, length: coordinates.count))

        let steps = Self.approachSteps(from: mapRoute.steps.map {
            (instruction: $0.instructions, distance: $0.distance)
        })
        guard !steps.isEmpty else { return }
        let total = steps.map(\.at).max() ?? 0

        approach = ApproachGuide(
            steps: steps,
            distance: max(mapRoute.distance, total),
            expectedTravelTime: mapRoute.expectedTravelTime,
            coordinates: coordinates
        )
        approachCoordinates = coordinates
        approachAnnounced = []
        if let loc = lastLocation {
            advanceApproach(with: loc)
        }
    }

    /// Turns MapKit's steps into maneuver positions measured from the start of
    /// the approach.
    ///
    /// MapKit names the maneuver at the END of a step: a 1290 m "Turn right
    /// onto 7th Ave" step means ride 1290 m, *then* turn. Recording the start
    /// of the step pointed every maneuver at the junction before it, so the
    /// banner described the turn after the one the rider was sitting at and
    /// counted down the block beyond it — the "350 ft" that would not go away
    /// at the light.
    nonisolated static func approachSteps(
        from steps: [(instruction: String, distance: CLLocationDistance)]
    ) -> [ApproachStep] {
        var out: [ApproachStep] = []
        var cursor = 0.0
        for (index, step) in steps.enumerated() {
            cursor += step.distance
            let text = StreetNames.instruction(
                step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !text.isEmpty else { continue }
            out.append(ApproachStep(
                id: index,
                instruction: text,
                symbol: NavStep.Turn.parse(text).symbol,
                at: cursor
            ))
        }
        return out
    }

    private func advanceApproach(with loc: CLLocation) {
        guard let guide = approach, !guide.steps.isEmpty else { return }
        let match = nearestPoint(on: guide.coordinates, to: loc.coordinate)
        let along = min(max(match.along, 0), guide.distance)

        // The maneuver the rider is heading toward: the next step boundary.
        let upcoming = guide.steps.first(where: { $0.at > along + 8 })
            ?? guide.steps.last
        guard let upcoming else { return }

        approachInstruction = upcoming.instruction
        approachSymbol = upcoming.symbol
        approachStepDistance = max(upcoming.at - along, 0)
        approachRemaining = max(guide.distance - along, 0)
        approachETA = guide.expectedTravelTime.map { time in
            guide.distance > 0 ? time * (approachRemaining / guide.distance) : 0
        }

        if approachStepDistance < 140,
           approachStepDistance > 5,
           !approachAnnounced.contains(upcoming.id) {
            approachAnnounced.insert(upcoming.id)
            // "Turn left onto..." with no distance was the other half of the
            // complaint: the rider could not tell which junction it meant.
            Speaker.shared.say("In \(Units.spokenDistance(approachStepDistance)), \(upcoming.instruction)",
                               kind: .navigation)
        }
    }

    private func clearApproach() {
        approachTask?.cancel()
        approachTask = nil
        approachFetching = false
        approach = nil
        approachInstruction = nil
        approachStepDistance = 0
        approachRemaining = 0
        approachETA = nil
        approachCoordinates = []
        approachAnnounced = []
        approachLastOrigin = nil
    }

    /// Closest point on a polyline, in meters along it. MapKit points are used
    /// so the maths is in a stable projected space rather than degrees.
    private func nearestPoint(on coordinates: [CLLocationCoordinate2D],
                              to coordinate: CLLocationCoordinate2D) -> (along: Double, lateral: Double) {
        guard coordinates.count > 1 else { return (0, .greatestFiniteMagnitude) }
        let p = MKMapPoint(coordinate)
        var best = (along: 0.0, lateral: Double.greatestFiniteMagnitude)
        var travelled = 0.0
        for index in 0..<(coordinates.count - 1) {
            let a = MKMapPoint(coordinates[index])
            let b = MKMapPoint(coordinates[index + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let segment = lengthSquared.squareRoot()
            let t = lengthSquared > 0
                ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
                : 0
            let projected = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            let lateral = p.distance(to: projected)
            if lateral < best.lateral {
                best = (travelled + t * segment, lateral)
            }
            travelled += segment
        }
        return best
    }

    @available(*, deprecated, message: "Use NavStep.Turn.parse(_:).symbol")
    nonisolated private static func approachSymbol(for instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("roundabout") { return "arrow.triangle.turn.up.right.circle" }
        if text.contains("u-turn") || text.contains("u turn") { return "arrow.uturn.left" }
        if text.contains("sharp left") { return "arrow.turn.down.left" }
        if text.contains("sharp right") { return "arrow.turn.down.right" }
        if text.contains("slight left") || text.contains("bear left") { return "arrow.up.left" }
        if text.contains("slight right") || text.contains("bear right") { return "arrow.up.right" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        if text.contains("merge") { return "arrow.triangle.merge" }
        if text.contains("arrive") || text.contains("destination") { return "flag.checkered" }
        return "arrow.up"
    }
}
