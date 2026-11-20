import Foundation
import CoreLocation
import SwiftData
import Observation
import MapKit

// MARK: - Trips (A3)

@Model
final class Trip {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TripDay.trip)
    var days: [TripDay]? = []

    init(title: String, notes: String = "") {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.createdAt = Date()
    }

    var sortedDays: [TripDay] {
        (days ?? []).sorted { $0.order < $1.order }
    }
}

@Model
final class TripDay {
    var id: UUID = UUID()
    var order: Int = 0
    var title: String = ""
    var startLabel: String = ""
    var endLabel: String = ""
    var distanceKm: Double = 0
    var notes: String = ""
    var savedRouteID: UUID?
    var trip: Trip?

    init(order: Int, title: String, startLabel: String = "", endLabel: String = "",
         distanceKm: Double = 0, notes: String = "", savedRouteID: UUID? = nil) {
        self.id = UUID()
        self.order = order
        self.title = title
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.distanceKm = distanceKm
        self.notes = notes
        self.savedRouteID = savedRouteID
    }
}

// MARK: - Service / setup notes (C3)

@Model
final class SetupNote {
    var id: UUID = UUID()
    var bikeID: UUID?
    var createdAt: Date = Date()
    var title: String = ""
    var frontPressure: Double = 0
    var rearPressure: Double = 0
    var notes: String = ""

    init(bikeID: UUID?, title: String, frontPressure: Double = 0,
         rearPressure: Double = 0, notes: String = "") {
        self.id = UUID()
        self.bikeID = bikeID
        self.createdAt = Date()
        self.title = title
        self.frontPressure = frontPressure
        self.rearPressure = rearPressure
        self.notes = notes
    }
}

// MARK: - Conditions (A1) — sun/light first slice

nonisolated struct RideConditions {
    let date: Date
    let sunrise: Date?
    let sunset: Date?
    let rideDuration: TimeInterval
    let warnings: [String]

    var daylightRemaining: TimeInterval? {
        guard let sunset else { return nil }
        return sunset.timeIntervalSince(date)
    }

    var headline: String {
        guard let sunset else { return "Sun times unavailable for this latitude" }
        let time = sunset.formatted(date: .omitted, time: .shortened)
        if let remaining = daylightRemaining, remaining > 0 {
            return "Sunset \(time) · \(Units.clock(remaining)) of light"
        }
        return "Sunset was \(time)"
    }

    var weatherNote: String {
        "WeatherKit needs an Apple Developer entitlement; this build uses on-device sun/light only."
    }
}

nonisolated enum ConditionsService {
    static func snapshot(route: PlannedRoute?, bike: Bike?, at date: Date = Date()) -> RideConditions {
        let coordinate = route?.points.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let sun = sunTimes(on: date, coordinate: coordinate)
        let duration = route?.expectedTravelTime
            ?? max((route?.length ?? 0) / max(18, 1), 0)
        var warnings: [String] = []
        if let sunset = sun.sunset {
            if date >= sunset {
                warnings.append("It is after sunset — expect low light and cold tyres.")
            } else if sunset.timeIntervalSince(date) < duration {
                warnings.append("You would finish after sunset (\(sunset.formatted(date: .omitted, time: .shortened))).")
            }
        }
        if let elevation = route?.maxElevation, elevation > 500 {
            warnings.append("Ridge tops reach \(Units.elevationText(elevation)) — expect a temperature drop.")
        }
        if warnings.isEmpty {
            warnings.append("Daylight covers the planned ride. Weather is not fetched in this build.")
        }
        return RideConditions(date: date, sunrise: sun.sunrise, sunset: sun.sunset,
                              rideDuration: duration, warnings: warnings)
    }

    /// NOAA's compact solar position formulas. Good to a couple of minutes,
    /// which is enough for a daylight warning.
    static func sunTimes(on date: Date, coordinate: CLLocationCoordinate2D) -> (sunrise: Date?, sunset: Date?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let day = calendar.ordinality(of: .day, in: .year, for: date) else { return (nil, nil) }
        let latitude = coordinate.latitude * .pi / 180
        let gamma = 2 * Double.pi / 365 * Double(day - 1)
        let equationOfTime = 229.18 * (0.000075
            + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918
            - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let zenith = 90.833 * .pi / 180
        let cosHourAngle = (cos(zenith) / (cos(latitude) * cos(declination)))
            - tan(latitude) * tan(declination)
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return (nil, nil) }
        let hourAngle = acos(cosHourAngle) * 180 / .pi
        let timeZoneMinutes = Double(TimeZone.current.secondsFromGMT(for: date)) / 60
        let solarNoon = 720 - 4 * coordinate.longitude - equationOfTime + timeZoneMinutes
        let start = calendar.startOfDay(for: date)
        let sunrise = start.addingTimeInterval((solarNoon - 4 * hourAngle) * 60)
        let sunset = start.addingTimeInterval((solarNoon + 4 * hourAngle) * 60)
        return (sunrise, sunset)
    }
}

// MARK: - Range (A2)

nonisolated struct RangeSummary {
    enum Verdict: String {
        case fits = "Fits"
        case tight = "Tight"
        case exceeds = "Exceeds"
        case unknown = "Unknown"
    }

    let rangeKm: Double
    let usableKm: Double
    let comfortableKm: Double
    let tankFraction: Double
    let routeKm: Double
    let verdict: Verdict
    let note: String
}

nonisolated enum RangePolicy {
    static func summary(for bike: Bike?, routeLengthMeters: Double,
                        tankFraction: Double? = nil) -> RangeSummary {
        let range = max(bike?.fuelRangeKm ?? 260, 1)
        let storedFraction = UserDefaults.standard.object(forKey: "fuel.tankFraction") as? Double ?? 0.8
        let fraction = min(max(tankFraction ?? storedFraction, 0.1), 1)
        let usable = max(range * fraction, 1)
        let comfortable = usable * 0.9
        let routeKm = routeLengthMeters / 1_000
        let verdict: RangeSummary.Verdict
        let note: String
        if routeKm <= 0 {
            verdict = .unknown
            note = "Choose a route to compare with the \(Int(fraction * 100))% tank."
        } else if routeKm <= comfortable {
            verdict = .fits
            note = "Fits inside 90% of the usable \(Int(fraction * 100))% tank."
        } else if routeKm <= usable {
            verdict = .tight
            note = "Within range, but little reserve. Plan fuel."
        } else {
            verdict = .exceeds
            note = "Longer than the estimated range. Fuel stop needed."
        }
        return RangeSummary(rangeKm: range, usableKm: usable, comfortableKm: comfortable,
                            tankFraction: fraction, routeKm: routeKm,
                            verdict: verdict, note: note)
    }
}

// MARK: - Route links (A6)

nonisolated enum RouteLink {
    static let host = "route"
    static let version = 1
    static let maxEncodedLength = 14_000

    nonisolated struct LinkPoint: Codable, Sendable {
        let lat: Double
        let lon: Double
        let road: Int64
    }

    nonisolated struct Payload: Codable, Sendable {
        let version: Int
        let name: String
        let kind: String
        let laps: Int
        let surface: String
        let expectedTravelTime: Double?
        let points: [LinkPoint]
        let steps: [NavStep]
        let waypoints: [LinkPoint]
        let createdAt: Date
    }

    static func url(for saved: SavedRoute) -> URL? {
        let points = saved.points.map { LinkPoint(lat: $0.lat, lon: $0.lon, road: $0.road) }
        let steps = (try? JSONDecoder().decode([NavStep].self, from: saved.stepsData)) ?? []
        let kind = saved.isLoop ? "loop" : (saved.isSprint ? "sprint" : "directions")
        let payload = Payload(version: version, name: saved.name, kind: kind,
                              laps: saved.laps, surface: saved.surfaceRaw,
                              expectedTravelTime: saved.expectedTravelTime > 0 ? saved.expectedTravelTime : nil,
                              points: points, steps: steps,
                              waypoints: saved.waypoints.map { LinkPoint(lat: $0.latitude, lon: $0.longitude, road: 0) },
                              createdAt: saved.createdAt)
        return url(payload)
    }

    static func url(for route: PlannedRoute) -> URL? {
        let payload = Payload(version: version,
                              name: route.displayName ?? "A shared route",
                              kind: route.kind.isLoop ? "loop" : (route.kind.isSprint ? "sprint" : "directions"),
                              laps: route.laps,
                              surface: route.surface.rawValue,
                              expectedTravelTime: route.expectedTravelTime,
                              points: route.points.map { LinkPoint(lat: $0.lat, lon: $0.lon, road: $0.road) },
                              steps: route.steps,
                              waypoints: route.waypoints.map { LinkPoint(lat: $0.latitude, lon: $0.longitude, road: 0) },
                              createdAt: Date())
        return url(payload)
    }

    private static func url(_ payload: Payload) -> URL? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard encoded.count <= maxEncodedLength else { return nil }
        var components = URLComponents()
        components.scheme = "revert"
        components.host = host
        components.queryItems = [URLQueryItem(name: "d", value: encoded)]
        return components.url
    }

    static func payload(from url: URL) -> Payload? {
        guard url.scheme == "revert", url.host == host,
              let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value else { return nil }
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version, payload.points.count > 1 else { return nil }
        return payload
    }

    static func route(from payload: Payload) -> PlannedRoute? {
        let points = payload.points.map { RoutePoint(lat: $0.lat, lon: $0.lon, road: $0.road) }
        guard points.count > 1 else { return nil }
        let kind: RouteKind = payload.kind == "loop" ? .loop : (payload.kind == "sprint" ? .sprint : .directions)
        var route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0,
                                 displayName: payload.name,
                                 expectedTravelTime: payload.expectedTravelTime,
                                 kind: kind)
        route.steps = payload.steps
        route.waypoints = payload.waypoints.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        route.laps = max(payload.laps, 1)
        route.surface = LoopSurface(rawValue: payload.surface) ?? .paved
        return route
    }
}

// MARK: - User marks (B1)

nonisolated struct UserHazard: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: String
    let lat: Double
    let lon: Double
    let createdAt: Date
    let road: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Rider marks enter the same corridor alert engine as OSM hazards.
    var asHazard: Hazard {
        Hazard(id: -max(Int64(createdAt.timeIntervalSince1970 * 1_000), 1),
               kind: .userMark, lat: lat, lon: lon)
    }
}

@MainActor
@Observable
final class UserMarksStore {
    static let shared = UserMarksStore()
    private let key = "user.marks.hazards"
    private(set) var hazards: [UserHazard] = []
    private(set) var avoidedRoads: [String] = []

    var routeHazards: [Hazard] { hazards.map(\.asHazard) }

    init() {
        reload()
        reloadAvoided()
    }

    /// Rider marks are advisory, not permanent: after 90 days a pothole has
    /// usually been filled or the road resurfaced, so it stops warning.
    static let markLifetime: TimeInterval = 90 * 86_400
    /// Two reports of the same kind within this distance are one hazard.
    private static let duplicateRadius = 25.0

    func addHazard(kind: String, coordinate: CLLocationCoordinate2D, road: String?) {
        let mark = UserHazard(id: UUID(), kind: kind, lat: coordinate.latitude,
                              lon: coordinate.longitude, createdAt: Date(), road: road)
        // Pressing the button twice, or two riders reporting the same pothole,
        // used to produce two alerts for one hazard.
        hazards.removeAll { existing in
            existing.kind == kind && Self.meters(existing.coordinate, coordinate) <= Self.duplicateRadius
        }
        hazards.insert(mark, at: 0)
        if hazards.count > 100 { hazards.removeLast(hazards.count - 100) }
        save()
    }

    static func isExpired(_ mark: UserHazard, now: Date = Date()) -> Bool {
        now.timeIntervalSince(mark.createdAt) > markLifetime
    }

    private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    func delete(_ hazard: UserHazard) {
        hazards.removeAll { $0.id == hazard.id }
        save()
    }

    func clear() {
        hazards = []
        save()
    }

    func avoid(_ road: String) {
        RouteTaste.shared.avoid(road)
        reloadAvoided()
    }

    func stopAvoiding(_ road: String) {
        RouteTaste.shared.stopAvoiding(road)
        reloadAvoided()
    }

    private func reloadAvoided() {
        avoidedRoads = RouteTaste.shared.snapshot().avoided.sorted()
    }

    private func reload() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([UserHazard].self, from: data) else {
            hazards = []
            return
        }
        hazards = decoded.filter { !Self.isExpired($0) }
        if hazards.count != decoded.count { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hazards) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Ghost (B2)

nonisolated struct GhostTrack {
    let ride: Ride
    let start: Date
    let points: [RidePoint]

    init?(ride: Ride) {
        let points = ride.points
        guard points.count > 1, let start = points.first?.time else { return nil }
        self.ride = ride
        self.start = start
        self.points = points
    }

    var duration: TimeInterval { ride.durationSeconds }

    func coordinate(at elapsed: TimeInterval) -> CLLocationCoordinate2D? {
        guard !points.isEmpty else { return nil }
        let target = start.addingTimeInterval(max(elapsed, 0))
        if target <= points[0].time { return points[0].coordinate }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            if target <= b.time {
                let span = max(b.time.timeIntervalSince(a.time), 0.001)
                let t = min(max(target.timeIntervalSince(a.time) / span, 0), 1)
                return CLLocationCoordinate2D(
                    latitude: a.lat + (b.lat - a.lat) * t,
                    longitude: a.lon + (b.lon - a.lon) * t
                )
            }
        }
        return points.last?.coordinate
    }

    func distance(at elapsed: TimeInterval) -> Double {
        guard !points.isEmpty else { return 0 }
        let target = start.addingTimeInterval(max(elapsed, 0))
        var covered = 0.0
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            if target <= b.time {
                let span = max(b.time.timeIntervalSince(a.time), 0.001)
                let t = min(max(target.timeIntervalSince(a.time) / span, 0), 1)
                let segment = CLLocation(latitude: a.lat, longitude: a.lon)
                    .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
                return covered + segment * t
            }
            covered += CLLocation(latitude: a.lat, longitude: a.lon)
                .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
        }
        return covered
    }
}

// MARK: - Ride again (B4)

nonisolated enum RideAgainRoute {
    static func make(ride: Ride, saved: SavedRoute?) -> PlannedRoute? {
        if let saved, let route = saved.plannedRoute() { return route }
        let points = ride.points.map { RidePoint in
            RoutePoint(lat: RidePoint.lat, lon: RidePoint.lon, road: 0)
        }
        guard points.count > 2 else { return nil }
        var route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0,
                                 displayName: ride.routeName ?? "Ride again",
                                 expectedTravelTime: ride.durationSeconds,
                                 kind: ride.isCar ? .directions : .loop)
        route.laps = max(ride.laps, 1)
        route.steps = steps(for: ride, route: route)
        return route
    }

    private static func steps(for ride: Ride, route: PlannedRoute) -> [NavStep] {
        var steps = [NavStep(id: 0, turn: .start, road: nil, at: 0, distance: 0)]
        let turns = RideAnalysis.turns(from: ride.points)
        for turn in turns {
            guard turn.apexIndex < route.points.count else { continue }
            steps.append(NavStep(id: steps.count,
                                 turn: turn.direction > 0 ? .right : .left,
                                 road: nil,
                                 at: turn.apexIndex,
                                 distance: route.cumulative[turn.apexIndex],
                                 text: "Turn \(turn.label.lowercased())")
            )
        }
        steps.append(NavStep(id: steps.count, turn: .arrive, road: nil,
                             at: route.points.count - 1, distance: route.length))
        return steps
    }
}

// MARK: - Corner report (C1)

nonisolated struct CornerInsight: Identifiable {
    let id: Int
    let label: String
    let apex: CLLocationCoordinate2D
    let entrySpeed: Double
    let apexSpeed: Double
    let exitSpeed: Double
    let lean: Double
    let time: TimeInterval
}

nonisolated struct CornerReport {
    let corners: [CornerInsight]
    let score: Int
    let summary: String

    init(ride: Ride) {
        let points = ride.points
        let turns = RideAnalysis.turns(from: points)
        var corners: [CornerInsight] = []
        for turn in turns {
            let before = points[max(0, turn.apexIndex - 10)]
            let apex = points[turn.apexIndex]
            let after = points[min(points.count - 1, turn.apexIndex + 10)]
            let entry = before.speed
            let apexSpeed = apex.speed
            let exit = after.speed
            let time = apex.time.timeIntervalSince(ride.startDate)
            corners.append(CornerInsight(id: turn.id, label: turn.label, apex: turn.coordinate,
                                         entrySpeed: entry, apexSpeed: apexSpeed, exitSpeed: exit,
                                         lean: turn.peakLean, time: time))
        }
        self.corners = corners
        let braking = corners.filter { $0.exitSpeed + 1 < $0.entrySpeed }.count
        let score = corners.isEmpty ? 0 : max(0, min(100, 100 - braking * 7))
        self.score = score
        self.summary = corners.isEmpty
            ? "No corners detected in this track."
            : "\(corners.count) corners · \(braking) with exit speed below entry · smoothness \(score)/100."
    }
}

// MARK: - Segments (C4)

nonisolated struct SegmentCandidate: Identifiable, Sendable {
    let id: Int
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let lengthMeters: Double
    let cornerCount: Int
    let bestSpeed: Double
}

@Model
final class SegmentRecord {
    var id: UUID = UUID()
    var rideID: UUID = UUID()
    var rideIDString: String = ""
    var name: String = ""
    var lengthMeters: Double = 0
    var cornerCount: Int = 0
    var bestSpeed: Double = 0
    var coordinatesData: Data = Data()
    var createdAt: Date = Date()

    init(rideID: UUID = UUID(), rideIDString: String, candidate: SegmentCandidate, createdAt: Date = Date()) {
        self.id = UUID()
        self.rideID = rideID
        self.rideIDString = rideIDString
        self.name = candidate.name
        self.lengthMeters = candidate.lengthMeters
        self.cornerCount = candidate.cornerCount
        self.bestSpeed = candidate.bestSpeed
        self.coordinatesData = (try? JSONEncoder().encode(candidate.coordinates.map { [$0.latitude, $0.longitude] })) ?? Data()
        self.createdAt = createdAt
    }

    var coordinates: [CLLocationCoordinate2D] {
        guard let pairs = try? JSONDecoder().decode([[Double]].self, from: coordinatesData) else { return [] }
        return pairs.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }
}

nonisolated enum SegmentDetector {
    static func detect(points: [RidePoint], limit: Int = 8) -> [SegmentCandidate] {
        let turns = RideAnalysis.turns(from: points)
        guard !turns.isEmpty else { return [] }
        var groups: [[RideTurn]] = []
        var current: [RideTurn] = []
        for turn in turns {
            if let last = current.last,
               points[turn.apexIndex].time.timeIntervalSince(points[last.apexIndex].time) > 240 {
                if current.count >= 2 { groups.append(current) }
                current = []
            }
            current.append(turn)
        }
        if current.count >= 2 { groups.append(current) }
        return groups.prefix(limit).enumerated().compactMap { index, group in
            guard let first = group.first, let last = group.last,
                  first.apexIndex < points.count, last.apexIndex < points.count else { return nil }
            let coords = points[first.apexIndex...last.apexIndex].map(\.coordinate)
            let length = CLLocation(latitude: coords.first!.latitude, longitude: coords.first!.longitude)
                .distance(from: CLLocation(latitude: coords.last!.latitude, longitude: coords.last!.longitude))
            let maxSpeed = group.map(\.speed).max() ?? 0
            return SegmentCandidate(id: index, name: "Segment \(index + 1)",
                                    coordinates: coords, lengthMeters: max(length, 0),
                                    cornerCount: group.count, bestSpeed: maxSpeed)
        }
    }
}

// MARK: - Monthly recap (C2)

nonisolated struct MonthlyRecap {
    let month: Date
    let rides: [Ride]
    let distanceMeters: Double
    let durationSeconds: Double
    let climbMeters: Double
    let longestRide: Ride?
    let topSpeedMps: Double

    init(month: Date, rides: [Ride]) {
        let calendar = Calendar.current
        let selected = rides.filter {
            calendar.isDate($0.startDate, equalTo: month, toGranularity: .month)
                && calendar.isDate($0.startDate, equalTo: month, toGranularity: .year)
        }
        self.month = month
        self.rides = selected.sorted { $0.startDate < $1.startDate }
        self.distanceMeters = selected.reduce(0) { $0 + $1.distanceMeters }
        self.durationSeconds = selected.reduce(0) { $0 + $1.durationSeconds }
        self.climbMeters = selected.reduce(0) { $0 + $1.elevationGainMeters }
        self.longestRide = selected.max { $0.distanceMeters < $1.distanceMeters }
        self.topSpeedMps = selected.map(\.maxSpeedMps).max() ?? 0
    }

    var title: String {
        month.formatted(.dateTime.month(.wide).year())
    }
}


// MARK: - Import re-plan (A5)

@MainActor
enum RouteReplanner {
    /// Snaps an imported track to roads by routing through it in ~15 km legs.
    /// The original track is never uploaded; MapKit receives only the sampled
    /// waypoints, exactly like a normal A→B search.
    static func replan(track: [CLLocationCoordinate2D], name: String,
                       onProgress: @MainActor (Int, Int) -> Void = { _, _ in }) async -> PlannedRoute? {
        guard track.count > 1 else { return nil }
        var waypoints: [CLLocationCoordinate2D] = [track[0]]
        var anchor = track[0]
        var sinceAnchor = 0.0
        for coordinate in track.dropFirst() {
            let leg = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            sinceAnchor += leg
            anchor = coordinate
            if sinceAnchor >= 15_000 {
                waypoints.append(coordinate)
                sinceAnchor = 0
            }
        }
        if let last = track.last,
           CLLocation(latitude: last.latitude, longitude: last.longitude)
            .distance(from: CLLocation(latitude: waypoints.last!.latitude,
                                       longitude: waypoints.last!.longitude)) > 50 {
            waypoints.append(last)
        }
        guard waypoints.count >= 2 else { return nil }

        var routes: [MKRoute] = []
        for index in 1..<waypoints.count {
            guard !Task.isCancelled else { return nil }
            onProgress(index - 1, max(waypoints.count - 1, 1))
            let request = MKDirections.Request()
            request.source = MKMapItem.revert(location: CLLocation(latitude: waypoints[index - 1].latitude,
                                                                   longitude: waypoints[index - 1].longitude))
            request.destination = MKMapItem.revert(location: CLLocation(latitude: waypoints[index].latitude,
                                                                        longitude: waypoints[index].longitude))
            request.transportType = .automobile
            VehiclePreferences.apply(to: request)
            request.requestsAlternateRoutes = false
            guard let response = try? await MKDirections(request: request).calculate(),
                  !Task.isCancelled,
                  let first = response.routes.first else {
                return nil
            }
            routes.append(first)
            onProgress(index, max(waypoints.count - 1, 1))
        }
        var route = PlannedRoute(mapRoutes: routes, waypoints: waypoints,
                                 kind: .directions, surface: .paved)
        route.displayName = name
        return route
    }
}

// MARK: - Day GPX export (A3)

extension SavedRoute {
    /// A day’s saved route as a GPX file for another device or planner.
    var gpxExportURL: URL? {
        guard points.count > 1 else { return nil }
        let start = createdAt
        let ridePoints = points.enumerated().map { index, point in
            RidePoint(lat: point.lat, lon: point.lon, alt: 0, speed: 0,
                      time: start.addingTimeInterval(Double(index)), lean: nil)
        }
        return GPX.writeTempFile(points: ridePoints, startDate: start)
    }
}
