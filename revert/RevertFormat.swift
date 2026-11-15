import Foundation

/// One place for user-visible numbers and dates.
///
/// `String(format:)` is still used for machine/log strings and the fixed
/// `h:mm:ss` clock, but anything a rider reads as a distance, speed, elevation,
/// count or calendar date goes through here so it respects the locale.
///
/// Pure, stateless formatting: `Units` runs off the main actor (the route
/// planner formats distances from a background task), so this namespace must
/// be nonisolated rather than inheriting the project's MainActor default.
nonisolated enum RevertFormat {
    /// Locale-aware decimal formatting with automatic thousands grouping.
    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(decimals))
                .grouping(.automatic)
        )
    }

    /// "Nov 14"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Nov 14, 2026"
    static func mediumDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Saturday, November 14, 2026 at 7:55 PM"
    static func fullDateTime(_ date: Date) -> String {
        date.formatted(date: .complete, time: .shortened)
    }

    /// "14" — for the calendar block in ride rows.
    static func dayNumber(_ date: Date) -> String {
        date.formatted(.dateTime.day())
    }

    /// "NOV" — the caller uppercases when the design needs it.
    static func monthAbbreviation(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    /// "Tue, Nov 14 at 10:18 PM"
    static func rowDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// Rider-facing aggregate duration: "42 min", "1 h 30 m", "3 h 04 m".
    /// The precise `h:mm:ss` clock is still `Units.clock` for a ride row.
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(String(format: "%02d", minutes)) m"
    }
}
