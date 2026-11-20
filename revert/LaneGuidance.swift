import Foundation

/// Lane-level advice derived from OpenStreetMap's `turn:lanes` tagging.
///
/// OSM writes it as one entry per lane, left to right, separated by `|`, with
/// `;` for a lane that serves several movements:
///
///     turn:lanes = left|through|through;right
///
/// That is the whole model: which lane may do what at the junction ahead.
nonisolated struct LaneGuidance: Hashable, Codable, Sendable {
    enum Direction: String, Codable, Sendable {
        case left, slightLeft, through, slightRight, right
        case sharpLeft, sharpRight, uTurn, mergeLeft, mergeRight, none
    }

    struct Lane: Hashable, Codable, Sendable {
        let directions: [Direction]

        var symbol: String {
            if directions.contains(.left) || directions.contains(.sharpLeft) { return "arrow.turn.up.left" }
            if directions.contains(.right) || directions.contains(.sharpRight) { return "arrow.turn.up.right" }
            if directions.contains(.slightLeft) { return "arrow.up.left" }
            if directions.contains(.slightRight) { return "arrow.up.right" }
            if directions.contains(.uTurn) { return "arrow.uturn.left" }
            return "arrow.up"
        }
    }

    /// Every lane at the junction, left to right.
    let lanes: [Lane]
    /// Indices of the lanes that serve the coming manoeuvre.
    let recommended: [Int]

    var activeCount: Int { recommended.count }

    var phrase: String {
        guard !recommended.isEmpty else { return "" }
        let count = recommended.count
        if recommended.first == 0 {
            return count == 1 ? "use the left lane" : "use the \(Self.number(count)) left lanes"
        }
        if recommended.last == lanes.count - 1 {
            return count == 1 ? "use the right lane" : "use the \(Self.number(count)) right lanes"
        }
        return count == 1 ? "use the centre lane" : "use the \(Self.number(count)) centre lanes"
    }

    /// Which lanes to draw as active, left to right, for a banner.
    var activeFlags: [Bool] {
        lanes.indices.map { recommended.contains($0) }
    }

    /// When to draw the lane strip. The spoken prompt still follows the
    /// speed-band table; the drawing waits until the rider is close enough to
    /// use it, roughly 1 km on a highway and 400 m in town.
    static func revealDistance(forSpeed speed: Double) -> Double {
        if speed > 25 { return 1_600 }
        if speed > 15 { return 800 }
        return 400
    }

    // MARK: Parsing

    static func parse(turnLanes raw: String, turn: NavStep.Turn) -> LaneGuidance? {
        let tokens = raw
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        guard !tokens.isEmpty, tokens.contains(where: { !$0.isEmpty }) else { return nil }

        let lanes = tokens.map { token -> Lane in
            let directions = token
                .split(separator: ";")
                .compactMap { direction(String($0)) }
            return Lane(directions: directions.isEmpty ? [.through] : directions)
        }
        let wanted = targets(for: turn)
        let recommended = lanes.indices.filter { index in
            lanes[index].directions.contains(where: wanted.contains)
        }
        guard !recommended.isEmpty else { return nil }
        return LaneGuidance(lanes: lanes, recommended: recommended)
    }

    private static func direction(_ token: String) -> Direction? {
        switch token.lowercased() {
        case "left": .left
        case "slight_left", "slightleft": .slightLeft
        case "through", "straight": .through
        case "slight_right", "slightright": .slightRight
        case "right": .right
        case "sharp_left", "sharpleft": .sharpLeft
        case "sharp_right", "sharpRight": .sharpRight
        case "reverse", "uturn", "u_turn": .uTurn
        case "merge_to_left", "mergeleft": .mergeLeft
        case "merge_to_right", "mergeright": .mergeRight
        case "none": Direction.none
        default: nil
        }
    }

    /// Which lane movements actually serve this manoeuvre. A slight left can be
    /// served by a "left" lane and vice versa; a plain left is not satisfied by
    /// a through-only lane.
    private static func targets(for turn: NavStep.Turn) -> Set<Direction> {
        switch turn {
        case .left, .sharpLeft: [.left, .sharpLeft]
        case .slightLeft: [.slightLeft, .left]
        case .right, .sharpRight: [.right, .sharpRight]
        case .slightRight: [.slightRight, .right]
        case .straight, .start, .arrive: [.through]
        case .uTurn: [.uTurn]
        }
    }

    private static func number(_ value: Int) -> String {
        switch value {
        case 2: "two"
        case 3: "three"
        case 4: "four"
        default: "\(value)"
        }
    }
}
