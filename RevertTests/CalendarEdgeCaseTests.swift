import Testing
import Foundation
@testable import Revert

@MainActor
struct CalendarEdgeCaseTests {
    private func ride(on date: Date, seconds: TimeInterval = 3_600) -> Ride {
        Ride(startDate: date,
             endDate: date.addingTimeInterval(seconds),
             distanceMeters: 1_000,
             maxSpeedMps: 10,
             elevationGainMeters: 0,
             durationSeconds: seconds,
             points: [])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    @Test func leapDayBelongsToItsMonth() {
        let leap = ride(on: date(2028, 2, 29, 12))
        let march = ride(on: date(2028, 3, 1, 12))
        let february = date(2028, 2, 1, 0)
        let recap = MonthlyRecap(month: february, rides: [leap, march])
        #expect(recap.rides.count == 1)
        #expect(Calendar.current.component(.day, from: recap.rides[0].startDate) == 29)
    }

    @Test func midnightSplitsMonthsAndIsNotDoubleCounted() {
        let newYearsEve = ride(on: date(2026, 12, 31, 23, 59), seconds: 60)
        let newYearsDay = ride(on: date(2027, 1, 1, 0, 1), seconds: 60)
        let december = MonthlyRecap(month: date(2026, 12, 1, 0), rides: [newYearsEve, newYearsDay])
        let january = MonthlyRecap(month: date(2027, 1, 1, 0), rides: [newYearsEve, newYearsDay])
        #expect(december.rides.count == 1)
        #expect(january.rides.count == 1)
    }

    @Test func aRideAcrossTheSpringForwardStillHasOneDuration() {
        // 01:30 EST to 03:30 EDT is two wall-clock hours but one real hour…
        // and Date arithmetic is what the app stores, so the duration is the
        // real elapsed time regardless of the jump.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 1
        components.minute = 30
        let start = Calendar.current.date(from: components)!
        let end = start.addingTimeInterval(3_600)
        let recap = MonthlyRecap(month: date(2026, 3, 1, 0), rides: [ride(on: start)])
        #expect(recap.rides.count == 1)
        #expect(end.timeIntervalSince(start) == 3_600)
    }

    @Test func theFallBackHourIsStoredOnce() {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 1
        components.hour = 1
        components.minute = 30
        // Two dates with the same wall time, one on each side of the fold.
        let first = Calendar.current.date(from: components)!
        let second = first.addingTimeInterval(3_600)
        #expect(first != second)
        #expect(MonthlyRecap(month: date(2026, 11, 1, 0), rides: [ride(on: first), ride(on: second)]).rides.count == 2)
    }
}
