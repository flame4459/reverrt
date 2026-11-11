#if canImport(CarPlay)
import CarPlay
import UIKit

/// Entry point for the CarPlay display. CarPlay starts this scene when the
/// phone connects to a supported vehicle; the phone's own scene keeps running.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayRideCoordinator?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        let coordinator = CarPlayRideCoordinator(interfaceController: interfaceController,
                                                 window: window)
        self.coordinator = coordinator
        coordinator.start()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        coordinator?.stop()
        coordinator = nil
    }
}
#endif
