import Foundation
import CoreLocation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
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
    var lap: Int = 1          // 1-based; a new lap re-arms the device alerts
}

@Observable
final class AlertManager {
    var activeAlert: ActiveAlert?
    var curveAlert: CurveWarning?
    var surfaceAlert: SurfaceAlert?
    var speedLimitMph: Int?
    var isOverLimit = false
    /// Updated when the rider crosses onto a new OSM way; voice marks use it
    /// to name the road being avoided without another geocoding pass.
    private(set) var currentRoadName: String?

    @ObservationIgnored private let store = HazardStore.shared
    @ObservationIgnored private let roadStore = RoadStore.shared
    @ObservationIgnored private let curveEngine = CurveEngine()
    @ObservationIgnored private var lastKindAlert: [HazardKind: Date] = [:]
    @ObservationIgnored private var overSince: Date?
    @ObservationIgnored private var lastOverAlert = Date.distantPast
    @ObservationIgnored private var lastHazardSpeak = Date.distantPast
    @ObservationIgnored private var lastRoadID: Int64?
    @ObservationIgnored private var surfaceAlertedAt: [Int64: Date] = [:]
    @ObservationIgnored private var announcedDevices = Set<Int64>()
    @ObservationIgnored private var lastDeviceRouteID: UUID?
    @ObservationIgnored private var lastDeviceLap = 1
    @ObservationIgnored private var routeHazards: [Hazard] = []
    @ObservationIgnored private var cachedHazards: [Hazard] = []
    @ObservationIgnored private var hazardCacheAt = Date.distantPast
    @ObservationIgnored private var hazardCacheCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored private var cachedRoads: [Road] = []
    @ObservationIgnored private var roadCacheAt = Date.distantPast
    @ObservationIgnored private var roadCacheCoordinate: CLLocationCoordinate2D?
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

    /// Add a rider mark to an already loaded route without throwing away the
    /// OSM corridor result.
    func addRouteHazard(_ hazard: Hazard, for routeID: UUID) {
        guard routeHazardsRouteID == routeID else { return }
        routeHazards.append(hazard)
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

    // MARK: Debug counters

    var hazardTileCount: Int { store.loadedTileCount }
    var hazardItemCount: Int { store.itemCount }
    var roadTileCount: Int { roadStore.loadedTileCount }
    var roadItemCount: Int { roadStore.itemCount }
    var pendingTileCount: Int { store.pendingCount + roadStore.pendingCount }
    /// nil until the route-corridor query answers.
    var routeHazardCount: Int? { routeHazardsLoaded ? routeHazards.count : nil }

    @ObservationIgnored private var lastDataLine = Date.distantPast

    /// Call on every GPS update.
    func handle(_ loc: CLLocation) {
        // When the route-corridor query has succeeded *with devices*, the tile
        // cache is not needed and we avoid a second Overpass download. An empty
        // answer keeps the tiles warm as a fallback.
        if !routeHazardsLoaded || routeHazards.isEmpty {
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
        if let lap = routeContext?.lap, lap != lastDeviceLap {
            // Every device on the loop deserves its warning on each pass.
            announcedDevices.removeAll()
            lastDeviceLap = lap
            activeAlert = nil
        }

        // Road matching, speed limits and surface warnings are speed-independent:
        // they must keep updating while stopped at a light.
        handleRoad(loc, now)

        handleHazards(loc, now, context: routeContext)
        logDataIfDue(now, context: routeContext)
    }

    private func logDataIfDue(_ now: Date, context: RideRouteContext?) {
        guard now.timeIntervalSince(lastDataLine) > 60 else { return }
        lastDataLine = now
        RideDebug.shared.data([
            ("hazardTiles", "\(hazardTileCount)"),
            ("hazardItems", "\(hazardItemCount)"),
            ("roadTiles", "\(roadTileCount)"),
            ("roadItems", "\(roadItemCount)"),
            ("pending", "\(pendingTileCount)"),
            ("routeHazards", routeHazardCount.map { "\($0)" } ?? "not-loaded"),
            ("source", (routeHazardsLoaded && !routeHazards.isEmpty) ? "corridor" : "tiles"),
            ("context", context == nil ? "none" : "ok"),
            ("matchedRoad", curveEngine.current.map { "\($0.road.id)" } ?? "none"),
            ("limit", speedLimitMph.map { "\($0)" } ?? "none")
        ])
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
                // The device can be announced from up to ~400 m out, so the
                // refresh window has to cover the distance it was announced at
                // or the banner is cleared on the very next fix.
                route: context.route, near: context.progress,
                ahead: max(alert.distance, 80) + 50, maxLateral: 45
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

        let hazards: [Hazard]
        if routeHazardsRouteID == context.route.id, routeHazardsLoaded, !routeHazards.isEmpty {
            hazards = routeHazards
        } else {
            // Either the corridor query has not answered, failed, or answered
            // with nothing. Reuse the tile fallback for a few seconds: with
            // 6,000 cached hazards this loop is the single hottest path in the
            // alert engine, and the set barely changes over 50 metres.
            let moved = hazardCacheCoordinate.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) > 50
            } ?? true
            if moved || now.timeIntervalSince(hazardCacheAt) > 5 {
                cachedHazards = HazardStore.items(near: loc.coordinate)
                hazardCacheAt = now
                hazardCacheCoordinate = loc.coordinate
            }
            hazards = cachedHazards
        }

        var best: (hazard: Hazard, ahead: Double, match: RouteCorridorMatch, lookahead: Double)?

        for h in hazards {
            let kind = h.kind
            // Cheap reject before projecting a distant device onto the route.
            if abs(h.lat - loc.coordinate.latitude) > 0.01
                || abs(h.lon - loc.coordinate.longitude) > 0.015 { continue }

            let lookahead = Self.alertDistance(speed: loc.speed, kind: kind, reactionTime: reactionTime)
            let lateralLimit = kind.lateralTolerance
            guard let match = RouteCorridor.project(
                latitude: h.lat, longitude: h.lon,
                route: context.route, near: context.progress,
                behind: 20, ahead: lookahead, maxLateral: lateralLimit
            ) else {
                continue
            }

            let ahead = match.along - context.progress
            guard ahead >= 8, ahead <= lookahead else { continue }

            // A camera tagged for the opposite carriageway can sit 10 m to the
            // side and still project onto this route. Its bearing tells us it
            // is not watching this direction of travel.
            if h.facesAway(from: loc.course >= 0 ? loc.course : nil) {
                RideDebug.shared.skip(h, reason: "facing-away", ahead: ahead)
                continue
            }

            // Settings are only consulted once a device is genuinely on the
            // corridor, so a withheld alert can name the reason it was withheld.
            guard AlertSettings.enabled(kind.settingsKey) else {
                RideDebug.shared.skip(h, reason: "disabled", ahead: ahead)
                continue
            }
            if (kind == .stop || kind == .signal), speedMph < hazardThreshold {
                RideDebug.shared.skip(h, reason: "under-speed-gate", ahead: ahead)
                continue
            }
            guard !announcedDevices.contains(h.id) else {
                RideDebug.shared.skip(h, reason: "already-announced", ahead: ahead)
                continue
            }
            if kind.kindCooldown > 0, let t = lastKindAlert[kind], now.timeIntervalSince(t) < kind.kindCooldown {
                RideDebug.shared.skip(h, reason: "cooldown", ahead: ahead)
                continue
            }

            if best == nil || ahead < best!.ahead {
                best = (h, ahead, match, lookahead)
            }
        }

        guard let best else { return }
        // Dense urban blocks can put a light and a stop sign within a few
        // seconds. One audible hazard at a time; the next fix will still see
        // it after the gap and announce it if it is genuinely close.
        guard now.timeIntervalSince(lastHazardSpeak) >= 3 else { return }
        lastHazardSpeak = now
        announcedDevices.insert(best.hazard.id)
        lastKindAlert[best.hazard.kind] = now
        activeAlert = ActiveAlert(hazard: best.hazard, distance: best.ahead, since: now)
        haptic()
        let spoken = Narrator.hazard(best.hazard.kind, distance: best.ahead)
        Speaker.shared.say(spoken)
        RideDebug.shared.hazard(best.hazard,
                               ahead: best.ahead,
                               lateral: best.match.lateral,
                               location: loc,
                               progress: context.progress,
                               lookahead: best.lookahead,
                               spoken: spoken.fallback)
        HelmetAudio.shared.hazardCue(
            relativeBearing: signedBearing(from: loc, to: best.hazard.coordinate),
            urgent: best.hazard.kind == .stop || best.hazard.kind == .signal
        )
    }

    /// Waze-style warning distances, in metres: short in town, long on a fast
    /// road, scaled by the kind so a school gets less notice than a camera.
    /// The rider's reaction time still adds on top, so slowing it down in
    /// Settings lengthens every warning rather than being ignored.
    nonisolated static func alertDistance(speed: Double, kind: HazardKind,
                                          reactionTime: Double) -> Double {
        let band: Double
        switch speed {
        case ..<7: band = 150        // under ~16 mph
        case ..<14: band = 220       // under ~31 mph
        case ..<22: band = 320       // under ~49 mph
        default: band = 420          // motorway pace
        }
        let reaction = speed * reactionTime
        let braking = (speed * speed) / (2 * 4.5)
        let scaled = max(band, reaction + braking) * kind.warningFactor
        return min(max(scaled, 120), kind.maxLookahead)
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

        // Always match to the road (needed for limits and surface); only detect curves when none is showing.
        // The nearest 7,000 roads do not need to be fetched and matched on every fix.
        let moved = roadCacheCoordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) > 30
        } ?? true
        if moved || now.timeIntervalSince(roadCacheAt) > 2 {
            cachedRoads = RoadStore.items(near: loc.coordinate)
            roadCacheAt = now
            roadCacheCoordinate = loc.coordinate
        }
        let roads = cachedRoads
        if let w = curveEngine.evaluate(loc, roads: roads, detectCurves: curvesOn && curveAlert == nil) {
            curveAlert = w
            haptic()
            speak(w.spoken)
            HelmetAudio.shared.turnCue(direction: w.dir == .left ? -1 : 1)
            RideDebug.shared.curve(w, location: loc)
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
        if limit != speedLimitMph {
            speedLimitMph = limit
            RideDebug.shared.speedLimit(limit, road: cur.road.name, location: loc)
        }
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
                    RideDebug.shared.overLimit(mph: mph, limit: l, location: loc)
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
            currentRoadName = cur.road.name
            RideDebug.shared.road(cur.road, limit: limit, unpaved: cur.road.isUnpaved, location: loc)
            if AlertSettings.enabled("alert.surface"), cur.road.isUnpaved,
               now.timeIntervalSince(surfaceAlertedAt[cur.road.id] ?? .distantPast) > 600 {
                surfaceAlertedAt[cur.road.id] = now
                surfaceAlert = SurfaceAlert(text: cur.road.surfaceName, since: now)
                haptic()
                speak("Unpaved road")
                RideDebug.shared.surface(cur.road.surfaceName, location: loc)
            }
        }
    }

    // MARK: Feedback
    #if canImport(UIKit)
    @ObservationIgnored private let feedback = UINotificationFeedbackGenerator()
    #endif

    private func haptic() {
        // Riders who silence their phone still get the visual banner; this
        // key exists so that choice is explicit rather than accidental.
        guard UserDefaults.standard.object(forKey: "alert.haptics") == nil
                || UserDefaults.standard.bool(forKey: "alert.haptics") else { return }
        #if canImport(UIKit)
        feedback.notificationOccurred(.warning)
        #endif
    }

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
