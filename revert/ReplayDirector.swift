import Foundation
import CoreLocation

// MARK: - Director model

nonisolated enum DirectorShotKind: String, CaseIterable, Identifiable {
    case establishing
    case chase
    case orbit
    case trackside
    case flyby
    case hero
    case outro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .establishing: "Establishing"
        case .chase: "Chase"
        case .orbit: "Orbit"
        case .trackside: "Trackside"
        case .flyby: "Fly-by"
        case .hero: "Hero low"
        case .outro: "Outro"
        }
    }

    var icon: String {
        switch self {
        case .establishing: "map.fill"
        case .chase: "video.fill"
        case .orbit: "arrow.triangle.2.circlepath.camera"
        case .trackside: "camera.fill"
        case .flyby: "airplane"
        case .hero: "speedometer"
        case .outro: "flag.checkered"
        }
    }

    var isOverview: Bool { self == .establishing || self == .outro }
}

nonisolated struct DirectorSample {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let lean: Double
    let speed: Double
    let altitude: Double
    let index: Int
    let elapsed: TimeInterval

    static func at(points: [RidePoint], elapsed: TimeInterval) -> DirectorSample? {
        guard let first = points.first else { return nil }
        let target = first.time.addingTimeInterval(max(elapsed, 0))
        if target <= first.time {
            return make(points: points, index: 0, next: min(1, points.count - 1), t: 0,
                        elapsed: max(elapsed, 0))
        }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            if target <= b.time {
                let span = max(b.time.timeIntervalSince(a.time), 0.001)
                let t = min(max(target.timeIntervalSince(a.time) / span, 0), 1)
                return make(points: points, index: index - 1, next: index, t: t, elapsed: elapsed)
            }
        }
        let last = max(points.count - 1, 0)
        return make(points: points, index: last, next: last, t: 0, elapsed: elapsed)
    }

    private static func make(points: [RidePoint], index: Int, next: Int, t: Double,
                             elapsed: TimeInterval) -> DirectorSample {
        let a = points[index], b = points[next]
        let coordinate = CLLocationCoordinate2D(
            latitude: a.lat + (b.lat - a.lat) * t,
            longitude: a.lon + (b.lon - a.lon) * t
        )
        return DirectorSample(
            coordinate: coordinate,
            heading: bearing(from: a.coordinate, to: b.coordinate),
            lean: (a.lean ?? 0) + ((b.lean ?? 0) - (a.lean ?? 0)) * t,
            speed: a.speed + (b.speed - a.speed) * t,
            altitude: a.alt + (b.alt - a.alt) * t,
            index: t >= 0.5 ? next : index,
            elapsed: elapsed
        )
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func destination(from coordinate: CLLocationCoordinate2D,
                            meters: Double, heading: Double) -> CLLocationCoordinate2D {
        let radians = heading * .pi / 180
        let latRadians = coordinate.latitude * .pi / 180
        let dLat = meters / 111_320 * cos(radians)
        let dLon = meters / (111_320 * max(cos(latRadians), 0.01)) * sin(radians)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat,
                                      longitude: coordinate.longitude + dLon)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

nonisolated struct DirectorMoment: Identifiable {
    let id: Int
    let apexIndex: Int
    let elapsed: TimeInterval
    let coordinate: CLLocationCoordinate2D
    let lean: Double
    let speed: Double
    let entrySpeed: Double
    let exitSpeed: Double
    let score: Double
    let label: String
}

nonisolated struct FilmShot: Identifiable {
    let id: Int
    let kind: DirectorShotKind
    let moment: DirectorMoment?
    let rideStart: TimeInterval
    let rideEnd: TimeInterval
    let apexElapsed: TimeInterval?
    let duration: TimeInterval
    let title: String

    var apexFraction: Double {
        guard let apexElapsed, rideEnd > rideStart else { return 0.5 }
        return min(max((apexElapsed - rideStart) / (rideEnd - rideStart), 0), 1)
    }

    /// Screen progress -> ride time. The corner shot holds the apex for a
    /// moment, so the film gets a real speed ramp instead of constant speed.
    func rideElapsed(at p: Double) -> TimeInterval {
        let progress = min(max(p, 0), 1)
        guard let apexElapsed, rideEnd - rideStart > 1.2 else {
            return rideStart + (rideEnd - rideStart) * progress
        }
        let apex = min(max(apexElapsed, rideStart + 0.35), rideEnd - 0.35)
        let slowStart = max(rideStart, apex - 0.45)
        let slowEnd = min(rideEnd, apex + 0.45)
        if progress < 0.38 {
            let t = progress / 0.38
            return rideStart + (slowStart - rideStart) * ease(t)
        }
        if progress < 0.66 {
            let t = (progress - 0.38) / 0.28
            return slowStart + (slowEnd - slowStart) * t
        }
        let t = (progress - 0.66) / 0.34
        return slowEnd + (rideEnd - slowEnd) * ease(t)
    }

    private func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

nonisolated struct ReplayFilm {
    let shots: [FilmShot]
    let moments: [DirectorMoment]
    let highlights: [DirectorMoment]
    let duration: TimeInterval
    let routeName: String
    let distanceMeters: Double
    let rideDuration: TimeInterval

    @MainActor
    static func make(ride: Ride) -> ReplayFilm {
        let points = ride.points
        guard let first = points.first, let last = points.last else {
            return ReplayFilm(shots: [], moments: [], highlights: [], duration: 1,
                              routeName: ride.routeName ?? "Ride",
                              distanceMeters: ride.distanceMeters,
                              rideDuration: ride.durationSeconds)
        }
        let start = first.time
        let rideEnd = max(last.time.timeIntervalSince(start), 1)
        let turns = RideAnalysis.turns(from: points)
        var moments: [DirectorMoment] = []
        for turn in turns {
            let apex = min(max(turn.apexIndex, 0), points.count - 1)
            let before = points[min(max(apex - 10, 0), points.count - 1)]
            let after = points[min(max(apex + 10, 0), points.count - 1)]
            let lean = abs(turn.peakLean)
            let speed = turn.speed
            let braking = max(0, before.speed - turn.speed)
            let score = lean * 1.4 + speed * 0.6 + braking * 0.8
            moments.append(DirectorMoment(
                id: moments.count,
                apexIndex: apex,
                elapsed: points[apex].time.timeIntervalSince(start),
                coordinate: points[apex].coordinate,
                lean: turn.peakLean,
                speed: turn.speed,
                entrySpeed: before.speed,
                exitSpeed: after.speed,
                score: score,
                label: "\(turn.label) · \(Int(lean.rounded()))°"
            ))
        }
        if moments.isEmpty {
            let apex = points.indices.max { points[$0].speed < points[$1].speed } ?? points.count / 2
            let point = points[apex]
            moments.append(DirectorMoment(
                id: 0,
                apexIndex: apex,
                elapsed: point.time.timeIntervalSince(start),
                coordinate: point.coordinate,
                lean: point.lean ?? 0,
                speed: point.speed,
                entrySpeed: point.speed,
                exitSpeed: point.speed,
                score: point.speed,
                label: "Fastest stretch"
            ))
        }
        let ranked = moments.sorted { $0.score > $1.score }
        var selected: [DirectorMoment] = []
        for moment in ranked {
            guard selected.count < 5 else { break }
            guard selected.allSatisfy({ abs($0.elapsed - moment.elapsed) > 7 }) else { continue }
            selected.append(moment)
        }
        selected.sort { $0.elapsed < $1.elapsed }

        var shots: [FilmShot] = []
        var shotID = 0

        func append(_ kind: DirectorShotKind, _ start: TimeInterval, _ end: TimeInterval,
                    apex: TimeInterval?, moment: DirectorMoment?, title: String,
                    duration: TimeInterval) {
            let clampedStart = min(max(start, 0), rideEnd)
            let clampedEnd = min(max(end, clampedStart + 1), max(rideEnd, clampedStart + 1))
            shots.append(FilmShot(id: shotID, kind: kind, moment: moment,
                                  rideStart: clampedStart, rideEnd: clampedEnd,
                                  apexElapsed: apex, duration: duration, title: title))
            shotID += 1
        }

        let introEnd = min(max(rideEnd * 0.10, 4), rideEnd)
        append(.establishing, 0, min(introEnd, 10), apex: nil, moment: nil,
               title: "The route", duration: 3.2)

        let kinds: [DirectorShotKind] = [.chase, .orbit, .trackside, .flyby, .hero]
        for (index, moment) in selected.enumerated() {
            let start = max(0, moment.elapsed - 3.2)
            let end = min(rideEnd, moment.elapsed + 4.0)
            let kind = kinds[index % kinds.count]
            append(kind, start, end, apex: moment.elapsed, moment: moment,
                   title: "\(kind.title) · \(moment.label)",
                   duration: 5.0)
        }

        let outroStart = max(0, rideEnd - 8)
        append(.outro, outroStart, rideEnd, apex: nil, moment: nil,
               title: "The finish", duration: 3.6)

        let total = shots.reduce(0) { $0 + $1.duration }
        return ReplayFilm(shots: shots, moments: moments, highlights: selected,
                          duration: max(total, 1),
                          routeName: ride.routeName ?? "Ride",
                          distanceMeters: ride.distanceMeters,
                          rideDuration: ride.durationSeconds)
    }

    func shot(at filmTime: TimeInterval) -> (shot: FilmShot, progress: Double, elapsed: TimeInterval)? {
        guard !shots.isEmpty else { return nil }
        let clamped = min(max(filmTime, 0), duration)
        var cursor = 0.0
        for shot in shots {
            if clamped <= cursor + shot.duration || shot.id == shots.last?.id {
                let progress = min(max((clamped - cursor) / max(shot.duration, 0.01), 0), 1)
                return (shot, progress, shot.rideElapsed(at: progress))
            }
            cursor += shot.duration
        }
        guard let last = shots.last else { return nil }
        return (last, 1, last.rideEnd)
    }

    func startTime(of shot: FilmShot) -> TimeInterval {
        var cursor = 0.0
        for item in shots {
            if item.id == shot.id { return cursor }
            cursor += item.duration
        }
        return 0
    }
}

// MARK: - Camera

nonisolated struct DirectorCameraPlan {
    let center: CLLocationCoordinate2D
    let heading: Double
    let distance: Double
    let pitch: Double
    let showRider: Bool
}

nonisolated enum DirectorCamera {
    static func plan(shot: FilmShot, sample: DirectorSample, progress: Double,
                     route: PlannedRoute?, ahead: CLLocationCoordinate2D? = nil) -> DirectorCameraPlan {
        switch shot.kind {
        case .establishing, .outro:
            let center = route.flatMap { route -> CLLocationCoordinate2D? in
                guard !route.points.isEmpty else { return nil }
                return route.points[route.points.count / 2].coordinate
            } ?? sample.coordinate
            return DirectorCameraPlan(center: center, heading: sample.heading,
                                      distance: shot.kind == .outro ? 1_900 : 2_400,
                                      pitch: 36, showRider: false)
        case .chase:
            return DirectorCameraPlan(
                center: ahead ?? DirectorSample.destination(from: sample.coordinate, meters: 42,
                                                            heading: sample.heading),
                heading: sample.heading,
                distance: 540 + min(sample.speed * 2.6, 140),
                pitch: 55,
                showRider: true
            )
        case .hero:
            return DirectorCameraPlan(
                center: ahead ?? DirectorSample.destination(from: sample.coordinate, meters: 16,
                                                            heading: sample.heading),
                heading: sample.heading,
                distance: 320 + min(sample.speed * 1.5, 90),
                pitch: 46,
                showRider: true
            )
        case .orbit:
            let sway = sin((progress - 0.5) * .pi) * 62
            return DirectorCameraPlan(
                center: ahead ?? DirectorSample.destination(from: sample.coordinate, meters: 8,
                                                            heading: sample.heading),
                heading: (sample.heading + sway + 360).truncatingRemainder(dividingBy: 360),
                distance: 430,
                pitch: 55,
                showRider: true
            )
        case .trackside:
            return DirectorCameraPlan(
                center: ahead ?? sample.coordinate,
                heading: (sample.heading + 70).truncatingRemainder(dividingBy: 360),
                distance: 300 + min(sample.speed * 1.2, 80),
                pitch: 42,
                showRider: true
            )
        case .flyby:
            let flyby = ahead ?? DirectorSample.destination(from: sample.coordinate, meters: 110,
                                                            heading: sample.heading)
            return DirectorCameraPlan(
                center: flyby,
                heading: (sample.heading + 180).truncatingRemainder(dividingBy: 360),
                distance: 260 + min(sample.speed * 1.2, 80),
                pitch: 44,
                showRider: true
            )
        }
    }

    static func overview(center: CLLocationCoordinate2D, distance: Double,
                         heading: Double) -> DirectorCameraPlan {
        DirectorCameraPlan(center: center, heading: heading,
                           distance: max(distance, 900), pitch: 35, showRider: false)
    }
}

// MARK: - Rider direction atlas

nonisolated enum RiderViewDirection: Int, CaseIterable, Identifiable {
    case rear
    case rearRight
    case right
    case frontRight
    case front
    case frontLeft
    case left
    case rearLeft

    var id: Int { rawValue }

    static func from(relativeBearing: Double) -> RiderViewDirection {
        let normalized = ((relativeBearing + 180).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) - 180
        let index = Int(((normalized + 22.5) / 45).rounded(.down))
        return RiderViewDirection(rawValue: (index % 8 + 8) % 8) ?? .rear
    }
}

nonisolated enum RiderSpriteAtlas {
    /// The eight direction slots are wired now; the supplied sheet currently
    /// has three distinct views, so the missing angles fall back to the nearest
    /// supplied frame. New art can replace an alias without touching the camera.
    static func assetName(for direction: RiderViewDirection) -> String {
        switch direction {
        case .rear, .front:
            return "chase-rider-straight"
        case .rearRight, .right, .frontRight:
            return "chase-rider-right"
        case .rearLeft, .left, .frontLeft:
            return "chase-rider-left"
        }
    }

    static func assetName(forRiderHeading heading: Double, cameraHeading: Double,
                          lean: Double) -> String {
        if abs(lean) > 10 {
            return lean > 0 ? "chase-rider-right" : "chase-rider-left"
        }
        let direction = RiderViewDirection.from(relativeBearing: cameraHeading - heading)
        return assetName(for: direction)
    }
}
