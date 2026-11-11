import Testing
import Foundation
import CoreLocation
@testable import Revert

/// Deterministic checks for the route algorithm. Everything here runs against
/// synthetic geometry or a synthetic grid, so it does not need the network and
/// cannot drift with OSM edits.
@MainActor
struct RouteAlgorithmTests {

    // MARK: Curvature

    @Test func straightRoadHasNoRidingValue() {
        let road = (0...40).map { index in
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0 + Double(index) * 0.00025)
        }
        let stats = Curvature.measure(road)
        #expect(stats.lengthMeters > 800)
        #expect(stats.value == 0)
        #expect(stats.cornerShare == 0)
        #expect(stats.cornersPerKm == 0)
        #expect(stats.degreesPerKm < 1)
        #expect(stats.minRadiusMeters == .infinity)
        #expect(stats.comfortableMps == Curvature.maximumComfortableMps)
    }

    @Test func flowingCircleScoresAsCorners() {
        let points = circle(radius: 100, count: 140)
        let stats = Curvature.measure(points)
        #expect(stats.value > 45)
        #expect(stats.cornerShare > 0.9)
        #expect(abs(stats.minRadiusMeters - 100) < 8)
        #expect(stats.comfortableMps > 15 && stats.comfortableMps < 22)
        #expect(stats.degreesPerKm > 300)
    }

    @Test func tightCircleBeatsSweeper() {
        let tight = Curvature.measure(circle(radius: 35, count: 140))
        let open = Curvature.measure(circle(radius: 220, count: 180))
        #expect(tight.value > open.value)
        #expect(tight.tightShare > 0.5)
        #expect(open.tightShare < 0.05)
        #expect(tight.comfortableMps < open.comfortableMps)
    }

    @Test func hairpinIsTighterThanASweeper() {
        let hairpin = hairpinPoints(radius: 18)
        let stats = Curvature.measure(hairpin)
        #expect(stats.minRadiusMeters < 25)
        // The bend is only ~56 m of a ~456 m fixture, so the share is small
        // even though the radius itself is a genuine hairpin.
        #expect(stats.tightShare > 0.08)
    }

    // MARK: Graph construction

    @Test func graphChunksLongRoadsIntoShortEdges() {
        var coords: [Double] = []
        for index in 0...60 {
            coords.append(37.0)
            coords.append(-122.0 + Double(index) * 0.0005)   // ~50 m apart
        }
        let road = Road(
            id: 1, highway: "tertiary", name: "Long Straight", maxspeed: nil,
            maxspeedForward: nil, maxspeedBackward: nil, surface: "asphalt",
            oneway: nil, ref: nil, coords: coords,
            minLat: 37.0, maxLat: 37.0,
            minLon: coords.min()!, maxLon: coords.max()!
        )
        let graph = RoadGraph(roads: [road], forced: [RoadGraph.key(37.0, -122.0)])
        #expect(graph.edges.count >= 16)   // both directions, 3 km split near 220 m
        #expect(graph.edges.allSatisfy { $0.length <= 300 })
        #expect(graph.edges.allSatisfy { $0.value == 0 })
    }

    // MARK: Preferences

    @Test func roadNameMatchingIsFuzzy() {
        #expect(RoadPreferences.normalize("Skyline Blvd.") == "skyline boulevard")
        #expect(RoadPreferences.matches("skyline boulevard", query: "skyline"))
        #expect(RoadPreferences.matches("state route 9", query: "route 9"))
        #expect(!RoadPreferences.matches("main street", query: "st"))
        #expect(!RoadPreferences.matches("oak avenue", query: "maple"))

        func road(_ name: String) -> Road {
            Road(id: 1, highway: "tertiary", name: name, maxspeed: nil,
                 maxspeedForward: nil, maxspeedBackward: nil, surface: nil,
                 oneway: nil, ref: nil, coords: [37, -122, 37.001, -122.001],
                 minLat: 37, maxLat: 37.001, minLon: -122.001, maxLon: -122)
        }
        let preferences = RoadPreferences(
            preferred: [RoadPreferences.normalize("Skyline Blvd")],
            avoided: [RoadPreferences.normalize("Gravel Pit Rd")],
            learned: [RoadPreferences.normalize("Skyline Blvd"): 3]
        )
        #expect(preferences.multiplier(for: road("Skyline Boulevard")) < 0.9)
        #expect(preferences.multiplier(for: road("Gravel Pit Road")) > 2)
        #expect(preferences.multiplier(for: road("Market Street")) == 1)
    }

    @Test func hazardDensityRaisesCostNearSignals() {
        let hazards = [
            Hazard(id: 1, kind: .signal, lat: 37.0, lon: -122.0),
            Hazard(id: 2, kind: .signal, lat: 37.0, lon: -122.0),
            Hazard(id: 3, kind: .stop, lat: 37.0002, lon: -122.0002)
        ]
        let density = HazardDensity(hazards)
        #expect(density != nil)
        let factor = density!.costFactor(latitude: 37.0, longitude: -122.0, date: noonSunday)
        #expect(factor > 1.4)
        #expect(density!.interruptionCount(latitude: 37.0, longitude: -122.0, date: noonSunday) >= 3)
        // Far away from the cluster there is no penalty.
        #expect(density!.costFactor(latitude: 37.1, longitude: -122.1, date: noonSunday) == 1)
    }

    // MARK: Loop search

    @Test func loopSearchHitsDistanceAndProducesEta() {
        let roads = gridRoads()
        let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: center,
            length: 6_000,
            style: .twisty,
            date: noonSunday,
            deadline: Date().addingTimeInterval(8),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        for route in routes {
            let error = abs(route.length / 6_000 - 1)
            #expect(error < 0.20, "loop was \(route.length) m for a 6 km request")
            #expect(route.expectedTravelTime != nil)
            #expect((route.expectedTravelTime ?? 0) > 60)
            #expect(route.retraced < 0.06)
            #expect(!route.steps.contains { $0.turn == .uTurn })
            #expect(route.twistPerKm >= 0)
        }
    }

    @Test func loopSearchPrefersTwistyRoads() {
        let roads = twistyGridRoads()
        let routes = RouteBuilder.loops(
            roads: roads,
            start: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            length: 6_000,
            style: .twisty,
            date: noonSunday,
            deadline: Date().addingTimeInterval(8),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        let used = routes.flatMap(\.usedRoadNames)
        #expect(used.contains("Twisty Ridge Road"))
        for route in routes {
            #expect(abs(route.length / 6_000 - 1) < 0.20)
        }
    }

    @Test func plannedRouteRecordsRoadNames() {
        let road = Road(id: 42, highway: "tertiary", name: "Skyline Boulevard",
                        maxspeed: nil, maxspeedForward: nil, maxspeedBackward: nil,
                        surface: nil, oneway: nil, ref: nil,
                        coords: [37, -122, 37.001, -122.001],
                        minLat: 37, maxLat: 37.001, minLon: -122.001, maxLon: -122)
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37, lon: -122, road: 42),
                RoutePoint(lat: 37.0005, lon: -122.0005, road: 42),
                RoutePoint(lat: 37.001, lon: -122.001, road: 42)
            ],
            roads: [42: road], twistPerKm: 90, retraced: 0, bearing: 0
        )
        #expect(route.usedRoadNames == ["Skyline Boulevard"])
    }

    // MARK: Regression: lean corridors vs residential grid

    @Test func leanCorridorsReportNoJunctions() {
        let roads = corridorGrid(includeResidential: false)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: CLLocationCoordinate2D(latitude: 40.735, longitude: -73.687),
            length: 6_000,
            style: .extreme,
            date: noonSunday,
            deadline: Date().addingTimeInterval(8),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        // Three parallel corridors never meet, so there is no circuit to find.
        // The through-node fallback now gets past the junction check, so the
        // useful diagnostic is "no closed circuit", not "no junctions".
        #expect(routes.isEmpty)
        #expect(RouteBuilder.lastFailure != nil)
    }

    @Test func residentialGridConnectsLeanCorridors() {
        let roads = corridorGrid(includeResidential: true)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: CLLocationCoordinate2D(latitude: 40.735, longitude: -73.687),
            length: 6_000,
            style: .extreme,
            date: noonSunday,
            deadline: Date().addingTimeInterval(8),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        #expect(routes.allSatisfy { ($0.expectedTravelTime ?? 0) > 0 })
    }

    // MARK: Regression: New Hyde Park report

    @Test func planningRadiusCoversTheWholeLoopExtent() {
        // 15 miles needs ~7.4 km, not the old 4.4 km: the template circle
        // reaches twice its radius from the start.
        #expect(RoutePlanner.planningRadiusKm(forMiles: 15) > 6.5)
        #expect(RoutePlanner.planningRadiusKm(forMiles: 15) < 9)
        #expect(RoutePlanner.planningRadiusKm(forMiles: 1_000) <= 20)
    }

    @Test func loopSearchSurvivesAnAreaSmallerThanTheRequest() {
        // 2.9 km of 120 m blocks cannot hold a 15-mile loop. It must still
        // return the longest available loop, not fail.
        let roads = suburbGrid(rows: 25, blockMeters: 120)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: CLLocationCoordinate2D(latitude: 40.735, longitude: -73.687),
            length: 15 * 1_609.344,
            style: .extreme,
            date: noonSunday,
            deadline: Date().addingTimeInterval(8),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        for route in routes {
            #expect(route.length < 15 * 1_609.344 * 0.85)
            #expect(route.scoreLabel?.contains("Longest") == true)
            #expect((route.expectedTravelTime ?? 0) > 0)
            #expect(!route.steps.contains { $0.turn == .uTurn })
        }
    }

    @Test func suburbGridBuildsAFifteenMileLoop() {
        // 9 km of dense 120 m blocks, the scale of the reported area.
        let roads = suburbGrid(rows: 75, blockMeters: 120)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: CLLocationCoordinate2D(latitude: 40.735, longitude: -73.687),
            length: 15 * 1_609.344,
            style: .extreme,
            date: noonSunday,
            deadline: Date().addingTimeInterval(10),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty)
        for route in routes {
            #expect(abs(route.length / (15 * 1_609.344) - 1) < 0.20)
            #expect((route.expectedTravelTime ?? 0) > 0)
        }
    }

    // MARK: Regression: Brookville 10 mi report

    /// The reported pin was 2.6 km from the nearest mapped road and every
    /// candidate was rejected. Snapping to the nearest road and allowing
    /// pass-through waypoints has to turn that into a loop.
    @Test func loopSearchSnapsAStartThatIsFarFromAnyRoad() {
        let center = CLLocationCoordinate2D(latitude: 40.8349, longitude: -73.5980)
        let ringCenter = CLLocationCoordinate2D(
            latitude: center.latitude + 4_600 / 110_540.0,
            longitude: center.longitude
        )
        let roads = ringRoad(center: ringCenter, radiusMeters: 2_000)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: center,
            length: 12_000,
            style: .extreme,
            date: noonSunday,
            deadline: Date().addingTimeInterval(10),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty,
                "a 2 km ring 2.6 km from the pin should still plan: \(RouteBuilder.lastFailure ?? "nil")")
        #expect(RouteBuilder.lastNotice?.contains("moved") == true)
        for route in routes {
            #expect(route.length > 8_000)
            #expect(!route.steps.contains { $0.turn == .uTurn })
        }
    }

    /// A ring road has no 3-way junctions at all; the old candidate filter
    /// returned "0 usable junctions". Pass-through chunk nodes must work.
    @Test func loopSearchUsesPassThroughNodesOnARing() {
        let center = CLLocationCoordinate2D(latitude: 40.8349, longitude: -73.5980)
        // The ring's seam vertex sits exactly on the pin.
        let ringCenter = CLLocationCoordinate2D(
            latitude: center.latitude - 2_000 / 110_540.0,
            longitude: center.longitude
        )
        let roads = ringRoad(center: ringCenter, radiusMeters: 2_000)
        let routes = RouteBuilder.loops(
            roads: roads,
            start: center,
            length: 12_000,
            style: .twisty,
            date: noonSunday,
            deadline: Date().addingTimeInterval(10),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty, "a ring without junctions should still plan: \(RouteBuilder.lastFailure ?? "nil")")
        for route in routes {
            #expect(route.length > 6_000)
        }
    }

    /// The reported area in practice: a handful of arterial roads with real
    /// junctions, and a pin 2.4 km south of the grid in a residential pocket.
    /// The loop must start from the snapped road and still come out near 10 mi.
    @Test func sparseArterialGridBuildsALoopFromAnOffRoadPin() {
        let pin = CLLocationCoordinate2D(latitude: 40.8349, longitude: -73.5980)
        let roads = arterialGrid(
            northOf: pin,
            nearestEdgeMeters: 2_400,
            rows: 6,
            spacingMeters: 1_500
        )
        let routes = RouteBuilder.loops(
            roads: roads,
            start: pin,
            length: 10 * 1_609.344,
            style: .extreme,
            date: noonSunday,
            deadline: Date().addingTimeInterval(12),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(!routes.isEmpty, "an arterial grid 2.4 km from the pin should plan: \(RouteBuilder.lastFailure ?? "nil")")
        for route in routes {
            #expect(abs(route.length / (10 * 1_609.344) - 1) < 0.35)
            #expect(!route.steps.contains { $0.turn == .uTurn })
        }
    }

    /// The lap gate is graded, not binary. A shared connector is acceptable;
    /// a real out-and-back tail is not.
    @Test func lapCheckIsGradedButStillRejectsAnOutAndBack() {
        let sharedConnector = LoopGeometry.Analysis(
            totalMeters: 16_000, repeatedMeters: 2_000,
            reversalMeters: 0, longestSpurMeters: 0
        )
        #expect(!LoopGeometry.isLapable(sharedConnector))
        #expect(LoopGeometry.isLapable(sharedConnector, limits: .relaxed))

        let heavyReuse = LoopGeometry.Analysis(
            totalMeters: 16_000, repeatedMeters: 3_200,
            reversalMeters: 0, longestSpurMeters: 0
        )
        #expect(!LoopGeometry.isLapable(heavyReuse, limits: .relaxed))
        #expect(LoopGeometry.isLapable(heavyReuse, limits: .loose))

        let outAndBack = LoopGeometry.Analysis(
            totalMeters: 16_000, repeatedMeters: 3_200,
            reversalMeters: 2_000, longestSpurMeters: 400
        )
        #expect(!LoopGeometry.isLapable(outAndBack, limits: .relaxed))
        #expect(!LoopGeometry.isLapable(outAndBack, limits: .loose))
    }

    /// When the pin really is nowhere near a road, the reason must say how far
    /// away the nearest one is — not "loaded 51 roads but the start is not near
    /// a mapped road".
    @Test func unreachableStartReportsTheActualDistance() {
        let center = CLLocationCoordinate2D(latitude: 40.8349, longitude: -73.5980)
        let road = straightRoad(offsetMeters: 8_000, lengthMeters: 400, from: center)
        let distance = RouteBuilder.distanceToNearestRoad(in: [road], from: center)
        #expect(abs(distance - 8_000) < 50)

        let routes = RouteBuilder.loops(
            roads: [road],
            start: center,
            length: 6_000,
            style: .twisty,
            date: noonSunday,
            deadline: Date().addingTimeInterval(6),
            surface: .paved,
            preferences: .empty,
            hazards: []
        )
        #expect(routes.isEmpty)
        #expect(RouteBuilder.lastFailure?.contains("nearest mapped road") == true)
    }

    // MARK: Fixtures

    private var noonSunday: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8       // a Sunday
        components.hour = 12
        return Calendar.current.date(from: components) ?? .distantPast
    }

    private func circle(radius: Double, count: Int) -> [CLLocationCoordinate2D] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(37.0 * .pi / 180)
        return (0...count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            return CLLocationCoordinate2D(
                latitude: 37.0 + radius * cos(angle) / latitudeScale,
                longitude: -122.0 + radius * sin(angle) / longitudeScale
            )
        }
    }

    private func hairpinPoints(radius: Double) -> [CLLocationCoordinate2D] {
        // Straight in, 180-degree bend, straight out.
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(37.0 * .pi / 180)
        var points: [CLLocationCoordinate2D] = []
        for index in 0...20 {
            points.append(CLLocationCoordinate2D(
                latitude: 37.0,
                longitude: -122.0 - Double(index) * 10 / longitudeScale
            ))
        }
        for index in 0...12 {
            let angle = Double.pi * Double(index) / 12
            points.append(CLLocationCoordinate2D(
                latitude: 37.0 + radius * sin(angle) / latitudeScale,
                longitude: -122.0 - 210 / longitudeScale - radius * (1 - cos(angle)) / longitudeScale
            ))
        }
        for index in 0...20 {
            points.append(CLLocationCoordinate2D(
                latitude: 37.0,
                longitude: -122.0 - 210 / longitudeScale - Double(index) * 10 / longitudeScale
            ))
        }
        return points
    }

    /// A 9x9 lattice of intersecting tertiary roads, 400 m apart.
    private func gridRoads() -> [Road] {
        let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let spacing = 400.0
        let latitudeStep = spacing / 110_540.0
        let longitudeStep = spacing / (111_320.0 * cos(center.latitude * .pi / 180))
        let count = 9
        var roads: [Road] = []
        var identifier: Int64 = 1

        for row in 0..<count {
            let latitude = center.latitude + Double(row - count / 2) * latitudeStep
            var coords: [Double] = []
            for column in 0..<count {
                coords.append(latitude)
                coords.append(center.longitude + Double(column - count / 2) * longitudeStep)
            }
            let minLon = center.longitude + Double(-count / 2) * longitudeStep
            let maxLon = center.longitude + Double(count / 2) * longitudeStep
            roads.append(Road(
                id: identifier, highway: "tertiary", name: "East \(row) Road",
                maxspeed: "35 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: latitude, maxLat: latitude, minLon: minLon, maxLon: maxLon
            ))
            identifier += 1
        }

        for column in 0..<count {
            let longitude = center.longitude + Double(column - count / 2) * longitudeStep
            var coords: [Double] = []
            for row in 0..<count {
                coords.append(center.latitude + Double(row - count / 2) * latitudeStep)
                coords.append(longitude)
            }
            let minLat = center.latitude + Double(-count / 2) * latitudeStep
            let maxLat = center.latitude + Double(count / 2) * latitudeStep
            roads.append(Road(
                id: identifier, highway: "tertiary", name: "North \(column) Road",
                maxspeed: "35 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: minLat, maxLat: maxLat, minLon: longitude, maxLon: longitude
            ))
            identifier += 1
        }

        return roads
    }

    /// Two of the nine rows are genuinely twisty; the rest are dead straight.
    /// The loop search must choose the curved road when it is on the way.
    /// A Nassau-style network: a few north-south secondary corridors and an
    /// east-west residential grid. Without the residential ways the corridors
    /// never share a node, which is exactly the reported "0 usable junctions".
    private func corridorGrid(includeResidential: Bool) -> [Road] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(40.735 * .pi / 180)
        let centerLatitude = 40.735
        let centerLongitude = -73.687
        var roads: [Road] = []
        var identifier: Int64 = 900

        let verticalX = [-1_500.0, 0.0, 1_500.0]
        for x in verticalX {
            var coords: [Double] = []
            for step in 0...24 {
                coords.append(centerLatitude + Double(step * 200 - 2_400) / latitudeScale)
                coords.append(centerLongitude + x / longitudeScale)
            }
            roads.append(Road(
                id: identifier, highway: "secondary", name: "Corridor \(Int(x))",
                maxspeed: "40 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: centerLatitude - 0.03, maxLat: centerLatitude + 0.03,
                minLon: centerLongitude + x / longitudeScale,
                maxLon: centerLongitude + x / longitudeScale
            ))
            identifier += 1
        }

        if includeResidential {
            for step in 0...24 {
                let latitude = centerLatitude + Double(step * 200 - 2_400) / latitudeScale
                var coords: [Double] = []
                for x in stride(from: -1_500.0, through: 1_500.0, by: 250.0) {
                    coords.append(latitude)
                    coords.append(centerLongitude + x / longitudeScale)
                }
                roads.append(Road(
                    id: identifier, highway: "residential", name: "Cross \(step)",
                    maxspeed: "25 mph", maxspeedForward: nil, maxspeedBackward: nil,
                    surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                    minLat: latitude, maxLat: latitude,
                    minLon: centerLongitude - 1_500 / longitudeScale,
                    maxLon: centerLongitude + 1_500 / longitudeScale
                ))
                identifier += 1
            }
        }
        return roads
    }

    /// Dense suburban grid: 120 m blocks, residential roads with a few
    /// intermediate vertices, like Nassau County.
    private func suburbGrid(rows: Int, blockMeters: Double) -> [Road] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(40.735 * .pi / 180)
        let latitudeStep = blockMeters / latitudeScale
        let longitudeStep = blockMeters / longitudeScale
        let centerLatitude = 40.735
        let centerLongitude = -73.687
        let verticesPerBlock = 8
        var roads: [Road] = []
        var identifier: Int64 = 500

        for row in 0..<rows {
            let latitude = centerLatitude + Double(row - rows / 2) * latitudeStep
            var coords: [Double] = []
            for column in 0..<rows {
                let longitude = centerLongitude + Double(column - rows / 2) * longitudeStep
                if column > 0 {
                    for vertex in 1..<verticesPerBlock {
                        let fraction = Double(vertex) / Double(verticesPerBlock)
                        coords.append(latitude)
                        coords.append(longitude - longitudeStep + fraction * longitudeStep)
                    }
                }
                coords.append(latitude)
                coords.append(longitude)
            }
            roads.append(Road(
                id: identifier, highway: "residential", name: "Street \(row)",
                maxspeed: "30 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: latitude, maxLat: latitude,
                minLon: centerLongitude - Double(rows / 2) * longitudeStep,
                maxLon: centerLongitude + Double(rows / 2) * longitudeStep
            ))
            identifier += 1
        }

        for column in 0..<rows {
            let longitude = centerLongitude + Double(column - rows / 2) * longitudeStep
            var coords: [Double] = []
            for row in 0..<rows {
                let latitude = centerLatitude + Double(row - rows / 2) * latitudeStep
                if row > 0 {
                    for vertex in 1..<verticesPerBlock {
                        let fraction = Double(vertex) / Double(verticesPerBlock)
                        coords.append(latitude - latitudeStep + fraction * latitudeStep)
                        coords.append(longitude)
                    }
                }
                coords.append(latitude)
                coords.append(longitude)
            }
            roads.append(Road(
                id: identifier, highway: "residential", name: "Avenue \(column)",
                maxspeed: "30 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: centerLatitude - Double(rows / 2) * latitudeStep,
                maxLat: centerLatitude + Double(rows / 2) * latitudeStep,
                minLon: longitude, maxLon: longitude
            ))
            identifier += 1
        }
        return roads
    }

    private func twistyGridRoads() -> [Road] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(37.0 * .pi / 180)
        let spacing = 400.0
        let latitudeStep = spacing / latitudeScale
        let longitudeStep = spacing / longitudeScale
        let rows = 9
        var roads: [Road] = []
        var identifier: Int64 = 100

        for row in 0..<rows {
            let latitude = 37.0 + Double(row - rows / 2) * latitudeStep
            let isTwisty = row == 2 || row == 6
            var coords: [Double] = []
            for column in 0..<rows {
                let longitude = -122.0 + Double(column - rows / 2) * longitudeStep
                if isTwisty && column > 0 {
                    for step in 1...5 {
                        let fraction = Double(step) / 6
                        let offset = sin(fraction * Double.pi) * 45.0 / latitudeScale
                        coords.append(latitude + offset)
                        coords.append(longitude - longitudeStep + fraction * longitudeStep)
                    }
                }
                coords.append(latitude)
                coords.append(longitude)
            }
            roads.append(Road(
                id: identifier, highway: "tertiary",
                name: isTwisty ? "Twisty Ridge Road" : "Grid Row \(row)",
                maxspeed: "35 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: latitude - 0.001, maxLat: latitude + 0.001,
                minLon: -122.1, maxLon: -121.9
            ))
            identifier += 1
        }

        for column in 0..<rows {
            let longitude = -122.0 + Double(column - rows / 2) * longitudeStep
            var coords: [Double] = []
            for row in 0..<rows {
                coords.append(37.0 + Double(row - rows / 2) * latitudeStep)
                coords.append(longitude)
            }
            roads.append(Road(
                id: identifier, highway: "tertiary", name: "Grid Column \(column)",
                maxspeed: "35 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: 36.9, maxLat: 37.1, minLon: longitude, maxLon: longitude
            ))
            identifier += 1
        }
        return roads
    }

    /// One closed OSM way. Every vertex is pass-through only (degree two); the
    /// duplicated first/last vertex is the only junction.
    private func ringRoad(
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        vertices: Int = 96
    ) -> [Road] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(center.latitude * .pi / 180)
        var coords: [Double] = []
        coords.reserveCapacity((vertices + 1) * 2)
        for index in 0...vertices {
            let angle = 2 * Double.pi * Double(index) / Double(vertices)
            coords.append(center.latitude + radiusMeters * cos(angle) / latitudeScale)
            coords.append(center.longitude + radiusMeters * sin(angle) / longitudeScale)
        }
        let latitudeSpan = radiusMeters / latitudeScale
        let longitudeSpan = radiusMeters / longitudeScale
        return [Road(
            id: 7_001, highway: "tertiary", name: "Ridge Ring",
            maxspeed: "40 mph", maxspeedForward: nil, maxspeedBackward: nil,
            surface: "asphalt", oneway: nil, ref: nil, coords: coords,
            minLat: center.latitude - latitudeSpan, maxLat: center.latitude + latitudeSpan,
            minLon: center.longitude - longitudeSpan, maxLon: center.longitude + longitudeSpan
        )]
    }

    private func straightRoad(
        offsetMeters: Double,
        lengthMeters: Double,
        from center: CLLocationCoordinate2D
    ) -> Road {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(center.latitude * .pi / 180)
        let latitude = center.latitude + offsetMeters / latitudeScale
        let startLon = center.longitude - (lengthMeters / 2) / longitudeScale
        let endLon = center.longitude + (lengthMeters / 2) / longitudeScale
        return Road(
            id: 7_100, highway: "tertiary", name: "Far Away Road",
            maxspeed: "40 mph", maxspeedForward: nil, maxspeedBackward: nil,
            surface: "asphalt", oneway: nil, ref: nil,
            coords: [latitude, startLon, latitude, endLon],
            minLat: latitude, maxLat: latitude,
            minLon: startLon, maxLon: endLon
        )
    }

    /// A coarse grid of arterial roads whose nearest edge is `nearestEdgeMeters`
    /// north of the pin. `rows` roads each way, so every crossing is a junction.
    private func arterialGrid(
        northOf center: CLLocationCoordinate2D,
        nearestEdgeMeters: Double,
        rows: Int,
        spacingMeters: Double
    ) -> [Road] {
        let latitudeScale = 110_540.0
        let longitudeScale = 111_320.0 * cos(center.latitude * .pi / 180)
        let halfSpan = Double(rows - 1) / 2 * spacingMeters
        let gridLatitude = center.latitude + (nearestEdgeMeters + halfSpan) / latitudeScale
        let latitudeStep = spacingMeters / latitudeScale
        let longitudeStep = spacingMeters / longitudeScale
        var roads: [Road] = []
        var identifier: Int64 = 8_000

        for row in 0..<rows {
            let latitude = gridLatitude + Double(row - rows / 2) * latitudeStep
            var coords: [Double] = []
            for column in 0..<rows {
                coords.append(latitude)
                coords.append(center.longitude + Double(column - rows / 2) * longitudeStep)
            }
            roads.append(Road(
                id: identifier, highway: "secondary", name: "Arterial \(row)",
                maxspeed: "40 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: latitude, maxLat: latitude,
                minLon: center.longitude - halfSpan / longitudeScale,
                maxLon: center.longitude + halfSpan / longitudeScale
            ))
            identifier += 1
        }

        for column in 0..<rows {
            let longitude = center.longitude + Double(column - rows / 2) * longitudeStep
            var coords: [Double] = []
            for row in 0..<rows {
                coords.append(gridLatitude + Double(row - rows / 2) * latitudeStep)
                coords.append(longitude)
            }
            roads.append(Road(
                id: identifier, highway: "secondary", name: "Cross \(column)",
                maxspeed: "40 mph", maxspeedForward: nil, maxspeedBackward: nil,
                surface: "asphalt", oneway: nil, ref: nil, coords: coords,
                minLat: gridLatitude - halfSpan / latitudeScale,
                maxLat: gridLatitude + halfSpan / latitudeScale,
                minLon: longitude, maxLon: longitude
            ))
            identifier += 1
        }
        return roads
    }
}
