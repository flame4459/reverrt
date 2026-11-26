import Foundation

/// Turns Revert's directions and alerts into a mix of voice-pack clips and
/// synthesised text.
///
/// Voice packs only contain fixed sentences ("Turn right", "In 400 meters").
/// Anything dynamic — a street name, a speed, a distance Waze never recorded —
/// is spoken by the system voice, exactly like Waze itself does. Every clip
/// carries its own fallback wording, so an incomplete pack still sounds like a
/// voice pack: only the missing phrase is synthesised, not the whole sentence.
@MainActor
enum Narrator {
    // MARK: Examples (Settings previews)

    static var exampleAlert: VoicePrompt {
        VoicePrompt(
            parts: [.clip(.approachSpeedCamera, fallback: "Speed camera"), .text("in 300 feet")],
            fallback: "Speed camera in 300 feet"
        )
    }

    static var exampleInstruction: VoicePrompt {
        let spoken = Units.spokenDistance(800)
        let distance = Units.isMetric ? VoiceClip.distance800 : VoiceClip.distance800Imperial
        return VoicePrompt(
            parts: [
                .optionalClip(distance),
                .clip(.turnRight, fallback: "Turn right"),
                .text("onto Market Street")
            ],
            fallback: "In \(spoken), turn right onto Market Street"
        )
    }

    /// A pack-only sample for the picker: no street name, so the preview shows
    /// the recorded voice rather than mixing in the system synthesiser.
    static var previewInstruction: VoicePrompt {
        let spoken = Units.spokenDistance(800)
        let distance = Units.isMetric ? VoiceClip.distance800 : VoiceClip.distance800Imperial
        return VoicePrompt(
            parts: [.optionalClip(distance), .clip(.turnRight, fallback: "Turn right")],
            fallback: "In \(spoken), turn right"
        )
    }

    // MARK: Navigation

    static var arrival: VoicePrompt {
        VoicePrompt(parts: [.clip(.arrive, fallback: "You have arrived")],
                    fallback: "You have arrived")
    }

    static var routeUpdated: VoicePrompt {
        VoicePrompt(parts: [.clip(.ticker, fallback: "Route updated")],
                    fallback: "Route updated")
    }

    static func routeStarted(road: String?) -> VoicePrompt {
        let normalized = road.map(StreetNames.road)
        let fallback = normalized.map { "Route started. Head out on \($0)" } ?? "Route started"
        var parts: [VoicePrompt.Part] = [
            .clip(.randomStart(), fallback: "Starting navigation")
        ]
        if let normalized, !normalized.isEmpty {
            parts.append(.text("on \(normalized)"))
        }
        return VoicePrompt(parts: parts, fallback: fallback)
    }

    /// A long straight: Google-style "Continue on <road> for <distance>".
    static func straight(road: String?, distance: Double) -> VoicePrompt {
        let spoken = Units.spokenDistance(distance)
        let normalized = road.map(StreetNames.road)
        let fallback: String
        var parts: [VoicePrompt.Part] = [
            .clip(.straight, fallback: "Continue straight")
        ]
        if let normalized, !normalized.isEmpty {
            fallback = "Continue on \(normalized) for \(spoken)"
            parts.append(.text("on \(normalized)"))
        } else {
            fallback = "Continue straight for \(spoken)"
        }
        parts.append(.text("for \(spoken)"))
        return VoicePrompt(parts: parts, fallback: fallback)
    }

    /// "Turn left onto X" reads as "In 300 feet, turn left onto X": after a
    /// distance the verb loses its capital, as it does in every nav voice.
    private static func afterDistance(_ instruction: String) -> String {
        guard let first = instruction.first else { return instruction }
        return first.lowercased() + instruction.dropFirst()
    }

    /// A turn-by-turn announcement. `distance` is the distance still to run
    /// before the manoeuvre, or `nil` when the rider is almost on it.
    static func instruction(_ step: NavStep, distance: Double?) -> VoicePrompt {
        let spokenInstruction = afterDistance(step.instruction)
        let laneLead = step.laneGuidance.flatMap { lanes -> String? in
            distance == nil || lanes.phrase.isEmpty ? nil : "\(lanes.phrase) to "
        } ?? ""
        let fallback = distance.map { "In \(Units.spokenDistance($0)), \(laneLead)\(spokenInstruction)" }
            ?? step.instruction

        if step.turn == .arrive {
            // The arrive step is current for the last few hundred metres, so a
            // bare "You have arrived" used to fire a quarter mile early.
            // Within a few metres it is the arrival itself, not an approach.
            guard let distance, distance > 30 else { return arrival }
            let spoken = Units.spokenDistance(distance)
            return VoicePrompt(
                parts: [.clip(.arrive, fallback: "You will arrive")],
                fallback: "In \(spoken), you will arrive"
            )
        }

        // MapKit routes carry prose ("Turn right onto Market Street"); offline
        // routes carry a manoeuvre and a road name.
        if let text = step.text, !text.isEmpty {
            var parts = parse(text)
            if let distance {
                // Accuracy rule: the distance is spoken by TTS at the value the
                // rider is actually approaching. Recorded clips exist only at a
                // handful of lengths; using the nearest one turned 55 m into
                // "200 meters".
                parts.insert(.text("In \(Units.spokenDistance(distance))"), at: 0)
            }
            return parts.isEmpty ? VoicePrompt(text: fallback)
                                 : VoicePrompt(parts: parts, fallback: fallback)
        }

        var parts: [VoicePrompt.Part] = []
        if let distance {
            parts.append(.text("In \(Units.spokenDistance(distance))"))
        }
        if let lanes = step.laneGuidance, !lanes.phrase.isEmpty {
            // At the final prompt there is no "in X, …" lead to attach to, so
            // the lane advice becomes its own short sentence. Dropping it here
            // removed the one cue that matters as the rider commits.
            parts.append(.text(distance == nil ? "\(lanes.phrase)." : "\(lanes.phrase) to"))
        }
        if let clip = turnClip(step.turn) {
            parts.append(.clip(clip, fallback: turnPhrase(step.turn)))
        }
        if let road = step.road, !road.isEmpty {
            let normalized = StreetNames.road(road)
            parts.append(.text(step.turn == .start ? "on \(normalized)" : "onto \(normalized)"))
        }
        guard parts.contains(where: { part in
            switch part {
            case .clip, .optionalClip: return true
            case .text: return false
            }
        }) else {
            return VoicePrompt(text: fallback)
        }
        return VoicePrompt(parts: parts, fallback: fallback)
    }

    static func turnClip(_ turn: NavStep.Turn) -> VoiceClip? {
        switch turn {
        case .left, .sharpLeft: .turnLeft
        case .slightLeft: .keepLeft
        case .right, .sharpRight: .turnRight
        case .slightRight: .keepRight
        case .straight: .straight
        case .uTurn: .uTurn
        case .start, .arrive: nil
        }
    }

    static func turnPhrase(_ turn: NavStep.Turn) -> String {
        switch turn {
        case .start: "Start riding"
        case .straight: "Continue straight"
        case .slightLeft: "Keep left"
        case .left: "Turn left"
        case .sharpLeft: "Sharp left"
        case .slightRight: "Keep right"
        case .right: "Turn right"
        case .sharpRight: "Sharp right"
        case .uTurn: "Make a U-turn"
        case .arrive: "You have arrived"
        }
    }

    /// An approach-to-start manoeuvre. `ApproachStep` carries prose, not a
    /// `NavStep`, so this keeps the same distance-first, lower-cased wording.
    static func approach(_ instruction: String, distance: Double) -> VoicePrompt {
        VoicePrompt(text: "In \(Units.spokenDistance(distance)), \(afterDistance(instruction))")
    }

    /// The rider is not on the route yet: tell them where the start is.
    static func startGuidance(distance: Double) -> VoicePrompt {
        VoicePrompt(text: "Head to the start. \(Units.spokenDistance(distance)) away.")
    }

    static func lap(_ lap: Int, of total: Int, last: TimeInterval?) -> VoicePrompt {
        var text = "Lap \(lap) of \(total)."
        if let last, last.isFinite, last > 10 {
            text += " \(Units.spokenClock(last)) for the last one."
        }
        return VoicePrompt(text: text)
    }

    static func loopComplete(total: TimeInterval?) -> VoicePrompt {
        if let total, total.isFinite, total > 10 {
            return VoicePrompt(text: "Loop complete. \(Units.spokenClock(total)) total.")
        }
        return VoicePrompt(text: "Loop complete.")
    }

    static func sprintFinish(time: TimeInterval?) -> VoicePrompt {
        if let time, time.isFinite, time > 5 {
            return VoicePrompt(text: "Finish. \(Units.spokenClock(time)).")
        }
        return VoicePrompt(text: "Finish.")
    }

    static let missedTurn = VoicePrompt(text: "You missed the turn. Finding a new route.")
    static let offRoute = VoicePrompt(text: "Off route. Finding a way back.")
    static let backOnRoute = VoicePrompt(text: "Back on route.")
    static let navigationEnded = VoicePrompt(text: "Navigation ended.")
    static let routeUpdatedContinue = VoicePrompt(text: "Route updated. Continue.")

    // MARK: Alerts

    static func hazard(_ kind: HazardKind, distance: Double) -> VoicePrompt {
        let spokenDistance = Units.spokenApproachDistance(distance)
        let fallback = "\(kind.approachName) in \(spokenDistance)"
        let clip: VoiceClip?
        switch kind {
        case .speedCamera: clip = .approachSpeedCamera
        case .redLightCamera: clip = .approachRedLightCamera
        case .userMark: clip = nil
        default: clip = nil
        }
        guard let clip else { return VoicePrompt(text: fallback) }
        return VoicePrompt(
            parts: [.clip(clip, fallback: kind.approachName), .text("in \(spokenDistance)")],
            fallback: fallback
        )
    }

    // MARK: Prose parsing

    /// Splits an English MapKit instruction into a recorded manoeuvre clip and
    /// whatever follows it (usually "onto Main Street", spoken by TTS).
    static func parse(_ text: String) -> [VoicePrompt.Part] {
        var working = StreetNames.instruction(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !working.isEmpty else { return [] }

        // MapKit can prefix its own distance; Revert announces distance first.
        if working.lowercased().hasPrefix("in "),
           let comma = working.firstIndex(of: ","),
           working.distance(from: working.startIndex, to: comma) < 28 {
            working = String(working[working.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
        }

        let lower = working.lowercased()

        // Roundabout exits. A Waze pack records each ordinal as a whole phrase
        // ("take the second exit"), so use it instead of handing that part of
        // the instruction to the system voice.
        if let exitParts = roundaboutExitParts(working) {
            var parts: [VoicePrompt.Part] = []
            if lower.contains("roundabout") {
                parts.append(.clip(.roundabout, fallback: "At the roundabout"))
            }
            parts.append(contentsOf: exitParts)
            return parts
        }

        let manoeuvres: [(phrase: String, clip: VoiceClip, spoken: String)] = [
            ("continue straight", .straight, "Continue straight"),
            ("continue", .straight, "Continue"),
            ("head straight", .straight, "Continue straight"),
            ("go straight", .straight, "Continue straight"),
            ("proceed", .straight, "Continue"),
            ("turn left", .turnLeft, "Turn left"),
            ("turn right", .turnRight, "Turn right"),
            ("keep left", .keepLeft, "Keep left"),
            ("keep right", .keepRight, "Keep right"),
            ("bear left", .keepLeft, "Keep left"),
            ("bear right", .keepRight, "Keep right"),
            ("slight left", .keepLeft, "Slight left"),
            ("slight right", .keepRight, "Slight right"),
            ("sharp left", .turnLeft, "Sharp left"),
            ("sharp right", .turnRight, "Sharp right"),
            ("merge left", .keepLeft, "Merge left"),
            ("merge right", .keepRight, "Merge right"),
            ("fork left", .keepLeft, "Keep left"),
            ("fork right", .keepRight, "Keep right"),
            ("stay left", .keepLeft, "Stay left"),
            ("stay right", .keepRight, "Stay right"),
            ("take the ramp on the left", .exitLeft, "Take the ramp on the left"),
            ("take the ramp on the right", .exitRight, "Take the ramp on the right"),
            ("take the ramp", .exitRight, "Take the ramp"),
            ("make a u-turn", .uTurn, "Make a U-turn"),
            ("make a u turn", .uTurn, "Make a U-turn"),
            ("u-turn", .uTurn, "Make a U-turn"),
            ("take the exit on the left", .exitLeft, "Take the exit on the left"),
            ("take the exit on the right", .exitRight, "Take the exit on the right"),
            ("take exit on the left", .exitLeft, "Take the exit on the left"),
            ("take exit on the right", .exitRight, "Take the exit on the right"),
            ("at the roundabout", .roundabout, "At the roundabout"),
            ("roundabout", .roundabout, "At the roundabout"),
            ("you have arrived", .arrive, "You have arrived"),
            ("arrive", .arrive, "You have arrived")
        ]

        for manoeuvre in manoeuvres where lower.hasPrefix(manoeuvre.phrase) {
            let rest = String(working.dropFirst(manoeuvre.phrase.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
            var parts: [VoicePrompt.Part] = [
                .clip(manoeuvre.clip, fallback: manoeuvre.spoken)
            ]
            if !rest.isEmpty, rest.lowercased() != "at your destination" {
                parts.append(.text(rest))
            }
            return parts
        }
        return []
    }

    /// Every ordinal a Waze pack records, with the clip that says it.
    private static let roundaboutExitClips: [(word: String, clip: VoiceClip, spoken: String)] = [
        ("1st", .firstExit, "first"),
        ("first", .firstExit, "first"),
        ("2nd", .secondExit, "second"),
        ("second", .secondExit, "second"),
        ("3rd", .thirdExit, "third"),
        ("third", .thirdExit, "third"),
        ("4th", .fourthExit, "fourth"),
        ("fourth", .fourthExit, "fourth"),
        ("5th", .fifthExit, "fifth"),
        ("fifth", .fifthExit, "fifth"),
        ("6th", .sixthExit, "sixth"),
        ("sixth", .sixthExit, "sixth"),
        ("7th", .seventhExit, "seventh"),
        ("seventh", .seventhExit, "seventh")
    ]

    /// Splits "…take the 2nd exit onto Main Street" into the recorded exit
    /// phrase and the road name. Returns nil when the instruction has no
    /// ordinal exit (a plain "take the exit on the left", an eighth exit, or
    /// a street that happens to contain the word "exit").
    private static func roundaboutExitParts(_ text: String) -> [VoicePrompt.Part]? {
        let lower = text.lowercased()
        // Indices from `lower` are only safe on `text` when the fold kept the
        // same byte layout; otherwise fall back to the system voice.
        guard lower.utf8.count == text.utf8.count,
              let exitRange = lower.range(of: " exit") else { return nil }
        let lead = String(lower[..<exitRange.lowerBound])
        guard let match = roundaboutExitClips.first(where: { lead.hasSuffix($0.word) }) else { return nil }

        // Reject "21st", "twenty-first": the ordinal has to stand on its own.
        let start = lead.index(lead.endIndex, offsetBy: -match.word.count)
        if start > lead.startIndex {
            let previous = lead[lead.index(before: start)]
            guard !previous.isNumber, !previous.isLetter, previous != "-" else { return nil }
        }

        let cut = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: exitRange.upperBound))
        let trailing = String(text[cut...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        var parts: [VoicePrompt.Part] = [.clip(match.clip, fallback: "take the \(match.spoken) exit")]
        if !trailing.isEmpty { parts.append(.text(trailing)) }
        return parts
    }
}
