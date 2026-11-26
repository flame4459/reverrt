import Foundation
import Network
import Observation

/// A single reachability check for the map renderer.
///
/// The immersive renderer streams its tile archive from a hosted server, so a
/// blank map usually means "no connection", not "no route". The cockpit uses
/// this to say so and to offer the MapKit renderer instead of pretending the
/// tiles are bundled.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        #if DEBUG
        if CommandLine.arguments.contains("-debugOfflineNetwork") {
            isOnline = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                NetworkMonitor.shared.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "revert.network.monitor"))
    }
}
