import AVFoundation
import Foundation

/// Small synthesised soundtrack for the film: a low engine note whose pitch
/// follows speed, plus filtered wind. No audio assets, no network, and no
/// microphone permission.
///
/// All AVAudioEngine work runs on a private serial queue. Starting or stopping
/// sound must never block the map/replay main thread on a simulator or a device
/// with no audio route.
final class ReplayAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let enginePlayer = AVAudioPlayerNode()
    private let windPlayer = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let queue = DispatchQueue(label: "revert.replay.audio", qos: .userInitiated)
    private var running = false
    private var configured = false
    private var engineBuffer: AVAudioPCMBuffer?
    private var windBuffer: AVAudioPCMBuffer?
    private var gain: Float = 1
    private var targetEngineVolume: Float = 0.07
    private var targetWindVolume: Float = 0.025

    func start() {
        queue.async { [weak self] in self?.startLocked() }
    }

    func update(speed: Double, lean: Double) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            let normalized = min(max(speed / 35, 0), 1)
            self.pitch.rate = Float(0.78 + normalized * 0.58)
            self.pitch.pitch = Float(min(abs(lean), 30) * 8)
            self.targetEngineVolume = Float(0.045 + normalized * 0.055)
            self.targetWindVolume = Float(0.015 + normalized * 0.045)
            self.applyVolume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.running else {
                self.teardown()
                return
            }
            for step in stride(from: 17, through: 0, by: -1) {
                let delay = Double(17 - step) * 0.024
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.gain = Float(step) / 18
                    self.applyVolume()
                }
            }
            self.queue.asyncAfter(deadline: .now() + 0.42) { [weak self] in
                self?.teardown()
            }
        }
    }

    private func startLocked() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            AudioSessionWork.perform {
                try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try? session.setActive(true)
            }
            if engineBuffer == nil { engineBuffer = makeEngineBuffer() }
            if windBuffer == nil { windBuffer = makeWindBuffer() }
            guard let engineBuffer, let windBuffer else { return }
            if !configured {
                engine.attach(enginePlayer)
                engine.attach(windPlayer)
                engine.attach(pitch)
                let format = engineBuffer.format
                engine.connect(enginePlayer, to: pitch, format: format)
                engine.connect(pitch, to: engine.mainMixerNode, format: format)
                engine.connect(windPlayer, to: engine.mainMixerNode, format: windBuffer.format)
                configured = true
            }
            pitch.rate = 0.9
            gain = 0
            enginePlayer.volume = 0
            windPlayer.volume = 0
            engine.prepare()
            try engine.start()
            enginePlayer.scheduleBuffer(engineBuffer, at: nil, options: .loops)
            windPlayer.scheduleBuffer(windBuffer, at: nil, options: .loops)
            enginePlayer.play()
            windPlayer.play()
            running = true
            for step in 1...18 {
                queue.asyncAfter(deadline: .now() + Double(step) * 0.032) { [weak self] in
                    guard let self, self.running else { return }
                    self.gain = Float(step) / 18
                    self.applyVolume()
                }
            }
        } catch {
            RevertDiagnostics.log("replay audio start failed: \(error.localizedDescription)")
            teardown()
        }
    }

    private func applyVolume() {
        enginePlayer.volume = targetEngineVolume * gain
        windPlayer.volume = targetWindVolume * gain
    }

    private func teardown() {
        enginePlayer.stop()
        windPlayer.stop()
        engine.stop()
        running = false
        gain = 0
        AudioSessionWork.perform {
            try? AVAudioSession.sharedInstance().setActive(false,
                                                          options: .notifyOthersOnDeactivation)
        }
    }

    private func makeEngineBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else { return nil }
        let frames: AVAudioFrameCount = 44_100 * 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        var noiseState: Float = 0
        for index in 0..<Int(frames) {
            let t = Float(index) / 44_100
            let fundamental = 38 + 9 * sin(t * 0.37)
            let phase = 2 * Float.pi * fundamental * t
            let tone = sin(phase) * 0.45
                + sin(phase * 2) * 0.20
                + sin(phase * 3.02) * 0.10
                + sin(phase * 5.01) * 0.04
            let white = Float.random(in: -1...1) * 0.08
            noiseState = noiseState * 0.94 + white * 0.06
            let sample = (tone + noiseState) * 0.55
            channels[0][index] = sample
            channels[1][index] = sample * 0.96
        }
        return buffer
    }

    private func makeWindBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else { return nil }
        let frames: AVAudioFrameCount = 44_100 * 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        var low: Float = 0
        var high: Float = 0
        for index in 0..<Int(frames) {
            let white = Float.random(in: -1...1)
            low = low * 0.985 + white * 0.015
            high = high * 0.72 + white * 0.28
            let sample = low * 0.7 + high * 0.18
            channels[0][index] = sample
            channels[1][index] = sample * 0.94
        }
        return buffer
    }
}
