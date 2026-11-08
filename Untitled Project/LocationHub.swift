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

    func requestAlwaysIfNeeded() {
        guard !requestedAlways, authorizationStatus == .authorizedWhenInUse else { return }
        requestedAlways = true
        manager.requestAlwaysAuthorization()
    }

    /// Called when navigation or recording needs turn-level accuracy.
    func beginPrecise() {
        preciseClients += 1
        applyConfiguration()
    }

    func endPrecise() {
        preciseClients = max(preciseClients - 1, 0)
        applyConfiguration()
    }

    /// Called while a ride needs background location.
    func beginBackground() {
        backgroundClients += 1
        applyConfiguration()
    }

    func endBackground() {
        backgroundClients = max(backgroundClients - 1, 0)
        applyConfiguration()
    }

    private func applyConfiguration() {
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
        guard let location = locations.last,
              location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= 1_000 else { return }
        lastLocation = location
        for handler in locationSubscribers.values {
            handler(location)
        }
    }
}
