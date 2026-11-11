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
        let fallback = road.map { "Route started. Head out on \($0)" } ?? "Route started"
        var parts: [VoicePrompt.Part] = [
            .clip(.randomStart(), fallback: "Starting navigation")
        ]
        if let road, !road.isEmpty {
            parts.append(.text("on \(road)"))
        }
        return VoicePrompt(parts: parts, fallback: fallback)
    }

    /// A turn-by-turn announcement. `distance` is the distance still to run
    /// before the manoeuvre, or `nil` when the rider is almost on it.
    static func instruction(_ step: NavStep, distance: Double?) -> VoicePrompt {
        let fallback = distance.map { "In \(Units.spokenDistance($0)), \(step.instruction)" }
            ?? step.instruction

        if step.turn == .arrive { return arrival }

        // MapKit routes carry prose ("Turn right onto Market Street"); offline
        // routes carry a manoeuvre and a road name.
        if let text = step.text, !text.isEmpty, step.road == nil {
            var parts = parse(text)
            if let distance,
               let clip = VoiceClip.distanceClip(forMeters: distance, metric: Units.isMetric) {
                parts.insert(.optionalClip(clip), at: 0)
            }
            return parts.isEmpty ? VoicePrompt(text: fallback)
                                 : VoicePrompt(parts: parts, fallback: fallback)
        }

        var parts: [VoicePrompt.Part] = []
        if let distance,
           let clip = VoiceClip.distanceClip(forMeters: distance, metric: Units.isMetric) {
            parts.append(.optionalClip(clip))
        }
        if let clip = turnClip(step.turn) {
            parts.append(.clip(clip, fallback: turnPhrase(step.turn)))
        }
        if let road = step.road, !road.isEmpty {
            parts.append(.text(step.turn == .start ? "on \(road)" : "onto \(road)"))
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

    // MARK: Alerts

    static func hazard(_ kind: HazardKind, distance: Double) -> VoicePrompt {
        let spokenDistance = Units.spokenApproachDistance(distance)
        let fallback = "\(kind.approachName) in \(spokenDistance)"
        let clip: VoiceClip?
        switch kind {
        case .speedCamera: clip = .approachSpeedCamera
        case .redLightCamera: clip = .approachRedLightCamera
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
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return [] }

        // MapKit can prefix its own distance; Revert announces distance first.
        if working.lowercased().hasPrefix("in "),
           let comma = working.firstIndex(of: ","),
           working.distance(from: working.startIndex, to: comma) < 28 {
            working = String(working[working.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
        }

        let lower = working.lowercased()
        let manoeuvres: [(phrase: String, clip: VoiceClip, spoken: String)] = [
            ("continue straight", .straight, "Continue straight"),
            ("head straight", .straight, "Continue straight"),
            ("go straight", .straight, "Continue straight"),
            ("turn left", .turnLeft, "Turn left"),
            ("turn right", .turnRight, "Turn right"),
            ("keep left", .keepLeft, "Keep left"),
            ("keep right", .keepRight, "Keep right"),
            ("bear left", .keepLeft, "Keep left"),
            ("bear right", .keepRight, "Keep right"),
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
}
