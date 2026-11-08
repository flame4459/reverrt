import Foundation
import Speech
import AVFoundation
import Observation

/// Hands-free ride controls that run entirely on the phone.
///
/// `requiresOnDeviceRecognition` is always on. If the installed speech model
/// cannot run locally we refuse to listen rather than silently sending audio to
/// a server.
@MainActor
@Observable
final class VoiceCommandRecognizer {
    enum Command: Equatable {
        case startRide
        case pause
        case resume
        case saveRide
        case endRoute
        case repeatInstruction
        case calibrate
        case nextCamera
    }

    var isListening = false
    var transcript = ""
    var statusMessage: String?
    var authorizationDenied = false

    @ObservationIgnored var onCommand: ((Command) -> Void)?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var lastCommandAt = Date.distantPast
    @ObservationIgnored private var lastCommand: Command?
    /// True while the rider wants the microphone armed. Kept separate from
    /// `isListening` so an on-device recognition timeout can restart the tap
    /// instead of silently ending hands-free control mid-ride.
    @ObservationIgnored private var wantsListening = false
    @ObservationIgnored private var restartScheduled = false
    @ObservationIgnored private var restartCount = 0
    @ObservationIgnored private var listeningSince: Date?
    @ObservationIgnored private var generation = 0

    func start() {
        guard !isListening else { return }
        wantsListening = true
        restartCount = 0
        guard let recognizer else {
            wantsListening = false
            statusMessage = "Speech recognition is unavailable for this language."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            wantsListening = false
            statusMessage = "This iPhone has no on-device speech model for \(Locale.current.language.languageCode?.identifier ?? "this language"). Download it in Settings → Accessibility → Voice Control."
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.wantsListening = false
                    self.authorizationDenied = true
                    self.statusMessage = "Speech recognition permission is off."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.wantsListening = false
                            self.authorizationDenied = true
                            self.statusMessage = "Microphone permission is off."
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    func stop() {
        wantsListening = false
        restartScheduled = false
        teardown()
        if #available(iOS 27.0, *) {
            Task { @MainActor in
                _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
            }
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func teardown() {
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
    }

    /// SFSpeechRecognizer ends its task after a stretch of silence or a
    /// transient error. Restart quietly while the rider still wants hands-free
    /// control, with a small backoff and a cap so a broken microphone cannot
    /// spin forever.
    private func restartAfterRecognitionEnded() {
        guard wantsListening, !restartScheduled else { return }
        if let since = listeningSince, Date().timeIntervalSince(since) > 20 {
            restartCount = 0
        }
        restartScheduled = true
        teardown()
        restartCount += 1
        guard restartCount <= 8 else {
            wantsListening = false
            restartScheduled = false
            statusMessage = "Voice listening stopped. Tap the mic to start again."
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.restartScheduled = false
            guard self.wantsListening, !self.isListening else { return }
            self.begin()
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
            if #available(iOS 27.0, *) {
                Task { @MainActor in
                    _ = try? await session.activate(options: [])
                }
            } else {
                try session.setActive(true)
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.taskHint = .confirmation
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            // iOS 27's refined tap API throws and uses a refined `error`
            // placeholder for the old NSError out-parameter.
            if #available(iOS 27.0, *) {
                try input.__installTap(onBus: 0, bufferSize: 1_024, format: format, error: ()) { buffer, _ in
                    request.append(buffer)
                }
            } else {
                input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                    request.append(buffer)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()

            generation += 1
            let generation = generation
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.interpret(self.transcript)
                    }
                    if error != nil || result?.isFinal == true {
                        self.restartAfterRecognitionEnded()
                    }
                }
            }
            listeningSince = Date()
            isListening = true
            authorizationDenied = false
            statusMessage = nil
        } catch {
            // CoreAudio errors are not actionable for a rider. Keep the raw
            // description in the console and show a plain-language reason.
            print("VoiceCommandRecognizer: \(error)")
            RiderDiagnostics.log("voice start failed: \(error.localizedDescription)")
            statusMessage = "Couldn't start the microphone. Check that no other app is using it, then tap the mic again."
            wantsListening = false
            teardown()
        }
    }

    private func interpret(_ text: String) {
        let normalized = " " + text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + " "
        let now = Date()
        // A command must be at the end of the phrase: "pause ride".
        let matches: [(String, Command)] = [
            ("pause ride", .pause), ("pause", .pause),
            ("resume ride", .resume), ("resume", .resume), ("continue ride", .resume),
            ("start ride", .startRide),
            ("save ride", .saveRide), ("finish ride", .saveRide),
            ("end route", .endRoute), ("stop navigation", .endRoute), ("end navigation", .endRoute),
            ("repeat", .repeatInstruction), ("say again", .repeatInstruction),
            ("calibrate", .calibrate), ("calibrate lean", .calibrate),
            ("change camera", .nextCamera), ("camera", .nextCamera)
        ]
        guard let match = matches.first(where: { normalized.hasSuffix(" \($0.0) ") }) else { return }
        guard now.timeIntervalSince(lastCommandAt) > 1.5 || lastCommand != match.1 else { return }
        lastCommandAt = now
        lastCommand = match.1
        onCommand?(match.1)
    }
}
