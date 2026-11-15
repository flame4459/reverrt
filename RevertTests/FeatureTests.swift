import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct FeatureTests {
    private func route() -> PlannedRoute {
        let points = [
            RoutePoint(lat: 37.7750, lon: -122.4194, road: 0),
            RoutePoint(lat: 37.7800, lon: -122.4300, road: 0),
            RoutePoint(lat: 37.7900, lon: -122.4400, road: 0)
        ]
        return PlannedRoute(points: points, roads: [:], twistPerKm: 45,
                            retraced: 0, bearing: 45, displayName: "Test loop",
                            expectedTravelTime: 1_800, kind: .loop)
    }

    @Test func routeLinkRoundTrips() throws {
        var original = route()
        original.laps = 2
        original.surface = .mixed
        original.waypoints = [CLLocationCoordinate2D(latitude: 37.78, longitude: -122.43)]
        let url = try #require(RouteLink.url(for: original))
        let payload = try #require(RouteLink.payload(from: url))
        let decoded = try #require(RouteLink.route(from: payload))
        #expect(decoded.displayName == "Test loop")
        #expect(decoded.points.count == original.points.count)
        #expect(decoded.laps == 2)
        #expect(decoded.surface == .mixed)
        #expect(abs(decoded.length - original.length) < 1)
    }

    @Test func routeLinkRejectsForeignURL() {
        #expect(RouteLink.payload(from: URL(string: "https://example.com/route")!) == nil)
        #expect(RouteLink.route(from: RouteLink.Payload(
            version: 1, name: "x", kind: "loop", laps: 1, surface: "paved",
            expectedTravelTime: nil, points: [], steps: [], waypoints: [], createdAt: Date()
        )) == nil)
    }

    @Test func rangePolicyClassifiesLoops() {
        let bike = Bike(name: "Test", fuelRangeKm: 300)
        let fits = RangePolicy.summary(for: bike, routeLengthMeters: 100_000)
        #expect(fits.verdict == .fits)
        #expect(fits.comfortableKm == 270)
        let tight = RangePolicy.summary(for: bike, routeLengthMeters: 290_000)
        #expect(tight.verdict == .tight)
        let exceeds = RangePolicy.summary(for: bike, routeLengthMeters: 400_000)
        #expect(exceeds.verdict == .exceeds)
    }

    @Test func sunTimesAreOrdered() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-01T16:00:00Z"))
        let sun = ConditionsService.sunTimes(on: date,
                                            coordinate: CLLocationCoordinate2D(latitude: 37.7749,
                                                                               longitude: -122.4194))
        let sunrise = try #require(sun.sunrise)
        let sunset = try #require(sun.sunset)
        #expect(sunrise < sunset)
        #expect(Calendar.current.isDate(sunrise, inSameDayAs: date))
        #expect(Calendar.current.isDate(sunset, inSameDayAs: date))
    }

    @Test func monthlyRecapTotalsRidesInMonth() throws {
        let calendar = Calendar.current
        let month = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let rideA = Ride(startDate: month.addingTimeInterval(86_400),
                         endDate: month.addingTimeInterval(4_000),
                         distanceMeters: 10_000, maxSpeedMps: 20,
                         elevationGainMeters: 100, durationSeconds: 1_800, points: [])
        let rideB = Ride(startDate: month.addingTimeInterval(2 * 86_400),
                         endDate: month.addingTimeInterval(2 * 86_400 + 5_000),
                         distanceMeters: 25_000, maxSpeedMps: 30,
                         elevationGainMeters: 300, durationSeconds: 2_700, points: [])
        let other = Ride(startDate: month.addingTimeInterval(40 * 86_400),
                         endDate: month.addingTimeInterval(40 * 86_400 + 1_000),
                         distanceMeters: 5_000, maxSpeedMps: 10,
                         elevationGainMeters: 0, durationSeconds: 1_000, points: [])
        let recap = MonthlyRecap(month: month, rides: [rideA, rideB, other])
        #expect(recap.rides.count == 2)
        #expect(recap.distanceMeters == 35_000)
        #expect(recap.climbMeters == 400)
        #expect(recap.longestRide === rideB)
    }
}
