import Foundation

/// Decides which spoken stage is due for the next manoeuvre.
///
/// The cockpit used to track "rung 1/2/3" as indices. The rung *distances*
/// depend on speed, so when a rider slowed from highway to town speed the
/// indices already recorded at 3 km suppressed the 300 m and 150 m prompts
/// that had never been spoken at those distances. Stages are tracked by kind
/// instead: the thresholds move with speed, the record of what the rider has
/// actually heard does not.
nonisolated struct AnnouncementScheduler {

    /// Early awareness → primary approach → close reminder → immediate.
    enum Stage: Int, CaseIterable, Comparable, Sendable {
        case early = 0
        case middle = 1
        case close = 2
        case final = 3

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
        var title: String {
            switch self {
            case .early: "early"
            case .middle: "middle"
            case .close: "close"
            case .final: "final"
            }
        }
    }

    struct State: Equatable, Sendable {
        var spoken: Set<Stage> = []
        var lastDistance: Double?
        var lastAt: Date?

        init(spoken: Set<Stage> = [], lastDistance: Double? = nil, lastAt: Date? = nil) {
            self.spoken = spoken
            self.lastDistance = lastDistance
            self.lastAt = lastAt
        }
    }

    struct Decision: Equatable, Sendable {
        let stage: Stage
        /// `nil` means the immediate prompt ("Turn left onto X") with no distance.
        let spokenDistance: Double?
        /// What the scheduler actually measured; useful for tests and logs.
        let actualDistance: Double
    }

    /// The distance at which each stage becomes due for this speed.
    static func thresholds(speed: Double) -> [Stage: Double] {
        let early = NavigationManager.approachDistance(forSpeed: speed)
        let close = max(150, early * 0.18)
        let final = NavigationManager.finalPromptDistance(forSpeed: speed)
        // A close reminder inside the immediate band is noise, not information.
        let middle = max(early * 0.5, close + 60)
        return [.early: early,
                .middle: middle,
                .close: close,
                .final: final]
    }

    /// Apply one GPS update. Mutates `state` only when an announcement is
    /// actually returned; a skipped announcement stays available for a later
    /// fix at a distance where it is still useful.
    static func decide(state: inout State,
                       distance: Double,
                       speed: Double,
                       now: Date = Date(),
                       minimumGapMeters: Double = 40,
                       minimumGapSeconds: TimeInterval = 2.0) -> Decision? {
        guard distance.isFinite, distance >= 0 else { return nil }
        let limits = thresholds(speed: speed)
        let due = Stage.allCases.filter { stage in
            guard let limit = limits[stage] else { return false }
            return distance <= limit && !state.spoken.contains(stage)
        }
        guard let chosen = due.max() else { return nil }

        // Do not machine-gun the rider when the thresholds land close together
        // (or when GPS jitter moves the distance by a few metres).
        if let last = state.lastDistance {
            let gap = max(minimumGapMeters, speed * minimumGapSeconds)
            if last - distance < gap { return nil }
        }

        let hadSpokenEarlier = !state.spoken.isEmpty
        for stage in Stage.allCases {
            guard let limit = limits[stage], let chosenLimit = limits[chosen] else { continue }
            if limit >= chosenLimit { state.spoken.insert(stage) }
        }
        state.lastDistance = distance
        state.lastAt = now

        // The immediate prompt is only "Turn left" when the rider has already
        // had an advance warning. A step that becomes current at 40 m gets the
        // distance with it, or the rider hears a turn with no range.
        let spokenDistance: Double? = (chosen == .final && hadSpokenEarlier) ? nil : distance
        return Decision(stage: chosen, spokenDistance: spokenDistance, actualDistance: distance)
    }

    /// Would a turn announcement fire with this state? Used to keep a
    /// low-value "continue on" line from cancelling it in the same fix.
    static func wouldAnnounce(state: State, distance: Double, speed: Double) -> Bool {
        var probe = state
        return decide(state: &probe, distance: distance, speed: speed) != nil
    }
}
