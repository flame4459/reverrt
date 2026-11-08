import Foundation
import GameController
import Observation

/// Handlebar remotes and MFi controllers.
///
/// Most bar remotes present as a game controller (often a micro gamepad).
/// Actions are intentionally simple so they can be triggered with gloves:
/// pause/resume, repeat the instruction, end navigation, calibrate and change
/// camera. Bluetooth pairing is handled by iOS; the app only maps buttons.
@MainActor
@Observable
final class HandlebarRemote {
    enum Action {
        case pauseResume
        case repeatInstruction
        case endRoute
        case calibrate
        case nextCamera
    }

    var isConnected = false
    var controllerName: String?

    @ObservationIgnored var onAction: ((Action) -> Void)?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var disconnectTask: Task<Void, Never>?
    @ObservationIgnored private var configured: Set<ObjectIdentifier> = []
    @ObservationIgnored private var active = false

    func start() {
        guard !active else { return }
        guard UserDefaults.standard.object(forKey: "remote.enabled") as? Bool ?? true else { return }
        active = true

        connectTask = Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                guard !Task.isCancelled, let self,
                      let controller = note.object as? GCController else { continue }
                self.configure(controller)
            }
        }
        disconnectTask = Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(named: .GCControllerDidDisconnect) {
                guard !Task.isCancelled, let self else { continue }
                if let controller = note.object as? GCController {
                    self.configured.remove(ObjectIdentifier(controller))
                }
                self.refreshConnection()
            }
        }

        for controller in GCController.controllers() {
            configure(controller)
        }
        GCController.startWirelessControllerDiscovery {}
        refreshConnection()
    }

    func stop() {
        guard active else { return }
        active = false
        connectTask?.cancel()
        disconnectTask?.cancel()
        connectTask = nil
        disconnectTask = nil
        for controller in GCController.controllers() {
            clearHandlers(controller)
        }
        configured.removeAll()
        GCController.stopWirelessControllerDiscovery()
        isConnected = false
        controllerName = nil
    }

    private func refreshConnection() {
        let controllers = GCController.controllers()
        isConnected = !controllers.isEmpty
        controllerName = controllers.first?.vendorName
    }

    private func configure(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard !configured.contains(id) else { return }
        configured.insert(id)
        controller.playerIndex = .index1

        if let extended = controller.extendedGamepad {
            extended.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.pauseResume) } }
            }
            extended.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.repeatInstruction) } }
            }
            extended.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.endRoute) } }
            }
            extended.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.calibrate) } }
            }
            extended.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.nextCamera) } }
            }
            extended.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.nextCamera) } }
            }
        }

        if let micro = controller.microGamepad {
            micro.reportsAbsoluteDpadValues = false
            micro.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.pauseResume) } }
            }
            micro.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.repeatInstruction) } }
            }
            micro.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.nextCamera) } }
            }
            micro.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { Task { @MainActor in self?.fire(.calibrate) } }
            }
        }

        refreshConnection()
    }

    private func clearHandlers(_ controller: GCController) {
        controller.extendedGamepad?.buttonA.pressedChangedHandler = nil
        controller.extendedGamepad?.buttonB.pressedChangedHandler = nil
        controller.extendedGamepad?.buttonX.pressedChangedHandler = nil
        controller.extendedGamepad?.buttonY.pressedChangedHandler = nil
        controller.extendedGamepad?.dpad.up.pressedChangedHandler = nil
        controller.extendedGamepad?.dpad.down.pressedChangedHandler = nil
        controller.microGamepad?.buttonA.pressedChangedHandler = nil
        controller.microGamepad?.buttonX.pressedChangedHandler = nil
        controller.microGamepad?.dpad.up.pressedChangedHandler = nil
        controller.microGamepad?.dpad.down.pressedChangedHandler = nil
    }

    private func fire(_ action: Action) {
        onAction?(action)
    }
}
