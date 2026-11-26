import SwiftUI
import CoreLocation
import ImmersiveMap
import UIKit

/// A pin on the unified map. Images are drawn by the app so the same glyphs are
/// used on every screen.
nonisolated struct RevertMapPin: Identifiable {
    let id: UInt64
    let coordinate: CLLocationCoordinate2D
    let image: CGImage
}

/// How the camera follows the scene.
nonisolated enum RevertMapCamera: Equatable {
    /// Driven by the cockpit camera engine (`RideCameraDriver`) while riding.
    case follow
    /// Fit the whole route (planning, previews, replay overview).
    case overview
    /// A fixed position (a corner, a saved place, a replay frame).
    case fixed(center: CLLocationCoordinate2D, zoom: Double, bearing: Float = 0, pitch: Float = 0)

    static func == (lhs: RevertMapCamera, rhs: RevertMapCamera) -> Bool {
        switch (lhs, rhs) {
        case (.follow, .follow), (.overview, .overview):
            return true
        case let (.fixed(lc, lz, lb, lp), .fixed(rc, rz, rb, rp)):
            return lc.latitude == rc.latitude && lc.longitude == rc.longitude
                && lz == rz && lb == rb && lp == rp
        default:
            return false
        }
    }
}

/// Everything a map shows. One value type for every screen, so no screen grows
/// its own renderer.
struct RevertMapScene {
    var route: PlannedRoute?
    var progress: Double = 0
    var camera: RevertMapCamera = .follow
    var puck: CLLocationCoordinate2D?
    var approach: [CLLocationCoordinate2D] = []
    var track: [CLLocationCoordinate2D] = []
    var ghost: CLLocationCoordinate2D?
    var hazards: [CLLocationCoordinate2D] = []
    var pins: [RevertMapPin] = []
    /// The cockpit separates ridden from remaining road; previews draw one line.
    var showsRouteProgress: Bool = true

    static func cockpit(route: PlannedRoute?,
                        progress: Double,
                        puck: CLLocationCoordinate2D?,
                        approach: [CLLocationCoordinate2D],
                        track: [CLLocationCoordinate2D],
                        ghost: CLLocationCoordinate2D?,
                        hazards: [CLLocationCoordinate2D]) -> RevertMapScene {
        RevertMapScene(route: route,
                       progress: progress,
                       camera: .follow,
                       puck: puck,
                       approach: approach,
                       track: track,
                       ghost: ghost,
                       hazards: hazards)
    }

    static func overview(_ route: PlannedRoute?, progress: Double = 0,
                         pins: [RevertMapPin] = []) -> RevertMapScene {
        RevertMapScene(route: route,
                       progress: progress,
                       camera: .overview,
                       pins: pins,
                       showsRouteProgress: false)
    }
}

/// The one map renderer: ImmersiveMap (Metal/PMTiles) with the app's styling,
/// overlays and offline archive selection. The cockpit, previews, replay and
/// history all build a `RevertMapScene` and show this view.
struct RevertMapView: View {
    let scene: RevertMapScene
    /// Present only in the ride cockpit: drives the camera from the display link.
    var driver: RideCameraDriver?

    @State private var camera = ImmersiveMapCameraController()
    @State private var layers = ImmersiveMapLayersController()
    @State private var pins = ImmersiveMapPinsController()
    @State private var frameObserver: UUID?
    @State private var lastLayerSignature = ""
    @State private var lastPinSignature = ""
    @State private var viewport: CGSize = .zero
    @State private var isMapReady = false
    @State private var appliedCameraKey = ""
    @State private var framesRendered = 0

    var body: some View {
        GeometryReader { proxy in
            let archive = MapRegionStore.shared.archive(for: scene.puck
                                                        ?? scene.route?.points.first?.coordinate)
            ImmersiveMapView()
                .cameraController(camera)
                .cameraPosition(initialCamera)
                .layers(layers)
                .pins(pins)
                .pinSettings(shape: .circle, borderWidthPx: 2,
                             borderColor: SIMD4<Float>(1, 1, 1, 0.9),
                             fillColor: MapConfig.paceSIMD4(0.7),
                             contentInset: 0.06)
                .modelArchive(nil)
                .mapStyle(.night.apply { theme in
                    theme.labelOpacity.pois = 0
                })
                .labelSettings(labelSettings)
                .trees(isEnabled: false)
                .shadows(isEnabled: false)
                .atmosphere(isEnabled: false)
                .globe(isEnabled: false)
                .renderLoopSettings(.init(forceContinuousRendering: false,
                                          interactionFramesPerSecond: 120,
                                          labelFadeFramesPerSecond: 60))
                .tileArchive(archive.url)
                .onFrameRendered { _ in
                    framesRendered += 1
                    // The renderer has attached by the first frame, but its
                    // tile pipeline still needs the frame that follows: a
                    // camera move issued on frame one leaves it at zero
                    // coverage. Apply once two frames exist, and again if the
                    // viewport changes later.
                    if !isMapReady, framesRendered >= 2 {
                        isMapReady = true
                        applyCameraIfNeeded()
                    }
                }
                .onAppear {
                    viewport = proxy.size
                    refresh()
                    applyCameraIfNeeded()
                    if frameObserver == nil, let driver {
                        frameObserver = driver.addFrameObserver { frame in
                            camera.jump(to: Self.position(for: frame))
                        }
                    }
                }
                .onChange(of: proxy.size) { _, size in
                    // Rotation, split view, keyboard: fit again at the new size.
                    guard abs(size.width - viewport.width) > 0.5
                        || abs(size.height - viewport.height) > 0.5 else { return }
                    viewport = size
                    appliedCameraKey = ""
                    applyCameraIfNeeded()
                }
                .onDisappear {
                    if let frameObserver {
                        driver?.removeFrameObserver(frameObserver)
                        self.frameObserver = nil
                    }
                }
                .onChange(of: scene.route?.id) { _, _ in
                    appliedCameraKey = ""
                    refresh()
                    applyCameraIfNeeded()
                }
                .onChange(of: scene.camera) { _, _ in
                    appliedCameraKey = ""
                    applyCameraIfNeeded()
                }
                .onChange(of: scene.progress) { _, _ in refresh() }
                .onChange(of: scene.puck?.latitude) { _, _ in refresh() }
                .onChange(of: scene.puck?.longitude) { _, _ in refresh() }
                .onChange(of: scene.ghost?.latitude) { _, _ in refresh() }
                .onChange(of: scene.hazards.count) { _, _ in refresh() }
                .onChange(of: scene.pins.count) { _, _ in refresh() }
                .id("\(archiveKey(archive.source))-\(scene.camera == .overview ? "overview" : "follow")")
        }
    }

    // MARK: - Camera

    private var initialCamera: ImmersiveMapCameraPosition {
        if let fit = fittedCamera() { return fit.position }
        return fallbackPosition
    }

    /// The fit for the current scene and viewport, if there is enough geometry
    /// and a real viewport to fit it into.
    private func fittedCamera() -> RevertMapFit.Result? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        switch scene.camera {
        case .overview:
            let coordinates = frameCoordinates
            guard !coordinates.isEmpty else { return nil }
            return RevertMapFit.fit(coordinates, viewport: viewport, padding: 28)
        case .fixed(let center, let zoom, _, _):
            return RevertMapFit.Result(latitude: center.latitude,
                                       longitude: center.longitude,
                                       zoom: zoom)
        case .follow:
            return nil
        }
    }

    /// What an overview should contain: the route, else pins and the rider.
    private var frameCoordinates: [CLLocationCoordinate2D] {
        if let route = scene.route, route.coordinates.count > 1 {
            return route.coordinates
        }
        var coordinates = scene.pins.map(\.coordinate)
        if let puck = scene.puck { coordinates.append(puck) }
        if coordinates.isEmpty, let last = LocationHub.shared.lastLocation?.coordinate {
            coordinates.append(last)
        }
        return coordinates
    }

    private var fallbackPosition: ImmersiveMapCameraPosition {
        switch scene.camera {
        case .overview:
            return position(nearby: scene.puck ?? LocationHub.shared.lastLocation?.coordinate)
        case .fixed(let center, let zoom, let bearing, let pitch):
            return ImmersiveMapCameraPosition(latitudeDegrees: center.latitude,
                                              longitudeDegrees: center.longitude,
                                              zoom: zoom, bearing: bearing, pitch: pitch)
        case .follow:
            if let frame = driver?.frame { return Self.position(for: frame) }
            if let first = scene.route?.points.first?.coordinate {
                return ImmersiveMapCameraPosition(latitudeDegrees: first.latitude,
                                                  longitudeDegrees: first.longitude,
                                                  zoom: 14, bearing: 0, pitch: 0)
            }
            return position(nearby: scene.puck ?? LocationHub.shared.lastLocation?.coordinate)
        }
    }

    private func position(nearby coordinate: CLLocationCoordinate2D?) -> ImmersiveMapCameraPosition {
        guard let coordinate else { return .city(.sanFrancisco) }
        return ImmersiveMapCameraPosition(latitudeDegrees: coordinate.latitude,
                                          longitudeDegrees: coordinate.longitude,
                                          zoom: 14, bearing: 0, pitch: 0)
    }

    /// Applies the scene's camera once the map is attached, once per distinct
    /// camera request. A request made before readiness is kept, not dropped.
    private func applyCameraIfNeeded() {
        guard isMapReady, viewport.width > 0, viewport.height > 0 else { return }
        let key: String
        let target: ImmersiveMapCameraPosition
        switch scene.camera {
        case .follow:
            // The cockpit's driver owns the camera; without one, put the rider
            // at the start once.
            guard driver == nil else { return }
            key = "follow-\(scene.route?.id.uuidString ?? "-")"
            target = fallbackPosition
        case .overview:
            key = "overview-\(scene.route?.id.uuidString ?? "-")-\(Int(viewport.width))x\(Int(viewport.height))"
            target = fittedCamera()?.position ?? fallbackPosition
        case .fixed(let center, let zoom, let bearing, let pitch):
            key = "fixed-\(center.latitude),\(center.longitude),\(zoom),\(bearing),\(pitch)"
            target = ImmersiveMapCameraPosition(latitudeDegrees: center.latitude,
                                                longitudeDegrees: center.longitude,
                                                zoom: zoom, bearing: bearing, pitch: pitch)
        }
        print("MAPDEBUG apply key=\(key) targetZoom=\(target.zoom) viewport=\(viewport)")
        guard key != appliedCameraKey else { return }
        appliedCameraKey = key
        camera.jump(to: target)
    }

    private static func position(for frame: RideCameraFrame) -> ImmersiveMapCameraPosition {
        let zoom = min(max(17.8 - log2(max(frame.distance, 80) / 220), 10), 19)
        return ImmersiveMapCameraPosition(latitudeDegrees: frame.latitude,
                                          longitudeDegrees: frame.longitude,
                                          zoom: zoom,
                                          bearing: Float(frame.heading * .pi / 180),
                                          pitch: Float(frame.pitch * .pi / 180))
    }

    // MARK: - Layers and pins

    private func refresh() {
        refreshLayers()
        refreshPins()
    }

    private func refreshLayers() {
        let progressBucket = scene.showsRouteProgress ? Int(scene.progress / 100) : 0
        let signature = "\(scene.route?.id.uuidString ?? "-")|\(progressBucket)|"
            + "\(scene.approach.count)|\(scene.track.count)|\(scene.showsRouteProgress)"
        guard signature != lastLayerSignature else { return }
        lastLayerSignature = signature

        var registered: [(String, [ImmersiveMapPolyline])] = []

        if let route = scene.route, route.points.count > 1 {
            if scene.showsRouteProgress {
                let ribbon = RouteRibbon(route: route, progress: scene.progress)
                let felt = ribbon.travelled.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
                let ahead = ribbon.remaining.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
                if felt.count > 1 {
                    registered.append(("route-travelled", [ImmersiveMapPolyline(coordinates: felt)]))
                }
                var casings: [ImmersiveMapPolyline] = []
                if felt.count > 1 { casings.append(ImmersiveMapPolyline(coordinates: felt)) }
                if ahead.count > 1 { casings.append(ImmersiveMapPolyline(coordinates: ahead)) }
                registered.append(("route-casing", casings))
                let paced = ribbon.remainingSegments
                    .filter { $0.coordinates.count > 1 }
                    .map { segment in
                        ImmersiveMapPolyline(
                            coordinates: segment.coordinates.map {
                                GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                            },
                            style: ImmersiveMapPolylineStyle(color: MapConfig.paceSIMD4(segment.merit),
                                                             widthPoints: 5)
                        )
                    }
                registered.append(("route-remaining", paced))
            } else {
                let line = route.coordinates.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
                registered.append(("route-line", [ImmersiveMapPolyline(coordinates: line)]))
            }
        }

        if scene.approach.count > 1 {
            registered.append(("map-approach", [ImmersiveMapPolyline(
                coordinates: scene.approach.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            )]))
        }
        if scene.track.count > 1 {
            registered.append(("map-track", [ImmersiveMapPolyline(
                coordinates: scene.track.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            )]))
        }

        for (source, polylines) in registered {
            layers.register(source, identity: signature, polylines: polylines)
        }

        var descriptions: [ImmersiveMapLayer] = []
        if scene.route != nil {
            if scene.showsRouteProgress {
                descriptions.append(ImmersiveMapLayer(
                    source: "route-casing",
                    polylineStyle: ImmersiveMapPolylineStyle(
                        color: SIMD4<Float>(0.016, 0.035, 0.051, 1), widthPoints: 9),
                    zoomRange: 0...30))
                descriptions.append(ImmersiveMapLayer(
                    source: "route-travelled",
                    polylineStyle: ImmersiveMapPolylineStyle(
                        color: SIMD4<Float>(0.396, 0.953, 0.875, 0.35), widthPoints: 5),
                    zoomRange: 0...30))
                descriptions.append(ImmersiveMapLayer(
                    source: "route-remaining",
                    polylineStyle: ImmersiveMapPolylineStyle(
                        color: SIMD4<Float>(0.396, 0.953, 0.875, 1), widthPoints: 5),
                    zoomRange: 0...30))
            } else {
                descriptions.append(ImmersiveMapLayer(
                    source: "route-line",
                    polylineStyle: ImmersiveMapPolylineStyle(
                        color: MapConfig.paceSIMD4(0.7), widthPoints: 5),
                    zoomRange: 0...30))
            }
        }
        if scene.approach.count > 1 {
            descriptions.append(ImmersiveMapLayer(
                source: "map-approach",
                polylineStyle: ImmersiveMapPolylineStyle(
                    color: SIMD4<Float>(1.0, 0.72, 0.30, 0.85), widthPoints: 4),
                zoomRange: 0...30))
        }
        if scene.track.count > 1 {
            descriptions.append(ImmersiveMapLayer(
                source: "map-track",
                polylineStyle: ImmersiveMapPolylineStyle(
                    color: SIMD4<Float>(0.22, 0.78, 0.55, 0.85), widthPoints: 5),
                zoomRange: 0...30))
        }
        layers.set(descriptions)
    }

    private func refreshPins() {
        let signature = pinSignature()
        guard signature != lastPinSignature else { return }
        lastPinSignature = signature

        var all: [ImmersiveMapPin] = []
        if let puck = scene.puck {
            all.append(ImmersiveMapPin(id: 1,
                                       coordinate: GeoCoordinate(latitude: puck.latitude,
                                                                 longitude: puck.longitude),
                                       image: MapPinImages.puck))
        }
        if let ghost = scene.ghost {
            all.append(ImmersiveMapPin(id: 2,
                                       coordinate: GeoCoordinate(latitude: ghost.latitude,
                                                                 longitude: ghost.longitude),
                                       image: MapPinImages.ghost))
        }
        for (index, hazard) in scene.hazards.enumerated() {
            all.append(ImmersiveMapPin(id: 10 + UInt64(index),
                                       coordinate: GeoCoordinate(latitude: hazard.latitude,
                                                                 longitude: hazard.longitude),
                                       image: MapPinImages.hazard))
        }
        all.append(contentsOf: scene.pins.map {
            ImmersiveMapPin(id: $0.id,
                            coordinate: GeoCoordinate(latitude: $0.coordinate.latitude,
                                                      longitude: $0.coordinate.longitude),
                            image: $0.image)
        })
        pins.set(all)
    }

    private func pinSignature() -> String {
        func key(_ coordinate: CLLocationCoordinate2D?) -> String {
            guard let coordinate else { return "-" }
            return String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
        }
        var parts = [key(scene.puck), key(scene.ghost), "\(scene.hazards.count)"]
        for hazard in scene.hazards { parts.append(key(hazard)) }
        parts.append(scene.pins.map { "\($0.id)" }.joined(separator: ","))
        return parts.joined(separator: "|")
    }

    private var labelSettings: ImmersiveMapSettings.LabelSettings {
        var labels = ImmersiveMapSettings.default.labels
        labels.base.collisionSpacingPoints = 18
        labels.base.localDetailMaximumDistanceMeters = 260
        labels.landmarks.minimumZoom = 16
        return labels
    }

    private func archiveKey(_ source: MapArchiveSource) -> String {
        switch source {
        case .bundledStarter: "starter"
        case .installedRegion(let id): "region-\(id)"
        case .hosted: "hosted"
        }
    }
}

/// The same renderer under its old name, so references in notes and diagnostics
/// still resolve. New code uses `RevertMapView`.
typealias RideImmersiveMapView = RevertMapView

/// Glyphs are drawn once: pins take a `CGImage`, and every screen should show
/// the same marker for the same thing.
enum MapPinImages {
    static let puck = draw(size: 64) { context in
        let rect = CGRect(x: 6, y: 6, width: 52, height: 52)
        let path = UIBezierPath(ovalIn: rect)
        UIColor(red: 0.396, green: 0.953, blue: 0.875, alpha: 1).setFill()
        path.fill()
        UIColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3
        path.stroke()
        if let arrow = UIImage(systemName: "location.north.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            arrow.draw(in: CGRect(x: 21, y: 19, width: 22, height: 26))
        }
    }

    static let ghost = draw(size: 40) { _ in
        let circle = CGRect(x: 6, y: 6, width: 28, height: 28)
        UIColor(red: 0.85, green: 0.36, blue: 0.85, alpha: 1).setFill()
        UIBezierPath(ovalIn: circle).fill()
        UIColor.white.withAlphaComponent(0.85).setStroke()
        UIBezierPath(ovalIn: circle).stroke()
        if let runner = UIImage(systemName: "figure.run")?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            runner.draw(in: CGRect(x: 12, y: 12, width: 16, height: 16))
        }
    }

    static let hazard = draw(size: 32) { _ in
        let circle = CGRect(x: 3, y: 3, width: 26, height: 26)
        UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1).setFill()
        UIBezierPath(ovalIn: circle).fill()
        if let sign = UIImage(systemName: "exclamationmark.triangle.fill")?
            .withTintColor(.black, renderingMode: .alwaysOriginal) {
            sign.draw(in: CGRect(x: 9, y: 9, width: 14, height: 14))
        }
    }

    private static func draw(size: CGFloat, _ body: (UIGraphicsImageRendererContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image {
            body($0)
        }
        return image.cgImage ?? UIImage(systemName: "circle.fill")!.cgImage!
    }
}
