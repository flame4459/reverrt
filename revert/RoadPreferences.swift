import Foundation

/// Normalized road-name matching and the bounded multipliers the planner uses.
///
/// The old planner gave an exact name match a 0.42x cost, which let one typed
/// road name dominate an entire loop. These multipliers are deliberately
/// bounded so a preference nudges the search instead of steering it.
nonisolated struct RoadPreferences: Sendable {
    /// Normalized names the rider asked for.
    var preferred: Set<String> = []
    /// Normalized names to avoid (construction, bad surface, disliked road).
    var avoided: Set<String> = []
    /// Normalized name -> number of times the rider started a route using it.
    var learned: [String: Int] = [:]

    static let empty = RoadPreferences()

    // MARK: Name normalization
    private static let abbreviations: [String: String] = [
        "st": "street", "rd": "road", "blvd": "boulevard", "ave": "avenue",
        "hwy": "highway", "ln": "lane", "dr": "drive", "pkwy": "parkway",
        "cir": "circle", "ct": "court", "pl": "place", "trl": "trail",
        "tpke": "turnpike", "expy": "expressway", "sq": "square"
    ]

    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var tokens: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        let expanded = tokens.map { abbreviations[$0] ?? $0 }
        // Route numbers are often written "CA 9", "Route 9" or "9"; keep the
        // words but drop pure filler so "route 9" still matches "State Route 9".
        return expanded.joined(separator: " ")
    }

    /// True when a normalized road name contains the normalized query.
    /// Multi-word queries must appear as a contiguous phrase; a single word of
    /// four or more characters may appear anywhere as a whole word.
    static func matches(_ normalizedName: String, query: String) -> Bool {
        guard !normalizedName.isEmpty, !query.isEmpty else { return false }
        if normalizedName == query { return true }
        let paddedName = " \(normalizedName) "
        let paddedQuery = " \(query) "
        if paddedName.contains(paddedQuery) { return true }
        guard !query.contains(" "), query.count >= 4 else { return false }
        return paddedName.contains(paddedQuery)
    }

    func multiplier(for road: Road) -> Double {
        let names = [road.name, road.ref]
            .compactMap { $0 }
            .map(RoadPreferences.normalize)
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return 1 }

        for name in names where avoided.contains(where: { RoadPreferences.matches(name, query: $0) }) {
            return 2.6
        }
        for name in names where preferred.contains(where: { RoadPreferences.matches(name, query: $0) }) {
            return 0.85
        }
        var multiplier = 1.0
        for name in names {
            if let started = learned[name], started > 0 {
                multiplier = min(multiplier, max(0.82, 1 - 0.04 * Double(started)))
            }
        }
        return multiplier
    }
}

/// Local, on-device "taste" store. It only ever records which roads the rider
/// actually chose to ride, plus any names they explicitly avoid or prefer.
nonisolated final class RouteTaste: @unchecked Sendable {
    static let shared = RouteTaste()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let startedKey = "taste.startedRoads"
    private let avoidedKey = "taste.avoidedRoads"
    private let preferredKey = "taste.preferredRoads"
    private let maximumStartedEntries = 120

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> RoadPreferences {
        lock.lock()
        defer { lock.unlock() }
        return RoadPreferences(
            preferred: Set(defaults.stringArray(forKey: preferredKey) ?? []),
            avoided: Set(defaults.stringArray(forKey: avoidedKey) ?? []),
            learned: defaults.dictionary(forKey: startedKey) as? [String: Int] ?? [:]
        )
    }

    /// Called when the rider actually starts a planned route. This is the
    /// implicit signal: a loop that was good enough to ride gets its roads
    /// slightly cheaper next time.
    func recordStarted(_ roadNames: [String]) {
        guard !roadNames.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var started = defaults.dictionary(forKey: startedKey) as? [String: Int] ?? [:]
        for name in roadNames {
            let normalized = RoadPreferences.normalize(name)
            guard normalized.count >= 3 else { continue }
            started[normalized, default: 0] += 1
        }
        if started.count > maximumStartedEntries {
            let keep = started.sorted { $0.value > $1.value }.prefix(maximumStartedEntries)
            started = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        defaults.set(started, forKey: startedKey)
    }

    func prefer(_ name: String) {
        mutateList(preferredKey, adding: name, removingFrom: avoidedKey)
    }

    func avoid(_ name: String) {
        mutateList(avoidedKey, adding: name, removingFrom: preferredKey)
    }

    func clearLearned() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: startedKey)
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: startedKey)
        defaults.removeObject(forKey: avoidedKey)
        defaults.removeObject(forKey: preferredKey)
    }

    private func mutateList(_ addKey: String, adding name: String, removingFrom removeKey: String) {
        let normalized = RoadPreferences.normalize(name)
        guard !normalized.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var list = defaults.stringArray(forKey: addKey) ?? []
        if !list.contains(normalized) { list.append(normalized) }
        defaults.set(Array(list.suffix(60)), forKey: addKey)
        let other = (defaults.stringArray(forKey: removeKey) ?? []).filter { $0 != normalized }
        defaults.set(other, forKey: removeKey)
    }
}
