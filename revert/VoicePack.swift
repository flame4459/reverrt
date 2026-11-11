import Foundation

/// A voice in the Waze voice-pack archive.
///
/// Waze serves these packs as `<uuid>.tar.gz` bundles of fixed MP3 prompts
/// ("turn left", "in 400 meters", ...). Revert can speak those recordings
/// instead of the built-in synthesiser and still fall back to TTS for street
/// names, speed limits and anything the pack does not contain.
nonisolated struct VoicePack: Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case official
        case community

        var title: String {
            switch self {
            case .official: "Official"
            case .community: "Community"
            }
        }
    }

    /// The Waze voice UUID. Also used as the installed pack's folder name.
    let id: String
    let name: String
    let language: String
    let author: String?
    let source: Source
    /// Waze's CDN answered for this pack on the last catalogue check.
    /// Packs that stopped working stay listed but move behind the archive
    /// filter, because the link may come back.
    let downloadable: Bool

    var downloadURL: URL {
        let base = URL(string: "https://voice-prompts-ipv6.waze.com")!
        return base.appendingPathComponent("\(id).tar.gz")
    }

    var subtitle: String {
        if let author, !author.isEmpty {
            return "\(language) · \(author)"
        }
        return "\(language) · \(source.title)"
    }
}

/// A voice pack that has been downloaded and unpacked on this iPhone.
nonisolated struct InstalledVoicePack: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let author: String?
    let source: VoicePack.Source
    let installedAt: Date
    let clipCount: Int
    /// Shipped with the app so a good voice works before any download.
    let isBuiltIn: Bool

    var subtitle: String {
        if let author, !author.isEmpty {
            return "\(language) · \(author)"
        }
        return language
    }

    var isComplete: Bool { clipCount >= VoiceClip.standardClipCount }
}

/// The fixed prompt filenames Waze packs use. The raw value is the MP3's
/// base name without the extension.
nonisolated enum VoiceClip: String, CaseIterable, Hashable, Sendable {
    // Distances. The metric and imperial clips are different recordings:
    // `200.mp3` says "in 0.1 miles", `200meters.mp3` says "in 200 meters".
    case distance200Imperial = "200"
    case distance400Imperial = "400"
    case distance800Imperial = "800"
    case distance1500Imperial = "1500"
    case distance200 = "200meters"
    case distance400 = "400meters"
    case distance800 = "800meters"
    case distance1000 = "1000meters"
    case distance1500 = "1500meters"

    case andThen = "AndThen"
    case approachAccident = "ApproachAccident"
    case approachHazard = "ApproachHazard"
    case approachRedLightCamera = "ApproachRedLightCam"
    case approachSpeedCamera = "ApproachSpeedCam"
    case approachTraffic = "ApproachTraffic"
    case arrive = "Arrive"

    case exitLeft = "ExitLeft"
    case exitRight = "ExitRight"
    case keepLeft = "KeepLeft"
    case keepRight = "KeepRight"
    case roundabout = "Roundabout"
    case straight = "Straight"
    case turnLeft = "TurnLeft"
    case turnRight = "TurnRight"
    case uTurn = "uturn"

    case police = "Police"
    case ticker = "TickerPoints"

    case firstExit = "First"
    case secondExit = "Second"
    case thirdExit = "Third"
    case fourthExit = "Fourth"
    case fifthExit = "Fifth"
    case sixthExit = "Sixth"
    case seventhExit = "Seventh"

    case startDrive1 = "StartDrive1"
    case startDrive2 = "StartDrive2"
    case startDrive3 = "StartDrive3"
    case startDrive4 = "StartDrive4"
    case startDrive5 = "StartDrive5"
    case startDrive6 = "StartDrive6"
    case startDrive7 = "StartDrive7"
    case startDrive8 = "StartDrive8"
    case startDrive9 = "StartDrive9"

    /// Clips that must be present for a folder to count as a voice pack.
    static let requiredForInstall: Set<VoiceClip> = [.turnLeft, .turnRight, .straight]

    /// How many prompts a complete Waze pack contains.
    static var standardClipCount: Int { allCases.count }

    /// The nearest distance recording for a spoken distance. Waze only
    /// records a handful of distances, so the closest one is used.
    static func distanceClip(forMeters meters: Double, metric: Bool) -> VoiceClip? {
        guard meters.isFinite, meters > 0 else { return nil }
        let candidates: [(Double, VoiceClip)] = metric
            ? [(200, .distance200), (400, .distance400), (800, .distance800),
               (1_000, .distance1000), (1_500, .distance1500)]
            : [(200, .distance200Imperial), (400, .distance400Imperial),
               (800, .distance800Imperial), (1_500, .distance1500Imperial)]
        return candidates.min {
            abs(log(meters / $0.0)) < abs(log(meters / $1.0))
        }?.1
    }

    static func randomStart() -> VoiceClip {
        [.startDrive1, .startDrive2, .startDrive3, .startDrive4, .startDrive5,
         .startDrive6, .startDrive7, .startDrive8, .startDrive9].randomElement() ?? .startDrive1
    }
}

/// A spoken message as a sequence of recorded clips and synthesised text.
///
/// `fallback` is the full sentence used when no pack is selected. Each clip
/// also carries its own spoken wording, so a pack that is missing just one
/// prompt speaks that part with the system voice instead of dropping the whole
/// sentence to TTS — the difference between a voice that sounds consistent and
/// one that suddenly turns robotic.
nonisolated struct VoicePrompt: Equatable, Sendable {
    enum Part: Equatable, Sendable {
        /// Played when the pack has it; if not, `fallback` is spoken instead.
        case clip(VoiceClip, fallback: String)
        /// Played only when the pack has it. Used for distances: an incomplete
        /// pack is better off not announcing distance than switching to a
        /// different voice for half of every prompt.
        case optionalClip(VoiceClip)
        case text(String)
    }

    var parts: [Part]
    var fallback: String

    init(text: String) {
        self.parts = text.isEmpty ? [] : [.text(text)]
        self.fallback = text
    }

    init(parts: [Part], fallback: String) {
        self.parts = parts
        self.fallback = fallback
    }
}
