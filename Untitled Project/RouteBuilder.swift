import Foundation
import CoreLocation

/// Generates round-trip loops and reroutes. Pure computation, safe to run off the main thread.
///
/// The loop search is no longer "draw a circle and ask for directions". It
/// seeds a few loops, then improves them by inserting detours around the most
/// boring stretches of road, all inside a hard distance band. Because the
/// graph is chunked (see `RoadGraph`), the cost function can see the good part
/// of a long road instead of averaging it away.
nonisolated enum RouteBuilder {
    nonisolated private static let failureLock = NSLock()
    nonisolated(unsafe) private static var _lastFailure: String?

    /// Why the last `loops(...)` call returned nothing, for the UI.
    static var lastFailure: String? {
        failureLock.withLock { _lastFailure }
    }

    /// Something the rider should know about a *successful* plan — currently
    /// "the start moved to the nearest road".
    nonisolated(unsafe) private static var _lastNotice: String?
    nonisolated private static let noticeLock = NSLock()

    static var lastNotice: String? {
        noticeLock.withLock { _lastNotice }
    }

    private static func note(_ text: String?) {
        noticeLock.withLock { _lastNotice = text }
    }

    private static func fail(_ reason: String) -> [PlannedRoute] {
        failureLock.withLock { _lastFailure = reason }
        return []
    }

    /// Distance in metres from `start` to the nearest vertex of any usable road.
    /// Used by the planner to tell "this area has roads but they never come
    /// near the pin" apart from "the download returned nothing".
    nonisolated static func distanceToNearestRoad(
        in roads: [Road],
        from start: CLLocationCoordinate2D,
        includeUnpaved: Bool = false
    ) -> Double {
        var best = Double.infinity
        let kx = 111_320.0 * cos(start.latitude * .pi / 180)
        for road in roads where includeUnpaved || !road.isUnpaved {
            for index in 0..<road.count {
                let dy = (road.lat(index) - start.latitude) * 110_540.0
                let dx = (road.lon(index) - start.longitude) * kx
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < best { best = distance }
            }
        }
        return best
    }

    // MARK: - Cost model

    static func classFactor(_ highway: String) -> Double {
        switch highway {
        case "trunk": 1.9
        case "primary": 1.65
        case "secondary": 1.2
        case "tertiary": 0.95
        case "residential": 1.35
        case "track": 1.15
        case "path": 1.35
        case "service", "driveway", "parking_aisle": 2.4
        default: 0.9
        }
    }

    /// Cruising speed by road class when OSM has no posted limit.
    static func defaultSpeedMps(_ highway: String) -> Double {
        switch highway {
        case "trunk": 30
        case "primary": 26
        case "secondary": 25
        case "tertiary": 24
        case "residential": 13
        case "track": 11
        case "path": 7
        case "service", "driveway", "parking_aisle": 7
        default: 21
        }
    }

    /// Cost of riding each edge: twisty roads cost less than their length, straight ones more.
    static func costs(
        _ graph: RoadGraph,
        style: RouteStyle,
        date: Date,
        preferences: RoadPreferences,
        surface: LoopSurface,
        hazards: HazardDensity?,
        profile: TwistProfile? = nil
    ) -> [Double] {
        // Where twisty roads are scarce, a road's class says less about how
        // good it is to ride: a winding residential lane is the point.
        let classPower = profile?.classRelief ?? 1
        return graph.edges.map { edge in
            let road = graph.roads[edge.road]
            // The same road is worth different things to different riders.
            // Relaxed wants flowing sweepers, max-twisty wants hairpins, and
            // the default blends both with overall corner density.
            // Continuous, locally normalised curvature. `edge.value` keeps the
            // older category-shaped number for display.
            let baseValue = profile?.effective(edge.raw) ?? min(edge.raw / 100, 1)
            let value: Double
            switch style {
            case .relaxed:
                value = min(0.55 * baseValue + 0.65 * edge.sweeperShare, 1)
            case .twisty:
                value = baseValue
            case .extreme:
                value = min(0.60 * baseValue + 0.70 * edge.tightShare, 1)
            }
            let traffic = trafficPenalty(for: road.highway, at: date)
            // Paved planning should not be seduced by a tempting-looking
            // gravel shortcut; ADV mode actively prefers it.
            let surfaceFactor: Double
            if road.isUnpaved {
                switch surface {
                case .paved: surfaceFactor = 6.0
                case .mixed: surfaceFactor = 1.10
                case .adventure: surfaceFactor = 0.78
                }
            } else {
                surfaceFactor = surface == .adventure ? 1.08 : 1.0
            }
            let (latitude, longitude) = midpoint(edge, in: graph)
            let hazardFactor = hazards?.costFactor(
                latitude: latitude, longitude: longitude, date: date
            ) ?? 1
            // Bounded preference: a name match nudges, it does not steer.
            let preference = preferences.multiplier(for: road)
            return edge.length
                * (1.55 - 1.2 * value)
                * pow(classFactor(road.highway), classPower)
                * traffic
                * preference
                * surfaceFactor
                * hazardFactor
        }
    }

    static func trafficPenalty(for highway: String, at date: Date) -> Double {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isWeekday = (2...6).contains(weekday)
        let isMorningCommute = (7...9).contains(hour)
        let isEveningCommute = (16...19).contains(hour)

        guard isWeekday && (isMorningCommute || isEveningCommute) else {
            return 1.0
        }

        return switch highway {
        case "trunk": 2.2
        case "primary": 1.8
        case "secondary": 1.35
        case "tertiary": 1.08
        default: 0.96
        }
    }

    /// Realistic riding time for a chunk. Uses the curvature advisory speed,
    /// the posted limit when known, and adds standstill time for signals and
    /// stop signs. This is what makes an offline loop show an ETA at all.
    static func travelSeconds(
        _ edge: RoadGraph.Edge,
        graph: RoadGraph,
        date: Date,
        hazards: HazardDensity?
    ) -> Double {
        let road = graph.roads[edge.road]
        let limitMps = road.speedLimitMph(forward: true).map { Double($0) * 0.44704 }
        let cruise = limitMps.map { min($0, 34) } ?? defaultSpeedMps(road.highway)
        let speed = max(min(edge.comfortableMps, cruise), 5.5)
        var seconds = edge.length / speed
        if let hazards {
            let (latitude, longitude) = midpoint(edge, in: graph)
            seconds += hazards.delaySeconds(latitude: latitude, longitude: longitude, date: date)
        }
        return seconds
    }

    private static func midpoint(_ edge: RoadGraph.Edge, in graph: RoadGraph) -> (Double, Double) {
        (
            (graph.nodeLat[edge.from] + graph.nodeLat[edge.to]) / 2,
            (graph.nodeLon[edge.from] + graph.nodeLon[edge.to]) / 2
        )
    }

    private static func nearestVertex(_ roads: [Road], to c: CLLocationCoordinate2D,
                                      includeUnpaved: Bool = false)
        -> (key: Int64, lat: Double, lon: Double, dist: Double)? {
        let kx = 111_320.0 * cos(c.latitude * .pi / 180)
        var best: (key: Int64, lat: Double, lon: Double, dist: Double)?
        var bestD2 = Double.infinity
        for r in roads where includeUnpaved || !r.isUnpaved {
            for i in 0..<r.count {
                let dy = (r.lat(i) - c.latitude) * 110_540.0
                let dx = (r.lon(i) - c.longitude) * kx
                let d2 = dx * dx + dy * dy
                if d2 < bestD2 {
                    bestD2 = d2
                    best = (RoadGraph.key(r.lat(i), r.lon(i)), r.lat(i), r.lon(i), d2.squareRoot())
                }
            }
        }
        return best
    }

    // MARK: - Loop search

    /// Up to three different loops of about `length` meters starting and ending at `start`.
    nonisolated static func loops(
        roads: [Road],
        start: CLLocationCoordinate2D,
        length: Double,
        style: RouteStyle,
        date: Date = Date(),
        deadline: Date? = nil,
        surface: LoopSurface = .paved,
        preferredRoads: [String] = [],
        preferences: RoadPreferences = .empty,
        hazards: [Hazard] = []
    ) -> [PlannedRoute] {
        failureLock.withLock { _lastFailure = nil }
        note(nil)
        guard let sv = nearestVertex(roads, to: start, includeUnpaved: surface.includesUnpaved) else {
            return fail("no mapped roads are loaded around this start")
        }
        // Snap to the nearest mapped road instead of refusing the plan. A pin
        // dropped mid-block, on a long driveway or in a park is normal; the old
        // 2 km cut-off turned that into "the start is not near a mapped road"
        // even though the downloaded area was full of roads.
        guard sv.dist <= 6_000 else {
            return fail("the nearest mapped road is \(Units.distanceText(sv.dist, decimals: 1)) from the start pin")
        }
        if sv.dist > 250 {
            note("The start moved \(Units.distanceText(sv.dist, decimals: 1)) to the nearest mapped road.")
        }
        let graph = RoadGraph(roads: roads, forced: [sv.key], includeUnpaved: surface.includesUnpaved)
        guard let s = graph.node(forKey: sv.key) else { return [] }

        let deadlineDate = deadline ?? Date().addingTimeInterval(12)
        let budget = SearchBudget(deadline: deadlineDate)
        let density = HazardDensity(hazards)

        // A rider's typed names are merged with their learned taste.
        var merged = preferences
        merged.preferred.formUnion(
            preferredRoads
                .map { RoadPreferences.normalize($0) }
                .filter { !$0.isEmpty }
        )

        // One local profile per plan; both the cost function and the
        // improvement passes score roads relative to it.
        let profile = TwistProfile.make(edges: graph.edges)
        let baseCosts = costs(
            graph,
            style: style,
            date: date,
            preferences: merged,
            surface: surface,
            hazards: density,
            profile: profile
        )
        let shortestCosts = graph.edges.map { edge in
            edge.length * classFactor(graph.roads[edge.road].highway)
        }
        let times = graph.edges.map { edge in
            travelSeconds(edge, graph: graph, date: date, hazards: density)
        }
        let busyJunction = busyJunctions(in: graph)
        let model = Model(
            graph: graph,
            costs: baseCosts,
            profile: profile,
            shortestCosts: shortestCosts,
            times: times,
            hazards: density,
            date: date,
            busyJunction: busyJunction
        )

        // Only use nodes you can both reach from the start and get back from.
        let fwd = graph.reachable(from: s)
        let back = graph.reachable(from: s, reverse: true)

        func candidateNodes(minimumDegree: Int) -> [Int] {
            var nodes: [Int] = []
            for n in 0..<graph.nodeLat.count
            where fwd[n] && back[n] && n != s
                && graph.outEdges[n].count >= minimumDegree
                && graph.inEdges[n].count >= minimumDegree {
                nodes.append(n)
            }
            return nodes
        }

        // Real junctions first (3+ ways out), so a waypoint never lands on a
        // dead end and forces a U-turn.
        var cands = candidateNodes(minimumDegree: 3)
        // Sparse rural networks — exactly where the best twisty roads live —
        // can have no junction for kilometres, and a single long back road has
        // no junction at all. Fall back to pass-through nodes on a two-way road
        // (a 220 m chunk boundary has two ways in and two ways out). This
        // cannot create the dead-end spur the junction rule guards against:
        // the search already refuses to reverse onto the road it arrived on.
        if cands.count < 4 {
            let through = candidateNodes(minimumDegree: 2)
            if through.count > cands.count { cands = through }
        }
        let minimumJunctions = max(length < 10_000 ? 3 : 4, min(30, Int(length / 5_000)))
        guard cands.count >= min(minimumJunctions, 3) else {
            return fail("the mapped roads here don't contain enough connected junctions to build a loop")
        }

        let lat0 = sv.lat, lon0 = sv.lon
        let kx = 111_320.0 * cos(lat0 * .pi / 180)
        let ky = 110_540.0

        // How far the mapped network actually extends around the start. The
        // loop template is a circle through the start, so its waypoints can be
        // twice the template radius away. Without this clamp, a 15-mile loop
        // asks for junctions outside the downloaded roads, every seed fails to
        // snap, and the rider gets "couldn't build a loop".
        let networkRadius = usableNetworkRadius(
            cands: cands, graph: graph, latitude: lat0, longitude: lon0
        )
        let capacity = networkRadius > 0
            ? 2 * Double.pi * networkRadius * 0.55 * 1.3
            : length
        // If the area genuinely cannot hold the requested distance, plan the
        // longest loop it can hold instead of failing outright.
        let target = min(length, max(capacity, 1_000))
        let stopsPerLoop: Int
        if length < 8_000 {
            stopsPerLoop = 2
        } else if length >= 30_000 {
            stopsPerLoop = 4
        } else {
            stopsPerLoop = 3
        }

        func nearest(_ latitude: Double, _ longitude: Double, maxDist: Double) -> Int? {
            var bestN: Int?
            var bestD2 = Double.infinity
            for c in cands {
                let dy = (graph.nodeLat[c] - latitude) * ky
                let dx = (graph.nodeLon[c] - longitude) * kx
                let d2 = dx * dx + dy * dy
                if d2 < bestD2 { bestD2 = d2; bestN = c }
            }
            return bestD2.squareRoot() <= maxDist ? bestN : nil
        }

        /// Waypoints sit on a circle that passes through the start; ride
        /// through them in order and come home. This is only a seed: the
        /// detour pass below decides what the loop is actually made of.
        func buildLoop(theta: Double, clockwise: Bool, radius: Double,
                       allowWrapReversal: Bool = false) -> [Int]? {
            let t = theta * .pi / 180
            let cx = radius * sin(t)
            let cy = radius * cos(t)
            let phi0 = t + .pi
            let sign = clockwise ? 1.0 : -1.0
            var stops = [s]
            for k in 1...stopsPerLoop {
                let frac = Double(k) / Double(stopsPerLoop + 1)
                let angle = phi0 + sign * 2 * Double.pi * frac
                let px = cx + radius * sin(angle)
                let py = cy + radius * cos(angle)
                let waypointSearchRadius = max(radius * 0.6, length < 10_000 ? 300 : 0)
                let desiredLatitude = lat0 + py / ky
                let desiredLongitude = lon0 + px / kx
                // The ideal waypoint may sit just outside the downloaded
                // roads. Pull it to the nearest reachable junction instead of
                // abandoning the whole template.
                let snapped = nearest(
                    desiredLatitude,
                    desiredLongitude,
                    maxDist: waypointSearchRadius
                ) ?? nearest(
                    desiredLatitude,
                    desiredLongitude,
                    maxDist: max(waypointSearchRadius * 2.5, 4_000)
                )
                guard let w = snapped else { return nil }
                if stops.last != w { stops.append(w) }
            }
            stops.append(s)

            var working = baseCosts
            var all: [Int] = []
            var previousEdge: Int?

            for i in 1..<stops.count {
                guard budget.canSearch() else { return nil }

                // A loop must flow through the junction instead of turning
                // around on the road it just came from.
                var restore = -1
                if let previousEdge, graph.twin[previousEdge] >= 0 {
                    restore = graph.twin[previousEdge]
                    working[restore] *= 1_000
                }
                let leg = budget.search(
                    graph,
                    from: stops[i - 1],
                    to: stops[i],
                    costs: working
                )
                if restore >= 0 { working[restore] /= 1_000 }

                guard let leg, !leg.isEmpty else { return nil }
                if let previousEdge, leg.first == graph.twin[previousEdge] { return nil }
                for pair in zip(leg, leg.dropFirst()) where pair.1 == graph.twin[pair.0] {
                    return nil
                }

                all += leg
                previousEdge = leg.last

                // Encourage every later leg to use a different stretch of road.
                for e in leg {
                    working[e] *= 8
                    if graph.twin[e] >= 0 { working[graph.twin[e]] *= 8 }
                }
            }

            if allowWrapReversal == false,
               let first = all.first, let last = all.last, last == graph.twin[first] {
                return nil
            }
            return all
        }

        // Seed A: a real cycle through the start on the road network. It can
        // be short or long; the detour/shortcut passes size it to the request.
        func cycleSeed() -> [Int]? {
            for e in graph.outEdges[s].prefix(4) {
                guard budget.canSearch() else { return nil }
                var working = baseCosts
                working[e] *= 6
                if graph.twin[e] >= 0 { working[graph.twin[e]] *= 6 }
                guard let back = budget.search(
                    graph,
                    from: graph.edges[e].to,
                    to: s,
                    costs: working
                ), !back.isEmpty else { continue }
                let path = [e] + back
                let lengthOfPath = path.reduce(0) { $0 + graph.edges[$1].length }
                if lengthOfPath > max(target*0.2, 1_500) { return path }
            }
            return nil
        }

        var seeds: [(path: [Int], theta: Double)] = []

        if let cycle = cycleSeed() {
            let firstEdge = graph.edges[cycle[0]]
            let theta = RoadGraph.flat(
                lat0, lon0,
                graph.nodeLat[firstEdge.to], graph.nodeLon[firstEdge.to]
            ).heading
            seeds.append((cycle, theta))
        }

        // Seed B: directional circle seeds. Enough of them for the rider to
        // see clearly different headings, not so many that the budget is gone
        // before the improvement pass runs.
        func circleSeeds(acceptError: Double,
                         allowWrapReversal: Bool = false) -> [(path: [Int], theta: Double)] {
            var found: [(path: [Int], theta: Double)] = []
            let rotationCount = 6
            for index in 0..<rotationCount {
                guard budget.canSearch() else { break }
                let theta = Double(index) * (360.0 / Double(rotationCount))
                let clockwise = index % 2 == 0
                var radius = min(length / (2 * Double.pi * 1.3), max(networkRadius * 0.55, 500))
                var chosen: (path: [Int], err: Double)?

                for _ in 0..<2 {
                    guard budget.canSearch() else { break }
                    guard let path = buildLoop(theta: theta, clockwise: clockwise,
                                               radius: radius,
                                               allowWrapReversal: allowWrapReversal) else { break }
                    let pathLength = path.reduce(0) { $0 + graph.edges[$1].length }
                    guard pathLength > 0 else { break }
                    let err = abs(pathLength / target - 1)
                    if chosen == nil || err < chosen!.err { chosen = (path, err) }
                    if err < 0.10 { break }
                    radius = min(
                        max(radius * min(max(target / pathLength, 0.6), 1.6), 400),
                        max(networkRadius * 0.60, 500)
                    )
                }

                if let chosen, chosen.err < acceptError {
                    found.append((chosen.path, theta))
                }
            }
            return found
        }

        let normalSeeds = circleSeeds(acceptError: 0.35)
        let circleSeedCount = normalSeeds.count
        seeds += normalSeeds
        if seeds.isEmpty {
            // The distance the rider asked for does not fit the roads here, but
            // a loop that is 40% short still beats telling them there is
            // nothing to ride. The label says "longest loop in this area".
            seeds = circleSeeds(acceptError: 0.70)
            if !seeds.isEmpty {
                note("These roads can't hold the distance you asked for. This is the longest loop the area allows.")
            }
        }

        // Seeded before the improvement passes spend the search budget: a
        // pocket with a single entrance only yields a loop if the route is
        // allowed to come back down the road it left on. Kept aside for the
        // best-effort pass, never mixed into the normal candidates.
        var connectorSeeds: [(path: [Int], theta: Double)] = []
        if circleSeedCount == 0, seeds.count <= 1 {
            connectorSeeds = circleSeeds(acceptError: 0.85, allowWrapReversal: true)
        }
        if seeds.isEmpty {
            let relaxed = circleSeeds(acceptError: 0.90, allowWrapReversal: true)
            if !relaxed.isEmpty {
                seeds = relaxed
                note("The only way round here shares a stretch of road. Showing the best loop the area allows.")
            }
        }

        guard !seeds.isEmpty else {
            return fail("the mapped roads here don't form a closed circuit")
        }

        // Improve the seeds that are already closest to something worth riding.
        let rankedSeeds = seeds.sorted { lhs, rhs in
            quickScore(lhs.path, model: model, target: target)
                > quickScore(rhs.path, model: model, target: target)
        }

        var candidates: [(path: [Int], theta: Double)] = []
        for seed in rankedSeeds.prefix(3) {
            guard budget.canSearch() else { break }
            let improved = improve(
                seed.path,
                target: target,
                model: model,
                budget: budget
            )
            candidates.append((improved, seed.theta))
        }
        // Always keep the best raw seed as a distance fallback.
        if let bestRaw = rankedSeeds.first {
            candidates.append(bestRaw)
        }

        // Try the clean check first. If the network cannot offer a circuit
        // without reusing a stretch of road, accept a shared connector rather
        // than handing the rider nothing. Scoring still penalises retracing, so
        // a standard loop always outranks a relaxed one.
        var scored: [(route: PlannedRoute, metrics: Metrics)] = []
        let passes: [(limits: LoopGeometry.Limits, retraceLimit: Double)] = [
            (.standard, 0.05),
            (.relaxed, 0.16),
            (.loose, 0.24)
        ]
        for pass in passes {
            for candidate in candidates {
                guard let metrics = measure(
                    candidate.path,
                    model: model,
                    target: target,
                    requested: length,
                    retraceLimit: pass.retraceLimit
                ) else { continue }
                guard let route = makeRoute(
                    path: candidate.path,
                    metrics: metrics,
                    model: model,
                    surface: surface,
                    bearing: candidate.theta,
                    requestedLength: length,
                    limits: pass.limits
                ) else { continue }
                scored.append((route, metrics))
            }
            if !scored.isEmpty { break }
        }

        if scored.isEmpty {
            // Last resort. The rider asked for a ride, not for a textbook loop.
            // Relax the distance band and the shared-road limit, and stop
            // penalising stop signs and lights: in a dense grid those are the
            // checks that reject every candidate. Better to hand over the best
            // route that exists than an error.
            var bestEffortCandidates = candidates
            for seed in connectorSeeds.prefix(2) {
                let path = improve(seed.path, target: target, model: model, budget: budget)
                if !bestEffortCandidates.contains(where: { $0.path == path }) {
                    bestEffortCandidates.append((path, seed.theta))
                }
            }

            for candidate in bestEffortCandidates {
                guard let metrics = measure(
                    candidate.path,
                    model: model,
                    target: target,
                    requested: length,
                    retraceLimit: 0.45,
                    bestEffort: true
                ) else { continue }
                guard let route = makeRoute(
                    path: candidate.path,
                    metrics: metrics,
                    model: model,
                    surface: surface,
                    bearing: candidate.theta,
                    requestedLength: length,
                    limits: .bestEffort
                ) else { continue }
                scored.append((route, metrics))
            }
            if !scored.isEmpty {
                note("No clean, quiet loop fits here. This is the best route the roads allow.")
            }
        }

        guard !scored.isEmpty else {
            return fail("no candidate passed the loop checks")
        }

        // Hard distance band first: a rider who asks for 40 miles should not
        // be handed a 28-mile loop just because it is twistier.
        let withinEight = scored.filter { abs($0.metrics.length / target - 1) <= 0.08 }
        let withinFifteen = scored.filter { abs($0.metrics.length / target - 1) <= 0.15 }
        let pool = !withinEight.isEmpty ? withinEight : (!withinFifteen.isEmpty ? withinFifteen : scored)

        var picked: [(route: PlannedRoute, metrics: Metrics)] = []
        for candidate in pool.sorted(by: { $0.metrics.score > $1.metrics.score }) {
            let overlaps = picked.contains {
                overlapFraction(candidate.route.points, $0.route.points) > 0.35
            }
            if !overlaps || picked.isEmpty {
                picked.append(candidate)
            }
            if picked.count == 3 { break }
        }
        if picked.count < 3 {
            for candidate in pool.sorted(by: { $0.metrics.score > $1.metrics.score })
            where !picked.contains(where: { $0.route.id == candidate.route.id }) {
                let duplicate = picked.contains {
                    overlapFraction(candidate.route.points, $0.route.points) > 0.60
                }
                if !duplicate { picked.append(candidate) }
                if picked.count == 3 { break }
            }
        }
        return picked.map(\.route)
    }

    // MARK: - Improvement

    /// Inserts detours around the least interesting stretches until the loop
    /// reaches the requested length, then shortcuts any overshoot.
    private static func improve(
        _ original: [Int],
        target: Double,
        model: Model,
        budget: SearchBudget
    ) -> [Int] {
        var path = original

        // Grow: replace a boring edge with a better, longer way between the
        // same two junctions while staying inside the distance budget.
        for _ in 0..<3 {
            guard budget.canSearch() else { break }
            let currentLength = model.length(of: path)
            guard currentLength < target * 0.98 else { break }
            guard let index = detourCandidate(in: path, model: model) else { break }
            let edge = model.graph.edges[path[index]]
            var working = model.costs
            working[path[index]] *= 40
            let removedTwin = model.graph.twin[path[index]]
            if removedTwin >= 0 { working[removedTwin] *= 40 }
            // Favor new road over doubling back on the current loop.
            for e in path {
                working[e] *= 3
                let twin = model.graph.twin[e]
                if twin >= 0 { working[twin] *= 3 }
            }
            guard let detour = budget.search(
                model.graph,
                from: edge.from,
                to: edge.to,
                costs: working
            ), !detour.isEmpty, !detour.contains(path[index]) else { break }

            let added = model.length(of: detour) - edge.length
            let remaining = target * 1.04 - currentLength
            guard added >= 60, added <= remaining else { break }
            path.replaceSubrange(index...index, with: detour)
        }

        // Quality swap: a loop can already be the right length and still be
        // made of the wrong roads. Replace one boring stretch with a better
        // alternative when the length stays inside the band. This is the pass
        // that actually acts on "I asked for 40 miles and got the right
        // distance but the wrong roads".
        for _ in 0..<2 {
            guard budget.canSearch(), let index = detourCandidate(in: path, model: model) else { break }
            let edge = model.graph.edges[path[index]]
            var working = model.costs
            working[path[index]] *= 12
            let replacedTwin = model.graph.twin[path[index]]
            if replacedTwin >= 0 { working[replacedTwin] *= 12 }
            for edgeIndex in path {
                working[edgeIndex] *= 2
                let twin = model.graph.twin[edgeIndex]
                if twin >= 0 { working[twin] *= 2 }
            }
            guard let detour = budget.search(
                model.graph,
                from: edge.from,
                to: edge.to,
                costs: working
            ), !detour.isEmpty, !detour.contains(path[index]) else { break }

            let newLength = model.length(of: path) - edge.length + model.length(of: detour)
            guard newLength >= target * 0.94, newLength <= target * 1.06 else { break }
            let detourValue = model.value(of: detour)
            guard detourValue > model.score(edge) + 6 else { break }
            path.replaceSubrange(index...index, with: detour)
        }

        // Trim: if the loop overshoots, replace the least valuable spans with
        // shorter connections. At most a few searches per pass.
        for _ in 0..<4 {
            guard budget.canSearch() else { break }
            let currentLength = model.length(of: path)
            guard currentLength > target * 1.02 else { break }
            guard let shortcut = bestShortcut(path, model: model, budget: budget) else { break }
            path.replaceSubrange(shortcut.range, with: shortcut.path)
        }

        return path
    }

    private static func detourCandidate(in path: [Int], model: Model) -> Int? {
        guard path.count > 4 else { return nil }
        // Never replace the first or last edge: those carry the rider out of
        // and back into the start, and keeping them keeps the loop a loop.
        let inner = 1..<(path.count - 1)
        guard let index = inner.min(by: {
            model.score(model.graph.edges[path[$0]]) < model.score(model.graph.edges[path[$1]])
        }) else { return nil }
        // If even the worst edge is decent, a detour is unlikely to help.
        guard model.score(model.graph.edges[path[index]]) < 60 else { return nil }
        return index
    }

    private static func bestShortcut(
        _ path: [Int],
        model: Model,
        budget: SearchBudget
    ) -> (range: Range<Int>, path: [Int])? {
        guard path.count > 6 else { return nil }
        // Rank candidate spans by how little riding value they carry, then try
        // a handful. This keeps the pass to a few dozen searches.
        var spans: [(start: Int, end: Int, value: Double)] = []
        for start in 1..<(path.count - 2) {
            let end = min(start + 1, path.count - 2)
            let value = model.score(model.graph.edges[path[start]])
                + model.score(model.graph.edges[path[end]])
            spans.append((start, end, value))
        }
        spans.sort { $0.value < $1.value }

        var best: (range: Range<Int>, path: [Int], saving: Double)?
        for span in spans.prefix(4) {
            guard budget.canSearch() else { break }
            let from = model.graph.edges[path[span.start]].from
            let to = model.graph.edges[path[span.end]].to
            var working = model.shortestCosts
            for index in span.start...span.end {
                working[path[index]] *= 20
                let twin = model.graph.twin[path[index]]
                if twin >= 0 { working[twin] *= 20 }
            }
            guard let alternate = budget.search(
                model.graph,
                from: from,
                to: to,
                costs: working
            ), !alternate.isEmpty else { continue }

            let spanLength = (span.start...span.end).reduce(0.0) {
                $0 + model.graph.edges[path[$1]].length
            }
            let alternateLength = alternate.reduce(0.0) {
                $0 + model.graph.edges[$1].length
            }
            let saving = spanLength - alternateLength
            guard saving >= 120 else { continue }
            if best == nil || saving > best!.saving {
                best = (span.start..<(span.end + 1), alternate, saving)
            }
        }
        return best.map { ($0.range, $0.path) }
    }

    // MARK: - Metrics

    nonisolated private struct Metrics {
        let length: Double
        let value: Double
        let twistPerKm: Double
        let flow: Double
        let lap: Double
        let retraced: Double
        let interruptions: Int
        let timeSeconds: Double
        let score: Double
    }

    private static func quickScore(_ path: [Int], model: Model, target: Double) -> Double {
        let length = model.length(of: path)
        guard length > 0 else { return -.infinity }
        let error = abs(length / target - 1)
        return model.value(of: path) - error * 120
    }

    private static func measure(
        _ path: [Int],
        model: Model,
        target: Double,
        requested: Double,
        retraceLimit: Double = 0.05,
        bestEffort: Bool = false
    ) -> Metrics? {
        guard path.count >= 3 else { return nil }
        let length = model.length(of: path)
        guard length > 200 else { return nil }

        var weightedValue = 0.0
        var weightedTwist = 0.0
        var weightedSweeper = 0.0
        var seenSegments = Set<Int>()
        var repeated = 0.0
        var interruptions = 0

        for edgeIndex in path {
            let edge = model.graph.edges[edgeIndex]
            weightedValue += model.score(edge) * edge.length
            weightedTwist += edge.twist * edge.length
            weightedSweeper += edge.sweeperShare * edge.length
            if !seenSegments.insert(edge.seg).inserted { repeated += edge.length }
            if model.busyJunction[edge.to] { interruptions += 1 }
            if let hazards = model.hazards {
                let (latitude, longitude) = midpoint(edge, in: model.graph)
                interruptions += hazards.interruptionCount(
                    latitude: latitude, longitude: longitude, date: model.date
                )
            }
        }

        // No immediate reversal anywhere: that includes the wrap-around from
        // the last edge back onto the first. Best effort allows the wrap one,
        // because a loop out of a single-entrance pocket finishes by riding
        // back down the road it left on; geometry checks still reject a plain
        // out-and-back.
        for pair in zip(path, path.dropFirst()) where pair.1 == model.graph.twin[pair.0] {
            return nil
        }
        if !bestEffort, let first = path.first, let last = path.last,
           last == model.graph.twin[first] {
            return nil
        }

        let value = weightedValue / length
        let twist = weightedTwist / length
        let flow = min(weightedSweeper / length * 100, 100)
        let retraced = repeated / length
        guard retraced < retraceLimit else { return nil }

        let lap = lapScore(path, model: model)
        let time = path.reduce(0.0) { $0 + model.times[$1] }
        let closure = closureDistance(path, model: model)
        // Best effort accepts a loop that does not close as tightly and misses
        // the requested distance by more. It is still a loop the rider can
        // ride; the alternative was an error screen.
        guard closure < (bestEffort ? 600 : 250) else { return nil }

        let distanceError = abs(length / target - 1)
        // If the area forced the target down, a short loop is expected.
        let maximumError = bestEffort ? 0.75 : (requested > target * 1.02 ? 0.60 : 0.35)
        guard distanceError <= maximumError else { return nil }

        let retracePenalty = min(100, retraced * 1_500)
        // Stop signs and lights are a comfort preference, not a safety rule.
        // When nothing else fits, stop penalising them so the rider gets the
        // best route the area has instead of "couldn't build a loop".
        let interruptionPenalty = bestEffort
            ? 0
            : min(100, Double(interruptions) / max(length / 1_000, 0.5) * 12)
        let closureScore = max(0, 100 - closure / 2.5)
        let quality = 0.45 * value
            + 0.15 * flow
            + 0.12 * lap
            + 0.10 * (100.0 - retracePenalty)
            + 0.08 * (100.0 - interruptionPenalty)
            + 0.10 * closureScore
        // Strong, but still gradient-friendly so the search can tell a 30%
        // overshoot from a 10% one.
        let penalty = min(45.0, distanceError * 220.0)
        let score = quality - penalty

        return Metrics(
            length: length,
            value: value,
            twistPerKm: twist,
            flow: flow,
            lap: lap,
            retraced: retraced,
            interruptions: interruptions,
            timeSeconds: time,
            score: clamp(score, 0, 100)
        )
    }

    private static func lapScore(_ path: [Int], model: Model) -> Double {
        let total = model.length(of: path)
        guard total > 0 else { return 0 }
        var valueByBucket = [Double](repeating: 0, count: 4)
        var lengthByBucket = [Double](repeating: 0, count: 4)
        var travelled = 0.0
        for edgeIndex in path {
            let edge = model.graph.edges[edgeIndex]
            let midpoint = travelled + edge.length / 2
            let bucket = min(3, Int(midpoint / total * 4))
            valueByBucket[bucket] += model.score(edge) * edge.length
            lengthByBucket[bucket] += edge.length
            travelled += edge.length
        }
        var averages = [Double](repeating: 0, count: 4)
        for index in 0..<4 where lengthByBucket[index] > 0 {
            averages[index] = valueByBucket[index] / lengthByBucket[index]
        }
        let mean = averages.reduce(0, +) / 4
        guard mean > 0 else { return 0 }
        let spread = averages.map { abs($0 - mean) }.reduce(0, +) / 4 / mean
        return clamp(100 - spread * 100, 0, 100)
    }

    private static func closureDistance(_ path: [Int], model: Model) -> Double {
        guard let first = path.first, let last = path.last else { return 0 }
        return RoadGraph.flat(
            model.graph.nodeLat[model.graph.edges[first].from],
            model.graph.nodeLon[model.graph.edges[first].from],
            model.graph.nodeLat[model.graph.edges[last].to],
            model.graph.nodeLon[model.graph.edges[last].to]
        ).dist
    }

    private static func overlapFraction(
        _ lhs: [RoutePoint],
        _ rhs: [RoutePoint]
    ) -> Double {
        guard lhs.count > 1, rhs.count > 1 else { return 0 }
        // Sample both polylines and count proximity. Chunk-level overlap is
        // already handled by the distance band; this catches shapes that are
        // visually the same route.
        let sampleCount = 64
        let lhsSamples = stride(from: 0, to: lhs.count, by: max(1, lhs.count / sampleCount)).map { lhs[$0] }
        let rhsSamples = stride(from: 0, to: rhs.count, by: max(1, rhs.count / sampleCount)).map { rhs[$0] }
        let matches = lhsSamples.filter { point in
            rhsSamples.contains { other in
                RoadGraph.flat(point.lat, point.lon, other.lat, other.lon).dist < 60
            }
        }.count
        return Double(matches) / Double(max(lhsSamples.count, 1))
    }

    /// 90th-percentile distance from the start to a usable junction. A single
    /// outlier road should not make the planner believe the network is huge.
    private static func usableNetworkRadius(
        cands: [Int],
        graph: RoadGraph,
        latitude: Double,
        longitude: Double
    ) -> Double {
        guard !cands.isEmpty else { return 0 }
        let distances = cands
            .map { RoadGraph.flat(latitude, longitude, graph.nodeLat[$0], graph.nodeLon[$0]).dist }
            .sorted()
        let index = min(distances.count - 1, Int(Double(distances.count) * 0.9))
        return distances[index]
    }

    private static func busyJunctions(in graph: RoadGraph) -> [Bool] {
        // Four ways out means a full crossroad, not a T junction. Counting
        // distinct road ids undercounted those (a normal four-way crossing is
        // two roads meeting) and made the metric meaningless.
        (0..<graph.nodeLat.count).map { node in
            graph.outEdges[node].count >= 4
        }
    }

    // MARK: - Route construction

    private static func makeRoute(
        path: [Int],
        metrics: Metrics,
        model: Model,
        surface: LoopSurface,
        bearing: Double,
        requestedLength: Double,
        limits: LoopGeometry.Limits = .standard
    ) -> PlannedRoute? {
        let points = model.graph.points(for: path)
        guard points.count > 3 else { return nil }
        let byID = Dictionary(model.graph.roads.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var route = PlannedRoute(
            points: points,
            roads: byID,
            twistPerKm: metrics.twistPerKm,
            retraced: metrics.retraced,
            bearing: bearing,
            expectedTravelTime: metrics.timeSeconds,
            overallScore: metrics.score,
            flowScore: metrics.flow,
            lapScore: metrics.lap,
            interruptions: metrics.interruptions,
            scoreLabel: label(for: metrics, surface: surface, requestedLength: requestedLength),
            kind: .loop
        )
        route.surface = surface
        let uTurns = route.steps.filter { $0.turn == .uTurn }.count
        guard uTurns == 0 else { return nil }
        let analysis = LoopGeometry.analyze(
            points.map(\.coordinate),
            ignoreStartMeters: 250,
            ignoreEndMeters: 250
        )
        guard LoopGeometry.isLapable(analysis, limits: limits) else { return nil }
        return route
    }

    private static func label(
        for metrics: Metrics,
        surface: LoopSurface,
        requestedLength: Double
    ) -> String {
        // Only call it "longest" when the result is genuinely much shorter
        // than the request; a loop 10% short is just a loop 10% short.
        if metrics.length < requestedLength * 0.85 {
            return "Longest loop in this area"
        }
        if surface != .paved { return "\(surface.title) loop" }
        if metrics.value >= 58 { return "Twistiest" }
        if metrics.flow >= 35 { return "Flowing sweepers" }
        if metrics.lap >= 55 { return "Balanced lap" }
        return "Best overall"
    }

    // MARK: - Reroute
    /// A way back onto `route` from where the rider is now, rejoining at point `j` and following the old route from there.
    nonisolated static func reroute(roads: [Road], route: PlannedRoute, from c: CLLocationCoordinate2D, rejoinAt j: Int) -> PlannedRoute? {
        guard j < route.points.count, let a = nearestVertex(roads, to: c), a.dist < 400 else { return nil }
        let target = route.points[j]
        let tKey = RoadGraph.key(target.lat, target.lon)
        let graph = RoadGraph(roads: roads, forced: [a.key, tKey], includeUnpaved: true)
        guard let s = graph.node(forKey: a.key), let t = graph.node(forKey: tKey) else { return nil }

        let plain = graph.edges.map { $0.length * classFactor(graph.roads[$0.road].highway) }
        guard let path = graph.shortestPath(from: s, to: t, costs: plain) else { return nil }

        var pts = graph.points(for: path)
        if pts.isEmpty { pts = [target] }
        if j + 1 < route.points.count {
            pts += route.points[(j + 1)...]
        }
        guard pts.count > 2 else { return nil }

        let byID = Dictionary(roads.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return PlannedRoute(points: pts, roads: byID, twistPerKm: route.twistPerKm,
                            retraced: route.retraced, bearing: route.bearing)
    }

    // MARK: - Support types

    nonisolated private struct Model {
        let graph: RoadGraph
        let costs: [Double]
        let profile: TwistProfile?
        let shortestCosts: [Double]
        let times: [Double]
        let hazards: HazardDensity?
        let date: Date
        let busyJunction: [Bool]

        func length(of path: [Int]) -> Double {
            path.reduce(0) { $0 + graph.edges[$1].length }
        }

        /// 0...100 curvature score for one edge, relative to the local profile.
        func score(_ edge: RoadGraph.Edge) -> Double {
            (profile?.effective(edge.raw) ?? edge.value / 100) * 100
        }

        func value(of path: [Int]) -> Double {
            let total = length(of: path)
            guard total > 0 else { return 0 }
            return path.reduce(0.0) { $0 + score(graph.edges[$1]) * graph.edges[$1].length } / total
        }
    }

    /// Counts point-to-point searches so a pathological network cannot spin.
    nonisolated private final class SearchBudget {
        let deadline: Date
        var searches = 0
        let maximumSearches: Int

        init(deadline: Date, maximumSearches: Int = 90) {
            self.deadline = deadline
            self.maximumSearches = maximumSearches
        }

        func canSearch() -> Bool {
            !Task.isCancelled && Date() < deadline && searches < maximumSearches
        }

        func search(
            _ graph: RoadGraph,
            from: Int,
            to: Int,
            costs: [Double]
        ) -> [Int]? {
            guard canSearch() else { return nil }
            searches += 1
            return graph.shortestPath(from: from, to: to, costs: costs, deadline: deadline)
        }
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
