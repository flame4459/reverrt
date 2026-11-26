import AVFoundation
import Foundation

/// The one place that configures `AVAudioSession`.
///
/// Before this existed, `Speaker`, `HelmetAudio` and the speech recognizer each
/// set a category whenever they felt like it. A navigation prompt during
/// "Hey Ace" listening switched the session to `.playback` and killed the
/// microphone; helmet cues fought the recognizer for `.playAndRecord`.
///
/// The rule here: **recording is dominant**. While the rider is listening,
/// speech and helmet cues may play, but the category stays `.playAndRecord`
/// until listening stops.
@MainActor
final class AudioSessionOwner {
    static let shared = AudioSessionOwner()

    enum Mode: String {
        case idle
        case speech
        case helmet
        case recording
    }

    private(set) var mode: Mode = .idle
    private(set) var isInterrupted = false
    /// Set by `Speaker` to drop the current sentence on an interruption.
    var onInterruptionBegan: (() -> Void)?
    /// `true` when the system said the interruption can be resumed.
    var onInterruptionEnded: ((Bool) -> Void)?
    /// Posted after a route change, with the session's reason.
    var onRouteChanged: ((AVAudioSession.RouteChangeReason) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var deactivateTask: Task<Void, Never>?

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                AudioSessionOwner.shared.handleInterruption(note)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                AudioSessionOwner.shared.handleRouteChange(note)
            }
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            isInterrupted = true
            onInterruptionBegan?()
        case .ended:
            isInterrupted = false
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            if shouldResume { activate(mode == .idle ? .speech : mode) }
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        onRouteChanged?(reason)
    }

    /// Ask for a configuration. Recording is not downgraded by a lower-priority
    /// request; it is only changed by an explicit `.recording` stop.
    func activate(_ requested: Mode) {
        deactivateTask?.cancel()
        deactivateTask = nil
        let target: Mode
        if mode == .recording, requested != .recording {
            target = .recording
        } else {
            target = requested
        }
        mode = target
        if target == .idle { return }
        apply(target)
    }

    /// The recognizer cannot install its tap until the category is live, so it
    /// needs a barrier rather than fire-and-forget configuration.
    func activateRecordingAndWait() async {
        deactivateTask?.cancel()
        deactivateTask = nil
        mode = .recording
        await AudioSessionWork.performAndWait {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .measurement,
                                     options: [.duckOthers, .allowBluetoothHFP,
                                               .allowBluetoothA2DP, .defaultToSpeaker])
            try? session.setActive(true)
        }
    }

    /// Called by the recognizer when it stops listening.
    func recordingStopped() {
        if mode == .recording { mode = .idle }
    }

    /// Give the session back after speech finishes, unless something still
    /// needs it. Delayed so a following prompt does not re-activate.
    func releaseAfterIdle(delay: TimeInterval = 0.6) {
        deactivateTask?.cancel()
        let expected = mode
        deactivateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.mode == expected,
                  expected == .speech || expected == .helmet else { return }
            self.mode = .idle
            AudioSessionWork.perform {
                try? AVAudioSession.sharedInstance().setActive(false,
                                                              options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func apply(_ mode: Mode) {
        AudioSessionWork.perform {
            let session = AVAudioSession.sharedInstance()
            switch mode {
            case .recording:
                try? session.setCategory(.playAndRecord, mode: .measurement,
                                         options: [.duckOthers, .allowBluetoothHFP,
                                                   .allowBluetoothA2DP, .defaultToSpeaker])
            case .speech, .helmet:
                try? session.setCategory(.playback, mode: .voicePrompt,
                                         options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers,
                                                   .allowBluetoothA2DP, .allowBluetoothHFP])
            case .idle:
                return
            }
            try? session.setActive(true)
        }
    }
}
