#if canImport(CarPlay)
import CarPlay
import CoreLocation
import MapKit
import Observation
import UIKit

/// Owns the CarPlay map template and keeps it in step with the same
/// `NavigationManager` the phone uses. The car never starts a second route:
/// whichever screen starts or ends a ride, the other follows.
final class CarPlayRideCoordinator: NSObject {
    private let interfaceController: CPInterfaceController
    private let window: CPWindow
    private let navigation = RevertServices.shared.navigation
    private let mapViewController = CarPlayMapViewController()
    private let mapTemplate = CPMapTemplate()

    private var endButton: CPBarButton?

    private var navigationSession: CPNavigationSession?
    private var trip: CPTrip?
    private var tripRouteID: UUID?

    private var lastGuidance: CarPlayGuidance?
    private var arrivedAnnounced = false
    private var suppressedRouteID: UUID?
    private var addedManeuverSteps: Set<Int> = []
    private var addedArrivalManeuver = false

    private var isRunning = false
    private var refreshTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        self.window = window
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        window.rootViewController = mapViewController

        // A route can be started from the car while the phone is in a pocket.
        // Ask once for location if onboarding never did, so the map has a fix.
        if navigation.locationUndetermined {
            LocationHub.shared.requestWhenInUse()
        }

        mapTemplate.mapDelegate = self
        mapTemplate.guidanceBackgroundColor = UIColor(red: 0.02, green: 0.04, blue: 0.07, alpha: 1)
        mapTemplate.automaticallyHidesNavigationBar = false
        mapTemplate.hidesButtonsWithNavigationBar = false
        configureMapButtons()
        configureBarButtons()

        interfaceController.setRootTemplate(mapTemplate, animated: true) { [weak self] _, _ in
            guard let self, self.isRunning else { return }
            self.observeCamera()
            self.observeGuidance()
            self.refresh()
        }
    }

    /// The car screen went away. The phone keeps navigating; only the car's
    /// guidance session is torn down.
    func stop() {
        isRunning = false
        refreshTask?.cancel()
        refreshTask = nil
        routeTask?.cancel()
        routeTask = nil
        searchTask?.cancel()
        searchTask = nil

        navigationSession?.finishTrip()
        navigationSession = nil
        trip = nil
        tripRouteID = nil
        mapTemplate.hideTripPreviews()
        mapViewController.clearRoute()
    }

    // MARK: - Observation

    /// GPS arrives about eight times a second. The camera is updated at full
    /// rate; template content is coalesced so the car UI is not rebuilt per fix.
    private func observeCamera() {
        guard isRunning else { return }
        withObservationTracking {
            _ = navigation.cameraPose
            _ = navigation.route?.id
        } onChange: { [weak self] in
            // Unwrap before hopping to the main actor: a weak capture is a
            // mutable `var`, and reading it from inside another concurrent
            // closure is what Swift 6 rejects (`SendableClosureCaptures`).
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning else { return }
                self.mapViewController.update(pose: self.navigation.cameraPose,
                                              navigating: self.navigation.route != nil)
                self.observeCamera()
            }
        }
    }

    private func observeGuidance() {
        guard isRunning else { return }
        withObservationTracking {
            _ = navigation.route?.id
            _ = navigation.step?.id
            _ = navigation.nextStep?.id
            _ = navigation.stepDistance
            _ = navigation.remaining
            _ = navigation.arrived
            _ = navigation.rerouting
            _ = navigation.joined
            _ = navigation.estimatedTimeRemaining
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning else { return }
                self.scheduleRefresh()
                self.observeGuidance()
            }
        }
    }

    private func scheduleRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            self.refreshTask = nil
            self.refresh()
        }
    }

    // MARK: - Syncing the car with the phone

    private func refresh() {
        guard isRunning else { return }

        guard let route = navigation.route else {
            finishNavigationSession()
            mapTemplate.trailingNavigationBarButtons = []
            mapViewController.showRoute(nil, overview: false)
            mapViewController.update(pose: navigation.cameraPose, navigating: false)
            lastGuidance = nil
            suppressedRouteID = nil
            return
        }

        let guidance = navigation.carPlayGuidance
        if suppressedRouteID == route.id {
            mapTemplate.trailingNavigationBarButtons = []
            mapViewController.update(pose: navigation.cameraPose, navigating: false)
            return
        }
        if tripRouteID != route.id {
            suppressedRouteID = nil
            beginNavigationSession(for: route, guidance: guidance)
        }

        updateTravelEstimates(route: route, guidance: guidance)
        if guidance?.stepID != lastGuidance?.stepID
            || guidance?.arrived != lastGuidance?.arrived
            || guidance?.instruction != lastGuidance?.instruction {
            replaceManeuvers(route: route, guidance: guidance)
        }

        mapTemplate.trailingNavigationBarButtons = endButton.map { [$0] } ?? []
        mapViewController.showRoute(route, overview: false)
        mapViewController.update(pose: navigation.cameraPose, navigating: true)
        lastGuidance = guidance
    }

    private func beginNavigationSession(for route: PlannedRoute, guidance: CarPlayGuidance?) {
        if mapTemplate.isPanningInterfaceVisible {
            mapTemplate.dismissPanningInterface(animated: false)
        }
        mapTemplate.hideTripPreviews()

        finishNavigationSession()

        let newTrip = makeTrip(route, eta: guidance?.secondsRemaining)
        trip = newTrip
        tripRouteID = route.id
        arrivedAnnounced = false

        let session = mapTemplate.startNavigationSession(for: newTrip)
        navigationSession = session
        session.upcomingManeuvers = []
        addedManeuverSteps = []
        addedArrivalManeuver = false
        mapTemplate.updateEstimates(travelEstimates(distance: max(guidance?.remaining ?? route.length, 0),
                                                    eta: guidance?.secondsRemaining),
                                    for: newTrip)
        updateTravelEstimates(route: route, guidance: guidance)
        replaceManeuvers(route: route, guidance: guidance)
        lastGuidance = guidance
    }

    private func finishNavigationSession() {
        navigationSession?.finishTrip()
        navigationSession = nil
        trip = nil
        tripRouteID = nil
        arrivedAnnounced = false
    }

    private func updateTravelEstimates(route: PlannedRoute, guidance: CarPlayGuidance?) {
        guard let navigationSession, let trip else { return }
        let distance = max(guidance?.remaining ?? route.length, 0)
        mapTemplate.updateEstimates(travelEstimates(distance: distance,
                                                    eta: guidance?.secondsRemaining),
                                    for: trip)

        if let maneuver = navigationSession.upcomingManeuvers.first {
            let meters = max(guidance?.distanceToManeuver ?? 0, 0)
            navigationSession.updateEstimates(maneuverEstimates(distance: meters),
                                              for: maneuver)
        }
        if guidance?.arrived == true, !arrivedAnnounced {
            arrivedAnnounced = true
            navigationSession.pauseTrip(for: .arrived, description: "You have arrived")
        }
    }

    private func replaceManeuvers(route: PlannedRoute, guidance: CarPlayGuidance?) {
        guard let navigationSession else { return }
        let maneuvers = makeManeuvers(guidance: guidance)
        if #available(iOS 17.4, *) {
            addNewManeuvers(maneuvers, guidance: guidance, to: navigationSession)
        }
        navigationSession.upcomingManeuvers = maneuvers
        if let first = maneuvers.first {
            navigationSession.updateEstimates(
                maneuverEstimates(distance: max(guidance?.distanceToManeuver ?? 0, 0)),
                for: first
            )
        }
        if let road = navigation.step?.road, !road.isEmpty {
            navigationSession.currentRoadNameVariants = [road]
        } else {
            navigationSession.currentRoadNameVariants = [CarPlayText.rideTitle(route)]
        }
        if #available(iOS 17.4, *) {
            navigationSession.maneuverState = maneuverState(distance: guidance?.distanceToManeuver)
        }
    }

    // MARK: - Trip and maneuver building

    private func makeTrip(_ route: PlannedRoute, eta: TimeInterval?) -> CPTrip {
        let originCoordinate = route.points.first?.coordinate
            ?? navigation.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let destinationCoordinate = route.destination ?? route.points.last?.coordinate ?? originCoordinate

        let choice = CPRouteChoice(
            summaryVariants: [CarPlayText.rideTitle(route)],
            additionalInformationVariants: [CarPlayText.rideDetail(route)],
            selectionSummaryVariants: [CarPlayText.etaText(eta)]
        )

        let originItem = mapItem(name: "Start", coordinate: originCoordinate)
        let destinationItem = mapItem(name: CarPlayText.rideTitle(route), coordinate: destinationCoordinate)

        let newTrip: CPTrip
        if #available(iOS 26.4, *) {
            let origin = CPNavigationWaypoint(mapItem: originItem,
                                              locationThreshold: nil,
                                              entryPoints: [])
            let destination = CPNavigationWaypoint(mapItem: destinationItem,
                                                   locationThreshold: nil,
                                                   entryPoints: [])
            newTrip = CPTrip(originWaypoint: origin, destinationWaypoint: destination,
                             routeChoices: [choice])
        } else {
            newTrip = CPTrip(origin: originItem, destination: destinationItem, routeChoices: [choice])
        }
        newTrip.userInfo = route.id
        return newTrip
    }

    private func mapItem(name: String, coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        return item
    }

    /// `CPNavigationSession` wants every maneuver handed to it exactly once, in
    /// order. Re-adding the current/next maneuver on each refresh would pile up
    /// duplicates, so only steps the session has not seen are added.
    private func addNewManeuvers(_ maneuvers: [CPManeuver],
                                 guidance: CarPlayGuidance?,
                                 to session: CPNavigationSession) {
        if guidance?.arrived == true {
            guard !addedArrivalManeuver else { return }
            session.add(maneuvers)
            addedArrivalManeuver = true
            return
        }
        let stepIDs = [navigation.step?.id, navigation.nextStep?.id].compactMap { $0 }
        let newManeuvers = zip(stepIDs, maneuvers).compactMap { id, maneuver in
            addedManeuverSteps.contains(id) ? nil : maneuver
        }
        guard !newManeuvers.isEmpty else { return }
        session.add(newManeuvers)
        addedManeuverSteps.formUnion(stepIDs)
    }

    private func makeManeuvers(guidance: CarPlayGuidance?) -> [CPManeuver] {
        if guidance?.arrived == true {
            let arrive = CPManeuver()
            arrive.instructionVariants = ["You have arrived", "Arrived"]
            arrive.dashboardInstructionVariants = ["You have arrived", "Arrived"]
            arrive.symbolImage = UIImage(systemName: "flag.checkered")
            arrive.dashboardSymbolImage = UIImage(systemName: "flag.checkered")
            arrive.maneuverType = .arriveAtDestination
            arrive.initialTravelEstimates = CPTravelEstimates(
                distanceRemaining: Measurement(value: 0, unit: UnitLength.meters),
                timeRemaining: 0
            )
            return [arrive]
        }

        var maneuvers: [CPManeuver] = []
        if let step = navigation.step {
            maneuvers.append(makeManeuver(step: step,
                                          distance: guidance?.distanceToManeuver))
        }
        if let next = navigation.nextStep {
            let leg = max(next.distance - (navigation.step?.distance ?? next.distance), 0)
            maneuvers.append(makeManeuver(step: next, distance: leg))
        }
        if maneuvers.isEmpty {
            let fallback = CPManeuver()
            fallback.instructionVariants = [guidance?.instruction ?? "Follow the route"]
            fallback.dashboardInstructionVariants = [guidance?.instruction ?? "Follow the route"]
            fallback.symbolImage = UIImage(systemName: "arrow.up")
            fallback.maneuverType = .straightAhead
            maneuvers.append(fallback)
        }
        return maneuvers
    }

    private func makeManeuver(step: NavStep, distance: Double?) -> CPManeuver {
        let maneuver = CPManeuver()
        maneuver.instructionVariants = [step.instruction]
        maneuver.dashboardInstructionVariants = [step.instruction]
        maneuver.symbolImage = UIImage(systemName: step.symbol)
        maneuver.dashboardSymbolImage = UIImage(systemName: step.symbol)
        maneuver.maneuverType = maneuverType(for: step.turn)
        if let road = step.road, !road.isEmpty {
            maneuver.roadFollowingManeuverVariants = [road]
        }
        let meters = max(distance ?? 0, 0)
        maneuver.initialTravelEstimates = maneuverEstimates(distance: meters)
        return maneuver
    }

    private func maneuverType(for turn: NavStep.Turn) -> CPManeuverType {
        switch turn {
        case .start: .startRoute
        case .straight: .straightAhead
        case .slightLeft: .slightLeftTurn
        case .left: .leftTurn
        case .sharpLeft: .sharpLeftTurn
        case .slightRight: .slightRightTurn
        case .right: .rightTurn
        case .sharpRight: .sharpRightTurn
        case .uTurn: .uTurn
        case .arrive: .arriveAtDestination
        }
    }

    private func maneuverState(distance: Double?) -> CPManeuverState {
        guard let distance else { return .continue }
        if distance < 45 { return .execute }
        if distance < 250 { return .prepare }
        return .continue
    }

    // MARK: - Estimates

    private func travelEstimates(distance: Double, eta: TimeInterval?) -> CPTravelEstimates {
        CPTravelEstimates(
            distanceRemaining: Measurement(value: max(distance, 0), unit: UnitLength.meters),
            timeRemaining: eta ?? -1
        )
    }

    private func maneuverEstimates(distance: Double) -> CPTravelEstimates {
        CPTravelEstimates(
            distanceRemaining: Measurement(value: max(distance, 0), unit: UnitLength.meters),
            timeRemaining: timeToTravel(max(distance, 0))
        )
    }

    private func timeToTravel(_ meters: Double) -> TimeInterval {
        guard meters > 0 else { return 0 }
        if navigation.currentSpeedMps > 2 {
            return meters / navigation.currentSpeedMps
        }
        if let route = navigation.route,
           let expected = route.expectedTravelTime,
           route.length > 0 {
            return expected * meters / route.length
        }
        return -1
    }

    // MARK: - Buttons

    private func configureMapButtons() {
        let recenter = CPMapButton { [weak self] _ in self?.recenterOnRider() }
        recenter.image = UIImage(systemName: "location.fill")
        recenter.focusedImage = UIImage(systemName: "location.fill")

        let zoomIn = CPMapButton { [weak self] _ in self?.mapViewController.zoom(by: 1.8) }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")

        let zoomOut = CPMapButton { [weak self] _ in self?.mapViewController.zoom(by: 1 / 1.8) }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")

        mapTemplate.mapButtons = [recenter, zoomIn, zoomOut]
    }

    private func configureBarButtons() {
        let rides = CPBarButton(image: UIImage(systemName: "list.bullet") ?? UIImage()) { [weak self] _ in
            self?.presentRides()
        }
        mapTemplate.leadingNavigationBarButtons = [rides]

        endButton = CPBarButton(title: "End") { [weak self] _ in
            self?.confirmEndNavigation()
        }
        mapTemplate.trailingNavigationBarButtons = []
    }

    private func recenterOnRider() {
        if mapTemplate.isPanningInterfaceVisible {
            mapTemplate.dismissPanningInterface(animated: true)
        }
        mapViewController.recenter(pose: navigation.cameraPose)
    }

    // MARK: - Rides list

    private func presentRides() {
        interfaceController.pushTemplate(makeRidesTemplate(), animated: true) { _, _ in }
    }

    private func makeRidesTemplate() -> CPListTemplate {
        var sections: [CPListSection] = []

        if let route = navigation.route {
            let end = CPListItem(text: "End ride",
                                 detailText: CarPlayText.rideTitle(route),
                                 image: UIImage(systemName: "xmark.circle"))
            end.handler = { [weak self] _, completion in
                guard let self else {
                    completion()
                    return
                }
                self.interfaceController.popToRootTemplate(animated: true) { [weak self] _, _ in
                    self?.confirmEndNavigation()
                }
                completion()
            }
            sections.append(CPListSection(items: [end], header: "Now", sectionIndexTitle: nil))
        }

        let search = CPListItem(text: "Search destination",
                                detailText: "Find a place to ride to",
                                image: UIImage(systemName: "magnifyingglass"))
        search.handler = { [weak self] _, completion in
            self?.presentSearch()
            completion()
        }
        sections.append(CPListSection(items: [search], header: "Find a place", sectionIndexTitle: nil))

        let saved = CarPlayDestinations.savedRides(limit: 6)
        if !saved.isEmpty {
            let items = saved.map { destination -> CPListItem in
                let item = CPListItem(
                    text: destination.title,
                    detailText: destination.detail,
                    image: UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                )
                item.handler = { [weak self] _, completion in
                    self?.select(destination: destination)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Saved rides",
                                          sectionIndexTitle: nil))
        }

        let places = CarPlayDestinations.places(limit: 4)
        if !places.isEmpty {
            let items = places.map { destination -> CPListItem in
                let item = CPListItem(
                    text: destination.title,
                    detailText: destination.detail,
                    image: UIImage(systemName: placeImage(for: destination.id))
                )
                item.handler = { [weak self] _, completion in
                    self?.select(destination: destination)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Places",
                                          sectionIndexTitle: nil))
        }

        let visibleSections = Array(sections.prefix(Int(CPListTemplate.maximumSectionCount)))
        return CPListTemplate(title: "Rides", sections: visibleSections)
    }

    private func placeImage(for id: String) -> String {
        switch id {
        case "home": "house"
        case "work": "briefcase"
        default: "mappin"
        }
    }

    private func select(destination: CarPlayDestination) {
        if let route = destination.route {
            interfaceController.popToRootTemplate(animated: true) { [weak self] _, _ in
                self?.startRide(route: route, roads: destination.roads)
            }
            return
        }
        guard let coordinate = destination.coordinate else { return }
        guard let origin = navigation.currentLocation?.coordinate ?? navigation.userCoordinate else {
            showLocationUnavailable()
            return
        }

        interfaceController.popToRootTemplate(animated: true) { _, _ in }
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let route = try await self.directions(from: origin, to: coordinate)
                guard !Task.isCancelled else { return }
                self.startRide(route: route, roads: [])
            } catch {
                guard !Task.isCancelled else { return }
                RevertDiagnostics.log("CarPlay route failed: \(error.localizedDescription)")
                self.showMessage("Couldn't build that route",
                                 detail: "Check your connection and try again.")
            }
        }
    }

    private func startRide(route: PlannedRoute, roads: [Road]) {
        guard navigation.route == nil else {
            confirmReplace(route: route, roads: roads)
            return
        }
        launch(route: route, roads: roads)
    }

    private func confirmReplace(route: PlannedRoute, roads: [Road]) {
        let keep = CPAlertAction(title: "Keep riding", style: .cancel) { _ in }
        let start = CPAlertAction(title: "Start ride", style: .default) { [weak self] _ in
            self?.launch(route: route, roads: roads)
        }
        let alert = CPAlertTemplate(
            titleVariants: ["Replace your current ride with \(CarPlayText.rideTitle(route))?",
                            "Replace current ride?"],
            actions: [keep, start]
        )
        interfaceController.presentTemplate(alert, animated: true) { _, _ in }
    }

    private func launch(route: PlannedRoute, roads: [Road]) {
        mapViewController.showRoute(route, overview: false)
        navigation.start(route, roads: roads)
        refresh()
    }

    private func confirmEndNavigation() {
        guard navigation.route != nil else { return }
        let keep = CPAlertAction(title: "Keep riding", style: .cancel) { _ in }
        let end = CPAlertAction(title: "End ride", style: .destructive) { [weak self] _ in
            self?.navigation.stop()
            self?.refresh()
        }
        let alert = CPAlertTemplate(titleVariants: ["End ride?", "End navigation?"],
                                    actions: [keep, end])
        interfaceController.presentTemplate(alert, animated: true) { _, _ in }
    }

    private func showLocationUnavailable() {
        if navigation.locationDenied {
            showMessage("Location is off",
                        detail: "Open Revert on your iPhone and allow location access.")
        } else {
            showMessage("Waiting for GPS",
                        detail: "Move somewhere with a clear view of the sky, then try again.")
        }
    }

    private func showMessage(_ title: String, detail: String) {
        let combined = detail.isEmpty ? title : "\(title). \(detail)"
        let action = CPAlertAction(title: "OK", style: .default) { _ in }
        let alert = CPAlertTemplate(titleVariants: [combined, title], actions: [action])
        interfaceController.presentTemplate(alert, animated: true) { _, _ in }
    }

    // MARK: - Search

    private func presentSearch() {
        let search = CPSearchTemplate()
        search.delegate = self
        interfaceController.pushTemplate(search, animated: true) { _, _ in }
    }

    private func searchItems(for query: String) async -> [CPListItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let center = navigation.currentLocation?.coordinate ?? navigation.userCoordinate {
            request.region = MKCoordinateRegion(center: center,
                                                latitudinalMeters: 60_000,
                                                longitudinalMeters: 60_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(8).map { mapItem in
                let row = CPListItem(
                    text: mapItem.name ?? "Destination",
                    detailText: mapItem.addressRepresentations?
                        .fullAddress(includingRegion: false, singleLine: true)
                        ?? mapItem.address?.fullAddress
                        ?? "",
                    image: UIImage(systemName: "mappin")
                )
                row.handler = { [weak self] _, completion in
                    self?.select(searchResult: mapItem)
                    completion()
                }
                return row
            }
        } catch {
            return []
        }
    }

    private func select(searchResult mapItem: MKMapItem) {
        let coordinate = mapItem.location.coordinate
        guard let origin = navigation.currentLocation?.coordinate ?? navigation.userCoordinate else {
            showLocationUnavailable()
            return
        }
        interfaceController.popToRootTemplate(animated: true) { _, _ in }
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let route = try await self.directions(from: origin, to: coordinate)
                guard !Task.isCancelled else { return }
                self.startRide(route: route, roads: [])
            } catch {
                guard !Task.isCancelled else { return }
                RevertDiagnostics.log("CarPlay route failed: \(error.localizedDescription)")
                self.showMessage("Couldn't build that route",
                                 detail: "Check your connection and try again.")
            }
        }
    }

    private func directions(from origin: CLLocationCoordinate2D,
                            to destination: CLLocationCoordinate2D) async throws -> PlannedRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw CarPlayRouteError.noRoute
        }
        return PlannedRoute(mapRoute: route)
    }

    private enum CarPlayRouteError: LocalizedError {
        case noRoute

        var errorDescription: String? {
            "No drivable route was found. Try a different destination."
        }
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlayRideCoordinator: CPMapTemplateDelegate {
    func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
        // The vehicle's built-in navigation has taken over the screen. Stop the
        // car's guidance, but leave the ride running on the phone.
        suppressedRouteID = navigation.route?.id
        finishNavigationSession()
        mapTemplate.hideTripPreviews()
        mapTemplate.trailingNavigationBarButtons = []
        refresh()
    }

    func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {
        mapViewController.beginPan()
    }

    func mapTemplateWillDismissPanningInterface(_ mapTemplate: CPMapTemplate) {
        mapViewController.endPan()
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        mapViewController.pan(direction)
    }

    func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
        mapViewController.beginPan()
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate,
                     didUpdatePanGestureWithTranslation translation: CGPoint,
                     velocity: CGPoint) {
        mapViewController.updatePan(translation)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, didEndPanGestureWithVelocity velocity: CGPoint) {
        mapViewController.endPan()
    }

    func mapTemplateDidBeginZoomGesture(_ mapTemplate: CPMapTemplate) {
        mapViewController.beginZoom()
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate,
                     didUpdateZoomGestureWithCenter center: CGPoint,
                     scale: CGFloat,
                     velocity: CGFloat) {
        mapViewController.updateZoom(scale: scale)
    }

    func mapTemplateDidBeginRotationGesture(_ mapTemplate: CPMapTemplate) {
        mapViewController.beginRotation()
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate,
                     didRotateWithCenter center: CGPoint,
                     rotation: CGFloat,
                     velocity: CGFloat) {
        mapViewController.updateRotation(radians: rotation)
    }
}

// MARK: - CPSearchTemplateDelegate

extension CarPlayRideCoordinator: CPSearchTemplateDelegate {
    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                        updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchTask?.cancel()
            let suggestions = CarPlayDestinations.places(limit: 4).map { destination -> CPListItem in
                let row = CPListItem(text: destination.title,
                                     detailText: destination.detail,
                                     image: UIImage(systemName: "clock.arrow.circlepath"))
                row.handler = { [weak self] _, completion in
                    self?.select(destination: destination)
                    completion()
                }
                return row
            }
            completionHandler(suggestions)
            return
        }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let items = await self.searchItems(for: query)
            guard !Task.isCancelled else { return }
            completionHandler(items)
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                        selectedResult item: CPListItem,
                        completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
#endif
