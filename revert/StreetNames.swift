import Foundation

/// Human street names for both the banner and the voice.
///
/// MapKit and OSM hand us compact forms ("S 5th St", "125th Ave"). The system
/// voice reads "5th" as a word, but some voices round it to "fice"; spelling
/// the ordinal removes the ambiguity. The same pass turns suffix and
/// directional abbreviations into words so the banner reads like Google Maps.
nonisolated enum StreetNames {
    // MARK: Public

    /// Normalises a whole maneuver instruction, including the road phrase.
    static func instruction(_ text: String) -> String {
        var value = expandOrdinals(text)
        value = expandRoadPhrase(value)
        return value
    }

    /// Normalises a road name on its own.
    static func road(_ name: String) -> String {
        var value = expandOrdinals(name.trimmingCharacters(in: .whitespacesAndNewlines))
        value = expandLeadingDirectional(value)
        value = expandTrailingSuffix(value)
        return value
    }

    /// Pulls the road out of a MapKit sentence ("Turn right onto South Fifth
    /// Street"). Used when the step has no structured road field.
    static func roadName(from instruction: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(?:onto|on)\s+([^,]+)$"#
        ) else { return nil }
        let range = NSRange(instruction.startIndex..<instruction.endIndex, in: instruction)
        guard let match = regex.firstMatch(in: instruction, range: range),
              match.numberOfRanges > 1,
              let roadRange = Range(match.range(at: 1), in: instruction) else { return nil }
        let candidate = String(instruction[roadRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        return road(candidate)
    }

    // MARK: Ordinals

    private static let ordinalRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,3})(st|nd|rd|th)\b"#,
        options: [.caseInsensitive]
    )

    private static func expandOrdinals(_ text: String) -> String {
        guard let regex = ordinalRegex, !text.isEmpty else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text,
                                    range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let numberRange = Range(match.range(at: 1), in: result),
                  let wholeRange = Range(match.range, in: result),
                  let number = Int(result[numberRange]) else { continue }
            result.replaceSubrange(wholeRange, with: ordinalWords(number))
        }
        return result
    }

    private static let ordinalEndings: [String: String] = [
        "one": "first", "two": "second", "three": "third", "four": "fourth",
        "five": "fifth", "six": "sixth", "seven": "seventh", "eight": "eighth",
        "nine": "ninth", "ten": "tenth", "eleven": "eleventh", "twelve": "twelfth",
        "thirteen": "thirteenth", "fourteen": "fourteenth", "fifteen": "fifteenth",
        "sixteen": "sixteenth", "seventeen": "seventeenth", "eighteen": "eighteenth",
        "nineteen": "nineteenth", "twenty": "twentieth", "thirty": "thirtieth",
        "forty": "fortieth", "fifty": "fiftieth", "sixty": "sixtieth",
        "seventy": "seventieth", "eighty": "eightieth", "ninety": "ninetieth",
        "hundred": "hundredth", "thousand": "thousandth"
    ]

    private static func ordinalWords(_ number: Int) -> String {
        guard number > 0 else { return "\(number)th" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        guard var words = formatter.string(from: NSNumber(value: number)) else {
            return "\(number)th"
        }
        // Replace only the final word: "twenty-five" -> "twenty-fifth",
        // "one hundred" -> "one hundredth".
        let separator = words.lastIndex(where: { $0 == " " || $0 == "-" })
        let prefix = separator.map { String(words[...$0]) } ?? ""
        let tail = separator.map { String(words[words.index(after: $0)...]) } ?? words
        words = prefix + (ordinalEndings[tail] ?? "\(tail)th")
        func capitalize(_ part: Substring) -> String {
            guard let first = part.first else { return "" }
            return first.uppercased() + String(part.dropFirst())
        }
        return words
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(capitalize)
            .joined(separator: "-")
            .split(separator: " ", omittingEmptySubsequences: false)
            .map(capitalize)
            .joined(separator: " ")
    }

    // MARK: Road forms

    private static func expandRoadPhrase(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(onto|on)\s+([^,]+)$"#
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 2,
              let roadRange = Range(match.range(at: 2), in: text) else { return text }
        let raw = String(text[roadRange])
        let normalized = road(raw)
        guard normalized != raw else { return text }
        var result = text
        result.replaceSubrange(roadRange, with: normalized)
        return result
    }

    private static let directionWords: [String: String] = [
        "n": "North", "s": "South", "e": "East", "w": "West",
        "ne": "North East", "nw": "North West",
        "se": "South East", "sw": "South West"
    ]

    private static func expandLeadingDirectional(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(n|s|e|w|ne|nw|se|sw)\.?\s+"#
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: text) else { return text }
        let token = String(text[tokenRange]).lowercased()
        guard let word = directionWords[token] else { return text }
        var result = text
        result.replaceSubrange(Range(match.range, in: text)!, with: word + " ")
        return result
    }

    private static let suffixWords: [String: String] = [
        "st": "Street", "ave": "Avenue", "blvd": "Boulevard", "rd": "Road",
        "dr": "Drive", "ln": "Lane", "pkwy": "Parkway", "hwy": "Highway",
        "ct": "Court", "pl": "Place", "ter": "Terrace", "cir": "Circle",
        "sq": "Square", "rte": "Route", "expy": "Expressway", "fwy": "Freeway"
    ]

    private static func expandTrailingSuffix(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(st|ave|blvd|rd|dr|ln|pkwy|hwy|ct|pl|ter|cir|sq|rte|expy|fwy)\.?$"#
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: text) else { return text }
        let token = String(text[tokenRange]).lowercased()
        guard let word = suffixWords[token] else { return text }
        var result = text
        result.replaceSubrange(Range(match.range, in: text)!, with: word)
        return result
    }
}
