import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct CompanionCapabilityTests {
    private func fixture() -> CompanionContext {
        let bike = Bike(name: "Test bike", odometerKm: 12_000, fuelRangeKm: 300,
                        tankLiters: 15, serviceIntervalKm: 6_000, lastServiceKm: 5_000)
        let setup = SetupNote(bikeID: bike.id, title: "Road", frontPressure: 32, rearPressure: 36)
        let maintenance = MaintenanceEntry(date: Date(), odometerKm: 10_500,
                                           title: "Oil and filter", bike: bike)
        let now = Date()
        let conditions = RideConditions(
            date: now,
            sunrise: now.addingTimeInterval(-4 * 3_600),
            sunset: now.addingTimeInterval(3 * 3_600),
            rideDuration: 3_600,
            warnings: ["You would finish after sunset."]
        )
        let weather = CompanionWeather(condition: "Rain", temperatureC: 12,
                                       precipitationNowMM: 1.2, precipitationChance: 80)
        var c = CompanionContext()
        c.speedMps = 22.352
        c.remainingMeters = 17_702
        c.estimatedSeconds = 720
        c.nextManeuverMeters = 240
        c.nearestHazardMeters = 200
        c.hazardName = "Gravel"
        c.routeName = "Test loop"
        c.routeKey = "loop"
        c.routeIsLoop = true
        c.routeLengthMeters = 58_000
        c.routeClimbMeters = 320
        c.routeMaxElevation = 880
        c.routeTwistPerKm = 95
        c.routeSurface = "Paved"
        c.routeProgress = 0.42
        c.nextInstruction = "Turn right onto Ridge Road"
        c.nextRoad = "Ridge Road"
        c.currentRoad = "Market Street"
        c.speedLimitMph = 50
        c.lap = 2
        c.totalLaps = 3
        c.offRoute = true
        c.rideDistanceMeters = 24_000
        c.rideDurationSeconds = 1_320
        c.averageSpeedMps = 18
        c.maxSpeedMps = 30
        c.maxLeanAngle = 42
        c.bike = bike
        c.conditions = conditions
        c.weather = weather
        c.surfaceAlert = "Loose gravel ahead."
        c.curveAlert = "HAIRPIN LEFT"
        c.homeDistanceMeters = 4_800
        c.workDistanceMeters = 9_600
        c.setupNote = setup
        c.lastMaintenance = maintenance
        c.loopCountThisMonth = 3
        c.isStopped = false
        c.tankFraction = 0.5
        c.now = now
        return c
    }

    @Test func navigationAndSpeedFacts() {
        let context = fixture()
        #expect(CompanionTools.answer("how much further?", context: context)?.contains(Units.distanceText(17_702, decimals: 1)) == true)
        #expect(CompanionTools.answer("what's my ETA?", context: context)?.contains(Units.clock(720)) == true)
        #expect(CompanionTools.answer("how fast am I going?", context: context)?.contains(Units.speedText(22.352)) == true)
        #expect(CompanionTools.answer("what's the speed limit?", context: context)?.contains(Units.speedTextFromMph(50)) == true)
        #expect(CompanionTools.answer("what's next?", context: context)?.contains("Ridge Road") == true)
        #expect(CompanionTools.answer("what road is this?", context: context)?.contains("Market Street") == true)
        #expect(CompanionTools.answer("how far along am I?", context: context)?.contains("42 percent") == true)
        #expect(CompanionTools.answer("how far is the route?", context: context)?.contains(Units.distanceText(58_000, decimals: 1)) == true)
        #expect(CompanionTools.answer("what lap is this?", context: context)?.contains("2 of 3") == true)
        #expect(CompanionTools.answer("am I off route?", context: context)?.contains("off the route") == true)
    }

    @Test func rideAndRouteFacts() {
        let context = fixture()
        #expect(CompanionTools.answer("what's my average?", context: context)?.contains(Units.speedText(18)) == true)
        #expect(CompanionTools.answer("top speed?", context: context)?.contains(Units.speedText(30)) == true)
        #expect(CompanionTools.answer("max lean?", context: context)?.contains("42") == true)
        #expect(CompanionTools.answer("how much climbing?", context: context)?.contains(Units.elevationText(320)) == true)
        #expect(CompanionTools.answer("what's the surface?", context: context)?.contains("Paved") == true)
        #expect(CompanionTools.answer("any corner warning?", context: context)?.contains("HAIRPIN") == true)
        #expect(CompanionTools.answer("how did the ride go?", context: context)?.contains(Units.distanceText(24_000, decimals: 1)) == true)
    }

    @Test func fuelWeatherAndSunFacts() {
        let context = fixture()
        let fuelLeft = ((300 * 0.5) - 17.702) * 1_000
        #expect(CompanionTools.answer("how much fuel left?", context: context)?.contains(Units.distanceText(fuelLeft, decimals: 0)) == true)
        #expect(CompanionTools.answer("what's the weather?", context: context)?.contains("Rain") == true)
        #expect(CompanionTools.answer("when is sunrise?", context: context)?.contains("Sunrise") == true)
        #expect(CompanionTools.answer("when is sunset?", context: context)?.contains("Sunset") == true)
        #expect(CompanionTools.answer("how much daylight?", context: context)?.contains("daylight") == true)
    }

    @Test func hazardAndGarageFacts() {
        let context = fixture()
        #expect(CompanionTools.answer("anything to worry about?", context: context)?.contains("Gravel") == true)
        #expect(CompanionTools.answer("what are my tyre pressures?", context: context)?.contains(Units.pressureText(32)) == true)
        #expect(CompanionTools.answer("what's the odometer?", context: context)?.contains(Units.distanceText(12_000_000, decimals: 0)) == true)
        #expect(CompanionTools.answer("what's the tank?", context: context)?.contains(Units.volumeText(15)) == true)
        #expect(CompanionTools.answer("last maintenance?", context: context)?.contains("Oil and filter") == true)
        #expect(CompanionTools.answer("how's the bike?", context: context)?.lowercased().contains("service") == true)
    }

    @Test func savedPlacesAndMetaFacts() {
        let context = fixture()
        #expect(CompanionTools.answer("how far is home?", context: context)?.contains(Units.distanceText(4_800, decimals: 1)) == true)
        #expect(CompanionTools.answer("how far is work?", context: context)?.contains(Units.distanceText(9_600, decimals: 1)) == true)
        #expect(CompanionTools.answer("what's the route?", context: context)?.contains("Test loop") == true)
        #expect(CompanionTools.answer("what time is it?", context: context)?.isEmpty == false)
        #expect(CompanionTools.answer("who are you?", context: context)?.contains("Ace") == true)
        #expect(CompanionTools.answer("what can you do?", context: context)?.contains("ETA") == true)
    }

    @Test func homeCommandCanStartANavigationRoute() {
        var context = fixture()
        var started = false
        context.startHome = { started = true }
        let answer = CompanionTools.answer("take me home", context: context)
        #expect(started)
        #expect(answer?.contains("Heading home") == true)
    }

    @Test func memoryKeepsTheLastTwentyEpisodes() {
        let memory = CompanionMemory.shared
        memory.reset()
        defer { memory.reset() }
        for index in 0..<25 {
            memory.recordRide(routeKey: "loop-\(index % 3)", routeName: "Loop \(index)",
                              distanceMeters: Double(index) * 1_000,
                              durationSeconds: Double(index) * 60,
                              note: "Arrived")
        }
        #expect(memory.episodes.count == 20)
        #expect(memory.rides == 25)
    }

    @Test func checkInGateHonoursBudgetManeuverHazardAndSpeech() {
        var context = fixture()
        context.nextManeuverMeters = 9_999
        context.nearestHazardMeters = nil
        let now = Date()
        let old = now.addingTimeInterval(-11 * 60)
        #expect(CompanionCheckInGate.allows(now: now, lastCheckIn: old,
                                            lastRiderSpeech: now.addingTimeInterval(-30),
                                            context: context))
        #expect(!CompanionCheckInGate.allows(now: now, lastCheckIn: now.addingTimeInterval(-60),
                                             lastRiderSpeech: now.addingTimeInterval(-30),
                                             context: context))
        context.nextManeuverMeters = 20
        #expect(!CompanionCheckInGate.allows(now: now, lastCheckIn: old,
                                             lastRiderSpeech: now.addingTimeInterval(-30),
                                             context: context))
        context.nextManeuverMeters = 9_999
        context.nearestHazardMeters = 100
        #expect(!CompanionCheckInGate.allows(now: now, lastCheckIn: old,
                                             lastRiderSpeech: now.addingTimeInterval(-30),
                                             context: context))
        context.nearestHazardMeters = nil
        #expect(!CompanionCheckInGate.allows(now: now, lastCheckIn: old,
                                             lastRiderSpeech: now.addingTimeInterval(-5),
                                             context: context))
    }

    @Test func unknownAndFactGuard() {
        let context = fixture()
        #expect(CompanionTools.answer("tell me a story", context: context) == nil)
        #expect(CompanionTools.isFactRequest("tell me a story") == false)
        #expect(CompanionTools.isFactRequest("what's the weather?") == true)
        #expect(CompanionTools.isFactRequest("how fast?") == true)
    }

    @Test func weatherConditionMapping() {
        #expect(CompanionWeather.condition(for: 0) == "Clear")
        #expect(CompanionWeather.condition(for: 61) == "Rain")
        #expect(CompanionWeather.condition(for: 95) == "Thunderstorms")
    }
}
