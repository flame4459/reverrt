@preconcurrency import AVFoundation

/// One shared voice so hazard alerts and turn directions never talk over each other.
@MainActor
final class Speaker: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
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

    func say(_ text: String, kind: Kind = .alert) {
        // Navigation prompts and safety alerts are separate controls. Turning
        // off spoken hazard alerts must not silence turn-by-turn.
        let key = kind == .navigation ? "navigation.voice" : "alert.voice"
        guard AlertSettings.enabled(key) else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)

        utteranceSequence += 1
        deactivationTask?.cancel()
        deactivationTask = nil

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice()
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9

        // Navigation prompts should replace a stale prompt instead of forming an annoying queue.
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
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
            resolved = voices.first(where: { $0.quality == .enhanced }) ?? voices.first ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        cachedVoice = resolved
        cachedVoiceName = requestedName
        return resolved
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        release(s)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        release(s)
    }

    private func release(_ s: AVSpeechSynthesizer) {
        let currentSequence = utteranceSequence
        deactivationTask?.cancel()
        deactivationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled,
                  self.utteranceSequence == currentSequence,
                  !self.synth.isSpeaking else { return }
            if #available(iOS 27.0, *) {
                _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
            } else {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}
