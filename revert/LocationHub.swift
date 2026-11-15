import Foundation
import CoreLocation
import Observation

/// One GPS stream for the whole app.
///
/// Navigation and ride recording used to each own a `CLLocationManager`
/// running at best accuracy simultaneously. They now subscribe here instead,
/// so there is one radio, one accuracy policy, and one authoritative speed and
/// heading.
@MainActor
@Observable
final class LocationHub: NSObject, CLLocationManagerDelegate {
    static let shared = LocationHub()

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private(set) var lastLocation: CLLocation?
    /// When the route simulator is driving the app, real fixes are ignored and
    /// synthetic ones are published through the same subscriber path.
    private(set) var isSimulating = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var locationSubscribers: [UUID: (CLLocation) -> Void] = [:]
    @ObservationIgnored private var authorizationSubscribers: [UUID: (CLAuthorizationStatus) -> Void] = [:]
    @ObservationIgnored private var preciseClients = 0
    @ObservationIgnored private var backgroundClients = 0
    @ObservationIgnored private var requestedAlways = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        authorizationStatus = manager.authorizationStatus
        // Permission is requested by onboarding or by the first action that
        // actually needs a fix. Prompting from a singleton init meant the
        // system alert appeared before the rider had any context.
        applyConfiguration()
    }

    // MARK: Subscriptions

    @discardableResult
    func addSubscriber(_ handler: @escaping (CLLocation) -> Void) -> UUID {
        let id = UUID()
        locationSubscribers[id] = handler
        return id
    }

    func removeSubscriber(_ id: UUID) {
        locationSubscribers[id] = nil
    }

    @discardableResult
    func addAuthorizationSubscriber(_ handler: @escaping (CLAuthorizationStatus) -> Void) -> UUID {
        let id = UUID()
        authorizationSubscribers[id] = handler
        return id
    }

    func removeAuthorizationSubscriber(_ id: UUID) {
        authorizationSubscribers[id] = nil
    }

    // MARK: Policy

    func requestWhenInUse() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    // MARK: Simulation

    func beginSimulation() {
        guard !isSimulating else { return }
        isSimulating = true
        manager.stopUpdatingLocation()
    }

    func endSimulation() {
        guard isSimulating else { return }
        isSimulating = false
        applyConfiguration()
    }

    /// Publishes a synthetic fix exactly as if Core Location had delivered it.
    /// Navigation, the recorder and the alert engine all subscribe to this hub,
    /// so the rest of the app cannot tell the difference.
    func inject(_ location: CLLocation) {
        guard isSimulating else { return }
        lastLocation = location
        for handler in locationSubscribers.values {
            handler(location)
        }
    }

    func requestAlwaysIfNeeded() {
        guard !requestedAlways, authorizationStatus == .authorizedWhenInUse else { return }
        requestedAlways = true
        manager.requestAlwaysAuthorization()
    }

    /// Continuous recording needs "Always". "While Using" stops delivering
    /// fixes the moment the screen locks, which is most of a ride.
    var hasBackgroundAuthorization: Bool { authorizationStatus == .authorizedAlways }

    /// A claim on one of the hub's accuracy tiers.
    ///
    /// Releasing a lease twice does nothing, so two owners cleaning up the same
    /// claim (the recorder finishing a ride and the ride screen disappearing,
    /// say) can no longer drop the other owner's accuracy to 100 m mid-ride.
    /// Prefer this over counting begin/end calls by hand.
    @MainActor
    final class Lease {
        enum Tier { case precise, background }

        private weak var hub: LocationHub?
        private let tier: Tier
        private var active = true

        fileprivate init(hub: LocationHub, tier: Tier) {
            self.hub = hub
            self.tier = tier
        }

        /// Gives the claim back. Safe to call more than once, and safe after
        /// the hub has gone away.
        func release() {
            guard active else { return }
            active = false
            guard let hub else { return }
            switch tier {
            case .precise: hub.preciseClients = max(hub.preciseClients - 1, 0)
            case .background: hub.backgroundClients = max(hub.backgroundClients - 1, 0)
            }
            hub.applyConfiguration()
        }
    }

    /// Called when navigation or recording needs turn-level accuracy.
    func acquirePrecise() -> Lease {
        preciseClients += 1
        applyConfiguration()
        return Lease(hub: self, tier: .precise)
    }

    /// Called while a ride needs background location.
    func acquireBackground() -> Lease {
        backgroundClients += 1
        applyConfiguration()
        return Lease(hub: self, tier: .background)
    }

    /// Live claim counts. Exposed for diagnostics and unit tests; the rider
    /// never sees these directly.
    var preciseClaimCount: Int { preciseClients }
    var backgroundClaimCount: Int { backgroundClients }

    private func applyConfiguration() {
        if isSimulating {
            manager.stopUpdatingLocation()
            return
        }
        manager.desiredAccuracy = preciseClients > 0 ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = preciseClients > 0 ? 5 : 25
        let wantsBackground = backgroundClients > 0 && authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = wantsBackground
        manager.showsBackgroundLocationIndicator = wantsBackground
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    // MARK: Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        for handler in authorizationSubscribers.values {
            handler(authorizationStatus)
        }
        if backgroundClients > 0 {
            requestAlwaysIfNeeded()
        }
        applyConfiguration()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isSimulating else { return }
        // A batch can carry several fixes after a suspension, a background
        // stretch or a slow redraw. They are not guaranteed to be in order, so
        // the newest timestamp is the rider's position — `locations.last`
        // trusted the delivery order and could hand navigation a fix that was
        // already seconds old.
        guard let location = locations
            .filter({ $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 1_000 })
            .max(by: { $0.timestamp < $1.timestamp }) else { return }
        lastLocation = location
        for handler in locationSubscribers.values {
            handler(location)
        }
    }
}
