import Foundation
import SwiftUI
import Observation

// MARK: - State

nonisolated enum CompanionState: String, CaseIterable, Identifiable, Sendable {
    case on
    case askedOnly
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .on: "On"
        case .askedOnly: "Asked only"
        case .off: "Off"
        }
    }

    var shortTitle: String {
        switch self {
        case .on: "ON"
        case .askedOnly: "ASKED"
        case .off: "OFF"
        }
    }

    var icon: String {
        switch self {
        case .on: "waveform"
        case .askedOnly: "questionmark.bubble"
        case .off: "speaker.slash.fill"
        }
    }

    var next: CompanionState {
        switch self {
        case .on: .askedOnly
        case .askedOnly: .off
        case .off: .on
        }
    }
}

// MARK: - Wake word

nonisolated enum CompanionWakeWord {
    static let phrases = ["hey ace", "ace"]

    /// The question after “Hey Ace”, or nil when the phrase was not a whole
    /// word or had no question attached.
    static func query(from text: String) -> String? {
        for phrase in phrases {
            var searchStart = text.startIndex
            while let range = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive],
                                          range: searchStart..<text.endIndex) {
                let beforeOK = range.lowerBound == text.startIndex
                    || !text[text.index(before: range.lowerBound)].isLetter
                let afterOK = range.upperBound == text.endIndex
                    || !text[range.upperBound].isLetter
                if beforeOK, afterOK {
                    let query = String(text[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:"))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return query.isEmpty ? nil : query
                }
                searchStart = range.upperBound
            }
        }
        return nil
    }
}

// MARK: - Live ride slice

/// A deliberately small snapshot. The companion never reaches into views or
/// SwiftData itself; the cockpit hands it these values at the moment of speech.
struct CompanionContext {
    var speedMps: Double = 0
    var remainingMeters: Double = 0
    var estimatedSeconds: TimeInterval?
    var nextManeuverMeters: Double = 9_999
    var nearestHazardMeters: Double?
    var hazardName: String?
    var routeName: String?
    var routeKey: String?
    var routeIsLoop = false
    var routeLengthMeters: Double = 0
    var routeClimbMeters: Double = 0
    var routeMaxElevation: Double = 0
    var routeTwistPerKm: Double = 0
    var routeSurface: String?
    var routeProgress = 0.0
    var nextInstruction: String?
    var nextRoad: String?
    var turnsRemaining = 0
    var currentRoad: String?
    var speedLimitMph: Int?
    var lap = 1
    var totalLaps = 1
    var offRoute = false
    var rideDistanceMeters: Double = 0
    var rideDurationSeconds: Double = 0
    var averageSpeedMps: Double = 0
    var maxSpeedMps: Double = 0
    var maxLeanAngle: Double = 0
    var bike: Bike?
    var conditions: RideConditions?
    var lastRide: Ride?
    var weather: CompanionWeather?
    var surfaceAlert: String?
    var curveAlert: String?
    var homeDistanceMeters: Double?
    var workDistanceMeters: Double?
    /// The last instruction the navigation voice actually delivered.
    var lastInstruction: String?
    var startHome: (() -> Void)?
    var startWork: (() -> Void)?
    var setupNote: SetupNote?
    var lastMaintenance: MaintenanceEntry?
    var loopCountThisMonth = 0
    var isStopped = false
    var tankFraction = 0.8
    var now = Date()

    var isAtSpeed: Bool { speedMps > 1 }
    nonisolated var hasManeuverSoon: Bool { nextManeuverMeters < max(speedMps * 20, 80) }
    nonisolated var hasHazardSoon: Bool { (nearestHazardMeters ?? .infinity) < 300 }
}

// MARK: - Memory

nonisolated struct CompanionEpisode: Codable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var routeKey: String?
    var routeName: String?
    var distanceMeters: Double
    var durationSeconds: Double
    var note: String
}

nonisolated struct CompanionMemoryState: Codable, Sendable {
    var rides = 0
    var jokeIDs: [String] = []
    var loopCounts: [String: Int] = [:]
    var familiarity = 0
    var episodes: [CompanionEpisode] = []
}

@MainActor
final class CompanionMemory {
    static let shared = CompanionMemory()
    private let key = "companion.memory.v1"
    private(set) var state: CompanionMemoryState

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(CompanionMemoryState.self, from: data) {
            state = decoded
        } else {
            state = CompanionMemoryState()
        }
    }

    var rides: Int { state.rides }
    var familiarity: Int { state.familiarity }
    var recentJokeIDs: [String] { state.jokeIDs }
    var episodes: [CompanionEpisode] { state.episodes }

    func recordRide(routeKey: String?, routeName: String?,
                    distanceMeters: Double, durationSeconds: Double, note: String) {
        state.rides += 1
        state.familiarity = min(5, state.rides / 4)
        if let routeKey, !routeKey.isEmpty {
            state.loopCounts[routeKey, default: 0] += 1
        }
        state.episodes.append(CompanionEpisode(
            date: Date(), routeKey: routeKey, routeName: routeName,
            distanceMeters: distanceMeters, durationSeconds: durationSeconds,
            note: note
        ))
        if state.episodes.count > 20 {
            state.episodes.removeFirst(state.episodes.count - 20)
        }
        save()
    }

    func recordJoke(_ id: String) {
        state.jokeIDs.append(id)
        if state.jokeIDs.count > 10 {
            state.jokeIDs.removeFirst(state.jokeIDs.count - 10)
        }
        save()
    }

    func reset() {
        state = CompanionMemoryState()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Script

nonisolated enum CompanionScript {
    static let acknowledgements = ["Right.", "Mm.", "As you like."]

    static func start(distance: String, time: String, isLoop: Bool, address: String) -> String {
        if isLoop {
            return "Route's set, \(address). \(distance), \(time). Say the word if you want the long way."
        }
        return "Route's set, \(address). \(distance), \(time)."
    }

    static func arrival(distance: String, time: String, address: String) -> String {
        "That's you, \(address). \(distance) in \(time)."
    }

    static func range(_ distance: String) -> String {
        "Fuel in about \(distance). Plan a stop."
    }

    static func hazard(_ name: String, distance: String) -> String {
        "\(name) in \(distance). I'd not do that."
    }

    static func sunset(_ time: String) -> String {
        "Sunset is \(time). You've still got daylight."
    }

    static func thirdLoop() -> String {
        "Third time on this loop this month. You do like this one."
    }

    static func longStop() -> String {
        "Still here. I'll keep the engine warm; you take your time."
    }

    static func service(_ distance: String) -> String {
        "Chain's due in \(distance). Worth a look when you're home."
    }

    static func serviceDueNow() -> String {
        "Chain and fluids are due now. Worth ten minutes before the next ride."
    }

    static func unknown() -> String {
        "Ask me distance, ETA, speed, next turn, the road, fuel, weather, hazards, tyres, service or the route."
    }

    static let jokes: [(id: String, text: String)] = [
        ("road-notice", "You've ridden this road five times. The road has not noticed."),
        ("shortcut", "I could suggest a shortcut. I've met you."),
        ("long-way", "The long way is usually the right way. That's not a coincidence."),
        ("gravel", "Gravel is a character test. I'd rather not take it."),
        ("motorway", "Motorways are a waste of a motorcycle. I stand by that."),
        ("ridge", "Ridge roads. Valleys are for people in a hurry."),
        ("plans", "I've seen smoother plans. I've also seen worse ones."),
        ("weather", "You packed light. The weather may have opinions."),
        ("speed", "This is the part where I pretend not to notice the speed."),
        ("shortcuts", "No shortcuts. I checked twice."),
        ("scenic", "I don't do scenic. I do efficient with a view."),
        ("map", "The map says straight. The map has never met this road."),
        ("coffee", "You could stop for coffee. You won't."),
        ("contact", "I've planned a route. Whether it survives contact with the road is another matter."),
        ("signage", "That junction has seen better signage."),
        ("detour", "I'd call this a detour. You'd call it the route."),
        ("optimist", "The tank is half full. I'm an optimist."),
        ("manners", "A ridge road is just a valley road with better manners."),
        ("camber", "You can tell a lot about a road by its camber."),
        ("proper", "This one's a proper road. It has opinions."),
        ("gravel-warning", "I'd advise against the gravel. I'll also enjoy saying I told you."),
        ("unknown-turn", "No, I don't know where that turn goes. That's why we're going."),
        ("tidy", "Your line was tidy. I'll allow it."),
        ("empty", "The road is empty. Suspicious."),
        ("surfaces", "I've seen better surfaces. I've also seen worse company."),
        ("lunch", "You don't need a shortcut. You need a longer lunch."),
        ("rumour", "If this road were any narrower, it would be a rumour."),
        ("squiggle", "The map has a squiggle here. I respect a squiggle."),
        ("view", "There's a view coming. Try not to look at it for too long."),
        ("reason", "This route was chosen for a reason. I've forgotten the reason."),
        ("field", "I could navigate by feel. You'd end up in a field."),
        ("dry", "A motorcycle is a terrible way to stay dry. Excellent way to arrive."),
        ("roundabout", "That's a roundabout. I'll say it once."),
        ("bored", "I don't get bored. I get even."),
        ("home-joke", "Home is that way. Probably."),
        ("engine", "The engine sounds fine. The rider sounds speculative."),
        ("fuel-joke", "Fuel is a numbers game. You're losing."),
        ("road-notice-two", "The road has still not noticed you."),
        ("late", "The long way is only wrong if you're late. You're not late."),
        ("weather-facts", "The weather is doing something. I'll let you know when I have facts."),
        ("line", "I've seen racing lines. That was a commuting line."),
        ("quiet", "I'd say something profound, but the road is doing the talking."),
        ("arrival-joke", "We made it. I had every confidence. Mostly."),
        ("fuel-plan", "A fuel stop is just a scheduled interruption."),
        ("camera", "I won't comment on the camera. I'm not insured for opinions."),
        ("pass", "One more pass. That's what you said last time."),
        ("town", "That town looked nice. We didn't stop."),
        ("grip", "Grip is a rumour until the first corner."),
        ("map-two", "The map and I have agreed to disagree.")
    ]
}

// MARK: - Tools

@MainActor
enum CompanionTools {
    static func answer(_ text: String, context: CompanionContext) -> String? {
        let lower = text.lowercased()
        if lower.contains("never mind") { return nil }

        // Saved places first: "how far is home" must not be read as route distance.
        if lower.contains("home") {
            guard let distance = context.homeDistanceMeters else {
                return "I've no home saved. Set it in Saved places."
            }
            if lower.contains("take me") || lower.contains("go home") || lower == "home" {
                guard let startHome = context.startHome else {
                    return "Home is \(Units.distanceText(distance, decimals: 1)) away."
                }
                startHome()
                return "Heading home. \(Units.distanceText(distance, decimals: 1)) away."
            }
            return "Home is \(Units.distanceText(distance, decimals: 1)) away."
        }
        if lower.contains("work") && (lower.contains("far") || lower.contains("away") || lower.contains("distance")) {
            guard let distance = context.workDistanceMeters else {
                return "I've no work saved. Set it in Saved places."
            }
            return "Work is \(Units.distanceText(distance, decimals: 1)) away."
        }
        if lower.contains("work") && (lower.contains("take me") || lower.contains("go to")) {
            guard let distance = context.workDistanceMeters else {
                return "I've no work saved. Set it in Saved places."
            }
            context.startWork?()
            return "Heading to work. \(Units.distanceText(distance, decimals: 1)) away."
        }
        if lower.contains("where am i") || lower.contains("my location") {
            let road = context.currentRoad ?? "an unnamed road"
            return "On \(road), \(Int(min(max(context.routeProgress, 0), 1) * 100)) percent through the route."
        }
        if lower.contains("how far have i ridden") || lower.contains("ridden so far")
            || lower.contains("miles have i") || lower.contains("distance have i") {
            return "You've ridden \(Units.distanceText(context.rideDistanceMeters, decimals: 1))."
        }
        if lower.contains("how long have i been") || lower.contains("ride time") || lower.contains("elapsed") {
            return "\(Units.clock(context.rideDurationSeconds)) so far."
        }
        if lower.contains("turns left") || lower.contains("how many turns") {
            return "\(context.turnsRemaining) turn\(context.turnsRemaining == 1 ? "" : "s") left."
        }
        if lower.contains("next road") || lower.contains("what road next") {
            return context.nextRoad.map { "Next is \($0)." } ?? "No next road yet."
        }
        if lower.contains("which way") {
            return context.nextInstruction.map { "\($0) in \(Units.shortDistanceText(context.nextManeuverMeters))." } ?? "No maneuver coming up."
        }
        if lower.contains("what bike") || lower.contains("which bike") || lower.contains("what am i riding") {
            return context.bike.map { "You're on \($0.displayName)." } ?? "No bike set in the garage."
        }
        if lower.contains("twisty") || lower.contains("twist") {
            return "This route is \(RevertFormat.number(context.routeTwistPerKm, decimals: 0)) degrees per kilometre."
        }
        if lower.contains("paved") || lower.contains("pavement") || lower.contains("unpaved") {
            return "Surface: \(context.routeSurface ?? "unknown")."
        }
        if lower.contains("am i speeding") {
            guard let limit = context.speedLimitMph else { return "I've no speed limit for this road." }
            let current = Units.speedValue(context.speedMps)
            let limitValue = Units.speedValueFromMph(Double(limit))
            return current > limitValue + 1 ? "Yes. Ease off." : "No. Within the limit."
        }
        if lower.contains("your name") {
            return "Ace."
        }
        if lower == "hello" || lower.hasPrefix("hello ") || lower == "hi" || lower.hasPrefix("hi ") {
            return "Mm."
        }
        if lower.contains("thank") {
            return "Mm."
        }
        if lower.contains("are you there") || lower.contains("you there") {
            return "Right here."
        }
        if lower.contains("where are we going") || lower.contains("destination") || lower == "the plan" || lower.contains("what's the plan") {
            return context.routeName.map { "To \($0)." } ?? "No route set."
        }
        if lower.contains("traffic") {
            return "I've no traffic feed."
        }
        if lower.contains("wind") {
            return "I've no wind feed."
        }

        if lower.contains("route") && (lower.contains("how long") || lower.contains("how far") || lower.contains("length")) {
            return "\(context.routeName ?? "Route"): \(Units.distanceText(context.routeLengthMeters, decimals: 1))."
        }
        if lower.contains("progress") || lower.contains("how far along") || lower.contains("percent") {
            return "\(Int(min(max(context.routeProgress, 0), 1) * 100)) percent through the route."
        }
        if lower.contains("how much further") || lower.contains("how far") || lower.contains("distance left") || lower.contains("remaining") {
            let distance = Units.distanceText(context.remainingMeters, decimals: 1)
            let time = context.estimatedSeconds.map { Units.clock($0) } ?? "unknown time"
            return "\(distance). \(time)."
        }
        if lower.contains("eta") || lower.contains("how long") || lower.contains("arrive") || lower.contains("time left") {
            let time = context.estimatedSeconds.map { Units.clock($0) } ?? "unknown"
            return "About \(time) to go."
        }
        if lower.contains("speed limit") || lower == "limit" || lower.contains("what's the limit") {
            guard let limit = context.speedLimitMph else { return "I've no speed limit for this road." }
            return "The limit is \(Units.speedTextFromMph(Double(limit)))."
        }
        if lower.contains("average") {
            return "Average \(Units.speedText(context.averageSpeedMps))."
        }
        if lower.contains("max speed") || lower.contains("top speed") {
            return "Max \(Units.speedText(context.maxSpeedMps))."
        }
        if lower.contains("how fast") || lower.contains("my speed") || lower.contains("speed") {
            let current = Units.speedText(context.speedMps)
            if let limit = context.speedLimitMph {
                return "\(current). The limit is \(Units.speedTextFromMph(Double(limit)))."
            }
            return "\(current)."
        }
        if lower.contains("next turn") || lower.contains("next instruction") || lower.contains("what's next") {
            guard let instruction = context.nextInstruction else { return "No maneuver coming up." }
            return "\(instruction) in \(Units.shortDistanceText(context.nextManeuverMeters))."
        }
        if lower.contains("what road") || lower.contains("current road") || lower.contains("which road") {
            return context.currentRoad.map { "You're on \($0)." } ?? "I've no road name yet."
        }
        if lower.contains("lap") {
            return "Lap \(context.lap) of \(context.totalLaps)."
        }
        if lower.contains("off route") || lower.contains("off-route") {
            return context.offRoute ? "You're off the route." : "You're on the route."
        }
        if lower.contains("lean") {
            return "Max lean \(RevertFormat.number(context.maxLeanAngle, decimals: 0)) degrees."
        }
        if lower.contains("climb") || lower.contains("elevation") || lower.contains("how high") {
            let climb = Units.elevationText(context.routeClimbMeters)
            let high = Units.elevationText(context.routeMaxElevation)
            return "\(climb) of climbing, topping out at \(high)."
        }
        if lower.contains("surface") || lower.contains("paved") || lower.contains("pavement") || lower.contains("unpaved") {
            return "Route surface is \(context.routeSurface ?? "unknown")."
        }
        if lower.contains("gravel") {
            if let alert = context.surfaceAlert { return alert }
            return "Route surface is \(context.routeSurface ?? "unknown")."
        }
        if lower.contains("curve") || lower.contains("corner") {
            if let alert = context.curveAlert { return alert }
            return "No curve warning right now."
        }
        if lower.contains("weather") || lower.contains("rain") || lower.contains("temperature") || lower.contains("cold") || lower.contains("warm") {
            if let weather = context.weather { return weather.summary }
            if let warning = context.conditions?.warnings.first { return warning }
            return "I've no weather feed. Sunset is \(sunsetText(context))."
        }
        if lower.contains("sunrise") {
            return "Sunrise is \(context.conditions?.sunrise?.formatted(date: .omitted, time: .shortened) ?? "unknown")."
        }
        if lower.contains("sunset") || lower.contains("dark") || lower.contains("daylight") {
            let remaining = context.conditions?.daylightRemaining.map { Units.clock($0) } ?? "unknown"
            return "Sunset is \(sunsetText(context)). \(remaining) of daylight."
        }
        if lower.contains("fuel") || lower.contains("petrol") || lower.contains("gas") || lower.contains("range") {
            let range = (context.bike?.fuelRangeKm ?? 0) * context.tankFraction
            let left = range - context.remainingMeters / 1_000
            if range <= 0 { return "I've no range for this bike. Set it in the garage." }
            if left <= 0 { return "You're out of estimated range. Find fuel." }
            return "About \(Units.distanceText(max(left, 0) * 1_000, decimals: 0)) of fuel left."
        }
        if lower.contains("tyre") || lower.contains("tire") || lower.contains("pressure") {
            guard let setup = context.setupNote else { return "No tyre pressures saved for this bike." }
            return "Front \(Units.pressureText(setup.frontPressure)), rear \(Units.pressureText(setup.rearPressure))."
        }
        if lower.contains("odometer") || lower.contains("mileage") {
            guard let bike = context.bike else { return "No bike set in the garage." }
            return "Odometer \(Units.distanceText(bike.odometerKm * 1_000, decimals: 0))."
        }
        if lower.contains("tank") {
            guard let bike = context.bike else { return "No bike set in the garage." }
            return "\(Units.volumeText(bike.tankLiters)) tank, \(Units.distanceText(bike.fuelRangeKm * 1_000, decimals: 0)) range."
        }
        if lower.contains("maintenance") || lower.contains("last service") {
            guard let entry = context.lastMaintenance else { return "No maintenance entries yet." }
            return "Last: \(entry.title) at \(Units.distanceText(entry.odometerKm * 1_000, decimals: 0))."
        }
        if lower.contains("hazard") || lower.contains("worry") {
            guard let distance = context.nearestHazardMeters else {
                return "Nothing on the route right now."
            }
            return "\(context.hazardName ?? "Hazard") in \(Units.shortDistanceText(distance))."
        }
        if lower.contains("how did") || lower.contains("ride go") || lower.contains("stats") {
            let distance = Units.distanceText(context.rideDistanceMeters, decimals: 1)
            let time = Units.clock(context.rideDurationSeconds)
            if let last = context.lastRide, last.distanceMeters > 0 {
                let lastDistance = Units.distanceText(last.distanceMeters, decimals: 1)
                return "\(distance) in \(time). Your last was \(lastDistance)."
            }
            return "\(distance) in \(time)."
        }
        if lower.contains("bike") || lower.contains("service") || lower.contains("chain") {
            guard let bike = context.bike else { return "No bike set in the garage." }
            if bike.isServiceDue { return "Service is due. Chain and fluids." }
            return "Next service in \(Units.distanceText(bike.distanceToServiceKm * 1_000, decimals: 0))."
        }
        if lower.contains("route") || lower.contains("how long is") {
            let name = context.routeName ?? "Route"
            return "\(name): \(Units.distanceText(context.routeLengthMeters, decimals: 1)), \(context.routeClimbMeters > 0 ? Units.elevationText(context.routeClimbMeters) + " climbing" : "flat")."
        }
        if lower.contains("what time") || lower.contains("date") {
            return context.now.formatted(date: .abbreviated, time: .shortened)
        }
        if lower.contains("who are you") {
            return "Ace. I keep an eye on the road."
        }
        if lower.contains("help") || lower.contains("what can you") {
            return "Ask me distance, ETA, speed, next turn, road, fuel, weather, hazards, bike, tyres or service."
        }
        return nil
    }

    /// Questions that must be answered by live data, never by the model.
    static func isFactRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["distance", "far", "fuel", "petrol", "gas", "weather", "rain",
                     "temperature", "hazard", "gravel", "sunset", "sunrise", "dark",
                     "daylight", "home", "work", "service", "chain", "tyre", "tire",
                     "pressure", "odometer", "tank", "maintenance", "speed", "fast", "limit",
                     "eta", "arrive", "turn", "road", "route", "lap", "progress",
                     "lean", "climb", "elevation", "surface", "curve", "corner", "time", "date"]
        return words.contains { lower.contains($0) }
    }

    private static func sunsetText(_ context: CompanionContext) -> String {
        context.conditions?.sunset?.formatted(date: .omitted, time: .shortened) ?? "unknown"
    }
}

nonisolated enum CompanionCheckInGate {
    static func allows(now: Date, lastCheckIn: Date, lastRiderSpeech: Date,
                       context: CompanionContext) -> Bool {
        guard now.timeIntervalSince(lastCheckIn) >= 600 else { return false }
        guard now.timeIntervalSince(lastRiderSpeech) >= 20 else { return false }
        guard !context.hasManeuverSoon, !context.hasHazardSoon else { return false }
        return context.speedMps < 25 || context.isStopped
    }
}

// MARK: - Director

@MainActor
@Observable
final class CompanionDirector {
    static let shared = CompanionDirector()

    private(set) var state: CompanionState
    private(set) var lastLine: String?
    @ObservationIgnored private let memory = CompanionMemory.shared
    @ObservationIgnored private var lastCheckIn = Date.distantPast
    @ObservationIgnored private var lastRiderSpeech = Date.distantPast
    @ObservationIgnored private var lastAnswerAt = Date.distantPast
    @ObservationIgnored private var lastJokeAt = Date.distantPast
    @ObservationIgnored private var jokesThisRide = 0
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var didArrive = false
    @ObservationIgnored private var didRecordRide = false

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "companion.state"),
           let saved = CompanionState(rawValue: raw) {
            state = saved
        } else {
            state = .on
        }
    }

    var addressTerm: String {
        let value = UserDefaults.standard.string(forKey: "companion.addressTerm") ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "boss" : value
    }

    var ridesRemembered: Int { memory.rides }
    var familiarity: Int { memory.familiarity }
    var recentEpisodes: [CompanionEpisode] { memory.episodes }

    func cycleState() {
        setState(state.next)
    }

    func setState(_ newState: CompanionState) {
        guard newState != state else { return }
        state = newState
        UserDefaults.standard.set(newState.rawValue, forKey: "companion.state")
        RevertHaptics.select()
        if newState == .on {
            lastRiderSpeech = Date.distantPast
        }
    }

    func rideStarted(context: CompanionContext) {
        // Off means "no companion". Asked-only still remembers rides and greets
        // on arrival; only the unprompted chatter is gated on On.
        guard state != .off else { return }
        didStart = true
        didArrive = false
        didRecordRide = false
        lastCheckIn = Date()
        jokesThisRide = 0
        guard state == .on, !context.hasManeuverSoon, !context.hasHazardSoon else { return }
        let distance = Units.distanceText(context.routeLengthMeters, decimals: 1)
        let time = context.estimatedSeconds.map { Units.clock($0) } ?? "a while"
        speak(CompanionScript.start(distance: distance, time: time,
                                    isLoop: context.routeIsLoop, address: addressTerm))
    }

    func arrived(context: CompanionContext) {
        guard state != .off, !didArrive, didStart else { return }
        didArrive = true
        let distance = Units.distanceText(context.rideDistanceMeters, decimals: 1)
        let time = Units.clock(context.rideDurationSeconds)
        if state == .on {
            speak(CompanionScript.arrival(distance: distance, time: time, address: addressTerm))
        }
        recordRideIfNeeded(context)
    }

    func rideFinished(context: CompanionContext) {
        if didStart, !didArrive {
            recordRideIfNeeded(context)
        }
        didStart = false
        guard state == .on, let bike = context.bike, bike.isServiceDue else { return }
        // distanceToServiceKm clamps at zero, so a due bike used to be told
        // "due in 0 km".
        let remaining = max(bike.distanceToServiceKm, 0)
        if remaining < 1 {
            speak(CompanionScript.serviceDueNow())
        } else {
            speak(CompanionScript.service(Units.distanceText(remaining * 1_000, decimals: 0)))
        }
    }

    func noteRiderSpoke() {
        lastRiderSpeech = Date()
    }

    func answer(_ text: String, context: CompanionContext) -> String? {
        guard state != .off else { return nil }
        noteRiderSpoke()
        // At speed, one question and one answer. At a stop, the rider can
        // continue the thread. This also absorbs partial speech transcripts.
        if context.speedMps > 1, Date().timeIntervalSince(lastAnswerAt) < 8 {
            return nil
        }
        let lower = text.lowercased()
        if lower.contains("companion off") || lower.contains("turn off companion") || lower.contains("shut up") {
            setState(.off)
            return "Off."
        }
        if lower.contains("companion on") || lower.contains("turn on companion") {
            setState(.on)
            return "On."
        }
        if lower.contains("asked only") || lower.contains("only when asked") {
            setState(.askedOnly)
            return "Asked only."
        }
        // "Say that again" must work even as the rider approaches a turn —
        // that is exactly when it is asked.
        if lower.contains("repeat") || lower.contains("say that again")
            || lower.contains("what was that turn") || lower.contains("what did you say") {
            guard let last = context.lastInstruction, !last.isEmpty else {
                return "I've no instruction yet."
            }
            return last
        }
        if context.hasManeuverSoon { return nil }
        if lower.contains("joke") {
            guard context.speedMps < 18 else { return nil }
            if let line = joke() {
                lastAnswerAt = Date()
                return line
            }
            return nil
        }
        guard let local = CompanionTools.answer(text, context: context) else { return nil }
        lastAnswerAt = Date()
        return local
    }

    /// Tier 2 path. It is only reached when no deterministic tool matched and
    /// the question does not look like a live-fact request.
    func freeFormAnswer(_ text: String, context: CompanionContext) async -> String? {
        guard state != .off else { return nil }
        noteRiderSpoke()
        if context.hasManeuverSoon { return nil }
        if CompanionTools.isFactRequest(text) {
            return CompanionScript.unknown()
        }
        if text.lowercased().contains("joke") {
            return nil
        }
        if let generated = await CompanionLanguageModel.respond(to: text) {
            if context.speedMps > 1, Date().timeIntervalSince(lastAnswerAt) < 8 {
                return nil
            }
            lastAnswerAt = Date()
            return generated
        }
        return CompanionScript.unknown()
    }

    /// One unprompted line per ten minutes, and only when the rider is not
    /// already busy with a maneuver, hazard, or their own question.
    func tick(context: CompanionContext) {
        guard state == .on, didStart else { return }
        let now = Date()
        guard CompanionCheckInGate.allows(now: now, lastCheckIn: lastCheckIn,
                                          lastRiderSpeech: lastRiderSpeech,
                                          context: context) else { return }

        let line: String?
        if context.loopCountThisMonth >= 3 {
            line = CompanionScript.thirdLoop()
        } else if context.isStopped, now.timeIntervalSince(lastCheckIn) >= 1_800 {
            line = CompanionScript.longStop()
        } else if let warning = context.conditions?.warnings.first,
                  warning.localizedCaseInsensitiveContains("sunset") {
            line = warning
        } else {
            let range = (context.bike?.fuelRangeKm ?? 0) * context.tankFraction
            let left = range - context.remainingMeters / 1_000
            if range > 0, left > 0, left < 45 {
                line = CompanionScript.range(Units.distanceText(left * 1_000, decimals: 0))
            } else {
                line = nil
            }
        }
        guard let line else { return }
        lastCheckIn = now
        speak(line)
    }

    func resetMemory() {
        memory.reset()
    }

    private func joke() -> String? {
        guard state != .off else { return nil }
        guard jokesThisRide == 0 else { return "I've used my one for this ride." }
        guard Date().timeIntervalSince(lastJokeAt) > 300 else { return nil }
        let recent = Set(memory.recentJokeIDs)
        guard let joke = CompanionScript.jokes.first(where: { !recent.contains($0.id) }) else {
            return CompanionScript.jokes.randomElement()?.text
        }
        lastJokeAt = Date()
        jokesThisRide += 1
        memory.recordJoke(joke.id)
        return joke.text
    }

    private func recordRideIfNeeded(_ context: CompanionContext) {
        guard !didRecordRide else { return }
        didRecordRide = true
        memory.recordRide(routeKey: context.routeKey,
                          routeName: context.routeName,
                          distanceMeters: context.rideDistanceMeters,
                          durationSeconds: context.rideDurationSeconds,
                          note: didArrive ? "Arrived" : "Stopped")
    }

    private func speak(_ text: String) {
        lastLine = text
        Speaker.shared.say(text, kind: .companion)
    }
}

// MARK: - Cockpit chip

struct CompanionStateChip: View {
    @State private var director = CompanionDirector.shared
    var compact = false

    var body: some View {
        Button {
            director.cycleState()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: director.state.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(compact ? "ACE" : "ACE \(director.state.shortTitle)")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(director.state == .off ? MapUI.textTertiary : MapUI.ink)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(MapUI.panel.opacity(0.82), in: Capsule())
            .overlay(Capsule().stroke(director.state == .off ? MapUI.line : MapUI.accent.opacity(0.4),
                                      lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.5) {
            director.setState(.off)
        }
        .accessibilityLabel("Companion \(director.state.title)")
        .accessibilityHint("Tap to cycle On, Asked only and Off; long press to silence")
    }
}

// MARK: - Settings

struct CompanionSettingsView: View {
    @State private var director = CompanionDirector.shared
    @AppStorage("companion.addressTerm") private var addressTerm = "boss"
    @AppStorage("companion.wakeWord") private var wakeWord = true
    @AppStorage("companion.voice") private var aceVoice = true
    @AppStorage("voice.muted") private var voiceMuted = false
    @AppStorage("companion.preferBluetoothMic") private var preferBluetoothMic = true
    @State private var audioRoute = AudioRouteMonitor.shared
    @State private var confirmingForget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RevertInfoNote(
                    text: "Ace is on-device only. He answers distance, fuel, weather, hazards, sunset and bike questions. Off closes the microphone and never mutes navigation.",
                    systemImage: "waveform",
                    tint: Pulse.accent
                )

                if !CompanionLanguageModel.isAvailable {
                    RevertInfoNote(
                        text: "This iPhone can't run Ace's open-ended answers (Apple Intelligence is off, still downloading, or unsupported). Distance, fuel, weather, hazards, sunset and bike questions still work from built-in answers.",
                        systemImage: "exclamationmark.triangle",
                        tint: Pulse.warning
                    )
                }

                RevertSectionLabel(title: "Companion state")
                Picker("Companion", selection: Binding(
                    get: { director.state },
                    set: { director.setState($0) }
                )) {
                    ForEach(CompanionState.allCases) { state in
                        Text(state.title).tag(state)
                    }
                }
                .pickerStyle(.segmented)

                RevertSectionLabel(title: "Voice")
                Toggle(isOn: $aceVoice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ace speaks")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Pulse.ink)
                        Text("Separate from hazard and navigation voice. The cockpit's mute switch still silences everything.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .pulseCard()
                if voiceMuted {
                    RevertInfoNote(
                        text: "Voice is muted in the cockpit. Ace's state is unchanged, but nothing will be heard until you unmute.",
                        systemImage: "speaker.slash",
                        tint: Pulse.warning
                    )
                }

                RevertSectionLabel(title: "Wake word")
                Toggle(isOn: $wakeWord) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“Hey Ace” while riding")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Pulse.ink)
                        Text("Always waiting while a ride is active. Say “Hey Ace” before a question; the on-device microphone stays open and uses battery. Turn it off to use the mic button instead.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .pulseCard()
                .onChange(of: wakeWord) { _, on in
                    if on, director.state == .off { director.setState(.on) }
                }

                RevertSectionLabel(title: "Helmet microphone")
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: audioRoute.isBluetoothConnected ? "headphones" : "iphone.gen3")
                            .foregroundStyle(audioRoute.isBluetoothConnected ? Pulse.emerald : Pulse.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audioRoute.routeSummary)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Pulse.ink)
                            Text(audioRoute.isBluetoothConnected
                                 ? "Bluetooth headset detected. The companion will prefer its microphone for “Hey Ace” and questions."
                                 : "No Bluetooth headset detected. The iPhone microphone is the fallback.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Pulse.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Toggle("Prefer Bluetooth / Cardo microphone", isOn: $preferBluetoothMic)
                        .font(.system(.caption, design: .rounded))
                }
                .pulseCard()
                .onAppear {
                    audioRoute.start()
                    audioRoute.refresh()
                }
                RevertSectionLabel(title: "Address")
                HStack {
                    Text("Call the rider")
                    Spacer()
                    TextField("boss", text: $addressTerm)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                }
                .pulseCard()

                RevertSectionLabel(title: "Memory", detail: "On this iPhone")
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(director.ridesRemembered) rides remembered")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Pulse.ink)
                    Text("Familiarity \(director.familiarity)/5. Jokes and preferences are local; nothing is uploaded.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pulse.muted)
                    if let last = director.recentEpisodes.last {
                        Text("Last: \(last.routeName ?? "ride") · \(Units.distanceText(last.distanceMeters, decimals: 1)) · \(last.note)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Pulse.muted)
                    }
                    Button(role: .destructive) {
                        confirmingForget = true
                    } label: {
                        Label("Forget everything", systemImage: "trash")
                    }
                    .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                }
                .pulseCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .pulseBackground()
        .navigationTitle("Companion")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Forget everything?", isPresented: $confirmingForget) {
            Button("Forget", role: .destructive) { director.resetMemory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears remembered rides, jokes and familiarity on this iPhone.")
        }
    }
}
