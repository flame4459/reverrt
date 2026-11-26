@preconcurrency import AVFoundation

/// The app's one voice, with one rule: a manoeuvre is never cancelled by
/// chatter.
///
/// Everything that speaks goes through here — navigation, hazard alerts and
/// ACE — so a single priority queue can decide what the rider hears. A safety
/// alert may interrupt a turn prompt (the turn is replayed afterwards if it is
/// still relevant); ACE never interrupts navigation; stale navigation prompts
/// expire instead of queueing behind the ride.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var items: [Item] = []

    private var cachedVoice: AVSpeechSynthesisVoice?
    private var cachedVoiceName: String?
    private var cachedVoiceAt = Date.distantPast
    private var utteranceSequence = 0
    private var deactivationTask: Task<Void, Never>?

    private override init() {
        super.init()
        synth.delegate = self
    }

    enum Kind {
        case alert
        case navigation
        /// The companion has its own switch: turning off hazard speech must not
        /// silence Ace, and muting Ace must not silence hazard alerts.
        case companion
    }

    /// Lower raw value wins. The order is the product rule, not a suggestion.
    enum Priority: Int, Comparable {
        case safety = 0
        case immediateManeuver = 1
        case advanceManeuver = 2
        case deviation = 3
        case completion = 4
        case contextual = 5
        case companion = 6

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

        static func forKind(_ kind: Kind) -> Priority {
            switch kind {
            case .alert: .safety
            case .navigation: .advanceManeuver
            case .companion: .companion
            }
        }

        /// How long a queued prompt stays relevant. Directions age fast; a
        /// safety alert does not.
        var lifetime: TimeInterval {
            switch self {
            case .safety: 30
            case .immediateManeuver: 5
            case .advanceManeuver: 6
            case .deviation: 8
            case .completion: 10
            case .contextual: 8
            case .companion: 8
            }
        }
    }

    private enum Item {
        case clip(URL)
        case speech(String)
    }

    private struct Pending {
        let prompt: VoicePrompt
        let kind: Kind
        let priority: Priority
        let created: Date
        let relevance: (() -> Bool)?
    }

    private var current: Pending?
    private var pending: [Pending] = []
    /// A turn prompt cut short by a safety alert, replayed if still relevant.
    private var interrupted: Pending?
    private var lastSaid: (text: String, at: Date)?

    // MARK: - Planning (pure, tested)

    /// A prompt after clip availability is taken into account. Pure, so the
    /// clip-level fallback can be unit-tested without touching audio.
    nonisolated enum PlannedPart: Equatable, Sendable {
        case clip(VoiceClip)
        case speech(String)
    }

    nonisolated static func plan(for prompt: VoicePrompt,
                                 available: Set<VoiceClip>) -> [PlannedPart] {
        var parts: [PlannedPart] = []
        var pendingText = ""

        func flushText() {
            let trimmed = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(.speech(trimmed)) }
            pendingText = ""
        }

        for part in prompt.parts {
            switch part {
            case .clip(let clip, let fallback):
                if available.contains(clip) {
                    flushText()
                    parts.append(.clip(clip))
                } else {
                    pendingText += (pendingText.isEmpty ? "" : " ") + fallback
                }
            case .optionalClip(let clip):
                if available.contains(clip) {
                    flushText()
                    parts.append(.clip(clip))
                }
            case .text(let text):
                pendingText += (pendingText.isEmpty ? "" : " ") + text
            }
        }
        flushText()

        let usedClip = parts.contains {
            if case .clip = $0 { return true }
            return false
        }
        guard usedClip else {
            return prompt.fallback.isEmpty ? [] : [.speech(prompt.fallback)]
        }
        return parts
    }

    // MARK: - Public

    /// The last sentence handed to the synthesiser. Tests and the debug export
    /// read this; nothing in the UI depends on it.
    @ObservationIgnored private(set) var lastSpokenFallback: String?
    /// Recent sentences, newest last. Tests count callouts here.
    @ObservationIgnored private(set) var spokenHistory: [String] = []
    /// True while something is actually speaking.
    private var sessionInUse = false
    private var sessionHeldExternally = false

    func clearSpokenHistory() { spokenHistory.removeAll() }

    /// Called by the recognizer before it activates the microphone session.
    func holdSession() {
        sessionHeldExternally = true
        deactivationTask?.cancel()
        deactivationTask = nil
    }

    /// Called when the recognizer stops listening.
    func releaseSession() {
        sessionHeldExternally = false
    }

    func say(_ text: String, kind: Kind = .alert,
             priority: Priority? = nil, relevance: (() -> Bool)? = nil,
             allowDuplicate: Bool = false) {
        say(VoicePrompt(text: text), kind: kind, priority: priority,
            relevance: relevance, allowDuplicate: allowDuplicate)
    }

    func say(_ prompt: VoicePrompt, kind: Kind = .alert, pack: InstalledVoicePack? = nil,
             priority: Priority? = nil, relevance: (() -> Bool)? = nil,
             allowDuplicate: Bool = false) {
        guard !UserDefaults.standard.bool(forKey: "voice.muted") else { return }
        let key: String
        switch kind {
        case .navigation: key = "navigation.voice"
        case .alert: key = "alert.voice"
        case .companion: key = "companion.voice"
        }
        guard AlertSettings.enabled(key) else { return }
        guard !prompt.fallback.isEmpty else { return }

        let level = priority ?? Priority.forKind(kind)
        let now = Date()
        // The same sentence twice in a second is a bug, not emphasis.
        if !allowDuplicate {
            if let lastSaid, lastSaid.text == prompt.fallback,
               now.timeIntervalSince(lastSaid.at) < 1.5 { return }
            if current?.prompt.fallback == prompt.fallback { return }
            if pending.contains(where: { $0.prompt.fallback == prompt.fallback }) { return }
        }

        guard !resolve(prompt, pack: pack ?? VoicePackLibrary.shared.selectedPack).isEmpty else { return }

        lastSaid = (prompt.fallback, now)
        if kind == .navigation {
            RideDebug.shared.event("NAV-VOICE", [("text", prompt.fallback),
                                                 ("priority", "\(level.rawValue)")])
        }
        lastSpokenFallback = prompt.fallback
        spokenHistory.append(prompt.fallback)
        if spokenHistory.count > 20 { spokenHistory.removeFirst(spokenHistory.count - 20) }

        let entry = Pending(prompt: prompt, kind: kind, priority: level,
                            created: now, relevance: relevance)
        let busy = current != nil || !items.isEmpty

        if !busy {
            begin(entry)
            return
        }

        if let active = current, level < active.priority {
            // Keep a navigation prompt that a safety alert cut off; it is
            // replayed only if its relevance survives.
            if active.kind == .navigation, active.priority <= .advanceManeuver {
                interrupted = active
            }
            stopItems()
            current = nil
            begin(entry)
            return
        }
        enqueue(entry)
    }

    /// Drops queued navigation speech when navigation ends or is replaced.
    /// A safety alert and an in-progress sentence are left alone.
    func cancelNavigationPrompts() {
        pending.removeAll { $0.kind == .navigation }
        interrupted = nil
        if current?.kind == .navigation {
            stopItems()
            current = nil
            playNextQueued()
        }
    }

    /// Barge-in / ride teardown: cancel everything.
    func stop() {
        stopItems()
        current = nil
        pending.removeAll()
        interrupted = nil
        releaseSessionAfterIdle()
    }

    // MARK: - Queue

    private func enqueue(_ entry: Pending) {
        switch entry.priority {
        case .safety:
            pending.removeAll { $0.priority == .safety }
            pending.insert(entry, at: 0)
        case .immediateManeuver, .advanceManeuver:
            // Directions age fast: a newer instruction replaces an unspoken one.
            pending.removeAll { $0.kind == .navigation }
            pending.append(entry)
        case .companion:
            pending.removeAll { $0.priority == .companion }
            pending.append(entry)
        default:
            pending.append(entry)
        }
        if pending.count > 6 {
            // Drop the oldest low-priority entry, never a safety prompt.
            if let index = pending.indices
                .filter({ pending[$0].priority.rawValue >= Priority.completion.rawValue })
                .min(by: { pending[$0].created < pending[$1].created }) {
                pending.remove(at: index)
            } else {
                pending.removeLast()
            }
        }
        if current == nil { playNextQueued() }
    }

    private func playNextQueued() {
        let now = Date()
        pending.removeAll { entry in
            if now.timeIntervalSince(entry.created) > entry.priority.lifetime { return true }
            if let relevance = entry.relevance, !relevance() { return true }
            return false
        }
        if let candidate = interrupted {
            interrupted = nil
            if now.timeIntervalSince(candidate.created) < candidate.priority.lifetime,
               candidate.relevance?() ?? true {
                begin(candidate)
                return
            }
        }
        guard let next = pending.min(by: {
            $0.priority != $1.priority ? $0.priority < $1.priority : $0.created < $1.created
        }) else {
            releaseSessionAfterIdle()
            return
        }
        pending.removeAll { $0.prompt.fallback == next.prompt.fallback }
        begin(next)
    }

    private func begin(_ entry: Pending) {
        let pack = VoicePackLibrary.shared.selectedPack
        let resolved = resolve(entry.prompt, pack: pack)
        guard !resolved.isEmpty else {
            current = nil
            playNextQueued()
            return
        }
        current = entry
        activateSession()
        sessionInUse = true
        utteranceSequence += 1
        deactivationTask?.cancel()
        deactivationTask = nil
        items = resolved
        playNextItem()
    }

    /// Expands a prompt into playable items. Clips the pack has are played;
    /// a missing clip only costs its own phrase, which the system voice reads
    /// in place — never the whole sentence.
    private func resolve(_ prompt: VoicePrompt, pack: InstalledVoicePack?) -> [Item] {
        guard let pack else {
            return prompt.fallback.isEmpty ? [] : [.speech(prompt.fallback)]
        }
        let clips = VoicePackLibrary.shared.clips(for: pack)
        return Self.plan(for: prompt, available: Set(clips.keys)).compactMap { planned in
            switch planned {
            case .clip(let clip):
                return clips[clip].map { Item.clip($0) }
            case .speech(let text):
                return .speech(text)
            }
        }
    }

    private func playNextItem() {
        guard !items.isEmpty else {
            finishCurrent()
            return
        }
        let item = items.removeFirst()
        switch item {
        case .speech(let text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = selectedVoice()
            utterance.rate = 0.46
            utterance.pitchMultiplier = 1.0
            utterance.volume = 0.9
            synth.speak(utterance)

        case .clip(let url):
            do {
                let clipPlayer = try AVAudioPlayer(contentsOf: url)
                clipPlayer.delegate = self
                clipPlayer.volume = 0.92
                clipPlayer.prepareToPlay()
                player = clipPlayer
                if !clipPlayer.play() {
                    player = nil
                    playNextItem()
                }
            } catch {
                playNextItem()
            }
        }
    }

    private func finishCurrent() {
        current = nil
        playNextQueued()
    }

    private func stopItems() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        player?.stop()
        player = nil
        items = []
    }

    private func releaseSessionAfterIdle() {
        guard sessionInUse else { return }
        sessionInUse = false
        if sessionHeldExternally { return }
        AudioSessionOwner.shared.releaseAfterIdle()
    }

    private func activateSession() {
        // While the recognizer is listening the owner keeps `.playAndRecord`;
        // speech simply plays on that session. This is what stops a navigation
        // prompt from killing the microphone.
        AudioSessionOwner.shared.activate(.speech)
    }

    // MARK: - Voice

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        let requestedName = UserDefaults.standard.string(forKey: "alert.voiceName") ?? "System default"
        let now = Date()
        // A downloaded voice becomes available while the app is running; a
        // stale cache kept reading the old voice until relaunch.
        if cachedVoiceName == requestedName,
           now.timeIntervalSince(cachedVoiceAt) < 60 {
            return cachedVoice
        }

        let currentLang = Locale.current.language.languageCode?.identifier ?? "en"
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = allVoices.filter { $0.language.starts(with: currentLang) }
        let voices = matching.isEmpty ? allVoices.filter { $0.language.starts(with: "en") } : matching

        let resolved: AVSpeechSynthesisVoice?
        if requestedName != "System default",
           let requested = allVoices.first(where: {
               $0.name.localizedCaseInsensitiveCompare(requestedName) == .orderedSame
           }) {
            resolved = requested
        } else {
            resolved = voices.first(where: { $0.name.localizedCaseInsensitiveContains("Tom") && $0.quality == .enhanced })
                ?? allVoices.first(where: { $0.name.localizedCaseInsensitiveContains("Tom") })
                ?? voices.first(where: { $0.quality == .enhanced })
                ?? voices.first(where: { $0.quality == .premium })
                ?? voices.first
                ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        cachedVoice = resolved
        cachedVoiceName = requestedName
        cachedVoiceAt = now
        return resolved
    }

    // MARK: - Interruptions

    /// Called by `AudioSessionOwner` when a call/Siri takes the session.
    func handleInterruptionBegan() {
        stopItems()
        current = nil
    }

    /// Called after an interruption ends. Queued prompts are re-checked for
    /// age and relevance before anything plays.
    func handleInterruptionEnded(resume: Bool) {
        guard resume else {
            pending.removeAll()
            interrupted = nil
            return
        }
        playNextQueued()
    }

    // MARK: - Delegates

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.playNextItem()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playNextItem()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // A cancelled utterance was replaced; the queue has already moved on.
    }
}
