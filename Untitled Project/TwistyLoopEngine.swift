import Foundation
import CoreLocation
import MapKit

struct TwistyLoopSettings: Sendable {
    var candidateTemplates = 24
    var intermediateWaypoints = 3
    var samplingIntervalMeters = 10.0
    var shortWindowMeters = 300.0
    var mediumWindowMeters = 1_000.0
    var longWindowMeters = 3_000.0
    var minimumDistanceMeters = 15_000.0
    var targetDistanceMeters = 40_000.0
    var maximumDistanceMeters = 60_000.0
    var maximumDurationSeconds = 7_200.0
    var maximumResults = 5
    var mode: LoopMode = .extended
    var maximumOptimizationRounds = 3
    var maximumRouteRequests = 48

    nonisolated init(
        candidateTemplates: Int = 24,
        intermediateWaypoints: Int = 3,
        samplingIntervalMeters: Double = 10,
        shortWindowMeters: Double = 300,
        mediumWindowMeters: Double = 1_000,
        longWindowMeters: Double = 3_000,
        minimumDistanceMeters: Double = 15_000,
        targetDistanceMeters: Double = 40_000,
        maximumDistanceMeters: Double = 60_000,
        maximumDurationSeconds: Double = 7_200,
        maximumResults: Int = 5,
        mode: LoopMode = .extended,
        maximumOptimizationRounds: Int = 3,
        maximumRouteRequests: Int = 48
    ) {
        self.candidateTemplates = candidateTemplates
        self.intermediateWaypoints = intermediateWaypoints
        self.samplingIntervalMeters = samplingIntervalMeters
        self.shortWindowMeters = shortWindowMeters
        self.mediumWindowMeters = mediumWindowMeters
        self.longWindowMeters = longWindowMeters
        self.minimumDistanceMeters = minimumDistanceMeters
        self.targetDistanceMeters = targetDistanceMeters
        self.maximumDistanceMeters = maximumDistanceMeters
        self.maximumDurationSeconds = maximumDurationSeconds
        self.maximumResults = maximumResults
        self.mode = mode
        self.maximumOptimizationRounds = maximumOptimizationRounds
        self.maximumRouteRequests = maximumRouteRequests
    }
}

struct TwistyLoopCandidate: Identifiable, Sendable {
    let id = UUID()
    let points: [RoutePoint]
    let distanceMeters: Double
    let durationSeconds: Double
    let twistinessScore: Double
    let flowScore: Double
    let continuityScore: Double
    let loopQualityScore: Double
    let varietyScore: Double
    let finalScore: Double
    let lapScore: Double
    let retracedFraction: Double
    let reversalFraction: Double
    let cornerCount: Int
    let maneuverCount: Int
    let bearing: Double
    let recommendation: String
}

enum TwistyLoopError: Error {
    case noValidRoutes
}

actor TwistyLoopEngine {
    private let settings: TwistyLoopSettings
    private var requestCache: [String: CachedLeg] = [:]
    private var routeRequests = 0
    /// Wall-clock limit for the whole search. The UI is allowed to show a
    /// partial result rather than making the rider wait for a perfect one.
    private var deadline: Date?

    private var isExpired: Bool {
        guard let deadline else { return false }
        return Date() >= deadline
    }

    private struct CachedLeg {
        let route: MKRoute
        let key: String
    }

    private struct Template {
        let bearings: [Double]
        let radiusMeters: Double
    }

    /// A waypoint is only useful if it lands on a junction the rider can ride
    /// through. Arbitrary coordinates get snapped by MapKit to the nearest
    /// road, which is often a driveway or the head of a cul-de-sac.
    private struct WaypointSnapper: Sendable {
        struct Node: Sendable {
            let latitude: Double
            let longitude: Double
            /// How twisty the roads leaving this junction are, minus a small
            /// penalty for complex urban intersections.
            let score: Double
        }

        let nodes: [Node]
        let searchRadiusMeters: Double

        init?(
            roads: [Road],
            start: CLLocationCoordinate2D,
            includeUnpaved: Bool,
            loopRadiusMeters: Double
        ) {
            guard roads.count >= 8 else { return nil }
            let startKey = RoadGraph.key(start.latitude, start.longitude)
            let graph = RoadGraph(
                roads: roads,
                forced: [startKey],
                includeUnpaved: includeUnpaved
            )

            let minimumDistanceFromStart = max(300, loopRadiusMeters * 0.12)
            var nodes: [Node] = []
            nodes.reserveCapacity(graph.nodeLat.count / 4)

            for node in 0..<graph.nodeLat.count {
                let out = graph.outEdges[node].count
                let inbound = graph.inEdges[node].count
                // A dead-end head has one way in and one way out along the
                // same road. A junction has a third way to continue.
                guard out >= 1, inbound >= 1, out + inbound >= 3 else { continue }

                let distanceFromStart = RoadGraph.flat(
                    graph.nodeLat[node], graph.nodeLon[node],
                    start.latitude, start.longitude
                ).dist
                guard distanceFromStart >= minimumDistanceFromStart else { continue }

                let incidentEdges = graph.outEdges[node] + graph.inEdges[node]
                let highways = incidentEdges.map {
                    graph.roads[graph.edges[$0].road].highway
                }
                let isDrivewayOrAisle = highways.allSatisfy {
                    $0 == "service" || $0 == "driveway" || $0 == "parking_aisle"
                }
                guard !isDrivewayOrAisle else { continue }

                // Prefer a junction whose continuation is genuinely twisty.
                // Without this, the nearest junction wins even when it sits on
                // a straight grid road next to a great back road.
                let twist = graph.outEdges[node]
                    .map { graph.edges[$0].twist }
                    .max() ?? 0
                let degreePenalty = Double(max(0, out + inbound - 4)) * 3
                let score = min(twist / 120 * 100, 100) - degreePenalty

                nodes.append(Node(
                    latitude: graph.nodeLat[node],
                    longitude: graph.nodeLon[node],
                    score: score
                ))
            }

            guard nodes.count >= 4 else { return nil }
            self.nodes = nodes
            self.searchRadiusMeters = max(500, min(4_000, loopRadiusMeters * 0.30))
        }

        func snap(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
            var best: Node?
            var bestScore = -Double.infinity
            for node in nodes {
                let distance = RoadGraph.flat(
                    node.latitude, node.longitude,
                    coordinate.latitude, coordinate.longitude
                ).dist
                guard distance <= searchRadiusMeters else { continue }
                // Distance still matters: a twisty junction should not pull
                // the waypoint so far that the loop shape is lost.
                let distancePenalty = distance / searchRadiusMeters * 30
                let score = node.score - distancePenalty
                if score > bestScore {
                    bestScore = score
                    best = node
                }
            }
            guard let best else { return nil }
            return CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
        }
    }

    private struct Metrics {
        let twistiness: Double
        let flow: Double
        let continuity: Double
        let loopQuality: Double
        let variety: Double
        let lap: Double
    }

    private struct Corner {
        let lengthMeters: Double
        let minimumRadiusMeters: Double
        let totalAngleDegrees: Double
        let direction: Int
    }

    init(settings: TwistyLoopSettings) {
        self.settings = settings
    }

    func findLoops(
        startingAt center: CLLocationCoordinate2D,
        roads: [Road] = [],
        surface: LoopSurface = .paved,
        deadline: Date? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [TwistyLoopCandidate] {
        requestCache.removeAll(keepingCapacity: true)
        routeRequests = 0
        self.deadline = deadline

        let templates = makeTemplates()
        let nominalRadius = settings.targetDistanceMeters / (2 * Double.pi * 1.25)
        let snapper = WaypointSnapper(
            roads: roads,
            start: center,
            includeUnpaved: surface.includesUnpaved,
            loopRadiusMeters: nominalRadius
        )
        var candidates: [TwistyLoopCandidate] = []
        var nextTemplate = 0
        var completed = 0

        // Build a couple of templates at a time. Each template's legs also run
        // in parallel, so the wall-clock time is roughly one round of MapKit
        // requests per template instead of one per leg.
        try await withThrowingTaskGroup(of: [TwistyLoopCandidate].self) { group in
            var active = 0
            while active < 2, nextTemplate < templates.count, !isExpired {
                guard routeRequests + (settings.intermediateWaypoints + 1) <= settings.maximumRouteRequests else { break }
                let template = templates[nextTemplate]
                nextTemplate += 1
                group.addTask {
                    guard let candidate = try? await self.buildOptimizedLoop(
                        center: center,
                        template: template,
                        snapper: snapper
                    ) else {
                        return []
                    }
                    return [candidate]
                }
                active += 1
            }

            while let batch = try await group.next() {
                active -= 1
                completed += 1
                candidates.append(contentsOf: batch)
                progress?(Double(completed) / Double(max(templates.count, 1)))

                if nextTemplate < templates.count,
                   !isExpired,
                   routeRequests + (settings.intermediateWaypoints + 1) <= settings.maximumRouteRequests {
                    let template = templates[nextTemplate]
                    nextTemplate += 1
                    group.addTask {
                        guard let candidate = try? await self.buildOptimizedLoop(
                            center: center,
                            template: template,
                            snapper: snapper
                        ) else {
                            return []
                        }
                        return [candidate]
                    }
                    active += 1
                }
            }
        }

        let ranked = candidates.sorted { $0.finalScore > $1.finalScore }
        let distinct = removeSimilarLoops(ranked)
        guard !distinct.isEmpty else { throw TwistyLoopError.noValidRoutes }
        return Array(distinct.prefix(settings.maximumResults))
    }

    private func makeTemplates() -> [Template] {
        let circumferenceFactor = 2.0 * Double.pi * 1.25
        let baseRadius = settings.targetDistanceMeters / circumferenceFactor
        let factors = [0.75, 1.0, 1.25]
        var output: [Template] = []

        for rotation in stride(from: 0.0, to: 360.0, by: 45.0) {
            for factor in factors {
                let step = 360.0 / Double(settings.intermediateWaypoints + 1)
                let bearings = (0...settings.intermediateWaypoints).dropLast().map {
                    rotation + Double($0) * step
                }
                output.append(Template(bearings: bearings, radiusMeters: baseRadius * factor))
                if output.count == settings.candidateTemplates { return output }
            }
        }
        return output
    }

    /// A candidate that respected the distance band always beats a slightly
    /// better-scoring one that missed it; inside the band, score wins.
    private func isPreferred(
        _ candidate: TwistyLoopCandidate,
        over best: TwistyLoopCandidate,
        target: Double
    ) -> Bool {
        let candidateError = abs(candidate.distanceMeters / max(target, 1) - 1)
        let bestError = abs(best.distanceMeters / max(target, 1) - 1)
        let candidateFeasible = candidateError <= 0.15
        let bestFeasible = bestError <= 0.15
        if candidateFeasible != bestFeasible { return candidateFeasible }
        if candidateFeasible {
            if abs(candidate.finalScore - best.finalScore) > 2 {
                return candidate.finalScore > best.finalScore
            }
            return candidateError < bestError
        }
        return candidateError < bestError
    }

    /// Builds a template, then nudges its radius toward the requested
    /// distance. The old engine accepted anything from 70% to 135% of the
    /// target; that is why a "40 mile" loop could come back at 28.
    private func buildOptimizedLoop(
        center: CLLocationCoordinate2D,
        template: Template,
        snapper: WaypointSnapper?
    ) async throws -> TwistyLoopCandidate {
        let target = settings.targetDistanceMeters
        var best: TwistyLoopCandidate?
        var current = template
        let attempts = max(1, settings.maximumOptimizationRounds + 1)

        for _ in 0..<attempts {
            guard !isExpired else { break }
            let legsNeeded = settings.intermediateWaypoints + 1
            guard routeRequests + legsNeeded <= settings.maximumRouteRequests else { break }

            let candidate: TwistyLoopCandidate
            do {
                candidate = try await buildLoop(center: center, template: current, snapper: snapper)
            } catch {
                break
            }

            if best == nil || isPreferred(candidate, over: best!, target: target) {
                best = candidate
            }
            let error = candidate.distanceMeters / max(target, 1)
            if abs(error - 1) <= 0.08, candidate.finalScore >= 45 { return candidate }

            // Grow or shrink the template by the measured error. Clamp the
            // step so one bad route cannot throw the search into a far-away
            // road network.
            let scale = min(max(1 / error, 0.70), 1.40)
            current = Template(
                bearings: current.bearings,
                radiusMeters: current.radiusMeters * scale
            )
        }

        guard let best else { throw TwistyLoopError.noValidRoutes }
        return best
    }

    private func buildLoop(
        center: CLLocationCoordinate2D,
        template: Template,
        snapper: WaypointSnapper?
    ) async throws -> TwistyLoopCandidate {
        try Task.checkCancellation()
        guard !isExpired else { throw TwistyLoopError.noValidRoutes }
        let waypoints = try template.bearings.map { bearing -> CLLocationCoordinate2D in
            let desired = destinationCoordinate(
                from: center,
                bearingDegrees: bearing,
                distanceMeters: template.radiusMeters
            )
            guard let snapper else { return desired }
            guard let snapped = snapper.snap(desired) else {
                // Nowhere on this template is a through-junction. Skipping it
                // is better than dropping the rider into a cul-de-sac.
                throw TwistyLoopError.noValidRoutes
            }
            return snapped
        }
        let stops = [center] + waypoints + [center]
        var legs = [MKRoute?](repeating: nil, count: stops.count - 1)

        try await withThrowingTaskGroup(of: (Int, MKRoute?).self) { group in
            for index in 0..<(stops.count - 1) {
                group.addTask {
                    let leg = try await self.requestDrivingRoute(
                        from: stops[index],
                        to: stops[index + 1]
                    )
                    return (index, leg)
                }
            }
            for try await (index, leg) in group {
                legs[index] = leg
            }
        }

        guard legs.allSatisfy({ $0 != nil }) else { throw TwistyLoopError.noValidRoutes }
        let resolvedLegs = legs.compactMap { $0 }

        let combined = combineCoordinates(resolvedLegs)
        let coordinates = combined.coordinates
        guard coordinates.count >= 3 else { throw TwistyLoopError.noValidRoutes }

        let distance = resolvedLegs.reduce(0) { $0 + $1.distance }
        let duration = resolvedLegs.reduce(0) { $0 + $1.expectedTravelTime }
        guard distance >= settings.minimumDistanceMeters,
              distance <= settings.maximumDistanceMeters,
              duration <= settings.maximumDurationSeconds else {
            throw TwistyLoopError.noValidRoutes
        }

        // A U-turn instruction or an out-and-back spur is a dead end, not a
        // lap. The old code only scored backtracking, so a 150 m cul-de-sac at
        // a waypoint survived on a 40 km loop.
        guard !LoopGeometry.containsUTurn(resolvedLegs) else {
            throw TwistyLoopError.noValidRoutes
        }
        guard !hasReversingJoin(coordinates, at: combined.joins) else {
            throw TwistyLoopError.noValidRoutes
        }
        let overlap = LoopGeometry.analyze(
            coordinates,
            ignoreStartMeters: 250,
            ignoreEndMeters: 250
        )
        // A clean lap is preferred, but a shared connector is still a loop the
        // rider can ride. Refusing every candidate because the only road out of
        // the neighbourhood is reused is how a valid start ends up with
        // "couldn't build a loop".
        guard LoopGeometry.isLapable(overlap)
            || LoopGeometry.isLapable(overlap, limits: .relaxed)
            || LoopGeometry.isLapable(overlap, limits: .loose) else {
            throw TwistyLoopError.noValidRoutes
        }
        let retraced = overlap.repeatedFraction
        let metrics = scoreGeometry(coordinates, distanceMeters: distance)
        let closureMeters = distanceBetween(coordinates.first!, coordinates.last!)
        guard closureMeters < 250 else { throw TwistyLoopError.noValidRoutes }

        // Real maneuver density replaces the old constant. A loop with ten
        // turns per ten miles is a stop-and-go grid, even if its curvature
        // score is high.
        let maneuverCount = resolvedLegs.reduce(0) { partial, route in
            partial + route.steps.reduce(0) { count, step in
                let text = step.instructions
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !text.isEmpty,
                      !text.contains("arrive"),
                      !text.contains("continue") else { return count }
                return count + 1
            }
        }
        let miles = max(distance / 1_609.344, 0.1)
        let maneuversPer10Miles = Double(maneuverCount) / miles * 10
        let interruptionScore = clamp(100 - maneuversPer10Miles * 7,
                                      minimum: 0, maximum: 100)

        // Scores are deliberately independent so post-ride ratings can tune
        // these weights without weakening hard safety and loop constraints.
        let noBacktracking = clamp(100 - retraced * 500 - overlap.reversalFraction * 250,
                                   minimum: 0, maximum: 100)
        let closure = clamp(100 - closureMeters / 2.5, minimum: 0, maximum: 100)
        // Normalized weighting per mode so each metric is accounted for exactly once
        // and weights cleanly sum to 1.00.
        let interruptions = interruptionScore
        var finalScore: Double
        if settings.mode == .compact {
            finalScore = 0.20 * metrics.twistiness
                + 0.15 * metrics.flow
                + 0.10 * metrics.continuity
                + 0.10 * noBacktracking
                + 0.10 * closure
                + 0.05 * interruptions
                + 0.30 * metrics.lap
        } else {
            finalScore = 0.25 * metrics.twistiness
                + 0.20 * metrics.flow
                + 0.15 * metrics.continuity
                + 0.15 * noBacktracking
                + 0.10 * closure
                + 0.05 * interruptions
                + 0.10 * metrics.variety
        }
        // Prefer a loop that is actually the distance the rider asked for.
        let distanceError = abs(distance / max(settings.targetDistanceMeters, 1) - 1)
        finalScore = clamp(finalScore - min(45, distanceError * 220),
                           minimum: 0, maximum: 100)

        let points = coordinates.map {
            RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0)
        }

        return TwistyLoopCandidate(
            points: points,
            distanceMeters: distance,
            durationSeconds: duration,
            twistinessScore: metrics.twistiness,
            flowScore: metrics.flow,
            continuityScore: metrics.continuity,
            loopQualityScore: metrics.loopQuality,
            varietyScore: metrics.variety,
            finalScore: finalScore,
            lapScore: metrics.lap,
            retracedFraction: retraced,
            reversalFraction: overlap.reversalFraction,
            cornerCount: cornerCount(in: coordinates),
            maneuverCount: maneuverCount,
            bearing: bearing(from: center, to: waypoints[0]),
            recommendation: recommendation(for: metrics, mode: settings.mode)
        )
    }

    private func requestDrivingRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) async throws -> MKRoute? {
        let key = routeKey(start, end)
        if let cached = requestCache[key] { return cached.route }
        guard !isExpired else { return nil }
        guard routeRequests < settings.maximumRouteRequests else { return nil }
        routeRequests += 1

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: start.latitude, longitude: start.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: end.latitude, longitude: end.longitude),
            address: nil
        )
        request.transportType = .automobile
        // One route per leg. Asking for alternates triples the directions
        // traffic, and MapKit throttles the whole search when a plan fires
        // dozens of requests at once — which is indistinguishable from "there
        // is no loop here". The template search already tries many shapes.
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else { return nil }

        // Score each candidate exactly once. The old comparator re-ran the
        // full resample + corner analysis twice per comparison.
        var bestRoute = response.routes[0]
        var bestScore = -Double.greatestFiniteMagnitude
        for candidate in response.routes {
            let score = routeGeometryScore(candidate)
            if score > bestScore {
                bestScore = score
                bestRoute = candidate
            }
        }
        let route = bestRoute

        requestCache[key] = CachedLeg(route: route, key: key)
        return route
    }

    private func routeGeometryScore(_ route: MKRoute) -> Double {
        let coordinates = polylineCoordinates(route.polyline)
        guard coordinates.count > 2 else { return 0 }
        let metrics = scoreGeometry(coordinates, distanceMeters: route.distance)
        return metrics.twistiness
            + metrics.flow * 0.2
            - (route.hasHighways ? 20 : 0)
            - (route.hasTolls ? 5 : 0)
    }

    private func scoreGeometry(
        _ coordinates: [CLLocationCoordinate2D],
        distanceMeters: Double
    ) -> Metrics {
        let sampled = resample(coordinates, every: settings.samplingIntervalMeters)
        guard sampled.count > 2, distanceMeters > 0 else {
            return Metrics(twistiness: 0, flow: 0, continuity: 0, loopQuality: 0, variety: 0, lap: 0)
        }

        let windowPoints = max(2, Int(30 / max(settings.samplingIntervalMeters, 1)))
        guard sampled.count > windowPoints * 2 + 1 else {
            return Metrics(twistiness: 0, flow: 0, continuity: 0, loopQuality: 0, variety: 0, lap: 0)
        }
        let turns = (windowPoints..<(sampled.count - windowPoints)).map { index in
            let incoming = bearing(from: sampled[index - windowPoints], to: sampled[index])
            let outgoing = bearing(from: sampled[index], to: sampled[index + windowPoints])
            return normalizedAngle(outgoing - incoming)
        }
        let smoothedTurns = turns.indices.map { index in
            let start = max(0, index - 1)
            let end = min(turns.count - 1, index + 1)
            return turns[start...end].reduce(0, +) / Double(end - start + 1)
        }
        let corners = groupCorners(smoothedTurns, sampleInterval: settings.samplingIntervalMeters)
        let kilometers = distanceMeters / 1_000.0
        // A road can be tight in one place and dead straight everywhere else.
        // Look at curvature over 30 m, 300 m, 1 km and 3 km so a genuine
        // flowing road beats a single hairpin surrounded by straights.
        let multiScale = multiScaleCurvatureScore(sampled)
        // Radius-based, route-level curvature from the same definition the
        // graph planner uses. Blended with the multi-scale chord score so a
        // single hairpin cannot outrank a flowing mountain road.
        let measured = Curvature.measure(coordinates)
        let combinedTwist = clamp(measured.value * 0.7 + multiScale * 0.3,
                                  minimum: 0, maximum: 100)
        let totalTurn = smoothedTurns.reduce(0) { $0 + abs($1) }
        let directionChanges = zip(smoothedTurns, smoothedTurns.dropFirst()).filter {
            abs($0) >= 5 && abs($1) >= 5 && ($0 > 0) != ($1 > 0)
        }.count
        let alternationsPerKm = Double(directionChanges) / max(kilometers, 0.1)
        let sCurveBonus = clamp(alternationsPerKm / 3 * 100, minimum: 0, maximum: 100)
        let cornerDistance = corners.reduce(0) { $0 + $1.lengthMeters }
        let continuity = clamp((cornerDistance / max(distanceMeters, 1)) * 250, minimum: 0, maximum: 100)

        // A lap should keep worthwhile corners distributed around the whole ride,
        // rather than putting all of the fun in one short section.
        let quarterLength = max(sampled.count / 4, 1)
        let cornerBuckets = (0..<4).map { bucket in
            let lower = bucket * quarterLength
            let upper = bucket == 3 ? smoothedTurns.count : min((bucket + 1) * quarterLength, smoothedTurns.count)
            guard lower < upper else { return 0.0 }
            return smoothedTurns[lower..<upper].reduce(0) { $0 + abs($1) }
        }
        let meanBucket = cornerBuckets.reduce(0, +) / Double(cornerBuckets.count)
        let spread = meanBucket > 0
            ? cornerBuckets.map { abs($0 - meanBucket) }.reduce(0, +) / Double(cornerBuckets.count) / meanBucket
            : 1
        let distribution = clamp(100 - spread * 100, minimum: 0, maximum: 100)
        let connectorPenalty = clamp(100 - (cornerDistance / max(distanceMeters, 1)) * 180, minimum: 0, maximum: 100)
        let lap = clamp(distribution * 0.55 + (100 - connectorPenalty) * 0.30 + continuity * 0.15,
                        minimum: 0, maximum: 100)

        return Metrics(
            twistiness: combinedTwist,
            // Flow means sweepers, not straights. A perfectly straight route
            // has zero sweeper share and therefore zero flow.
            flow: clamp(measured.sweeperShare * 75 + sCurveBonus * 0.25,
                        minimum: 0, maximum: 100),
            continuity: continuity,
            loopQuality: clamp(totalTurn / max(kilometers, 0.1) / 180 * 100, minimum: 0, maximum: 100),
            variety: sCurveBonus,
            lap: lap
        )
    }

    /// Curvature at several chord lengths. A 40 km road with one hairpin and
    /// 39 km of straight should not score like a flowing mountain road.
    private func multiScaleCurvatureScore(_ sampled: [CLLocationCoordinate2D]) -> Double {
        let scales: [(meters: Double, weight: Double)] = [
            (30, 0.35),
            (settings.shortWindowMeters, 0.25),
            (settings.mediumWindowMeters, 0.20),
            (settings.longWindowMeters, 0.20)
        ]
        var weighted = 0.0
        var totalWeight = 0.0
        for scale in scales {
            guard let score = curvatureScore(sampled, windowMeters: scale.meters) else { continue }
            weighted += score * scale.weight
            totalWeight += scale.weight
        }
        return totalWeight > 0 ? weighted / totalWeight : 0
    }

    /// Average heading change per kilometre measured over `windowMeters`.
    /// Returns nil when the route is too short for that scale.
    private func curvatureScore(
        _ sampled: [CLLocationCoordinate2D],
        windowMeters: Double
    ) -> Double? {
        let interval = max(settings.samplingIntervalMeters, 1)
        let window = max(2, Int(windowMeters / interval))
        guard sampled.count > window * 2 + 1 else { return nil }

        var total = 0.0
        var count = 0
        for index in window..<(sampled.count - window) {
            let incoming = bearing(from: sampled[index - window], to: sampled[index])
            let outgoing = bearing(from: sampled[index], to: sampled[index + window])
            total += abs(normalizedAngle(outgoing - incoming))
            count += 1
        }
        guard count > 0 else { return nil }

        let averageTurn = total / Double(count)
        let degreesPerKm = averageTurn / max(windowMeters / 1_000, 0.001)
        return clamp(degreesPerKm / 180 * 100, minimum: 0, maximum: 100)
    }

    private func cornerCount(in coordinates: [CLLocationCoordinate2D]) -> Int {
        let sampled = resample(coordinates, every: settings.samplingIntervalMeters)
        let window = max(2, Int(30 / max(settings.samplingIntervalMeters, 1)))
        guard sampled.count > window * 2 + 1 else { return 0 }
        let turns = (window..<(sampled.count - window)).map { index in
            normalizedAngle(
                bearing(from: sampled[index], to: sampled[index + window])
                    - bearing(from: sampled[index - window], to: sampled[index])
            )
        }
        return groupCorners(turns, sampleInterval: settings.samplingIntervalMeters).count
    }

    private func recommendation(for metrics: Metrics, mode: LoopMode) -> String {
        if mode == .compact { return "Best short loop" }
        if metrics.flow >= 40 { return "Flowing sweepers" }
        if metrics.twistiness >= 55 { return "Tight and twisty" }
        if metrics.twistiness >= 40 { return "Twisty" }
        return "Best overall"
    }

    private func groupCorners(_ turns: [Double], sampleInterval: Double) -> [Corner] {
        var corners: [Corner] = []
        var startIndex: Int?
        var direction = 0
        var radius = Double.infinity
        var angle = 0.0

        func finish(at endIndex: Int) {
            guard let startIndex, endIndex > startIndex else { return }
            let length = Double(endIndex - startIndex + 1) * sampleInterval
            guard radius < 250, angle >= 12 else { return }
            corners.append(Corner(lengthMeters: length, minimumRadiusMeters: radius,
                                  totalAngleDegrees: angle, direction: direction))
        }

        for index in turns.indices {
            let turn = turns[index]
            let magnitude = abs(turn)
            let nextDirection = turn >= 0 ? 1 : -1
            // The two adjacent 30 m chords define the circumradius. The
            // prior small-angle approximation doubled this radius and made
            // genuinely tight corners look like medium sweepers.
            let turnRadians = magnitude * .pi / 180
            let radiusAtPoint = magnitude > 0.01
                ? 30 / max(2 * sin(turnRadians / 2), 0.000_001)
                : Double.infinity

            if magnitude >= 4, (startIndex == nil || nextDirection == direction) {
                if startIndex == nil { startIndex = index; direction = nextDirection }
                radius = min(radius, radiusAtPoint)
                angle += magnitude
            } else {
                finish(at: index - 1)
                startIndex = magnitude >= 4 ? index : nil
                direction = magnitude >= 4 ? nextDirection : 0
                radius = magnitude >= 4 ? radiusAtPoint : .infinity
                angle = magnitude >= 4 ? magnitude : 0
            }
        }
        finish(at: turns.count - 1)
        return corners
    }

    private func resample(
        _ coordinates: [CLLocationCoordinate2D],
        every interval: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var output = [coordinates[0]]
        var remaining = interval
        var previous = coordinates[0]

        for current in coordinates.dropFirst() {
            var start = previous
            var segmentRemaining = distanceBetween(start, current)

            while segmentRemaining >= remaining {
                let fraction = remaining / max(segmentRemaining, 0.001)
                let point = interpolate(start, current, fraction: fraction)
                output.append(point)
                start = point
                segmentRemaining -= remaining
                remaining = interval
            }

            remaining -= segmentRemaining
            previous = current
        }

        if output.last.map({ distanceBetween($0, coordinates.last!) > interval * 0.5 }) == true {
            output.append(coordinates.last!)
        }
        return output
    }

    /// A waypoint at the end of a road is joined by a 180° reversal: the rider
    /// arrives, then leaves back down the same road. Check the direction of
    /// travel either side of every leg boundary.
    private func hasReversingJoin(
        _ coordinates: [CLLocationCoordinate2D],
        at joins: [Int]
    ) -> Bool {
        for join in joins {
            guard let arrival = heading(coordinates, at: join, backwards: true),
                  let departure = heading(coordinates, at: join, backwards: false) else {
                continue
            }
            if abs(normalizedAngle(departure - arrival)) >= 140 { return true }
        }
        return false
    }

    private func heading(
        _ coordinates: [CLLocationCoordinate2D],
        at index: Int,
        backwards: Bool,
        lookAheadMeters: Double = 30
    ) -> Double? {
        guard index > 0, index < coordinates.count - 1 else { return nil }
        var travelled = 0.0
        if backwards {
            var cursor = index
            while cursor > 0, travelled < lookAheadMeters {
                travelled += distanceBetween(coordinates[cursor - 1], coordinates[cursor])
                cursor -= 1
            }
            guard travelled > 1 else { return nil }
            return bearing(from: coordinates[cursor], to: coordinates[index])
        } else {
            var cursor = index
            while cursor < coordinates.count - 1, travelled < lookAheadMeters {
                travelled += distanceBetween(coordinates[cursor], coordinates[cursor + 1])
                cursor += 1
            }
            guard travelled > 1 else { return nil }
            return bearing(from: coordinates[index], to: coordinates[cursor])
        }
    }

    private func removeSimilarLoops(_ loops: [TwistyLoopCandidate]) -> [TwistyLoopCandidate] {
        var selected: [TwistyLoopCandidate] = []
        for candidate in loops {
            guard !selected.contains(where: { routeSimilarity(candidate, $0) > 0.60 }) else { continue }
            selected.append(candidate)
        }
        return selected
    }

    private func routeSimilarity(
        _ first: TwistyLoopCandidate,
        _ second: TwistyLoopCandidate
    ) -> Double {
        let a = first.points.map(\.coordinate)
        let b = second.points.map(\.coordinate)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        // Bounding-box rejection first: most candidate pairs are nowhere near
        // each other, and this is the quadratic part of ranking.
        func box(_ points: [CLLocationCoordinate2D]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
            for point in points {
                minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
            }
            return (minLat, maxLat, minLon, maxLon)
        }
        let boxA = box(a), boxB = box(b)
        let latitudePad = 0.001
        let longitudePad = 0.0015
        guard boxA.maxLat >= boxB.minLat - latitudePad,
              boxB.maxLat >= boxA.minLat - latitudePad,
              boxA.maxLon >= boxB.minLon - longitudePad,
              boxB.maxLon >= boxA.minLon - longitudePad else { return 0 }

        // 24 samples per loop keeps this ~100× cheaper than the old 100×100
        // comparison while still catching genuinely duplicated geometry.
        let sampleA = stride(from: 0, to: a.count, by: max(1, a.count / 24)).map { a[$0] }
        let sampleB = stride(from: 0, to: b.count, by: max(1, b.count / 24)).map { b[$0] }
        return Double(sampleA.filter { point in
            sampleB.contains { distanceBetween(point, $0) < 50 }
        }.count) / Double(max(sampleA.count, 1))
    }

    private func polylineCoordinates(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }

    private func combineCoordinates(
        _ routes: [MKRoute]
    ) -> (coordinates: [CLLocationCoordinate2D], joins: [Int]) {
        var coordinates: [CLLocationCoordinate2D] = []
        var joins: [Int] = []
        for (index, route) in routes.enumerated() {
            let points = polylineCoordinates(route.polyline)
            guard !points.isEmpty else { continue }
            if index == 0 {
                coordinates = points
            } else {
                joins.append(max(coordinates.count - 1, 0))
                coordinates.append(contentsOf: points.dropFirst())
            }
        }
        return (coordinates, joins)
    }

    private func destinationCoordinate(
        from origin: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius
        let lat2 = asin(sin(lat1) * cos(angularDistance)
                        + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1),
                                cos(angularDistance) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func normalizedAngle(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private func routeKey(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f-%.5f,%.5f", start.latitude, start.longitude, end.latitude, end.longitude)
    }

    private func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        // Avoid two CLLocation allocations per call; resample() calls this
        // thousands of times per plan.
        RoadGraph.flat(a.latitude, a.longitude, b.latitude, b.longitude).dist
    }

    private func interpolate(
        _ start: CLLocationCoordinate2D,
        _ end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )
    }

    private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}
