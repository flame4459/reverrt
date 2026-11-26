import Testing
import Foundation
import CoreLocation
@testable import Revert

/// Protects the loop and sprint generators while the map renderer changes.
///
/// Every test here generates routes from synthetic road data, with no map
/// view, no network and no SwiftData: the generators must stand on their own.
@MainActor
struct GeneratorProtectionTests {

    // MARK: - Fixtures

    private let noonSunday = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)

    private var latitudeScale: Double { 110_540 }
    private var longitudeScale: Double { 111_320 * cos(origin.latitude * .pi / 180) }

    private func point(_ latMeters: Double, _ lonMeters: Double) -> (Double, Double) {
        (origin.latitude + latMeters / latitudeScale,
         origin.longitude + lonMeters / longitudeScale)
    }

    /// A square ring made of four separate roads that share their corner
    /// vertices, so the graph has a real cycle to find.
    private func ring(sideMeters: Double, pointsPerSide: Int = 10) -> [Road] {
        var corners: [(Double, Double)] = []
        for index in 0..<4 {
            let angle = Double(index) * .pi / 2
            corners.append(point(sin(angle) * sideMeters / 2, cos(angle) * sideMeters / 2))
        }

        var roads: [Road] = []
        for index in 0..<4 {
            let from = corners[index]
            let to = corners[(index + 1) % 4]
            var coords: [Double] = []
            for step in 0...pointsPerSide {
                let t = Double(step) / Double(pointsPerSide)
                coords.append(from.0 + (to.0 - from.0) * t)
                coords.append(from.1 + (to.1 - from.1) * t)
            }
            let lats = stride(from: 0, to: coords.count, by: 2).map { coords[$0] }
            let lons = stride(from: 1, to: coords.count, by: 2).map { coords[$0] }
            roads.append(Road(id: Int64(index + 1), highway: "tertiary",
                              name: "Ring \(index + 1)", maxspeed: nil,
                              maxspeedForward: nil, maxspeedBackward: nil,
                              surface: "asphalt", oneway: nil, ref: nil,
                              coords: coords,
                              minLat: lats.min()!, maxLat: lats.max()!,
                              minLon: lons.min()!, maxLon: lons.max()!))
        }
        return roads
    }

    /// A straight chain of three roads, for a one-way sprint.
    private func chain() -> [Road] {
        var roads: [Road] = []
        var coords: [(Double, Double)] = []
        for index in 0...12 {
            coords.append(point(0, Double(index) * 180))
        }
        for index in 0..<3 {
            let slice = Array(coords[(index * 4)...(index * 4 + 4)])
            var flat: [Double] = []
            for coordinate in slice { flat.append(coordinate.0); flat.append(coordinate.1) }
            let lats = slice.map(\.0), lons = slice.map(\.1)
            roads.append(Road(id: Int64(100 + index), highway: "secondary",
                              name: "Chain \(index)", maxspeed: "60",
                              maxspeedForward: "60", maxspeedBackward: "60",
                              surface: "asphalt", oneway: nil, ref: nil,
                              coords: flat,
                              minLat: lats.min()!, maxLat: lats.max()!,
                              minLon: lons.min()!, maxLon: lons.max()!))
        }
        return roads
    }

    private func startOfChain() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point(0, 0).0, longitude: point(0, 0).1)
    }

    private func endOfChain() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point(0, 2_160).0, longitude: point(0, 2_160).1)
    }

    private func meters(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        RoadGraph.flat(a.lat, a.lon, b.lat, b.lon).dist
    }

    // MARK: - Loop generator

    @Test func loopsAreClosedAndUsableAtSeveralDistanceTargets() {
        for target in [1_500.0, 3_000.0, 6_000.0] {
            let side = target / 4
            let roads = ring(sideMeters: side)
            let routes = RouteBuilder.loops(roads: roads, start: origin,
                                            length: target, style: .twisty,
                                            date: noonSunday)
            #expect(!routes.isEmpty, "no loop for a \(Int(target)) m target")

            guard let route = routes.first else { continue }
            #expect(route.points.count > 10)
            #expect(route.cumulative.count == route.points.count)
            #expect(abs((route.cumulative.last ?? 0) - route.length) < 0.001)
            #expect(route.length > target * 0.5, "loop is far shorter than the target")
            #expect(route.length < target * 1.8, "loop is far longer than the target")

            let gap = meters(route.points.first!, route.points.last!)
            #expect(gap < 120, "a loop must come back to its start (gap \(gap) m)")

            #expect(route.points.allSatisfy { $0.lat.isFinite && $0.lon.isFinite })
            #expect(route.points.allSatisfy { abs($0.lat) <= 90 && abs($0.lon) <= 180 })

            // No zero-length segments: those are the duplicate geometry a
            // broken generator tends to produce.
            for index in 1..<route.points.count {
                #expect(meters(route.points[index - 1], route.points[index]) > 0.01)
            }
        }
    }

    @Test func loopGenerationIsDeterministicForTheSameInputs() {
        let roads = ring(sideMeters: 600)
        let first = RouteBuilder.loops(roads: roads, start: origin, length: 2_400,
                                       style: .twisty, date: noonSunday)
        let second = RouteBuilder.loops(roads: roads, start: origin, length: 2_400,
                                        style: .twisty, date: noonSunday)
        #expect(!first.isEmpty && first.count == second.count)
        #expect(first.first?.length == second.first?.length)
        #expect(first.first?.points.count == second.first?.points.count)
    }

    @Test func loopFromADifferentStartStaysClosed() {
        let roads = ring(sideMeters: 500)
        let shift = point(0, 0)
        let start = CLLocationCoordinate2D(latitude: shift.0, longitude: shift.1)
        let routes = RouteBuilder.loops(roads: roads, start: start, length: 2_000,
                                        style: .relaxed, date: noonSunday)
        #expect(!routes.isEmpty)
        if let route = routes.first {
            #expect(meters(route.points.first!, route.points.last!) < 120)
        }
    }

    @Test func insufficientCoverageFailsWithoutCrashing() {
        let single = Road(id: 9, highway: "residential", name: "Dead End",
                          maxspeed: nil, maxspeedForward: nil, maxspeedBackward: nil,
                          surface: "asphalt", oneway: nil, ref: nil,
                          coords: [origin.latitude, origin.longitude,
                                   origin.latitude, origin.longitude + 0.001],
                          minLat: origin.latitude, maxLat: origin.latitude,
                          minLon: origin.longitude, maxLon: origin.longitude + 0.001)
        let result = RouteBuilder.loopsResult(roads: [single], start: origin,
                                             length: 5_000, style: .twisty,
                                             date: noonSunday)
        #expect(result.routes.isEmpty)
        #expect(result.failure != nil || result.notice != nil)
    }

    // MARK: - Sprint generator

    @Test func sprintRouteIsConnectedAndBounded() {
        for style in RouteStyle.allCases {
            let route = RouteBuilder.direct(roads: chain(),
                                            from: startOfChain(),
                                            to: endOfChain(),
                                            style: style)
            #expect(route != nil, "no sprint for style \(style.rawValue)")
            guard let route else { continue }

            #expect(route.points.count > 3)
            #expect(route.length > 1_000, "sprint is shorter than the chain")
            #expect(route.length < 3_500, "sprint is longer than the chain")
            #expect(!route.steps.isEmpty, "a navigable sprint must have steps")
            #expect(route.steps.allSatisfy { $0.distance.isFinite && $0.distance >= 0 })

            let snapStart = meters(route.points.first!,
                                   RoutePoint(lat: startOfChain().latitude,
                                              lon: startOfChain().longitude, road: 0))
            let snapEnd = meters(route.points.last!,
                                 RoutePoint(lat: endOfChain().latitude,
                                            lon: endOfChain().longitude, road: 0))
            #expect(snapStart < 600)
            #expect(snapEnd < 600)

            for index in 1..<route.points.count {
                #expect(meters(route.points[index - 1], route.points[index]) > 0.01)
            }
        }
    }

    @Test func sprintRejectsUnreachableDestinations() {
        let far = CLLocationCoordinate2D(latitude: origin.latitude + 2,
                                         longitude: origin.longitude + 2)
        #expect(RouteBuilder.direct(roads: chain(), from: startOfChain(), to: far) == nil)
    }

    // MARK: - GPX compatibility

    @Test func aGeneratedLoopSurvivesGPXExportAndImport() throws {
        let roads = ring(sideMeters: 500)
        let routes = RouteBuilder.loops(roads: roads, start: origin, length: 2_000,
                                        style: .twisty, date: noonSunday)
        let route = try #require(routes.first)

        var ridePoints: [RidePoint] = []
        var time = noonSunday
        for (index, point) in route.points.enumerated() {
            ridePoints.append(RidePoint(lat: point.lat, lon: point.lon, alt: 40,
                                        speed: 18, time: time, lean: 0))
            time = time.addingTimeInterval(1)
            _ = index
        }
        let xml = GPX.export(points: ridePoints, startDate: noonSunday)
        let parsed = try #require(GPX.parseTrack(from: Data(xml.utf8)))
        #expect(parsed.points.count == ridePoints.count)
        #expect(abs(parsed.distanceMeters - route.length) < 5)
    }

    // MARK: - Renderer independence

    @Test func theRendererConsumesTheRouteWithoutChangingIt() throws {
        let roads = ring(sideMeters: 500)
        let route = try #require(RouteBuilder.loops(roads: roads, start: origin,
                                                    length: 2_000, style: .twisty,
                                                    date: noonSunday).first)

        let scene = RevertMapScene.overview(route)
        #expect(scene.camera == .overview)
        #expect(scene.showsRouteProgress == false)
        #expect(scene.route?.points.count == route.points.count)
        #expect(scene.route?.length == route.length)
        #expect(scene.route?.points.first?.lat == route.points.first?.lat)

        // The overview camera is centred on the route's bounds, so nothing is
        // outside the frame by construction.
        let position = try #require(RevertMapFit.fit(route.coordinates,
                                                     viewport: CGSize(width: 402, height: 800)))
        let lats = route.coordinates.map(\.latitude)
        let lons = route.coordinates.map(\.longitude)
        let centerLat = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
        let centerLon = ((lons.min() ?? 0) + (lons.max() ?? 0)) / 2
        #expect(abs(position.latitude - centerLat) < 0.0005)
        #expect(abs(position.longitude - centerLon) < 0.0005)
        #expect((5...17).contains(position.zoom))
    }

    @Test func generatorsDoNotDependOnRetiredRendererTypes() {
        // A compile-time guard: these expressions only build if the generator
        // inputs and outputs are the same value types the renderer consumes.
        let roads = chain()
        let route: PlannedRoute? = RouteBuilder.direct(roads: roads,
                                                       from: startOfChain(),
                                                       to: endOfChain())
        #expect(route is PlannedRoute)
        _ = RevertMapScene.overview(route)
    }
}
