import SwiftUI
import MapKit
import UIKit

enum MapRendererKind: String, CaseIterable, Identifiable {
    case mapKit
    case swiftUI
    case immersive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mapKit: "MapKit renderer"
        case .swiftUI: "SwiftUI map"
        case .immersive: "ImmersiveMap (not bundled)"
        }
    }

    var isAvailable: Bool { true }
}

/// MKMapView behind SwiftUI. Overlays are reused by identity and the camera is
/// driven by RideCameraDriver; no SwiftUI state is written from updateUIView.
struct RideMapKitView: UIViewRepresentable {
    let route: PlannedRoute?
    let progress: Double
    let cameraFrame: RideCameraFrame?
    let puck: CLLocationCoordinate2D?
    let heading: Double
    let speed: Double
    let track: [CLLocationCoordinate2D]
    let approach: [CLLocationCoordinate2D]
    let ghost: CLLocationCoordinate2D?
    let hazards: [UserHazard]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.isPitchEnabled = true
        map.isRotateEnabled = false
        map.isZoomEnabled = true
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat,
                                                               emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.mapType = .mutedStandard
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        MapPerformance.overlay {
            context.coordinator.update(map: map,
                                       route: route,
                                       progress: progress,
                                       cameraFrame: cameraFrame,
                                       puck: puck,
                                       heading: heading,
                                       speed: speed,
                                       track: track,
                                       approach: approach,
                                       ghost: ghost,
                                       hazards: hazards)
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        private var routeID: UUID?
        private var lastProgress = -1.0
        private var routeOverlays: [MKPolyline] = []
        private var trackOverlay: MKPolyline?
        private var approachOverlay: MKPolyline?
        private var puckAnnotation: PuckAnnotation?
        private var ghostAnnotation: MKPointAnnotation?
        private var hazardAnnotations: [MKPointAnnotation] = []

        func update(map: MKMapView, route: PlannedRoute?, progress: Double,
                    cameraFrame: RideCameraFrame?, puck: CLLocationCoordinate2D?,
                    heading: Double, speed: Double,
                    track: [CLLocationCoordinate2D], approach: [CLLocationCoordinate2D],
                    ghost: CLLocationCoordinate2D?, hazards: [UserHazard]) {
            if routeID != route?.id || abs(progress - lastProgress) > 0.5 {
                routeID = route?.id
                lastProgress = progress
                rebuildRibbon(on: map, route: route, progress: progress)
            }
            rebuildTrack(on: map, track: track)
            rebuildApproach(on: map, approach: approach)
            updatePuck(on: map, coordinate: puck, heading: heading, speed: speed)
            updateGhost(on: map, coordinate: ghost)
            updateHazards(on: map, hazards: hazards)
            if let cameraFrame {
                let camera = MKMapCamera(lookingAtCenter: cameraFrame.coordinate,
                                         fromDistance: cameraFrame.distance,
                                         pitch: cameraFrame.pitch,
                                         heading: cameraFrame.heading)
                map.setCamera(camera, animated: false)
            }
        }

        private func rebuildRibbon(on map: MKMapView, route: PlannedRoute?, progress: Double) {
            map.removeOverlays(routeOverlays)
            routeOverlays.removeAll()
            guard let route else { return }
            let ribbon = RouteRibbon(route: route, progress: progress)
            func add(_ coordinates: [CLLocationCoordinate2D], title: String) {
                guard coordinates.count > 1 else { return }
                let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
                line.title = title
                routeOverlays.append(line)
            }
            add(ribbon.travelled, title: "ribbon-travelled-casing")
            add(ribbon.travelled, title: "ribbon-travelled")
            add(ribbon.remaining, title: "ribbon-remaining-casing")
            for segment in ribbon.remainingSegments {
                add(segment.coordinates, title: "pace-\(segment.merit)")
            }
            map.addOverlays(routeOverlays)
        }

        private func rebuildTrack(on map: MKMapView, track: [CLLocationCoordinate2D]) {
            guard track.count > 1 else { return }
            if let trackOverlay, track.count == trackOverlay.pointCount { return }
            if let trackOverlay { map.removeOverlay(trackOverlay) }
            let line = MKPolyline(coordinates: track, count: track.count)
            line.title = "track"
            trackOverlay = line
            map.addOverlay(line)
        }

        private func rebuildApproach(on map: MKMapView, approach: [CLLocationCoordinate2D]) {
            guard approach.count > 1 else { return }
            if let approachOverlay, approach.count == approachOverlay.pointCount { return }
            if let approachOverlay { map.removeOverlay(approachOverlay) }
            let line = MKPolyline(coordinates: approach, count: approach.count)
            line.title = "approach"
            approachOverlay = line
            map.addOverlay(line)
        }

        private func updatePuck(on map: MKMapView, coordinate: CLLocationCoordinate2D?,
                                heading: Double, speed: Double) {
            guard let coordinate else { return }
            if let puckAnnotation {
                puckAnnotation.coordinate = coordinate
                if let view = map.view(for: puckAnnotation) as? PuckAnnotationView {
                    view.update(heading: heading, speed: speed)
                }
            } else {
                let annotation = PuckAnnotation(coordinate: coordinate)
                puckAnnotation = annotation
                map.addAnnotation(annotation)
            }
        }

        private func updateGhost(on map: MKMapView, coordinate: CLLocationCoordinate2D?) {
            guard let coordinate else { return }
            if let ghostAnnotation {
                ghostAnnotation.coordinate = coordinate
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                annotation.title = "Ghost"
                ghostAnnotation = annotation
                map.addAnnotation(annotation)
            }
        }

        private func updateHazards(on map: MKMapView, hazards: [UserHazard]) {
            // The renderer only needs the current marks; rebuild when the
            // count changes. Coordinates are immutable in UserHazard.
            guard hazardAnnotations.count != hazards.count else { return }
            map.removeAnnotations(hazardAnnotations)
            hazardAnnotations = hazards.map { mark in
                let annotation = MKPointAnnotation()
                annotation.coordinate = mark.coordinate
                annotation.title = "Rider mark"
                return annotation
            }
            map.addAnnotations(hazardAnnotations)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            switch line.title {
            case "ribbon-travelled-casing", "ribbon-remaining-casing":
                renderer.strokeColor = UIColor(MapConfig.casing)
                renderer.lineWidth = 8
            case "ribbon-travelled":
                renderer.strokeColor = UIColor(MapConfig.accent).withAlphaComponent(0.35)
                renderer.lineWidth = 5
            case let title? where title.hasPrefix("pace-"):
                let merit = Double(title.dropFirst("pace-".count)) ?? 0
                renderer.strokeColor = UIColor(MapConfig.paceColor(merit))
                renderer.lineWidth = 5
            case "ribbon-remaining":
                renderer.strokeColor = UIColor(MapConfig.accent)
                renderer.lineWidth = 5
            case "track":
                renderer.strokeColor = UIColor(Pulse.emerald).withAlphaComponent(0.85)
                renderer.lineWidth = 4
            case "approach":
                renderer.strokeColor = UIColor(MapUI.amber).withAlphaComponent(0.85)
                renderer.lineWidth = 4
                renderer.lineDashPattern = [10, 8]
            default:
                renderer.strokeColor = .clear
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is PuckAnnotation {
                let id = "puck"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? PuckAnnotationView
                    ?? PuckAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.update(heading: 0, speed: 0)
                return view
            }
            if annotation.title == "Ghost" {
                let id = "ghost"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.markerTintColor = UIColor(Pulse.magenta)
                view.glyphImage = UIImage(systemName: "figure.run")
                view.annotation = annotation
                return view
            }
            if annotation.title == "Rider mark" {
                let id = "mark"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.markerTintColor = UIColor(MapUI.amber)
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
                view.annotation = annotation
                return view
            }
            return nil
        }
    }
}

final class PuckAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

final class PuckAnnotationView: MKAnnotationView {
    private let halo = UIView()
    private let dot = UIView()
    private let arrow = UIImageView(image: UIImage(systemName: "location.north.fill"))
    private var speed: Double = 0

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        backgroundColor = .clear
        halo.frame = bounds
        halo.backgroundColor = UIColor(MapConfig.accent).withAlphaComponent(0.18)
        halo.layer.cornerRadius = 27
        halo.layer.shadowColor = UIColor(MapConfig.accent).cgColor
        halo.layer.shadowRadius = 10
        halo.layer.shadowOpacity = 0.45
        addSubview(halo)
        dot.frame = bounds.insetBy(dx: 9, dy: 9)
        dot.backgroundColor = UIColor(MapConfig.accent)
        dot.layer.cornerRadius = 18
        dot.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        dot.layer.borderWidth = 2
        addSubview(dot)
        arrow.tintColor = .white
        arrow.contentMode = .scaleAspectFit
        arrow.frame = bounds.insetBy(dx: 18, dy: 18)
        addSubview(arrow)
    }

    required init?(coder: NSCoder) { nil }

    func update(heading: Double, speed: Double) {
        self.speed = speed
        transform = CGAffineTransform(rotationAngle: 0)
    }
}
