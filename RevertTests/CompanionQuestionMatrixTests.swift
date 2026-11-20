import Testing
import Foundation
@testable import Revert

/// A rider-style question matrix. The goal is not to test one happy phrase per
/// feature; it is to exercise the ways riders actually ask for the same fact.
@MainActor
struct CompanionQuestionMatrixTests {
    private func context() -> CompanionContext {
        let bike = Bike(name: "Test bike", odometerKm: 12_000, fuelRangeKm: 300,
                        tankLiters: 15, serviceIntervalKm: 6_000, lastServiceKm: 5_000)
        let setup = SetupNote(bikeID: bike.id, title: "Road", frontPressure: 32, rearPressure: 36)
        let maintenance = MaintenanceEntry(date: Date(), odometerKm: 10_500,
                                           title: "Oil and filter", bike: bike)
        let now = Date()
        let conditions = RideConditions(date: now,
                                       sunrise: now.addingTimeInterval(-4 * 3_600),
                                       sunset: now.addingTimeInterval(3 * 3_600),
                                       rideDuration: 3_600,
                                       warnings: [])
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
        c.turnsRemaining = 4
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
        c.weather = CompanionWeather(condition: "Rain", temperatureC: 12,
                                     precipitationNowMM: 1.2, precipitationChance: 80)
        c.surfaceAlert = "Loose gravel ahead."
        c.curveAlert = "HAIRPIN LEFT"
        c.homeDistanceMeters = 4_800
        c.workDistanceMeters = 9_600
        c.startHome = {}
        c.startWork = {}
        c.setupNote = setup
        c.lastMaintenance = maintenance
        c.loopCountThisMonth = 3
        c.isStopped = false
        c.tankFraction = 0.5
        c.now = now
        return c
    }

    private func answer(_ question: String, _ context: CompanionContext) -> String? {
        CompanionTools.answer(question, context: context)
    }

    private func expect(_ question: String, contains needle: String, context: CompanionContext) {
        let reply = answer(question, context)
        #expect(reply != nil, "No answer for: \(question)")
        if let reply {
            #expect(reply.localizedCaseInsensitiveContains(needle),
                    "\(question) -> \(reply) (expected \(needle))")
        }
    }

    @Test func navigationQuestions() {
        let c = context()
        expect("where am I?", contains: "Market Street", context: c)
        expect("what's my location?", contains: "Market Street", context: c)
        expect("how much further?", contains: "11", context: c)
        expect("how far to go?", contains: "11", context: c)
        expect("distance left?", contains: "11", context: c)
        expect("remaining distance?", contains: "11", context: c)
        expect("what's my ETA?", contains: "12", context: c)
        expect("when will I arrive?", contains: "12", context: c)
        expect("how long to go?", contains: "12", context: c)
        expect("how far along am I?", contains: "42 percent", context: c)
        expect("progress?", contains: "42 percent", context: c)
        expect("what lap is this?", contains: "Lap 2 of 3", context: c)
        expect("how many laps?", contains: "Lap 2 of 3", context: c)
        expect("am I off route?", contains: "off the route", context: c)
        expect("how many turns left?", contains: "4 turns", context: c)
        expect("what's next?", contains: "Ridge Road", context: c)
        expect("next turn?", contains: "Ridge Road", context: c)
        expect("which way?", contains: "Ridge Road", context: c)
        expect("next road?", contains: "Ridge Road", context: c)
        expect("what road is this?", contains: "Market Street", context: c)
        expect("how far is the route?", contains: Units.distanceText(58_000, decimals: 1), context: c)
        expect("how long is the route?", contains: Units.distanceText(58_000, decimals: 1), context: c)
    }

    @Test func speedAndRideQuestions() {
        let c = context()
        expect("how fast am I going?", contains: Units.speedText(22.352), context: c)
        expect("what's my speed?", contains: Units.speedText(22.352), context: c)
        expect("what's the speed limit?", contains: Units.speedTextFromMph(50), context: c)
        expect("am I speeding?", contains: "No", context: c)
        expect("what's my average?", contains: Units.speedText(18), context: c)
        expect("average speed?", contains: Units.speedText(18), context: c)
        expect("top speed?", contains: Units.speedText(30), context: c)
        expect("max speed?", contains: Units.speedText(30), context: c)
        expect("max lean?", contains: "42", context: c)
        expect("how did the ride go?", contains: "in", context: c)
        expect("how many miles have I ridden?", contains: "ridden", context: c)
        expect("how long have I been riding?", contains: "so far", context: c)
    }

    @Test func routeAndRoadQuestions() {
        let c = context()
        expect("how twisty is it?", contains: "degrees", context: c)
        expect("how much climbing?", contains: Units.elevationText(320), context: c)
        expect("what's the elevation?", contains: Units.elevationText(880), context: c)
        expect("what's the surface?", contains: "Paved", context: c)
        expect("is it paved?", contains: "Paved", context: c)
        expect("any curve warning?", contains: "HAIRPIN", context: c)
        expect("any corner warning?", contains: "HAIRPIN", context: c)
        expect("anything to worry about?", contains: "Gravel", context: c)
        expect("any hazards?", contains: "Gravel", context: c)
        expect("what's the route?", contains: "Test loop", context: c)
        expect("route name?", contains: "Test loop", context: c)
        expect("where are we going?", contains: "Test loop", context: c)
        expect("what's the plan?", contains: "Test loop", context: c)
        expect("what's my destination?", contains: "Test loop", context: c)
    }

    @Test func fuelGarageAndSetupQuestions() {
        let c = context()
        expect("how much fuel is left?", contains: "fuel", context: c)
        expect("what's my range?", contains: "fuel", context: c)
        expect("what's in the tank?", contains: "tank", context: c)
        expect("tyre pressures?", contains: "Front", context: c)
        expect("what are my tire pressures?", contains: "Front", context: c)
        expect("what's the odometer?", contains: "Odometer", context: c)
        expect("how's the bike?", contains: "service", context: c)
        expect("when is service due?", contains: "service", context: c)
        expect("last maintenance?", contains: "Oil and filter", context: c)
        expect("what bike am I on?", contains: "Test bike", context: c)
    }

    @Test func weatherSunAndTimeQuestions() {
        let c = context()
        expect("what's the weather?", contains: "Rain", context: c)
        expect("what's the weather doing?", contains: "Rain", context: c)
        expect("will it rain?", contains: "Rain", context: c)
        expect("what's the temperature?", contains: "Rain", context: c)
        expect("is it cold?", contains: "Rain", context: c)
        expect("when is sunrise?", contains: "Sunrise", context: c)
        expect("when is sunset?", contains: "Sunset", context: c)
        expect("how much daylight?", contains: "daylight", context: c)
        expect("what time is it?", contains: ":", context: c)
        expect("what's the date?", contains: ":", context: c)
    }

    @Test func savedPlacesAndMetaQuestions() {
        let c = context()
        expect("how far is home?", contains: "Home", context: c)
        expect("where is home?", contains: "Home", context: c)
        expect("take me home", contains: "Heading home", context: c)
        expect("go home", contains: "Heading home", context: c)
        expect("how far is work?", contains: "Work", context: c)
        expect("take me to work", contains: "Heading to work", context: c)
        expect("who are you?", contains: "Ace", context: c)
        expect("what's your name?", contains: "Ace", context: c)
        expect("help", contains: "Ask me", context: c)
        expect("what can you do?", contains: "Ask me", context: c)
        expect("are you there?", contains: "Right here", context: c)
        expect("hello", contains: "Mm", context: c)
        expect("thank you", contains: "Mm", context: c)
        expect("traffic?", contains: "traffic", context: c)
        expect("what's the wind?", contains: "wind", context: c)
    }

    @Test func unknownQuestionsAreNotInventedByTools() {
        let c = context()
        #expect(answer("tell me a story", c) == nil)
        #expect(answer("what is the meaning of life?", c) == nil)
    }
}
