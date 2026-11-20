import Foundation
import AVFoundation
import Observation

/// Watches the current audio route so the companion can prefer the helmet
/// headset microphone (Cardo and similar HFP units) instead of the iPhone mic.
/// It never opens the microphone by itself; it only observes route changes.
@MainActor
@Observable
final class AudioRouteMonitor {
    static let shared = AudioRouteMonitor()

    private(set) var bluetoothName: String?
    private(set) var inputName: String?
    private(set) var isBluetoothConnected = false
    private(set) var isUsingBluetoothInput = false

    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var active = false

    private init() {}

    var prefersBluetoothMic: Bool {
        UserDefaults.standard.object(forKey: "companion.preferBluetoothMic") as? Bool ?? true
    }

    var bluetoothInput: AVAudioSessionPortDescription? {
        let session = AVAudioSession.sharedInstance()
        return (session.availableInputs ?? []).first { input in
            input.portType == .bluetoothHFP || input.portType == .bluetoothLE
        }
    }

    var routeSummary: String {
        if isUsingBluetoothInput, let inputName { return inputName }
        if let bluetoothName { return "\(bluetoothName) ready" }
        return "iPhone microphone"
    }

    func start() {
        guard !active else { return }
        active = true
        refresh()
        routeTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        resetTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        guard active else { return }
        active = false
        routeTask?.cancel()
        resetTask?.cancel()
        routeTask = nil
        resetTask = nil
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.availableInputs ?? []
        let bluetooth = inputs.first {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
        }
        bluetoothName = bluetooth?.portName
        isBluetoothConnected = bluetooth != nil
        let current = session.currentRoute.inputs.first
        inputName = current?.portName
        isUsingBluetoothInput = current.map {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
        } ?? false
    }
}
