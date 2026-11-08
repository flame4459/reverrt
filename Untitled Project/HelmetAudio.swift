import AVFoundation
import Foundation

/// Spatial helmet cues.
///
/// The audio is rendered through `AVAudioEnvironmentNode` with HRTF, so a
/// hazard on the left is heard on the left of a stereo Bluetooth helmet. The
/// phone must be connected to the helmet as the audio route; intercom audio
/// itself is owned by the helmet (Cardo/Sena/etc.), not by this app.
@MainActor
final class HelmetAudio {
    static let shared = HelmetAudio()

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var started = false
    private var starting = false
    private var startGeneration = 0

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "helmet.binaural") as? Bool ?? true
    }

    func start() {
        guard !started, !starting, let format else { return }
        starting = true
        startGeneration += 1
        let generation = startGeneration
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .allowBluetoothA2DP, .allowBluetoothHFP])

        engine.attach(environment)
        engine.attach(player)
        // iOS 27 replaced the non-throwing connect methods with
        // connectNode(_:to:format:), which reports routing/format failures.
        if #available(iOS 27.0, *) {
            do {
                try engine.connectNode(player, to: environment, format: format)
                try engine.connectNode(environment, to: engine.mainMixerNode, format: nil)
            } catch {
                starting = false
                started = false
                return
            }
        } else {
            engine.connect(player, to: environment, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
        }
        engine.mainMixerNode.outputVolume = 0.9
        environment.renderingAlgorithm = .HRTFHQ
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        player.renderingAlgorithm = .HRTFHQ
        player.position = AVAudio3DPoint(x: 0, y: 0, z: -1.5)
        engine.prepare()

        // Async activation keeps the main thread responsive during the first
        // helmet cue; the engine starts as soon as the route is ready.
        Task { @MainActor in
            if #available(iOS 27.0, *) {
                _ = try? await session.activate(options: [])
            } else {
                try? session.setActive(true)
            }
            guard generation == self.startGeneration, !self.started else {
                self.starting = false
                return
            }
            do {
                try self.engine.start()
                self.started = true
            } catch {
                self.started = false
            }
            self.starting = false
        }
    }

    func stop() {
        startGeneration += 1
        starting = false
        player.stop()
        engine.stop()
        engine.detach(player)
        engine.detach(environment)
        started = false
    }

    /// A hazard relative to the rider: negative is left, positive is right.
    func hazardCue(relativeBearing: Double, urgent: Bool) {
        guard isEnabled else { return }
        let pan = Float(min(max(relativeBearing / 90, -1), 1))
        play(frequency: urgent ? 1_320 : 980, pan: pan,
             duration: urgent ? 0.18 : 0.11, gain: urgent ? 0.5 : 0.32, repeats: urgent ? 2 : 1)
    }

    /// A turn/curve cue: -1 left, +1 right.
    func turnCue(direction: Int) {
        guard isEnabled else { return }
        play(frequency: direction < 0 ? 720 : 880, pan: Float(direction) * 0.9,
             duration: 0.10, gain: 0.26, repeats: 1)
    }

    private func play(frequency: Double, pan: Float, duration: Double, gain: Float, repeats: Int) {
        if !started, !starting { start() }
        guard started, let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(format.sampleRate * duration)) else { return }
        buffer.frameLength = buffer.frameCapacity
        guard let channel = buffer.floatChannelData?[0] else { return }
        let sampleRate = format.sampleRate
        for frame in 0..<Int(buffer.frameLength) {
            let t = Double(frame) / sampleRate
            let envelope = sin(.pi * t / duration)
            channel[frame] = Float(sin(2 * .pi * frequency * t) * envelope * Double(gain))
        }

        player.stop()
        player.position = AVAudio3DPoint(x: pan * 2, y: 0, z: -1.5)
        for _ in 0..<max(repeats, 1) {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        if #available(iOS 27.0, *) {
            do {
                try player.playAudio()
            } catch {
                started = false
            }
        } else {
            player.play()
        }
    }
}
