import SwiftUI

/// Stable identifiers for the UI test suite.
///
/// Tests must depend on these values instead of screen copy. Copy is product
/// surface and changes as the UI is redesigned; an identifier is a contract.
/// `RevertUITests/UITestID.swift` mirrors these strings, and
/// `AccessibilityContractUITests` fails if a screen loses one.
enum AccessibilityID {
    enum Home {
        static let title = "home.title"
        static let destination = "home.destination"
        static let planRoute = "home.planRoute"
        static let openCockpit = "home.openCockpit"
        static let colorScheme = "home.colorScheme"
        static let menu = "home.menu"
        static let viewGarage = "home.viewGarage"
        static let savedPlaces = "home.savedPlaces"
        static let viewHistory = "home.viewHistory"
    }

    enum TabBar {
        static let home = "tab.home"
        static let routes = "tab.routes"
        static let ride = "tab.ride"
        static let garage = "tab.garage"
        static let history = "tab.history"

        static func id(for tab: PulseTab) -> String { "tab.\(tab.rawValue)" }
    }

    enum Routes {
        static let title = "routes.title"
        static let destination = "routes.destination"
        static let findRoute = "routes.findRoute"
        static let start = "routes.start"
        static let openMap = "routes.openMap"
        static let closeMap = "routes.closeMap"
        static let savedPlaces = "routes.savedPlaces"
    }

    enum Plan {
        static let title = "plan.title"
        static let findLoops = "plan.findLoops"
        static let close = "plan.close"
    }

    enum Cockpit {
        static let start = "cockpit.start"
        static let planRoute = "cockpit.planRoute"
        static let pause = "cockpit.pause"
        static let stop = "cockpit.stop"
        static let close = "cockpit.close"
        static let banner = "cockpit.banner"
    }

    enum Garage {
        static let title = "garage.title"
        static let add = "garage.add"
        static let search = "garage.search"
    }

    enum History {
        static let title = "history.title"
        static let importGPX = "history.import"
        static let search = "history.search"
        static let close = "history.close"
    }

    enum Settings {
        static let title = "settings.title"
        static let done = "settings.done"
    }

    enum Insights {
        static let title = "insights.title"
        static let close = "insights.close"
    }

    enum Safety {
        static let title = "safety.title"
        static let close = "safety.close"
    }

    enum Posters {
        static let title = "posters.title"
        static let close = "posters.close"
    }

    enum Summary {
        static let done = "summary.done"
        static let close = "summary.close"
    }

    enum Onboarding {
        static let title = "onboarding.title"
        static let primary = "onboarding.primary"
        static let skip = "onboarding.skip"
    }
}

extension View {
    /// Applies an identifier only when the caller supplied one. Shared
    /// components can stay unidentified by default instead of overwriting a
    /// call site's identifier with an empty string.
    @ViewBuilder
    func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
