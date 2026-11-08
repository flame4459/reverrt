import Foundation
import CoreLocation
import AVFoundation
import UIKit
import Observation

struct ActiveAlert: Equatable {
    var hazard: Hazard
    var distance: Double   // meters
    var since: Date
}

struct SurfaceAlert: Equatable {
    var text: String
    var since: Date
}


/// The slice of navigation state the alert engine needs. Keeping this small
/// avoids giving AlertManager a reference to the whole navigation manager.
nonisolated struct RideRouteContext {
    let route: PlannedRoute
    let progress: Double      // meters along the route where the rider is
}

@Observable
final class AlertManager {
    var activeAlert: ActiveAlert?
    var curveAlert: CurveWarning?
    var surfaceAlert: SurfaceAlert?
    var speedLimitMph: Int?
    var isOverLimit = false

    @ObservationIgnored private let store = HazardStore.shared
    @ObservationIgnored private let roadStore = RoadStore.shared
    @ObservationIgnored private let curveEngine = CurveEngine()
    @ObservationIgnored private var lastKindAlert: [HazardKind: Date] = [:]
    @ObservationIgnored private var overSince: Date?
    @ObservationIgnored private var lastOverAlert = Date.distantPast
    @ObservationIgnored private var lastRoadID: Int64?
    @ObservationIgnored private var surfaceAlertedAt: [Int64: Date] = [:]
    @ObservationIgnored private var announcedDevices = Set<Int64>()
    @ObservationIgnored private var lastDeviceRouteID: UUID?
    @ObservationIgnored private var routeHazards: [Hazard] = []
    @ObservationIgnored private var routeHazardsLoaded = false
    @ObservationIgnored private var routeHazardsRouteID: UUID?

    /// Called by the ride screen after the route-corridor Overpass query
    /// finishes. Pass nil when the request failed so the tile cache remains a
    /// fallback; pass [] when the route genuinely has no devices.
    func setRouteHazards(_ hazards: [Hazard]?, for routeID: UUID) {
        if routeHazardsRouteID != routeID {
            announcedDevices.removeAll()
            activeAlert = nil
        }
        routeHazards = hazards ?? []
        routeHazardsLoaded = hazards != nil
        routeHazardsRouteID = routeID
    }

    func clearRouteHazards() {
        routeHazards = []
        routeHazardsLoaded = false
        routeHazardsRouteID = nil
        announcedDevices.removeAll()
        activeAlert = nil
    }

    /// Set by the ride screen. When this returns nil (no active route, off
    /// route, or arrived) traffic-device alerts are suppressed entirely.
    @ObservationIgnored var routeProvider: (() -> RideRouteContext?)?

    /// Call on every GPS update.
    func handle(_ loc: CLLocation) {
        // When the route-corridor query has succeeded, the tile cache is not
        // needed for traffic devices and we avoid a second Overpass download.
        if !routeHazardsLoaded {
            store.ensureTiles(around: loc.coordinate)
        }
        roadStore.ensureTiles(around: loc.coordinate)
        let now = Date()
        surfaceAlertedAt = surfaceAlertedAt.filter { now.timeIntervalSince($0.value) < 900 }
        lastKindAlert = lastKindAlert.filter { now.timeIntervalSince($0.value) < 120 }

        let routeContext = routeProvider?()
        if let routeID = routeContext?.route.id, routeID != lastDeviceRouteID {
            announcedDevices.removeAll()
            lastDeviceRouteID = routeID
            activeAlert = nil
        }

        // Road matching, speed limits and surface warnings are speed-independent:
        // they must keep updating while stopped at a light.
        handleRoad(loc, now)

        handleHazards(loc, now, context: routeContext)
    }

    // MARK: Stop signs, lights, cameras, rail crossings, schools, roundabouts
    private func handleHazards(_ loc: CLLocation, _ now: Date, context: RideRouteContext?) {
        guard let context else {
            activeAlert = nil
            return
        }

        // Keep the on-screen alert tied to route distance, and clear it as
        // soon as the rider has passed the device.
        if let alert = activeAlert {
            if let match = RouteCorridor.project(
                latitude: alert.hazard.lat, longitude: alert.hazard.lon,
                route: context.route, near: context.progress, ahead: 80, maxLateral: 45
            ) {
                let ahead = match.along - context.progress
                if ahead < 8 {
                    activeAlert = nil
                } else {
                    activeAlert?.distance = ahead
                }
            } else {
                activeAlert = nil
            }
        }

        // Never chatter at walking/creeping speed. At 5 mph the rider is
        // already at the junction; announcing every device repeatedly is
        // worse than silence.
        guard loc.speed >= 3.0, loc.course >= 0 else { return }

        let speedMph = loc.speed * 2.23694
        let hazardThreshold = Double(UserDefaults.standard.object(forKey: "alert.hazardSpeedThreshold") as? Int ?? 0)
        let reactionTime = UserDefaults.standard.object(forKey: "alert.reactionTime") as? Double ?? 1.5
        let rawLookahead = loc.speed * reactionTime
            + (loc.speed * loc.speed) / (2 * 4.5)
            + loc.speed * 5.0

        let hazards: [Hazard]
        if routeHazardsRouteID == context.route.id, routeHazardsLoaded {
            hazards = routeHazards
        } else {
            hazards = store.items(near: loc.coordinate)
        }

        var best: (hazard: Hazard, ahead: Double, match: RouteCorridorMatch)?

        for h in hazards {
            let kind = h.kind
            guard AlertSettings.enabled(kind.settingsKey) else { continue }
            if (kind == .stop || kind == .signal), speedMph < hazardThreshold { continue }
            guard !announcedDevices.contains(h.id) else { continue }
            if kind.kindCooldown > 0, let t = lastKindAlert[kind], now.timeIntervalSince(t) < kind.kindCooldown {
                continue
            }
            // Cheap reject before projecting a distant device onto the route.
            if abs(h.lat - loc.coordinate.latitude) > 0.01
                || abs(h.lon - loc.coordinate.longitude) > 0.015 { continue }

            let lookahead = min(max(rawLookahead, 150), min(kind.maxLookahead, 400))
            let lateralLimit: Double
            switch kind {
            case .school: lateralLimit = 45       // schools sit back from the road
            case .roundabout: lateralLimit = 30
            default: lateralLimit = 14
            }
            guard let match = RouteCorridor.project(
                latitude: h.lat, longitude: h.lon,
                route: context.route, near: context.progress,
                behind: 20, ahead: lookahead, maxLateral: lateralLimit
            ) else {
                continue
            }

            let ahead = match.along - context.progress
            guard ahead >= 8, ahead <= lookahead else { continue }
            if best == nil || ahead < best!.ahead {
                best = (h, ahead, match)
            }
        }

        guard let best else { return }
        announcedDevices.insert(best.hazard.id)
        lastKindAlert[best.hazard.kind] = now
        activeAlert = ActiveAlert(hazard: best.hazard, distance: best.ahead, since: now)
        haptic()
        speak("\(best.hazard.kind.approachName) in \(Units.spokenApproachDistance(best.ahead))")
        HelmetAudio.shared.hazardCue(
            relativeBearing: signedBearing(from: loc, to: best.hazard.coordinate),
            urgent: best.hazard.kind == .stop || best.hazard.kind == .signal
        )
    }

    // MARK: Road: curves, speed limit, surface
    private func handleRoad(_ loc: CLLocation, _ now: Date) {
        let curvesOn = AlertSettings.enabled("alert.curves")
        if !curvesOn { curveAlert = nil }

        if let c = curveAlert {
            let apex = CLLocation(latitude: c.apexLat, longitude: c.apexLon)
            let d = loc.distance(from: apex)
            let diff = Geo.angleDiff(Geo.bearing(from: loc.coordinate, to: apex.coordinate), loc.course)
            if d < 20 || diff > 90 || now.timeIntervalSince(c.since) > 40 {
                curveAlert = nil
            } else {
                curveAlert?.distance = d
            }
        }

        // Always match to the road (needed for limits and surface); only detect curves when none is showing
        let roads = roadStore.items(near: loc.coordinate)
        if let w = curveEngine.evaluate(loc, roads: roads, detectCurves: curvesOn && curveAlert == nil) {
            curveAlert = w
            haptic()
            speak(w.spoken)
            HelmetAudio.shared.turnCue(direction: w.dir == .left ? -1 : 1)
        }
        updateRoadInfo(loc, now)
    }

    private func updateRoadInfo(_ loc: CLLocation, _ now: Date) {
        if let s = surfaceAlert, now.timeIntervalSince(s.since) > 10 { surfaceAlert = nil }

        guard let cur = curveEngine.current else {
            if speedLimitMph != nil { speedLimitMph = nil }
            if isOverLimit { isOverLimit = false }
            overSince = nil
            return
        }

        // Speed limit
        let limit = cur.road.speedLimitMph(forward: cur.forward)
        if limit != speedLimitMph { speedLimitMph = limit }
        let mph = loc.speed * 2.23694
        if let l = limit, mph > Double(l) {
            if !isOverLimit { isOverLimit = true }
            let tol = Double(UserDefaults.standard.object(forKey: "alert.limitTolerance") as? Int ?? 5)
            if AlertSettings.enabled("alert.overLimit"), mph > Double(l) + tol {
                if overSince == nil { overSince = now }
                if let o = overSince, now.timeIntervalSince(o) >= 5, now.timeIntervalSince(lastOverAlert) > 60 {
                    lastOverAlert = now
                    haptic()
                    speak("Over the speed limit")
                }
            } else {
                overSince = nil
            }
        } else {
            if isOverLimit { isOverLimit = false }
            overSince = nil
        }

        // Surface: warn when you move onto an unpaved road
        if cur.road.id != lastRoadID {
            lastRoadID = cur.road.id
            if AlertSettings.enabled("alert.surface"), cur.road.isUnpaved,
               now.timeIntervalSince(surfaceAlertedAt[cur.road.id] ?? .distantPast) > 600 {
                surfaceAlertedAt[cur.road.id] = now
                surfaceAlert = SurfaceAlert(text: cur.road.surfaceName, since: now)
                haptic()
                speak("Unpaved road")
            }
        }
    }

    // MARK: Feedback
    @ObservationIgnored private let feedback = UINotificationFeedbackGenerator()

    private func haptic() { feedback.notificationOccurred(.warning) }

    private func speak(_ text: String) { Speaker.shared.say(text) }


    private func signedBearing(from loc: CLLocation, to coordinate: CLLocationCoordinate2D) -> Double {
        var delta = Geo.bearing(from: loc.coordinate, to: coordinate) - loc.course
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }
}

nonisolated enum Geo {
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
