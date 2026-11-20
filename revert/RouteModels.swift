import Foundation
import CoreLocation
import MapKit

nonisolated enum LoopMode: String, CaseIterable, Identifiable, Sendable {
    case compact
    case extended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .extended: "Extended"
        }
    }

    var blurb: String {
        switch self {
        case .compact: "Short, dense loops designed to ride again."
        case .extended: "Longer loops with more variety between the good sections."
        }
    }
}

nonisolated enum RouteStyle: String, CaseIterable, Identifiable {
    case relaxed, twisty, extreme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .twisty: "Twisty"
        case .extreme: "Max twisty"
        }
    }

    var blurb: String {
        switch self {
        case .relaxed: "Gentle sweepers and scenic back roads."
        case .twisty: "Prefers winding roads. A good default."
        case .extreme: "Hunts for the tightest roads it can find."
        }
    }
}

nonisolated enum RouteKind {
    case loop
    case directions
    /// A one-way timed run from one chosen road or place to another. It
    /// navigates like directions but starts its clock at the start line.
    case sprint

    var isLoop: Bool { self == .loop }
    var isSprint: Bool { self == .sprint }
    /// Point-to-point routes end at a destination instead of the start.
    var isPointToPoint: Bool { self != .loop }
    /// Loops and sprints are timed from the start line; plain directions are
    /// not.
    var isTimed: Bool { self != .directions }
}

enum DirectionPreference: String, CaseIterable, Identifiable {
    case fastest
    case fun
    case sporty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastest: "Quickest"
        case .fun: "Scenic"
        case .sporty: "Twisty"
        }
    }

    var blurb: String {
        switch self {
        case .fastest: "Prioritizes the shortest estimated travel time."
        case .fun: "Looks for a more scenic, varied route with extra turns."
        case .sporty: "Favors twistier alternatives and avoids highways when possible."
        }
    }
}

nonisolated struct RoutePoint: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var road: Int64      // OSM way this point lies on (the road being ridden when you reach it)

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

nonisolated struct NavStep: Identifiable, Codable {
    enum Turn: String, Codable, Equatable {
        case start, straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn, arrive
    }

    let id: Int
    let turn: Turn
    let road: String?       // road you end up on
    let at: Int             // index in the route's points
    let distance: Double    // meters from the start of the route
    let text: String?
    /// Lane advice for this manoeuvre, when OSM tags the approach road with
    /// `turn:lanes`. MapKit routes have no way ids, so they never carry it.
    var laneGuidance: LaneGuidance? = nil

    init(id: Int, turn: Turn, road: String?, at: Int, distance: Double, text: String? = nil,
         laneGuidance: LaneGuidance? = nil) {
        self.id = id
        self.turn = turn
        self.road = road
        self.at = at
        self.distance = distance
        self.text = text
        self.laneGuidance = laneGuidance
    }

    var symbol: String {
        switch turn {
        case .start, .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left: "arrow.turn.up.left"
        case .sharpLeft: "arrow.turn.down.left"
        case .slightRight: "arrow.up.right"
        case .right: "arrow.turn.up.right"
        case .sharpRight: "arrow.turn.down.right"
        case .uTurn: "arrow.uturn.left"
        case .arrive: "flag.checkered"
        }
    }

    private var verb: String {
        switch turn {
        case .start: "Head out"
        case .straight: "Continue"
        case .slightLeft: "Bear left"
        case .left: "Turn left"
        case .sharpLeft: "Sharp left"
        case .slightRight: "Bear right"
        case .right: "Turn right"
        case .sharpRight: "Sharp right"
        case .uTurn: "Make a U-turn"
        case .arrive: "Arrive"
        }
    }

    var instruction: String {
        if let text, !text.isEmpty { return StreetNames.instruction(text) }
        switch turn {
        case .arrive: return "You have arrived"
        case .start: return road.map { "Head out on \(StreetNames.road($0))" } ?? "Start riding"
        case .uTurn: return "Make a U-turn"
        default: return road.map { "\(verb) onto \(StreetNames.road($0))" } ?? verb
        }
    }
}

nonisolated enum LoopSurface: String, CaseIterable, Identifiable, Codable, Sendable {
    case paved
    case mixed
    case adventure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paved: "Paved"
        case .mixed: "Mixed"
        case .adventure: "ADV"
        }
    }

    var blurb: String {
        switch self {
        case .paved: "Sealed roads only. Fast, smooth, predictable."
        case .mixed: "Allows gravel and track connectors between paved sections."
        case .adventure: "Prefers unpaved tracks and dual-sport loops."
        }
    }

    var icon: String {
        switch self {
        case .paved: "road.lanes"
        case .mixed: "car.rear.road.lane"
        case .adventure: "mountain.2.fill"
        }
    }

    var includesUnpaved: Bool { self != .paved }
}

nonisolated struct PlannedRoute: Identifiable {
    let id = UUID()
    var kind: RouteKind
    let points: [RoutePoint]
    let cumulative: [Double]                 // meters from the start, one per point
    let coordinates: [CLLocationCoordinate2D]
    var steps: [NavStep]
    let twistPerKm: Double
    let retraced: Double                     // fraction of the route that repeats road you already rode
    let bearing: Double                      // which way the loop heads from the start
    let expectedTravelTime: TimeInterval?
    let destination: CLLocationCoordinate2D?
    let isOfflinePreview: Bool
    var displayName: String?
    /// Loop metrics are geometry-derived for MapKit routes and graph-derived for offline routes.
    let overallScore: Double?
    let flowScore: Double?
    let lapScore: Double?
    let interruptions: Int?
    let scoreLabel: String?

    // Enrichment added after planning (waypoints, elevation). Defaults keep
    // every existing initializer source-compatible.
    var waypoints: [CLLocationCoordinate2D] = []
    var elevationProfile: [ElevationSample] = []
    var climbMeters: Double = 0
    var descentMeters: Double = 0
    var maxElevation: Double = 0
    var isMountainPassRoute: Bool = false
    var surface: LoopSurface = .paved
    /// How many times the circuit is ridden. Ignored by point-to-point routes,
    /// which are always a single run.
    var laps: Int = 3
    /// Distinct OSM road names ridden by this route, most-used first. Used by
    /// the on-device taste store when the rider actually starts the loop, and
    /// empty for MapKit routes that carry no way ids.
    var usedRoadNames: [String] = []
    /// Set when the route came from a saved loop, so the finished ride can be
    /// linked back to it for the leaderboard.
    var savedRouteID: UUID? = nil

    var length: Double { cumulative.last ?? 0 }

    /// 1...5
    var curviness: Int {
        switch twistPerKm {
        case ..<20: 1
        case ..<45: 2
        case ..<90: 3
        case ..<160: 4
        default: 5
        }
    }

    var heading: String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((bearing + 22.5) / 45) % 8]
    }

    init(
        points: [RoutePoint],
        roads: [Int64: Road],
        twistPerKm: Double,
        retraced: Double,
        bearing: Double,
        isOfflinePreview: Bool = false,
        displayName: String? = nil,
        expectedTravelTime: TimeInterval? = nil,
        overallScore: Double? = nil,
        flowScore: Double? = nil,
        lapScore: Double? = nil,
        interruptions: Int? = nil,
        scoreLabel: String? = nil,
        kind: RouteKind = .loop
    ) {
        let cumulative = Self.makeCumulative(points)
        self.kind = kind
        self.points = points
        self.cumulative = cumulative
        self.coordinates = points.map(\.coordinate)
        self.steps = PlannedRoute.makeSteps(points: points, cum: cumulative, roads: roads)
        self.twistPerKm = twistPerKm
        self.retraced = retraced
        self.bearing = bearing
        self.expectedTravelTime = expectedTravelTime
        self.destination = points.last?.coordinate
        self.isOfflinePreview = isOfflinePreview
        self.displayName = displayName
        self.overallScore = overallScore
        self.flowScore = flowScore
        self.lapScore = lapScore
        self.interruptions = interruptions
        self.scoreLabel = scoreLabel
        self.usedRoadNames = Self.roadNames(points: points, roads: roads)
        self.laps = kind.isLoop ? 3 : 1
    }

    private static func roadNames(points: [RoutePoint], roads: [Int64: Road]) -> [String] {
        var counts: [String: Int] = [:]
        for point in points where point.road != 0 {
            guard let road = roads[point.road] else { continue }
            guard let name = (road.name ?? road.ref)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(16)
            .map(\.key)
    }

    init(mapRoute: MKRoute) {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: mapRoute.polyline.pointCount)
        mapRoute.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))

        let points = coordinates.map { RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0) }
        let cumulative = Self.makeCumulative(points)
        self.kind = .directions
        self.points = points
        self.cumulative = cumulative
        self.coordinates = coordinates
        self.steps = Self.makeMapSteps(route: mapRoute, cumulative: cumulative)
        self.twistPerKm = 0
        self.retraced = 0
        self.bearing = 0
        self.expectedTravelTime = mapRoute.expectedTravelTime
        self.destination = coordinates.last
        self.isOfflinePreview = false
        self.displayName = nil
        self.overallScore = nil
        self.flowScore = nil
        self.lapScore = nil
        self.interruptions = nil
        self.scoreLabel = nil
        self.laps = 1
    }

    /// Combines MapKit legs (including intermediate waypoints) into a single
    /// turn-by-turn route. MKDirections has no multi-stop request, so the
    /// planner chains legs and stitches the geometry and instructions here.
    init(mapRoutes: [MKRoute], waypoints: [CLLocationCoordinate2D] = [], kind: RouteKind = .directions,
         surface: LoopSurface = .paved) {
        var combinedPoints: [RoutePoint] = []
        var stepSpecs: [(turn: NavStep.Turn, text: String, distance: Double, road: String?)] = []
        var offset = 0.0

        for (index, route) in mapRoutes.enumerated() {
            var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                       count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
            let legPoints = coordinates.map { RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0) }
            let legCumulative = Self.makeCumulative(legPoints)
            if index == 0 {
                combinedPoints = legPoints
            } else {
                combinedPoints += legPoints.dropFirst()
            }
            var legDistance = 0.0
            for mapStep in route.steps {
                let text = mapStep.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                legDistance = min(legDistance + mapStep.distance, legCumulative.last ?? 0)
                stepSpecs.append((Self.turn(for: text), text, offset + legDistance, nil))
            }
            offset += legCumulative.last ?? 0
        }

        let cumulative = Self.makeCumulative(combinedPoints)
        self.kind = kind
        self.points = combinedPoints
        self.cumulative = cumulative
        // A directions route is one pass, however many MapKit legs it took.
        // Leaving the 3-lap default here made the ETA triple and the rider
        // hear "Lap 2 of 3" at the destination.
        self.laps = kind.isLoop ? 3 : 1
        self.coordinates = combinedPoints.map(\.coordinate)
        self.steps = stepSpecs.map { spec in
            let at = cumulative.indices.min {
                abs(cumulative[$0] - spec.distance) < abs(cumulative[$1] - spec.distance)
            } ?? 0
            return NavStep(id: 0, turn: spec.turn, road: spec.road, at: at,
                           distance: spec.distance, text: spec.text)
        }.enumerated().map { index, step in
            NavStep(id: index, turn: step.turn, road: step.road, at: step.at,
                    distance: step.distance, text: step.text)
        } + [NavStep(id: stepSpecs.count, turn: .arrive, road: nil,
                     at: max(combinedPoints.count - 1, 0),
                     distance: cumulative.last ?? 0)]
        self.twistPerKm = 0
        self.retraced = 0
        self.bearing = 0
        self.expectedTravelTime = mapRoutes.reduce(0) { $0 + $1.expectedTravelTime }
        self.destination = kind == .directions ? combinedPoints.last?.coordinate : nil
        self.isOfflinePreview = false
        self.displayName = nil
        self.overallScore = nil
        self.flowScore = nil
        self.lapScore = nil
        self.interruptions = nil
        self.scoreLabel = nil
        self.waypoints = waypoints
        self.surface = surface
    }

    private static func makeCumulative(_ points: [RoutePoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var cumulative: [Double] = [0]
        for index in 1..<points.count {
            let distance = RoadGraph.flat(points[index - 1].lat, points[index - 1].lon, points[index].lat, points[index].lon).dist
            cumulative.append(cumulative[index - 1] + distance)
        }
        return cumulative
    }

    private static func makeMapSteps(route: MKRoute, cumulative: [Double]) -> [NavStep] {
        guard !cumulative.isEmpty else { return [] }
        var distance = 0.0
        var steps: [NavStep] = []

        for mapStep in route.steps {
            let instruction = mapStep.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else { continue }
            distance = min(distance + mapStep.distance, cumulative.last ?? 0)
            let pointIndex = cumulative.indices.min { abs(cumulative[$0] - distance) < abs(cumulative[$1] - distance) } ?? 0
            steps.append(NavStep(id: steps.count, turn: turn(for: instruction), road: nil,
                                 at: pointIndex, distance: distance, text: instruction))
        }

        steps.append(NavStep(id: steps.count, turn: .arrive, road: nil, at: cumulative.count - 1, distance: cumulative.last ?? 0))
        return steps
    }

    /// MapKit gives us prose instructions but no maneuver type. Classify the
    /// common English forms so the HUD does not show a straight arrow for
    /// "Turn right".
    private static func turn(for instruction: String) -> NavStep.Turn {
        let text = instruction.lowercased()
        if text.contains("u-turn") || text.contains("u turn") || text.contains("uturn") {
            return .uTurn
        }
        if text.contains("sharp right") { return .sharpRight }
        if text.contains("sharp left") { return .sharpLeft }
        if text.contains("slight right") || text.contains("bear right")
            || text.contains("keep right") || text.contains("fork right")
            || text.contains("merge right") { return .slightRight }
        if text.contains("slight left") || text.contains("bear left")
            || text.contains("keep left") || text.contains("fork left")
            || text.contains("merge left") { return .slightLeft }
        if text.contains("roundabout") || text.contains("rotary") {
            // MapKit does not tell us which exit; a gentle right keeps the
            // icon neutral without falsely promising a hard turn.
            return .slightRight
        }
        if text.contains("turn right") || text.contains("right onto")
            || text.contains("take the right") || text.contains("exit right") { return .right }
        if text.contains("turn left") || text.contains("left onto")
            || text.contains("take the left") || text.contains("exit left") { return .left }
        if text.contains("ramp") || text.contains("exit") { return .slightRight }
        return .straight
    }

    // MARK: Turn-by-turn
    private static func makeSteps(points: [RoutePoint], cum: [Double], roads: [Int64: Road]) -> [NavStep] {
        guard points.count > 2 else { return [] }

        func name(_ id: Int64) -> String? {
            guard let road = roads[id] else { return nil }
            return road.name ?? road.ref
        }

        func headingBefore(_ index: Int) -> Double {
            var prior = index - 1
            while prior > 0, cum[index] - cum[prior] < 20 { prior -= 1 }
            return RoadGraph.flat(points[prior].lat, points[prior].lon, points[index].lat, points[index].lon).heading
        }

        func headingAfter(_ index: Int) -> Double {
            var next = index + 1
            while next < points.count - 1, cum[next] - cum[index] < 20 { next += 1 }
            return RoadGraph.flat(points[index].lat, points[index].lon, points[next].lat, points[next].lon).heading
        }

        /// Turn angle at one vertex, using the two segments that actually meet
        /// there. The 20 m windows below are right for gentle bend detection,
        /// but they straddle a sharp corner and halve its angle — a 90° turn
        /// came out as "slight right".
        func vertexAngle(_ index: Int) -> Double {
            let incoming = RoadGraph.flat(points[index - 1].lat, points[index - 1].lon,
                                          points[index].lat, points[index].lon).heading
            let outgoing = RoadGraph.flat(points[index].lat, points[index].lon,
                                          points[index + 1].lat, points[index + 1].lon).heading
            var delta = outgoing - incoming
            while delta > 180 { delta -= 360 }
            while delta <= -180 { delta += 360 }
            return delta
        }

        func nearestVertexIndex(in road: Road, to point: RoutePoint) -> Int? {
            guard road.count > 0 else { return nil }
            var best = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for index in 0..<road.count {
                let dLat = road.lat(index) - point.lat
                let dLon = road.lon(index) - point.lon
                let distance = dLat * dLat + dLon * dLon
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return best
        }

        /// `turn:lanes` is tagged on the road the rider is leaving, so the
        /// approach way — the point before the corner — is the one to read.
        /// Directional variants only apply when the route travels that way.
        func laneGuidance(approach roadID: Int64, corner: Int, turn: NavStep.Turn) -> LaneGuidance? {
            guard let road = roads[roadID] else { return nil }
            let raw: String?
            if road.turnLanesForward != nil || road.turnLanesBackward != nil {
                let before = points[corner - 1]
                let after = points[corner]
                let forward: Bool
                if let from = nearestVertexIndex(in: road, to: before),
                   let to = nearestVertexIndex(in: road, to: after) {
                    forward = to >= from
                } else {
                    forward = true
                }
                raw = forward ? road.turnLanesForward : road.turnLanesBackward
            } else {
                raw = road.turnLanes
            }
            guard let raw else { return nil }
            return LaneGuidance.parse(turnLanes: raw, turn: turn)
        }

        func classify(_ angle: Double) -> NavStep.Turn {
            let magnitude = abs(angle)
            // Waze's junction rule: under 45° is a keep/slight movement,
            // over it is a turn; only a near-reversal becomes a U-turn.
            if magnitude < 20 { return .straight }
            if magnitude < 45 { return angle > 0 ? .slightRight : .slightLeft }
            if magnitude < 150 { return angle > 0 ? .right : .left }
            if magnitude < 165 { return angle > 0 ? .sharpRight : .sharpLeft }
            return .uTurn
        }

        var steps = [NavStep(id: 0, turn: .start, road: name(points[0].road), at: 0, distance: 0)]
        var lastAt = 0.0

        // MapKit loops have no OSM way ids, so their turns are derived from
        // geometry. The offline graph uses road boundaries, which are more
        // reliable when two roads run side by side.
        let geometryOnly = roads.isEmpty
        for corner in 1..<(points.count - 1) {
            var turn: NavStep.Turn

            if abs(points[corner - 1].lat - points[corner + 1].lat) < 1e-7 &&
                abs(points[corner - 1].lon - points[corner + 1].lon) < 1e-7 {
                turn = .uTurn
            } else if geometryOnly {
                // The windowed angle reaches past a nearby corner, so it can
                // claim a turn one vertex early — and that phantom turn used to
                // eat the 30 m suppression budget, dropping the real one. Only
                // a vertex that actually bends may start a turn; the windowed
                // reading is then used for the magnitude, because it captures
                // the full angle when the corner spans a couple of vertices.
                let vertex = vertexAngle(corner)
                guard abs(vertex) >= 15 else { continue }
                var angle = headingAfter(corner) - headingBefore(corner)
                while angle > 180 { angle -= 360 }
                while angle <= -180 { angle += 360 }
                if abs(angle) < abs(vertex) { angle = vertex }
                let kind = classify(angle)
                if kind == .straight { continue }
                turn = kind
            } else {
                // A new road starts at `corner`: the point itself carries the
                // new way id. Detecting the boundary one vertex early gave a
                // straight heading on both sides and missed the turn.
                guard points[corner - 1].road != points[corner].road else { continue }
                var angle = headingAfter(corner) - headingBefore(corner)
                while angle > 180 { angle -= 360 }
                while angle <= -180 { angle += 360 }
                let kind = classify(angle)
                let incomingName = name(points[corner - 1].road)
                let outgoingName = name(points[corner].road)
                let renamed = incomingName != outgoingName
                // A gentle movement that keeps the same primary road name is
                // the best continuation: Waze stays silent for it.
                if abs(angle) < 45, incomingName != nil, incomingName == outgoingName {
                    continue
                }
                if kind == .straight && !renamed { continue }
                turn = kind
            }

            // Avoid a wall of instructions from a long sweeping bend sampled
            // every few metres.
            if cum[corner] - lastAt < 30 { continue }
            let lanes = laneGuidance(approach: points[corner - 1].road, corner: corner, turn: turn)
            steps.append(NavStep(id: steps.count, turn: turn, road: name(points[corner].road),
                                 at: corner, distance: cum[corner], laneGuidance: lanes))
            lastAt = cum[corner]
        }

        steps.append(NavStep(id: steps.count, turn: .arrive, road: nil, at: points.count - 1, distance: cum[points.count - 1]))
        return steps
    }
}
