#if canImport(CarPlay)
import CarPlay
import MapKit
import UIKit

/// The one thing CarPlay lets a navigation app draw in its window: map content.
/// Every control and overlay is provided by CarPlay templates, so this view
/// controller deliberately holds nothing but the map and its camera state.
final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    private let mapView = MKMapView()

    private var displayedRouteID: UUID?
    private var routeOverlays: [MKOverlay] = []
    private var destinationAnnotation: MKPointAnnotation?

    private var pose: RideCameraPose?
    private var followsRider = true
    private var isNavigating = false
    private var cameraDistance: CLLocationDistance = 850
    private var heading: CLLocationDirection = 0

    private var panStartCenter: CLLocationCoordinate2D?
    private var zoomStartDistance: CLLocationDistance = 850
    private var rotationStartHeading: CLLocationDirection = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsBuildings = false
        // The car delivers pan/zoom/rotate as CPMapTemplateDelegate callbacks,
        // never as touches on this view.
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat,
                                                                   emphasisStyle: .muted)
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Route content

    /// Adds the planned route line and destination marker. `overview` frames the
    /// whole route for a trip preview; otherwise the camera follows the rider.
    func showRoute(_ route: PlannedRoute?, overview: Bool) {
        guard let route else {
            clearRoute()
            return
        }
        let isNewRoute = route.id != displayedRouteID
        if isNewRoute {
            install(route)
        }
        if overview {
            followsRider = false
            frameRoute()
        } else if isNewRoute {
            // Only a new route re-centers. Otherwise every guidance refresh
            // would yank the map back while the rider is panning it.
            followsRider = true
            if pose == nil {
                frameRoute()
            } else {
                applyCamera(animated: false)
            }
        }
    }

    func clearRoute() {
        if !routeOverlays.isEmpty {
            mapView.removeOverlays(routeOverlays)
            routeOverlays = []
        }
        if let destinationAnnotation {
            mapView.removeAnnotation(destinationAnnotation)
            self.destinationAnnotation = nil
        }
        displayedRouteID = nil
        followsRider = true
    }

    private func install(_ route: PlannedRoute) {
        if !routeOverlays.isEmpty {
            mapView.removeOverlays(routeOverlays)
            routeOverlays = []
        }
        if let destinationAnnotation {
            mapView.removeAnnotation(destinationAnnotation)
            self.destinationAnnotation = nil
        }

        let coordinates = route.coordinates
        guard coordinates.count > 1 else {
            displayedRouteID = route.id
            return
        }

        // A light casing keeps the route readable over the muted dark map.
        let casing = MKPolyline(coordinates: coordinates, count: coordinates.count)
        casing.title = "route-casing"
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        line.title = "route"
        routeOverlays = [casing, line]
        mapView.addOverlays(routeOverlays, level: .aboveRoads)

        if let end = route.destination ?? coordinates.last {
            let pin = MKPointAnnotation()
            pin.coordinate = end
            pin.title = route.kind == .loop ? "Start / finish" : "Destination"
            mapView.addAnnotation(pin)
            destinationAnnotation = pin
        }

        displayedRouteID = route.id
        if pose == nil {
            frameRoute()
        }
    }

    private func frameRoute() {
        guard let line = routeOverlays.last as? MKPolyline else { return }
        mapView.setVisibleMapRect(line.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 40, left: 56, bottom: 96, right: 56),
                                  animated: false)
    }

    // MARK: - Camera

    /// Called at GPS rate. Keeping this separate from template updates lets the
    /// map move smoothly without rebuilding CarPlay guidance on every fix.
    func update(pose: RideCameraPose?, navigating: Bool) {
        self.isNavigating = navigating
        if let pose {
            self.pose = pose
            if navigating {
                heading = pose.heading
            }
        }
        guard followsRider, pose != nil else { return }
        applyCamera(animated: false)
    }

    func recenter(pose: RideCameraPose?, distance: CLLocationDistance = 850) {
        if let pose { self.pose = pose }
        cameraDistance = distance
        followsRider = true
        applyCamera(animated: true)
    }

    func zoom(by factor: Double) {
        guard factor > 0 else { return }
        cameraDistance = min(max(cameraDistance / factor, 120), 40_000)
        applyCamera(animated: true)
    }

    private func applyCamera(animated: Bool) {
        let center = followsRider ? (pose?.coordinate ?? mapView.camera.centerCoordinate)
                                  : mapView.camera.centerCoordinate
        let cameraHeading = followsRider ? heading : mapView.camera.heading
        let camera = MKMapCamera(lookingAtCenter: center,
                                 fromDistance: cameraDistance,
                                 pitch: isNavigating ? 50 : 0,
                                 heading: cameraHeading)
        mapView.setCamera(camera, animated: animated)
    }

    // MARK: - Gestures forwarded by CPMapTemplate

    func beginPan() {
        if panStartCenter == nil {
            panStartCenter = mapView.camera.centerCoordinate
        }
        followsRider = false
    }

    /// `translation` is cumulative from the start of the gesture, so all pan
    /// updates are applied from the anchor stored in `beginPan()`.
    func updatePan(_ translation: CGPoint) {
        guard let start = panStartCenter else { return }
        let width = max(mapView.bounds.width, 1)
        let metersPerPoint = mapView.visibleMapRect.width / Double(width)
        let dx = Double(translation.x) * metersPerPoint
        let dy = Double(translation.y) * metersPerPoint
        let anchor = MKMapPoint(start)
        let moved = MKMapPoint(x: anchor.x - dx, y: anchor.y - dy)

        let camera = mapView.camera
        camera.centerCoordinate = moved.coordinate
        mapView.setCamera(camera, animated: false)
    }

    func endPan() {
        panStartCenter = nil
    }

    func pan(_ direction: CPMapTemplate.PanDirection) {
        followsRider = false
        var rect = mapView.visibleMapRect
        let dx = rect.size.width * 0.35
        let dy = rect.size.height * 0.35
        if direction.contains(.left) { rect.origin.x += dx }
        if direction.contains(.right) { rect.origin.x -= dx }
        if direction.contains(.up) { rect.origin.y -= dy }
        if direction.contains(.down) { rect.origin.y += dy }
        mapView.setVisibleMapRect(rect, animated: true)
    }

    func beginZoom() {
        zoomStartDistance = cameraDistance
    }

    func updateZoom(scale: CGFloat) {
        guard scale > 0 else { return }
        cameraDistance = min(max(zoomStartDistance / Double(scale), 120), 40_000)
        applyCamera(animated: false)
    }

    func beginRotation() {
        rotationStartHeading = mapView.camera.heading
        followsRider = false
    }

    func updateRotation(radians: CGFloat) {
        let camera = mapView.camera
        camera.heading = (rotationStartHeading + Double(radians) * 180 / .pi)
            .truncatingRemainder(dividingBy: 360)
        mapView.setCamera(camera, animated: false)
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKPolylineRenderer(polyline: line)
        renderer.lineCap = .round
        renderer.lineJoin = .round
        if line.title == "route-casing" {
            renderer.strokeColor = UIColor.white.withAlphaComponent(0.55)
            renderer.lineWidth = 12
        } else {
            renderer.strokeColor = UIColor(red: 0.15, green: 0.90, blue: 1.0, alpha: 1)
            renderer.lineWidth = 7
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        let identifier = "destination"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.markerTintColor = UIColor(red: 0.15, green: 0.90, blue: 1.0, alpha: 1)
        view.glyphTintColor = .black
        view.glyphImage = UIImage(systemName: "flag.checkered")
        view.displayPriority = .required
        view.canShowCallout = false
        return view
    }
}
#endif
