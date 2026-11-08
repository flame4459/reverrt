import Foundation
import CoreLocation
import MapKit
import Observation
import UIKit

/// Coordinates loop generation and point-to-point directions.
@Observable
final class RoutePlanner {
    enum Phase: Equatable {
        case idle
        case downloading(done: Int, total: Int)
        case planning
        case routing
        case failed(String)
        case done
    }

    var phase: Phase = .idle
    var progress = 0.0
    var elevationLoading = false
    var results: [PlannedRoute] = []
    var localResults: [PlannedRoute] = []
    var localRoutesLoading = false
    var localRoutesError: String?
    var prefetchingRoads = false
    /// A non-fatal fact about the current results, e.g. the start was snapped
    /// to the nearest mapped road.
    var notice: String?
    private(set) var roads: [Road] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var localSearchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchID = UUID()
    @ObservationIgnored private var loopCache: LoopCache?
    @ObservationIgnored private var localCache: (latitude: Double, longitude: Double, results: [PlannedRoute])?
    @ObservationIgnored private var generationID = UUID()

    private struct LoopCache {
        let latitude: Double
        let longitude: Double
        let miles: Double
        let style: RouteStyle
        let mode: LoopMode
        let surface: LoopSurface
        let shapingPins: [CLLocationCoordinate2D]
        let results: [PlannedRoute]
        let roads: [Road]
        let preferredRoads: [String]
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .planning, .routing: true
        default: false
        }
    }

    func generate(
        start: CLLocationCoordinate2D,
        miles: Double,
        style: RouteStyle,
        mode: LoopMode,
        surface: LoopSurface = .paved,
        shapingPins: [CLLocationCoordinate2D] = [],
        prefersPasses: Bool = false,
        preferredRoads: [String] = []
    ) {
        let id = UUID()
        generationID = id

        if let loopCache,
           loopCache.style == style,
           loopCache.mode == mode,
           loopCache.surface == surface,
           Self.samePins(loopCache.shapingPins, shapingPins),
           loopCache.preferredRoads == preferredRoads,
           abs(loopCache.miles - miles) < 0.1,
           CLLocation(latitude: loopCache.latitude, longitude: loopCache.longitude)
               .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) < 250 {
            task?.cancel()
            results = loopCache.results
            roads = loopCache.roads
            notice = nil
            phase = .done
            return
        }

        task?.cancel()
        // Background discovery and prefetch compete for the same network.
        // The plan owns it from here; a stale prefetch is the reason a first
        // tap could sit behind a much larger download.
        localSearchTask?.cancel()
        prefetchTask?.cancel()
        prefetchingRoads = false
        localRoutesLoading = false
        results = []
        roads = []
        notice = nil
        progress = 0
        let planningTask = Task {
            await run(
                start: start,
                length: miles * 1609.344,
                style: style,
                mode: mode,
                surface: surface,
                shapingPins: shapingPins,
                prefersPasses: prefersPasses,
                preferredRoads: preferredRoads
            )
        }
        task = planningTask

        // Hard ceiling. Whatever has been found by 27 seconds is what the
        // rider gets; they should never sit in front of a spinner forever.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 32_000_000_000)
            guard let self else { return }
            await MainActor.run {
                guard self.generationID == id else { return }
                if self.isBusy {
                    if self.results.isEmpty {
                        self.phase = .failed("Route generation is taking too long. Try a shorter distance or a different start point.")
                    } else {
                        self.phase = .done
                    }
                }
                self.progress = 1
                planningTask.cancel()
            }
        }
    }

    func directions(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D] = [],
        surface: LoopSurface = .paved,
        preference: DirectionPreference
    ) {
        task?.cancel()
        results = []
        roads = []
        phase = .idle
        if via.isEmpty {
            let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
            // Tapping Home while parked at home used to produce a 0.0 mi
            // "route" with a Start navigation button. Say so instead.
            if distance < 30 {
                phase = .failed("You're already there. Pick a destination away from your current spot.")
                return
            }
        }
        task = Task {
            await requestDirections(from: start, to: destination, via: via, surface: surface, preference: preference)
        }
    }

    /// Starts warming the OSM cache while the rider is still choosing a
    /// distance or style. By the time they tap Find scenic loops, the area is
    /// often already on disk and the graph fallback is instant.
    func prefetchRoads(
        around center: CLLocationCoordinate2D,
        miles: Double,
        surface: LoopSurface = .paved
    ) {
        // Above the MapKit threshold the graph planner is not used, so do not
        // pull a large area off the network for a 1,000-mile slider value.
        guard miles <= 50 else { return }
        // A prefetch is a head start, not the plan. The default slider value
        // is 40 miles, which with a correct loop extent is an 18 km radius —
        // a huge Overpass request that made the first real plan look stuck.
        let radiusKm = min(Self.planningRadiusKm(forMiles: miles), 8.0)
        let id = UUID()
        prefetchID = id
        prefetchTask?.cancel()
        prefetchingRoads = true
        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            // Debounce slider changes; only the last distance matters.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await RoadStore.area(center: center, radiusKm: radiusKm, surface: surface)
            // The outer `[weak self]` makes `self` a mutable weak box, which a
            // concurrently-executing closure may not touch. Re-capturing it
            // weakly here gives this hop its own immutable optional binding.
            await MainActor.run { [weak self] in
                guard let self, self.prefetchID == id else { return }
                self.prefetchingRoads = false
            }
        }
    }

    static func planningRadiusKm(forMiles miles: Double) -> Double {
        let length = miles * 1_609.344
        // The loop template is a circle *through the start*, so a waypoint can
        // be twice the template radius from the start. Sizing the area to one
        // radius (the old formula) put the far waypoints outside the downloaded
        // roads: a 15-mile plan in New Hyde Park could never build.
        // Max distance is length / (pi * 1.3); add a small buffer.
        return min(max(length / (Double.pi * 1_300) + 1.5, 3.0), 20)
    }

    private static func samePins(_ a: [CLLocationCoordinate2D], _ b: [CLLocationCoordinate2D]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            if RoadGraph.flat(lhs.latitude, lhs.longitude, rhs.latitude, rhs.longitude).dist > 15 { return false }
        }
        return true
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    /// Dismisses the current route preview as well as any request in flight.
    /// Cancelling alone left `results` populated, so closing the preview
    /// immediately re-showed the route the rider just dismissed.
    func clearResults() {
        task?.cancel()
        task = nil
        phase = .idle
        progress = 0
        results = []
        roads = []
        notice = nil
    }

    @MainActor
    private func logFailure(_ message: String) {
        RiderDiagnostics.log("route failure: \(message)")
    }

    private func requestDirections(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D],
        surface: LoopSurface,
        preference: DirectionPreference
    ) async {
        phase = .routing

        // A normal A→B search can give the rider genuine alternatives. The
        // multi-stop path below still needs one route per leg so the choices
        // stay combinable.
        if via.isEmpty {
            do {
                let request = MKDirections.Request()
                request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
                request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
                request.transportType = .automobile
                request.departureDate = Date()
                request.requestsAlternateRoutes = true
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled else { phase = .idle; return }
                let ordered = Self.orderRoutes(response.routes, preference: preference)
                guard !ordered.isEmpty else {
                    logFailure("no driving route")
                phase = .failed("No driving route is available for that destination.")
                    return
                }
                let planned = ordered.prefix(3).map { PlannedRoute(mapRoute: $0) }
                results = planned
                phase = .done
                if let first = planned.first {
                    await attachElevation(to: first.id, prefersPasses: false)
                }
                return
            } catch {
                guard !Task.isCancelled else { phase = .idle; return }
                logFailure("directions request failed")
                phase = .failed("Couldn't get directions to that destination. Check your connection and try again.")
                return
            }
        }

        let stops = [start] + via + [destination]
        do {
            var legs = [MKRoute?](repeating: nil, count: stops.count - 1)
            try await withThrowingTaskGroup(of: (Int, MKRoute).self) { group in
                for index in 0..<(stops.count - 1) {
                    let from = stops[index]
                    let to = stops[index + 1]
                    group.addTask {
                        let request = MKDirections.Request()
                        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
                        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
                        request.transportType = .automobile
                        request.departureDate = Date()
                        request.requestsAlternateRoutes = true
                        let response = try await MKDirections(request: request).calculate()
                        guard let route = Self.selectRoute(response.routes, preference: preference) else {
                            throw URLError(.resourceUnavailable)
                        }
                        return (index, route)
                    }
                }
                for try await (index, route) in group {
                    legs[index] = route
                }
            }
            guard !Task.isCancelled else {
                phase = .idle
                return
            }
            guard legs.allSatisfy({ $0 != nil }) else {
                logFailure("no driving route")
                phase = .failed("No driving route is available for that destination.")
                return
            }
            let combined = PlannedRoute(mapRoutes: legs.compactMap { $0 }, waypoints: via, surface: surface)
            results = [combined]
            phase = .done
            await attachElevation(to: combined.id, prefersPasses: false)
        } catch {
            guard !Task.isCancelled else {
                phase = .idle
                return
            }
            phase = .failed("Couldn't get directions to that destination. Check your connection and try again.")
        }
    }

    nonisolated private static func selectRoute(_ routes: [MKRoute], preference: DirectionPreference) -> MKRoute? {
        orderRoutes(routes, preference: preference).first
    }

    /// Best-first ordering for the full list of MapKit alternates.
    nonisolated private static func orderRoutes(_ routes: [MKRoute], preference: DirectionPreference) -> [MKRoute] {
        switch preference {
        case .fastest:
            return routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime }
        case .fun:
            return routes.sorted { funScore($0) > funScore($1) }
        case .sporty:
            return routes.sorted { sportyScore($0) > sportyScore($1) }
        }
    }

    nonisolated private static func funScore(_ route: MKRoute) -> Double {
        let highwayPenalty = route.hasHighways ? 0.65 : 1.0
        let tollPenalty = route.hasTolls ? 0.85 : 1.0
        let turnVariety = Double(turnCount(in: route)) * 500
        return (route.distance * highwayPenalty * tollPenalty) + turnVariety
    }

    nonisolated private static func sportyScore(_ route: MKRoute) -> Double {
        let highwayPenalty = route.hasHighways ? 0.45 : 1.0
        let turnScore = Double(turnCount(in: route)) * 1_200
        return (route.distance * highwayPenalty) + turnScore
    }

    nonisolated private static func turnCount(in route: MKRoute) -> Int {
        route.steps.filter { step in
            let instruction = step.instructions.lowercased()
            return instruction.contains("turn")
                || instruction.contains("curve")
                || instruction.contains("roundabout")
                || instruction.contains("bear")
                || instruction.contains("fork")
        }.count
    }

    private func mapKitLoop(start: CLLocationCoordinate2D, length: Double) async -> PlannedRoute? {
        let radius = length / (2 * Double.pi * 1.3)
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(start.latitude * .pi / 180)
        let offsets: [(Double, Double)] = [
            (radius * 0.86, radius * 0.50),
            (-radius * 0.43, radius * 0.75),
            (-radius * 0.43, -radius * 0.75)
        ]
        let waypoints = offsets.map { east, north in
            CLLocationCoordinate2D(
                latitude: start.latitude + north / latitudeScale,
                longitude: start.longitude + east / longitudeScale
            )
        }
        let points = [start, waypoints[0], waypoints[1], waypoints[2], start]

        do {
            let routes = try await withThrowingTaskGroup(of: (Int, MKRoute).self) { group in
                for index in 0..<4 {
                    group.addTask {
                        let request = MKDirections.Request()
                        request.source = MKMapItem(
                            location: CLLocation(latitude: points[index].latitude, longitude: points[index].longitude),
                            address: nil
                        )
                        request.destination = MKMapItem(
                            location: CLLocation(latitude: points[index + 1].latitude, longitude: points[index + 1].longitude),
                            address: nil
                        )
                        request.transportType = .automobile
                        request.requestsAlternateRoutes = false
                        let response = try await MKDirections(request: request).calculate()
                        guard let route = response.routes.first else {
                            throw URLError(.resourceUnavailable)
                        }
                        return (index, route)
                    }
                }

                var output = Array<MKRoute?>(repeating: nil, count: 4)
                while let (index, route) = try await group.next() {
                    output[index] = route
                }
                return output.compactMap { $0 }
            }

            guard routes.count == 4 else { return nil }
            var routePoints: [RoutePoint] = []
            for (index, route) in routes.enumerated() {
                var coordinates = [CLLocationCoordinate2D](
                    repeating: kCLLocationCoordinate2DInvalid,
                    count: route.polyline.pointCount
                )
                route.polyline.getCoordinates(
                    &coordinates,
                    range: NSRange(location: 0, length: coordinates.count)
                )
                let legPoints = coordinates.map {
                    RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0)
                }
                routePoints += index == 0 ? legPoints : Array(legPoints.dropFirst())
            }

            guard routePoints.count > 2 else { return nil }
            // The last line of defence: never show a loop with a U-turn or an
            // out-and-back spur, even when the offline graph is unavailable.
            guard !LoopGeometry.containsUTurn(routes) else { return nil }
            let analysis = LoopGeometry.analyze(
                routePoints.map(\.coordinate),
                ignoreStartMeters: 250,
                ignoreEndMeters: 250
            )
            guard LoopGeometry.isLapable(analysis)
                || LoopGeometry.isLapable(analysis, limits: .relaxed) else { return nil }
            return PlannedRoute(
                points: routePoints,
                roads: [:],
                twistPerKm: 0,
                retraced: 0,
                bearing: 0
            )
        } catch {
            return nil
        }
    }

    /// A three-leg loop through two waypoints. Fewer failure points than the
    /// four-leg template, so it still produces a ride when one of four legs
    /// would have failed.
    private func mapKitTriangleLoop(
        start: CLLocationCoordinate2D,
        length: Double
    ) async -> PlannedRoute? {
        let radius = length / (2 * Double.pi * 1.3)
        let center = Self.destination(from: start, bearingDegrees: 0, distanceMeters: radius)
        let first = Self.destination(from: center, bearingDegrees: 120, distanceMeters: radius)
        let second = Self.destination(from: center, bearingDegrees: 240, distanceMeters: radius)
        let stops = [start, first, second, start]

        async let firstLeg = Self.mapRoute(from: stops[0], to: stops[1])
        async let secondLeg = Self.mapRoute(from: stops[1], to: stops[2])
        async let lastLeg = Self.mapRoute(from: stops[2], to: stops[3])
        let resolved = await [firstLeg, secondLeg, lastLeg]
        let legs = resolved.compactMap { $0 }
        guard legs.count == 3 else { return nil }
        guard !LoopGeometry.containsUTurn(legs) else { return nil }

        var points: [RoutePoint] = []
        for (index, route) in legs.enumerated() {
            let legPoints = Self.mapPoints(route)
            points += index == 0 ? legPoints : Array(legPoints.dropFirst())
        }
        guard points.count > 3 else { return nil }
        guard let firstPoint = points.first, let lastPoint = points.last else { return nil }
        guard RoadGraph.flat(firstPoint.lat, firstPoint.lon, lastPoint.lat, lastPoint.lon).dist < 250 else {
            return nil
        }
        let analysis = LoopGeometry.analyze(
            points.map(\.coordinate),
            ignoreStartMeters: 250,
            ignoreEndMeters: 250
        )
        guard LoopGeometry.isLapable(analysis)
            || LoopGeometry.isLapable(analysis, limits: .relaxed) else { return nil }

        let measured = Curvature.measure(points: points)
        return PlannedRoute(
            points: points,
            roads: [:],
            twistPerKm: measured.degreesPerKm,
            retraced: analysis.repeatedFraction,
            bearing: RoadGraph.flat(
                start.latitude, start.longitude,
                first.latitude, first.longitude
            ).heading,
            expectedTravelTime: legs.reduce(0) { $0 + $1.expectedTravelTime }
        )
    }

    /// Builds a loop from two *alternate* Apple routes to the same
    /// destination: out on one, back on the other. This needs no Overpass data
    /// and avoids waypoint snapping entirely, so it still works in rural areas
    /// where the bulk road download times out.
    private func mapKitAlternateLoop(
        start: CLLocationCoordinate2D,
        length: Double
    ) async -> PlannedRoute? {
        let halfDistance = max(length / 2, 800)
        for bearing in stride(from: 0.0, to: 360.0, by: 90.0) {
            guard !Task.isCancelled else { return nil }
            let destination = Self.destination(
                from: start,
                bearingDegrees: bearing,
                distanceMeters: halfDistance
            )
            let request = MKDirections.Request()
            request.source = MKMapItem(
                location: CLLocation(latitude: start.latitude, longitude: start.longitude),
                address: nil
            )
            request.destination = MKMapItem(
                location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
                address: nil
            )
            request.transportType = .automobile
            request.requestsAlternateRoutes = true
            guard let response = try? await MKDirections(request: request).calculate(),
                  response.routes.count >= 2 else { continue }

            let outbound = response.routes[0]
            let inbound = response.routes[1]
            let outPoints = Self.mapPoints(outbound)
            let backPoints = Self.mapPoints(inbound)
            guard outPoints.count > 2, backPoints.count > 2 else { continue }

            var points = outPoints
            points += backPoints.dropFirst()
            guard points.count > 4,
                  let first = points.first,
                  let last = points.last,
                  RoadGraph.flat(first.lat, first.lon, last.lat, last.lon).dist < 250 else {
                continue
            }

            let analysis = LoopGeometry.analyze(
                points.map(\.coordinate),
                ignoreStartMeters: 50,
                ignoreEndMeters: 50
            )
            guard analysis.repeatedFraction < 0.10,
                  analysis.longestSpurMeters < 40 else { continue }

            // If the "alternate" is the same road back, the loop ends in a
            // U-turn at the far point. Reject that geometry.
            let join = outPoints.count - 1
            guard let arrival = Self.heading(points, at: join, backwards: true),
                  let departure = Self.heading(points, at: join, backwards: false) else { continue }
            var angle = departure - arrival
            while angle > 180 { angle -= 360 }
            while angle < -180 { angle += 360 }
            guard abs(angle) < 120 else { continue }

            let measured = Curvature.measure(points: points)
            return PlannedRoute(
                points: points,
                roads: [:],
                twistPerKm: measured.degreesPerKm,
                retraced: analysis.repeatedFraction,
                bearing: bearing,
                expectedTravelTime: outbound.expectedTravelTime + inbound.expectedTravelTime,
                overallScore: 55,
                flowScore: min(measured.sweeperShare * 100, 100),
                lapScore: nil,
                interruptions: nil,
                scoreLabel: "Live map loop"
            )
        }
        return nil
    }

    private static func heading(
        _ points: [RoutePoint],
        at index: Int,
        backwards: Bool,
        lookAheadMeters: Double = 40
    ) -> Double? {
        guard index > 0, index < points.count - 1 else { return nil }
        var travelled = 0.0
        if backwards {
            var cursor = index
            while cursor > 0, travelled < lookAheadMeters {
                travelled += RoadGraph.flat(
                    points[cursor - 1].lat, points[cursor - 1].lon,
                    points[cursor].lat, points[cursor].lon
                ).dist
                cursor -= 1
            }
            guard travelled > 1 else { return nil }
            return RoadGraph.flat(
                points[cursor].lat, points[cursor].lon,
                points[index].lat, points[index].lon
            ).heading
        } else {
            var cursor = index
            while cursor < points.count - 1, travelled < lookAheadMeters {
                travelled += RoadGraph.flat(
                    points[cursor].lat, points[cursor].lon,
                    points[cursor + 1].lat, points[cursor + 1].lon
                ).dist
                cursor += 1
            }
            guard travelled > 1 else { return nil }
            return RoadGraph.flat(
                points[index].lat, points[index].lon,
                points[cursor].lat, points[cursor].lon
            ).heading
        }
    }

    private func mapKitAlternateLoopWithTimeout(
        start: CLLocationCoordinate2D,
        length: Double,
        timeoutSeconds: TimeInterval
    ) async -> PlannedRoute? {
        await withTaskGroup(of: PlannedRoute?.self) { group in
            group.addTask { await self.mapKitAlternateLoop(start: start, length: length) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func destination(
        from origin: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let angular = distanceMeters / earthRadius
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func mapKitTriangleLoopWithTimeout(
        start: CLLocationCoordinate2D,
        length: Double,
        timeoutSeconds: TimeInterval
    ) async -> PlannedRoute? {
        await withTaskGroup(of: PlannedRoute?.self) { group in
            group.addTask { await self.mapKitTriangleLoop(start: start, length: length) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func mapKitLoopWithTimeout(start: CLLocationCoordinate2D, length: Double,
                                       timeoutSeconds: TimeInterval = 75) async -> PlannedRoute? {
        await withTaskGroup(of: PlannedRoute?.self) { group in
            group.addTask {
                await self.mapKitLoop(start: start, length: length)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Finds established scenic destinations within roughly 50 miles and builds
    /// three selectable loops through them. MapKit supplies the current local places.
    func discoverLocalRoutes(center: CLLocationCoordinate2D) {
        // Never compete with the main route search for MapKit bandwidth.
        guard !isBusy, !localRoutesLoading else { return }
        localSearchTask?.cancel()

        if let localCache,
           CLLocation(latitude: localCache.latitude, longitude: localCache.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 5_000 {
            localResults = localCache.results
            localRoutesError = localCache.results.isEmpty
                ? "No established scenic routes were found nearby. Try dropping a pin in a different area."
                : nil
            localRoutesLoading = false
            return
        }
        localRoutesError = nil
        localResults = []
        localRoutesLoading = true

        localSearchTask = Task {
            let routes = await Self.makeLocalRoutes(center: center)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.localResults = routes
                self.localRoutesLoading = false
                self.localRoutesError = routes.isEmpty
                    ? "No established scenic routes were found nearby. Try dropping a pin in a different area."
                    : nil
                if !routes.isEmpty {
                    self.localCache = (center.latitude, center.longitude, routes)
                }
            }
        }
    }

    private static func makeLocalRoutes(center: CLLocationCoordinate2D) async -> [PlannedRoute] {
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 80_000,
            longitudinalMeters: 80_000
        )
        let searches = [
            "motorcycle scenic route",
            "scenic byway",
            "scenic drive",
            "scenic overlook",
            "state park"
        ]
        var places: [MKMapItem] = []

        await withTaskGroup(of: [MKMapItem].self) { group in
            for query in searches {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    request.region = region
                    request.resultTypes = [.pointOfInterest]

                    guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
                    return response.mapItems
                }
            }
            for await items in group {
                places.append(contentsOf: items)
            }
        }

        var seen = Set<String>()
        let destinations = places
            .filter { item in
                let coordinate = item.location.coordinate
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                guard distance > 8_000 && distance <= 80_000 else { return false }
                let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
                return seen.insert(key).inserted
            }
            .sorted {
                let a = $0.location.distance(
                    from: CLLocation(latitude: center.latitude, longitude: center.longitude)
                )
                let b = $1.location.distance(
                    from: CLLocation(latitude: center.latitude, longitude: center.longitude)
                )
                return a < b
            }

        guard destinations.count >= 4 else { return [] }

        var output: [PlannedRoute] = []
        for index in 0..<min(3, destinations.count - 1) {
            let first = destinations[index]
            let second = destinations[(index + 2) % destinations.count]
            let firstCoordinate = first.location.coordinate
            let secondCoordinate = second.location.coordinate
            async let firstLegRequest = mapRoute(from: center, to: firstCoordinate)
            async let secondLegRequest = mapRoute(from: firstCoordinate, to: secondCoordinate)
            async let finalLegRequest = mapRoute(from: secondCoordinate, to: center)
            let (firstLeg, secondLeg, finalLeg) = await (firstLegRequest, secondLegRequest, finalLegRequest)
            guard let firstLeg, let secondLeg, let finalLeg else { continue }

            let points = mapPoints(firstLeg) + mapPoints(secondLeg).dropFirst() + mapPoints(finalLeg).dropFirst()
            guard points.count > 3 else { continue }

            let bearing = RoadGraph.flat(
                center.latitude,
                center.longitude,
                firstCoordinate.latitude,
                firstCoordinate.longitude
            ).heading

            let firstName = first.name ?? "Scenic destination"
            let secondName = second.name ?? "Scenic destination"
            let officialName = "\(firstName) to \(secondName) Loop"

            output.append(
                PlannedRoute(
                    points: points,
                    roads: [:],
                    twistPerKm: 0,
                    retraced: 0,
                    bearing: bearing,
                    displayName: officialName
                )
            )
        }

        return output
    }

    private static func mapRoute(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: source.latitude, longitude: source.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        return try? await MKDirections(request: request).calculate().routes.first
    }

    private static func mapPoints(_ route: MKRoute) -> [RoutePoint] {
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: coordinates.count)
        )
        return coordinates.map { RoutePoint(lat: $0.latitude, lon: $0.longitude, road: 0) }
    }

    private func run(
        start: CLLocationCoordinate2D,
        length: Double,
        style: RouteStyle,
        mode: LoopMode,
        surface: LoopSurface,
        shapingPins: [CLLocationCoordinate2D],
        prefersPasses: Bool,
        preferredRoads: [String]
    ) async {
        // RoadStore caps a downloaded area at 16 km. Planning beyond that
        // silently re-downloaded every time because the cache could never
        // satisfy the request.
        let radiusKm = Self.planningRadiusKm(forMiles: length / 1_609.344)

        await MainActor.run {
            IdleTimer.acquire("plan")
            progress = 0.05
            phase = .planning
        }
        defer {
            Task { @MainActor in IdleTimer.release("plan") }
        }

        // Shaping pins are explicit. Do not fight them with a generated
        // template: build the loop through the pins, then come home.
        if !shapingPins.isEmpty {
            if let route = await mapKitLoopThrough(start: start, pins: shapingPins, surface: surface) {
                await MainActor.run {
                    progress = 1
                    self.roads = []
                    results = [route]
                    loopCache = LoopCache(
                        latitude: start.latitude,
                        longitude: start.longitude,
                        miles: length / 1609.344,
                        style: style,
                        mode: mode,
                        surface: surface,
                        shapingPins: shapingPins,
                        results: [route],
                        roads: [],
                        preferredRoads: preferredRoads
                    )
                    phase = .done
                }
                await attachElevation(to: route.id, prefersPasses: prefersPasses)
            } else {
                await MainActor.run {
                    phase = .failed("Couldn't build a loop through those shaping pins. Try moving one closer to a road.")
                }
            }
            return
        }

        // Very long loops are too large for the offline graph and too heavy
        // for the twisty template search. Build one direct MapKit loop and
        // validate it instead of downloading a tiny area. The old 300 km
        // threshold left 100–186 mile requests in a dead zone where the graph
        // area was capped at 16 km but MapKit was never used.
        if length > 80_000 {
            if let route = await mapKitLoopWithTimeout(start: start, length: length, timeoutSeconds: 20) {
                await MainActor.run {
                    progress = 1
                    results = [route]
                    self.roads = []
                    phase = .done
                }
                await attachElevation(to: route.id, prefersPasses: prefersPasses)
            } else {
                await MainActor.run {
                    phase = .failed("A loop that long needs live map routing. Check your connection and try again, or reduce the distance.")
                }
            }
            return
        }

        // Decoding the bulk cache is real work. Do it once, off the main thread.
        let cachedRoads = await Task.detached(priority: .userInitiated) {
            RoadStore.cachedArea(center: start, radiusKm: radiusKm, surface: surface)
        }.value

        let waypointCount = length < 8_000 ? 1 : (length < 60_000 ? 2 : 3)
        let mapKitSettings = TwistyLoopSettings(
            candidateTemplates: length < 8_000 ? 10 : 18,
            intermediateWaypoints: waypointCount,
            samplingIntervalMeters: length > 150_000 ? 25 : 10,
            shortWindowMeters: 300,
            mediumWindowMeters: 1_000,
            longWindowMeters: 3_000,
            minimumDistanceMeters: max(length * 0.70, length < 10_000 ? 800 : 3_000),
            targetDistanceMeters: length,
            maximumDistanceMeters: max(length * 1.35, length + (length < 10_000 ? 800 : 5_000)),
            maximumDurationSeconds: max(3_600, length / 9),
            maximumResults: 5,
            mode: mode,
            // One correction pass is enough; more retries burn the 30-second
            // budget without improving the choice much.
            maximumOptimizationRounds: 1,
            maximumRouteRequests: 32
        )
        let mapKitEngine = TwistyLoopEngine(settings: mapKitSettings)

        // The OSM download is only needed when MapKit cannot build a loop, so
        // run it alongside the MapKit search instead of blocking on it first.
        let roadsTask = Task.detached(priority: .utility) {
            (try? await RoadStore.area(center: start, radiusKm: radiusKm, cached: cachedRoads, surface: surface)) ?? []
        }

        // Stop signs, lights and school zones come from the same tiles the
        // alerts already use, so this is a disk read, never a second download.
        let hazardsTask = Task.detached(priority: .utility) { () -> [Hazard] in
            let coverage = HazardStore.shared.coverage(center: start, radiusKm: radiusKm)
            guard coverage.missing == 0 else { return [] }
            return await HazardStore.shared.loadArea(center: start, radiusKm: radiusKm)
        }

        // MapKit cannot honour a surface preference, so ADV/mixed planning goes
        // straight to the offline graph where surface tags are known.
        //
        // The graph planner runs in parallel with MapKit, not after it. In
        // dense suburbs MapKit often burns its whole budget and returns
        // nothing; serialising the two meant the graph never got a chance and
        // the rider saw an error after waiting out both deadlines.
        let planningStart = Date()
        let graphTask = Task.detached(priority: .userInitiated) {
            () -> (routes: [PlannedRoute], roads: [Road], failure: String?, notice: String?) in
            let downloaded = await roadsTask.value
            guard !Task.isCancelled else { return ([], [], nil, nil) }
            let hazards = await hazardsTask.value
            let taste = RouteTaste.shared.snapshot()

            func plan(_ roads: [Road], deadline: Date) -> [PlannedRoute] {
                RouteBuilder.loops(
                    roads: roads,
                    start: start,
                    length: length,
                    style: style,
                    date: Date(),
                    deadline: deadline,
                    surface: surface,
                    preferredRoads: preferredRoads,
                    preferences: taste,
                    hazards: hazards
                )
            }

            let elapsed = Date().timeIntervalSince(planningStart)
            // Leave headroom inside the 27-second UI ceiling even if the road
            // download was slow.
            let remaining = max(2.0, 24.0 - elapsed)

            // The lean paved set is arterials only, and a start deep inside a
            // residential pocket can be a long way from the nearest one. The
            // old retry keyed off the failure string, so a partial download
            // ("51 roads") went straight through and the rider was told the
            // start was not near a road. Retry whenever the loaded roads do not
            // actually reach the pin — and widen as well as densify, because
            // the residential grid that connects the arterials can sit just
            // outside the first radius.
            let nearestRoad = RouteBuilder.distanceToNearestRoad(
                in: downloaded,
                from: start,
                includeUnpaved: surface.includesUnpaved
            )
            let uncovered = downloaded.isEmpty || nearestRoad > 400

            var usedRoads = downloaded
            var routes: [PlannedRoute] = []
            if !downloaded.isEmpty {
                // Do not spend the full planning budget on a graph that does
                // not reach the pin when a denser download is about to replace
                // it; that extra time is what pushed the whole plan past the
                // 32-second ceiling.
                let firstBudget = uncovered ? 4.0 : 10.0
                routes = plan(
                    downloaded,
                    deadline: Date().addingTimeInterval(min(firstBudget, remaining))
                )
            }
            var failure = RouteBuilder.lastFailure
            var notice = RouteBuilder.lastNotice

            let needsDenseGrid = uncovered
                || (failure?.contains("junction") ?? false)
                || (failure?.contains("closed circuit") ?? false)
                || (failure?.contains("near a mapped road") ?? false)
            if routes.isEmpty,
               needsDenseGrid,
               !Task.isCancelled,
               Date().timeIntervalSince(planningStart) < 20 {
                let denseRadius = min(max(radiusKm * 1.5, 6.0), 10.0)
                if let dense = try? await RoadStore.downloadArea(
                    center: start,
                    radiusKm: denseRadius,
                    surface: surface,
                    classes: "secondary|tertiary|unclassified|primary|residential|track",
                    timeout: 12
                ), !dense.isEmpty {
                    usedRoads = dense
                    // Never let the second pass itself run past the UI ceiling.
                    let denseElapsed = Date().timeIntervalSince(planningStart)
                    let denseBudget = max(2.0, min(9.0, 29.0 - denseElapsed))
                    routes = plan(dense, deadline: Date().addingTimeInterval(denseBudget))
                    failure = RouteBuilder.lastFailure
                    notice = RouteBuilder.lastNotice
                }
            }
            if !routes.isEmpty { failure = nil }
            return (routes, usedRoads, failure, notice)
        }
        defer { graphTask.cancel() }

        var mapKitLoops: [TwistyLoopCandidate]?
        var quickPublished = false
        if surface == .paved {
            // A quick loop on screen in eight seconds, a deeper search in
            // fourteen. The graph is already running beside both.
            let planningDeadline = Date().addingTimeInterval(14)
            let quickTask = Task<PlannedRoute?, Never> {
                if let loop = await self.mapKitLoopWithTimeout(
                    start: start,
                    length: length,
                    timeoutSeconds: 8
                ) {
                    return loop
                }
                // A four-leg loop fails when any one waypoint is bad (a park,
                // a one-way, a private road). Two waypoints give it a second
                // chance without touching the graph.
                return await self.mapKitTriangleLoopWithTimeout(
                    start: start,
                    length: length,
                    timeoutSeconds: 5
                )
            }
            let fullTask = Task<[TwistyLoopCandidate], Never> {
                // Give the cheap four-leg loop a head start. Firing the full
                // search's direction requests at the same instant is what gets
                // MapKit to throttle the whole plan, which then looks exactly
                // like "there are no loops here".
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return [] }
                let found = try? await mapKitEngine.findLoops(
                    startingAt: start,
                    roads: cachedRoads ?? [],
                    surface: surface,
                    deadline: planningDeadline,
                    progress: { value in
                        Task { @MainActor in
                            self.progress = 0.05 + value * 0.55
                        }
                    }
                )
                return found ?? []
            }

            // When the area is already on disk the graph needs seconds, not
            // MapKit's full search. Show its loops as soon as they exist,
            // without making the quick MapKit loop wait for the graph's dense
            // retry. The deeper MapKit result can still replace them below.
            if cachedRoads != nil, !Task.isCancelled {
                let generation = generationID
                Task { [weak self] in
                    let early = await graphTask.value
                    guard !early.routes.isEmpty else { return }
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.generationID == generation,
                              self.results.isEmpty else { return }
                        self.roads = early.roads
                        self.notice = early.notice
                        self.results = early.routes
                        self.phase = .done
                        self.progress = max(self.progress, 0.8)
                    }
                }
            }

            if let quick = await quickTask.value, !Task.isCancelled {
                quickPublished = await MainActor.run {
                    guard self.results.isEmpty else { return false }
                    self.results = [quick]
                    self.phase = .done
                    self.progress = max(self.progress, 0.45)
                    return true
                }
            }

            mapKitLoops = await fullTask.value
        }

        // If the 27-second ceiling already fired it has set the phase; do not
        // overwrite it with .idle on the way out.
        guard !Task.isCancelled else { return }

        var mapKitRoutes: [PlannedRoute] = []
        if let mapKitLoops, !mapKitLoops.isEmpty {
            // The displayed curviness (and the star rating) must come from the
            // geometry, not from the score that ranked it.
            let allRoutes = mapKitLoops.map { candidate in
                let measured = Curvature.measure(points: candidate.points)
                return PlannedRoute(
                    points: candidate.points,
                    roads: [:],
                    twistPerKm: measured.degreesPerKm,
                    retraced: candidate.retracedFraction,
                    bearing: candidate.bearing,
                    displayName: candidate.recommendation,
                    expectedTravelTime: candidate.durationSeconds,
                    overallScore: candidate.finalScore,
                    flowScore: candidate.flowScore,
                    lapScore: candidate.lapScore,
                    interruptions: candidate.maneuverCount,
                    scoreLabel: candidate.recommendation
                )
            }
            let onDistance = allRoutes.filter {
                abs($0.length / max(length, 1) - 1) <= 0.20
            }
            mapKitRoutes = onDistance.isEmpty ? allRoutes : onDistance
        }

        // A MapKit loop that respects the distance is good enough to show
        // immediately; do not keep the rider waiting for the graph.
        let mapKitWithinBand = mapKitRoutes.contains {
            abs($0.length / max(length, 1) - 1) <= 0.15
        }
        if mapKitWithinBand {
            await applyMapKitResults(
                mapKitRoutes,
                start: start,
                length: length,
                style: style,
                mode: mode,
                surface: surface,
                preferredRoads: preferredRoads,
                prefersPasses: prefersPasses,
                roadsTask: roadsTask
            )
            return
        }

        // Otherwise take the graph result; it has been running since the tap.
        let graphResult = await graphTask.value
        guard !Task.isCancelled else { return }

        let found = graphResult.routes
        if !found.isEmpty {
            let roads = graphResult.roads
            await MainActor.run {
                progress = 1
                self.roads = roads
                notice = graphResult.notice
                results = found
                loopCache = LoopCache(
                    latitude: start.latitude,
                    longitude: start.longitude,
                    miles: length / 1609.344,
                    style: style,
                    mode: mode,
                    surface: surface,
                    shapingPins: [],
                    results: found,
                    roads: roads,
                    preferredRoads: preferredRoads
                )
                phase = .done
            }
            for route in found {
                await attachElevation(to: route.id, prefersPasses: prefersPasses)
            }
            return
        }

        // MapKit had something, just outside the distance band. Showing it is
        // better than failing, and the card prints the actual distance.
        if !mapKitRoutes.isEmpty {
            await applyMapKitResults(
                mapKitRoutes,
                start: start,
                length: length,
                style: style,
                mode: mode,
                surface: surface,
                preferredRoads: preferredRoads,
                prefersPasses: prefersPasses,
                roadsTask: roadsTask
            )
            return
        }

        if quickPublished {
            await MainActor.run {
                progress = 1
                phase = .done
            }
            return
        }

        // Nothing produced a route from cached or downloaded roads. As a last
        // resort, build a loop from two alternate Apple routes; this needs no
        // Overpass data at all.
        if !Task.isCancelled,
           let alternate = await mapKitAlternateLoopWithTimeout(
               start: start,
               length: length,
               timeoutSeconds: 8
           ) {
            await MainActor.run {
                progress = 1
                results = [alternate]
                roads = []
                phase = .done
            }
            await attachElevation(to: alternate.id, prefersPasses: prefersPasses)
            return
        }

        // Nothing produced a route. Say which half failed so the message is
        // actionable instead of a generic "couldn't build a loop".
        let roads = graphResult.roads
        await MainActor.run {
            progress = 1
            if roads.isEmpty {
                // Never show NSURLErrorDomain strings to a rider. The useful
                // action is the same for a timeout, dropped signal or blocked
                // Overpass mirror.
                phase = .failed(
                    prefetchingRoads
                        ? "Map data for this area is still downloading. Give it a moment, then tap Find scenic loops again."
                        : "Couldn't load road data for this area. Check your connection, then try again."
                )
            } else {
                // `graphResult.failure` belongs to the attempt whose roads are
                // in `graphResult.roads`. The old code read the global
                // `RouteBuilder.lastFailure`, which a later retry had already
                // overwritten — that is how "Loaded 51 roads" and "the start is
                // not near a mapped road" ended up in the same sentence.
                let detail = graphResult.failure.map { raw -> String in
                    let sentence = raw.prefix(1).uppercased() + raw.dropFirst()
                    return " \(sentence)."
                } ?? ""
                let distance = Units.distanceTextFromMiles(length / 1609.344, decimals: 0)
                phase = .failed(
                    "Couldn't build a \(distance) loop from this start.\(detail) Try a different start or a shorter distance."
                )
            }
        }
    }

    /// Publishes MapKit loops and lets the road download finish so an off-route
    /// rider can still rejoin the loop later.
    private func applyMapKitResults(
        _ routes: [PlannedRoute],
        start: CLLocationCoordinate2D,
        length: Double,
        style: RouteStyle,
        mode: LoopMode,
        surface: LoopSurface,
        preferredRoads: [String],
        prefersPasses: Bool,
        roadsTask: Task<[Road], Never>
    ) async {
        progress = 1
        roads = []
        notice = nil
        results = routes
        loopCache = LoopCache(
            latitude: start.latitude,
            longitude: start.longitude,
            miles: length / 1609.344,
            style: style,
            mode: mode,
            surface: surface,
            shapingPins: [],
            results: routes,
            roads: [],
            preferredRoads: preferredRoads
        )
        phase = .done

        let expectedIDs = Set(routes.map(\.id))
        Task { [weak self] in
            let downloaded = await roadsTask.value
            guard !downloaded.isEmpty else { return }
            await MainActor.run {
                guard let self, Set(self.results.map(\.id)) == expectedIDs else { return }
                self.roads = downloaded
            }
        }

        for route in routes {
            await attachElevation(to: route.id, prefersPasses: prefersPasses)
        }
    }

    /// Attaches a terrain profile to one result. Runs after the route is
    /// already visible so a slow/absent elevation service never blocks the map.
    private func attachElevation(to id: UUID, prefersPasses: Bool) async {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        let route = results[index]
        guard route.elevationProfile.isEmpty, route.length > 500 else { return }
        elevationLoading = true
        let profile = await ElevationService.profile(coordinates: route.coordinates,
                                                     totalMeters: route.length)
        elevationLoading = false
        guard !profile.isEmpty,
              let liveIndex = results.firstIndex(where: { $0.id == id }) else { return }
        var updated = results[liveIndex]
        updated.elevationProfile = profile
        updated.climbMeters = profile.totalClimb
        updated.descentMeters = profile.totalDescent
        updated.maxElevation = profile.summit
        updated.isMountainPassRoute = profile.hasMountainPass
        results[liveIndex] = updated
        if prefersPasses {
            results.sort {
                if $0.isMountainPassRoute != $1.isMountainPassRoute { return $0.isMountainPassRoute }
                return $0.climbMeters > $1.climbMeters
            }
        }
    }

    /// Build a closed loop through explicit shaping pins. MapKit has no
    /// multi-stop API, so the legs are requested together and stitched.
    private func mapKitLoopThrough(start: CLLocationCoordinate2D,
                                   pins: [CLLocationCoordinate2D],
                                   surface: LoopSurface) async -> PlannedRoute? {
        let cleanPins = pins.filter {
            RoadGraph.flat($0.latitude, $0.longitude, start.latitude, start.longitude).dist > 200
        }
        let stops = [start] + cleanPins + [start]
        guard stops.count >= 3 else { return nil }
        var legs = [MKRoute?](repeating: nil, count: stops.count - 1)
        do {
            try await withThrowingTaskGroup(of: (Int, MKRoute).self) { group in
                for index in 0..<(stops.count - 1) {
                    let from = stops[index]
                    let to = stops[index + 1]
                    group.addTask {
                        let request = MKDirections.Request()
                        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
                        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
                        request.transportType = .automobile
                        request.requestsAlternateRoutes = false
                        let response = try await MKDirections(request: request).calculate()
                        guard let route = response.routes.first else { throw URLError(.resourceUnavailable) }
                        return (index, route)
                    }
                }
                for try await (index, route) in group { legs[index] = route }
            }
        } catch {
            return nil
        }
        guard legs.allSatisfy({ $0 != nil }) else { return nil }
        return PlannedRoute(mapRoutes: legs.compactMap { $0 }, waypoints: cleanPins,
                            kind: .loop, surface: surface)
    }

}
