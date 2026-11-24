import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct LoopLapTests {
    /// A 400 m circle, so a "lap" is unambiguous and the start and end meet.
    private func circleRoute(laps: Int) -> PlannedRoute {
        let center = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.5)
        let radius = 400 / (2 * Double.pi)
        let count = 72
        let points = (0..<count).map { index -> RoutePoint in
            let angle = Double(index) / Double(count) * 2 * Double.pi
            let lat = center.latitude + (radius * cos(angle)) / 111_320
            let lon = center.longitude + (radius * sin(angle)) / (111_320 * cos(center.latitude * .pi / 180))
            return RoutePoint(lat: lat, lon: lon, road: 0)
        }
        var route = PlannedRoute(points: points, roads: [:], twistPerKm: 0,
                                 retraced: 0, bearing: 0, kind: .loop)
        route.laps = laps
        return route
    }

    private func fix(on route: PlannedRoute, at angle: Double,
                     backwards: Bool = false, when: Date = Date()) -> CLLocation {
        let count = route.points.count
        let index = ((Int((angle / (2 * .pi)) * Double(count)) % count) + count) % count
        let point = route.points[index]
        // Counter-clockwise tangent is θ + 90°; riding the other way is the
        // opposite bearing.
        let tangent = angle * 180 / .pi + 90
        let course = (backwards ? tangent + 180 : tangent).truncatingRemainder(dividingBy: 360)
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                          altitude: 10, horizontalAccuracy: 4, verticalAccuracy: 4,
                          course: course < 0 ? course + 360 : course, speed: 10, timestamp: when)
    }

    @Test func ridingTheLoopBackwardsFlipsTheGuidance() {
        let defaults = UserDefaults.standard
        let previousMuted = defaults.object(forKey: "voice.muted")
        let previousVoice = defaults.object(forKey: "navigation.voice")
        defaults.set(true, forKey: "voice.muted")
        defaults.set(false, forKey: "navigation.voice")
        defer {
            if let previousMuted { defaults.set(previousMuted, forKey: "voice.muted") }
            else { defaults.removeObject(forKey: "voice.muted") }
            if let previousVoice { defaults.set(previousVoice, forKey: "navigation.voice") }
            else { defaults.removeObject(forKey: "navigation.voice") }
        }

        let route = circleRoute(laps: 2)
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])
        nav.handle(fix(on: route, at: 0))
        #expect(nav.joined)

        // Ride clockwise while the route runs counter-clockwise.
        // The second vertex is a reliable tell: on a circle the reversed route
        // starts on the opposite side, whereas the first/last points nearly meet.
        let originalSecond = route.points[1]
        for step in 1...6 {
            let angle = -(Double(step) * 0.05)
            nav.handle(fix(on: route, at: angle, backwards: true))
        }
        let second = try? #require(nav.route?.points[1])
        #expect(abs((second?.lon ?? 0) - originalSecond.lon) > 0.00005,
                "the route should have been reversed, not followed backwards")
    }

    @Test func threeLapsCountOnceEachAndEndOnlyOnTheLast() {
        let defaults = UserDefaults.standard
        let previousMuted = defaults.object(forKey: "voice.muted")
        let previousVoice = defaults.object(forKey: "navigation.voice")
        defaults.set(true, forKey: "voice.muted")
        defaults.set(false, forKey: "navigation.voice")
        defer {
            if let previousMuted { defaults.set(previousMuted, forKey: "voice.muted") }
            else { defaults.removeObject(forKey: "voice.muted") }
            if let previousVoice { defaults.set(previousVoice, forKey: "navigation.voice") }
            else { defaults.removeObject(forKey: "navigation.voice") }
        }

        let route = circleRoute(laps: 3)
        let nav = NavigationManager()
        defer { nav.stop() }
        nav.start(route, roads: [])

        // First fix at the line joins the loop.
        nav.handle(fix(on: route, at: 0))
        #expect(nav.joined)
        #expect(nav.lap == 1)

        var lapsSeen: [Int] = []
        var arrivedAt: Int?
        let stepsPerLap = 40
        for step in 1...(stepsPerLap * 3) {
            let angle = Double(step) / Double(stepsPerLap) * 2 * .pi
            nav.handle(fix(on: route, at: angle))
            if nav.lap != lapsSeen.last { lapsSeen.append(nav.lap) }
            if nav.arrived, arrivedAt == nil { arrivedAt = step }
        }

        #expect(lapsSeen == [1, 2, 3], "laps seen: \(lapsSeen)")
        #expect(arrivedAt == stepsPerLap * 3, "arrived at step \(arrivedAt ?? -1) of 120")
        #expect(nav.arrived)
    }
}
