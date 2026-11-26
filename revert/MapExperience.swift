import Foundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Geometry

nonisolated enum RouteGeometry {
    static func coordinate(at distance: Double, route: PlannedRoute) -> CLLocationCoordinate2D? {
        guard let first = route.points.first?.coordinate else { return nil }
        guard route.points.count > 1 else { return first }
        let clamped = min(max(distance, 0), route.length)
        guard let index = route.cumulative.firstIndex(where: { $0 >= clamped }) else {
            return route.points.last?.coordinate
        }
        guard index > 0 else { return first }
        let start = route.cumulative[index - 1]
        let end = route.cumulative[index]
        let span = max(end - start, 0.001)
        let t = (clamped - start) / span
        let a = route.points[index - 1]
        let b = route.points[index]
        return CLLocationCoordinate2D(latitude: a.lat + (b.lat - a.lat) * t,
                                      longitude: a.lon + (b.lon - a.lon) * t)
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = b - a
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }
}

// MARK: - Map matching

nonisolated struct RouteMatch: Equatable, Sendable {
    let coordinate: CLLocationCoordinate2D
    let progress: Double
    let lateralMeters: Double

    static func == (lhs: RouteMatch, rhs: RouteMatch) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.progress == rhs.progress
            && lhs.lateralMeters == rhs.lateralMeters
    }
}

nonisolated enum RouteMatcher {
    static func match(_ fix: CLLocationCoordinate2D, route: PlannedRoute,
                      minimumProgress: Double = 0) -> RouteMatch? {
        guard route.points.count > 1 else { return nil }
        let raw = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        var best: RouteMatch?
        for index in 1..<route.points.count {
            let a = route.points[index - 1]
            let b = route.points[index]
            let pa = CLLocation(latitude: a.lat, longitude: a.lon)
            let pb = CLLocation(latitude: b.lat, longitude: b.lon)
            let segment = max(pa.distance(from: pb), 0.001)
            let t = min(max(projection(fix, a: a, b: b), 0), 1)
            let coordinate = CLLocationCoordinate2D(
                latitude: a.lat + (b.lat - a.lat) * t,
                longitude: a.lon + (b.lon - a.lon) * t
            )
            let distance = raw.distance(from: CLLocation(latitude: coordinate.latitude,
                                                         longitude: coordinate.longitude))
            let progress = route.cumulative[index - 1] + segment * t
            guard progress >= minimumProgress - 1 else { continue }
            if best == nil || distance < best!.lateralMeters {
                best = RouteMatch(coordinate: coordinate,
                                  progress: max(progress, minimumProgress),
                                  lateralMeters: distance)
            }
        }
        guard let best, best.lateralMeters <= 30 else { return nil }
        return best
    }

    private static func projection(_ p: CLLocationCoordinate2D,
                                   a: RoutePoint, b: RoutePoint) -> Double {
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(a.lat * .pi / 180)
        let px = (p.longitude - a.lon) * lonScale
        let py = (p.latitude - a.lat) * latScale
        let bx = (b.lon - a.lon) * lonScale
        let by = (b.lat - a.lat) * latScale
        let denom = bx * bx + by * by
        guard denom > 0.0001 else { return 0 }
        return (px * bx + py * by) / denom
    }
}

// MARK: - Camera

nonisolated struct RideCameraFrame: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var heading: Double
    var pitch: Double
    var distance: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated struct RideCameraEngine: Sendable {
    private(set) var frame: RideCameraFrame?
    private(set) var progress: Double = 0
    private var latitudeVelocity = 0.0
    private var longitudeVelocity = 0.0
    private var lastTimestamp: TimeInterval?

    mutating func update(route: PlannedRoute?, rawProgress: Double, speed: Double,
                         maneuverMeters: Double, fallbackHeading: Double,
                         timestamp: TimeInterval,
                         centered: Bool = false,
                         mode: RideCameraMode = .cockpit) -> RideCameraFrame? {
        guard let route else { return frame }
        let dt = min(max(timestamp - (lastTimestamp ?? timestamp), 0), 0.1)
        lastTimestamp = timestamp
        progress = max(progress, rawProgress)
        // Dead reckoning between GPS fixes; the target progress itself is
        // replaced by the next real fix.
        if dt > 0 { progress = min(progress + max(speed, 0) * dt, route.length) }

        let curvature = Self.curvatureDegreesPerMetre(route: route, progress: progress)
        // Speed alone gives a camera that arrives at a corner late. Adding the
        // road's own curvature extends the lead exactly where the view needs
        // it, and leaves straights alone.
        let curveBoost = 1 + min(curvature * 6, 0.8)
        let lookAhead = centered ? 0 : min(max(0.55 * speed * 3, 12), 55) * curveBoost
        // Lead the filtered fix by a fraction of a second so the camera is
        // already where the rider's eyes are, not one GPS interval late.
        // Classic follow opts out: the rider stays centred.
        let predictedProgress = centered ? progress : progress + speed * 0.18
        let center = RouteGeometry.coordinate(at: predictedProgress + lookAhead, route: route)
            ?? route.points.first?.coordinate
        guard let center else { return frame }
        let ahead = RouteGeometry.coordinate(at: progress + (centered ? 14 : lookAhead + 8),
                                             route: route) ?? center
        let routeHeading = RouteGeometry.bearing(from: center, to: ahead)
        // North up means exactly that: the map does not rotate with the road.
        let targetHeading = mode.usesPose
            ? (routeHeading.isFinite ? routeHeading : fallbackHeading)
            : 0
        let dtCappedForHeading = max(dt, 0.001)
        // The selected mode owns the pose. Before this, cockpit and chase
        // produced identical frames because both were hard-coded here, which is
        // why changing the view appeared to do nothing.
        let pitch = mode.pitch
        var distance = mode.distance(for: speed)
        if !centered, maneuverMeters > 0, maneuverMeters < 150 { distance *= 0.85 }

        guard var current = frame else {
            let initial = RideCameraFrame(latitude: center.latitude, longitude: center.longitude,
                                          heading: targetHeading, pitch: pitch, distance: distance)
            frame = initial
            return initial
        }

        // Heading eases with a fixed time constant, so the same corner turns at
        // the same rate at 60 Hz and 120 Hz. The old per-tick gain of 0.15 made
        // the camera twice as quick on a 120 Hz display.
        let headingDelta = RouteGeometry.angleDelta(current.heading, targetHeading)
        let slewAlpha = 1 - exp(-dtCappedForHeading / Self.headingTimeConstant)
        let maxTurn = Self.maximumTurnRate * dtCappedForHeading
        let desiredHeading = current.heading
            + min(max(headingDelta * slewAlpha, -maxTurn), maxTurn)
        current.heading = desiredHeading.truncatingRemainder(dividingBy: 360)
        if current.heading < 0 { current.heading += 360 }

        // A real critically damped spring on the camera centre: velocity is
        // state, integrated semi-implicitly, so it cannot overshoot and it
        // keeps moving smoothly across a dropped frame. The old code was a
        // first-order filter wearing a spring's comment.
        let dtCapped = max(dt, 0.001)
        let omega = Self.springOmega
        latitudeVelocity += (omega * omega * (center.latitude - current.latitude)
                             - 2 * omega * latitudeVelocity) * dtCapped
        longitudeVelocity += (omega * omega * (center.longitude - current.longitude)
                              - 2 * omega * longitudeVelocity) * dtCapped
        current.latitude += latitudeVelocity * dtCapped
        current.longitude += longitudeVelocity * dtCapped

        let alpha = 1 - exp(-omega * dtCapped)
        current.pitch += (pitch - current.pitch) * alpha
        current.distance += (distance - current.distance) * alpha
        frame = current
        return current
    }

    /// Critically damped: damping ratio 1, settles in roughly 0.6 s.
    static let springOmega = 5.66
    /// Heading follows with a 120 ms time constant.
    static let headingTimeConstant = 0.12
    /// A junction may not whip the view faster than this.
    static let maximumTurnRate = 120.0

    /// How sharply the route bends over the next stretch, in degrees per
    /// metre. Straight road returns ~0; a 90° corner inside 30 m returns ~3.
    static func curvatureDegreesPerMetre(route: PlannedRoute, progress: Double) -> Double {
        guard let a = RouteGeometry.coordinate(at: progress + 15, route: route),
              let b = RouteGeometry.coordinate(at: progress + 45, route: route),
              let c = RouteGeometry.coordinate(at: progress + 75, route: route) else { return 0 }
        let first = RouteGeometry.bearing(from: a, to: b)
        let second = RouteGeometry.bearing(from: b, to: c)
        guard first.isFinite, second.isFinite else { return 0 }
        return abs(RouteGeometry.angleDelta(first, second)) / 30
    }

    mutating func reset() {
        frame = nil
        progress = 0
        latitudeVelocity = 0
        longitudeVelocity = 0
        lastTimestamp = nil
    }
}

@MainActor
@Observable
final class RideCameraDriver {
    /// Published at ~15 Hz for SwiftUI's benefit; the per-frame camera path
    /// goes through `frameObservers` so the renderer never waits on a body
    /// re-evaluation.
    private(set) var frame: RideCameraFrame?
    @ObservationIgnored private var frameObservers: [UUID: @MainActor (RideCameraFrame) -> Void] = [:]
    @ObservationIgnored private var lastPublish = 0.0
    @ObservationIgnored private var engine = RideCameraEngine()
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var route: PlannedRoute?
    @ObservationIgnored private var progress = 0.0
    @ObservationIgnored private var speed = 0.0
    @ObservationIgnored private var maneuver = 9_999.0
    @ObservationIgnored private var fallbackHeading = 0.0
    @ObservationIgnored private var centered = false
    @ObservationIgnored private var mode: RideCameraMode = .cockpit
    @ObservationIgnored private var manual = false
    @ObservationIgnored private var overviewTarget: RideCameraFrame?
    /// Smoothed, per-frame values. The UI feeds a new fix a few times a second;
    /// the camera must move every frame, so progress is dead-reckoned forward
    /// between fixes and gently corrected when the next one lands.
    @ObservationIgnored private var progressCurrent = 0.0
    @ObservationIgnored private var speedCurrent = 0.0
    @ObservationIgnored private var headingCurrent = 0.0
    @ObservationIgnored private var lastTickTime: Double = 0
    @ObservationIgnored private var hasFix = false

    @discardableResult
    func addFrameObserver(_ observer: @escaping @MainActor (RideCameraFrame) -> Void) -> UUID {
        let id = UUID()
        frameObservers[id] = observer
        return id
    }

    func removeFrameObserver(_ id: UUID) {
        frameObservers.removeValue(forKey: id)
    }

    /// Hand every frame to the direct observers, but only publish a value into
    /// SwiftUI at ~15 Hz. The map camera is driven by the observers; the body
    /// re-evaluation is only for the MapKit fallback and readouts.
    private func publish(_ next: RideCameraFrame) {
        for observer in frameObservers.values {
            observer(next)
        }
        let now = CACurrentMediaTime()
        guard now - lastPublish >= (1.0 / 15.0) else { return }
        lastPublish = now
        frame = next
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stop following and show one fixed pose. Used for north-up and Reduce
    /// Motion, where the camera must not animate but still needs to reflect
    /// the rider's position.
    func present(staticFrame next: RideCameraFrame) {
        link?.invalidate()
        link = nil
        engine.reset()
        manual = false
        overviewTarget = nil
        publish(next)
    }

    func stop() {
        link?.invalidate()
        link = nil
        engine.reset()
        hasFix = false
        lastTickTime = 0
        // Keep the last frame: clearing it made the renderer fall back to its
        // initial camera, which is how changing view modes used to throw the map
        // to another city. A stopped camera should hold its last pose.
        manual = false
        overviewTarget = nil
    }

    func update(route: PlannedRoute?, progress: Double, speed: Double,
                maneuverMeters: Double, fallbackHeading: Double,
                centered: Bool = false, mode: RideCameraMode = .cockpit) {
        self.route = route
        self.progress = progress
        self.speed = speed
        self.maneuver = maneuverMeters
        self.fallbackHeading = fallbackHeading
        self.centered = centered
        self.mode = mode
        manual = true
        overviewTarget = nil
        if route == nil {
            frame = nil
        }
        if !hasFix {
            progressCurrent = progress
            speedCurrent = speed
            headingCurrent = fallbackHeading
            hasFix = true
        }
    }

    func showOverview(route: PlannedRoute) {
        guard let first = route.points.first?.coordinate else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in route.points {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let latMeters = (maxLat - minLat) * 111_320
        let lonMeters = (maxLon - minLon) * 111_320 * cos(center.latitude * .pi / 180)
        let span = max(latMeters, lonMeters)
        let distance = min(max(span * 1.35 + 240, 900), 2_400)
        overviewTarget = RideCameraFrame(latitude: center.latitude, longitude: center.longitude,
                                         heading: 0, pitch: 0, distance: distance)
        manual = true
    }

    func clearOverview() {
        overviewTarget = nil
    }

    @objc private func tick() {
        guard manual else { return }
        let now = CACurrentMediaTime()
        let dt = lastTickTime == 0 ? (1.0 / 60.0) : min(max(now - lastTickTime, 0.001), 0.1)
        lastTickTime = now
        if let overviewTarget {
            let current = frame ?? overviewTarget
            let alpha = 0.055
            let next = RideCameraFrame(
                latitude: current.latitude + (overviewTarget.latitude - current.latitude) * alpha,
                longitude: current.longitude + (overviewTarget.longitude - current.longitude) * alpha,
                heading: current.heading + RouteGeometry.angleDelta(current.heading, 0) * alpha,
                pitch: current.pitch + (0 - current.pitch) * alpha,
                distance: current.distance + (overviewTarget.distance - current.distance) * alpha
            )
            publish(next)
            return
        }
        // Dead reckoning plus correction: advance at the current speed so the
        // camera never freezes between fixes, then pull toward the real fix.
        let predicted = progressCurrent + max(speedCurrent, 0) * dt
        let alpha = 1 - exp(-dt / 0.12)
        progressCurrent = predicted + (progress - predicted) * alpha
        if abs(progress - progressCurrent) > 60 { progressCurrent = progress }
        speedCurrent += (speed - speedCurrent) * alpha
        headingCurrent += RouteGeometry.angleDelta(headingCurrent, fallbackHeading)
            * (1 - exp(-dt / 0.18))

        let updated = MapPerformance.camera {
            engine.update(route: route, rawProgress: progressCurrent, speed: speedCurrent,
                          maneuverMeters: maneuver, fallbackHeading: headingCurrent,
                          timestamp: now, centered: centered, mode: mode)
        }
        if let updated {
            publish(updated)
        }
    }
}

// MARK: - Ribbon

nonisolated struct RibbonSegment: Identifiable, Sendable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let merit: Double
}

nonisolated struct RouteRibbon: Sendable {
    let travelled: [CLLocationCoordinate2D]
    let remaining: [CLLocationCoordinate2D]
    let remainingSegments: [RibbonSegment]

    init(route: PlannedRoute, progress: Double, tolerance: Double = 4) {
        if route.points.count < 2 {
            self.travelled = []
            self.remaining = []
            self.remainingSegments = []
            return
        }
        let split = min(max(progress, 0), route.length)
        var passed: [CLLocationCoordinate2D] = []
        var ahead: [CLLocationCoordinate2D] = []
        if let first = route.points.first?.coordinate { passed.append(first) }
        for index in 1..<route.points.count {
            let point = route.points[index].coordinate
            if route.cumulative[index] <= split {
                passed.append(point)
            } else {
                if ahead.isEmpty,
                   let cut = RouteGeometry.coordinate(at: split, route: route) {
                    passed.append(cut)
                    ahead.append(cut)
                }
                ahead.append(point)
            }
        }
        if ahead.isEmpty, let last = route.points.last?.coordinate { ahead.append(last) }
        self.travelled = Self.simplify(passed, tolerance: tolerance)
        self.remaining = Self.simplify(ahead, tolerance: tolerance)
        self.remainingSegments = Self.segments(from: self.remaining)
    }

    /// Chunks the remaining ribbon into short merit-shaded pieces. The merit is
    /// based on heading change in the chunk, so a straight connector stays
    /// cool and a switchback cluster warms up.
    static func segments(from points: [CLLocationCoordinate2D]) -> [RibbonSegment] {
        guard points.count > 1 else { return [] }
        let chunk = 10
        var result: [RibbonSegment] = []
        var index = 1
        while index < points.count {
            let end = min(index + chunk, points.count - 1)
            var coords = Array(points[(index - 1)...end])
            if index > 1, let first = points[index - 1] as CLLocationCoordinate2D?,
               let last = coords.first, first.latitude == last.latitude && first.longitude == last.longitude {
                coords[0] = first
            }
            var angle = 0.0
            if coords.count > 2 {
                let a = RouteGeometry.bearing(from: coords[0], to: coords[1])
                let b = RouteGeometry.bearing(from: coords[coords.count - 2], to: coords[coords.count - 1])
                angle = abs(RouteGeometry.angleDelta(a, b))
            }
            let merit = min(max(angle / 35, 0), 1)
            result.append(RibbonSegment(coordinates: coords, merit: merit))
            index = end + 1
        }
        return result
    }

    static func simplify(_ points: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            var maxDistance = 0.0
            var index = start
            if end > start + 1 {
                for i in (start + 1)..<end {
                    let d = perpendicularDistance(points[i], a: points[start], b: points[end])
                    if d > maxDistance { maxDistance = d; index = i }
                }
            }
            if maxDistance > tolerance {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    private static func perpendicularDistance(_ p: CLLocationCoordinate2D,
                                               a: CLLocationCoordinate2D,
                                               b: CLLocationCoordinate2D) -> Double {
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(a.latitude * .pi / 180)
        let px = (p.longitude - a.longitude) * lonScale
        let py = (p.latitude - a.latitude) * latScale
        let bx = (b.longitude - a.longitude) * lonScale
        let by = (b.latitude - a.latitude) * latScale
        let denom = sqrt(bx * bx + by * by)
        guard denom > 0.001 else { return sqrt(px * px + py * py) }
        return abs(px * by - py * bx) / denom
    }
}

// MARK: - Config and puck

enum MapConfig {
    static let accent = Color(red: 0.396, green: 0.953, blue: 0.875)
    static let casing = Color(red: 0.016, green: 0.035, blue: 0.051)

    static func paceColor(_ merit: Double) -> Color {
        let m = min(max(merit, 0), 1)
        return Color(red: 0.396 + 0.20 * m,
                     green: 0.953 - 0.02 * m,
                     blue: 0.875 - 0.15 * m)
    }

    static func paceSIMD4(_ merit: Double) -> SIMD4<Float> {
        let m = min(max(merit, 0), 1)
        return SIMD4<Float>(Float(0.396 + 0.20 * m),
                            Float(0.953 - 0.02 * m),
                            Float(0.875 - 0.15 * m), 1)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
