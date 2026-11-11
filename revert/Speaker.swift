@preconcurrency import AVFoundation

/// The app's one voice. Alert and navigation prompts share it so they never
/// talk over each other.
///
/// A prompt is played as a queue of items: recorded voice-pack clips where the
/// selected pack has them, system speech for everything else. With no pack
/// selected every prompt is spoken by the system voice, as before.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var queue: [Item] = []
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var cachedVoiceName: String?
    private var utteranceSequence = 0
    private var deactivationTask: Task<Void, Never>?

    private override init() {
        super.init()
        synth.delegate = self
    }

    enum Kind {
        case alert
        case navigation
    }

    private enum Item {
        case clip(URL)
        case speech(String)
    }

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

        // With no clip to play, use the original sentence: joining the
        // per-phrase fallbacks would drop punctuation and sound clipped.
        let usedClip = parts.contains {
            if case .clip = $0 { return true }
            return false
        }
        guard usedClip else {
            return prompt.fallback.isEmpty ? [] : [.speech(prompt.fallback)]
        }
        return parts
    }

    func say(_ text: String, kind: Kind = .alert) {
        say(VoicePrompt(text: text), kind: kind)
    }

    /// Speaks a composed prompt. `pack` overrides the rider's selection, which
    /// lets Settings preview a pack that has not been chosen yet.
    func say(_ prompt: VoicePrompt, kind: Kind = .alert, pack: InstalledVoicePack? = nil) {
        // Navigation prompts and safety alerts are separate controls. Turning
        // off spoken hazard alerts must not silence turn-by-turn.
        let key = kind == .navigation ? "navigation.voice" : "alert.voice"
        guard AlertSettings.enabled(key) else { return }

        let selected = pack ?? VoicePackLibrary.shared.selectedPack
        let items = resolve(prompt, pack: selected)
        guard !items.isEmpty else { return }

        activateSession()
        utteranceSequence += 1
        deactivationTask?.cancel()
        deactivationTask = nil

        stopCurrent()
        queue = items
        playNext()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
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

    private func playNext() {
        guard !queue.isEmpty else {
            finishQueue()
            return
        }

        let item = queue.removeFirst()
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
                    playNext()
                }
            } catch {
                // A damaged clip should not swallow the rest of the prompt.
                playNext()
            }
        }
    }

    private func stopCurrent() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        player?.stop()
        player = nil
        queue = []
    }

    private func finishQueue() {
        let sequence = utteranceSequence
        deactivationTask?.cancel()
        deactivationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled,
                  self.utteranceSequence == sequence,
                  !self.synth.isSpeaking,
                  self.player == nil else { return }
            if #available(iOS 27.0, *) {
                _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
            } else {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        let requestedName = UserDefaults.standard.string(forKey: "alert.voiceName") ?? "System default"
        if cachedVoiceName == requestedName { return cachedVoice }

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
            resolved = voices.first(where: { $0.quality == .premium })
                ?? voices.first(where: { $0.quality == .enhanced })
                ?? voices.first
                ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        cachedVoice = resolved
        cachedVoiceName = requestedName
        return resolved
    }

    // MARK: Delegates

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.playNext()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playNext()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // A cancelled utterance has been replaced by a newer prompt; the queue
        // has already moved on, so do not advance it here.
    }
}
