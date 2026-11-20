import SwiftUI
import UIKit
import CoreLocation
import ImmersiveMap

/// The vector/PMTiles ride renderer. The camera is fed by RideCameraDriver;
/// the route and rider are ImmersiveMap layers so they can be styled and
/// updated without rebuilding the map view.
struct RideImmersiveMapView: View {
    let route: PlannedRoute?
    let progress: Double
    let cameraFrame: RideCameraFrame?
    let puck: CLLocationCoordinate2D?
    /// Optional: when present the camera is driven straight from the display
    /// link, without a SwiftUI body re-evaluation per frame.
    var driver: RideCameraDriver? = nil

    @State private var camera = ImmersiveMapCameraController()
    @State private var layers = ImmersiveMapLayersController()
    @State private var pins = ImmersiveMapPinsController()
    @State private var frameStats = MapFrameStats()
    @State private var puckPinSet = false
    @State private var lastRouteIdentity = ""
    @State private var registeredPuck = false
    @State private var lastRiderKey = ""
    @State private var frameObserver: UUID?

    var body: some View {
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
                // POI plates are the loudest thing on a moving map and they
                // have nothing to do with the route.
                theme.labelOpacity.pois = 0
            })
            .labelSettings(labelSettings)
            // Navigation view: no relief, trees, shadows, atmosphere or globe.
            // Nothing below zoom 10 needs them, and they are the GPU budget.
            .trees(isEnabled: false)
            .shadows(isEnabled: false)
            .atmosphere(isEnabled: false)
            .globe(isEnabled: false)
            .renderLoopSettings(.init(forceContinuousRendering: false,
                                      interactionFramesPerSecond: 120,
                                      labelFadeFramesPerSecond: 60))
            .tileArchive(Self.preferredTileArchive)
            .onFrameRendered { frame in
                frameStats.record(frame)
            }
            .overlay(alignment: .topTrailing) {
                if CommandLine.arguments.contains("-debugFrameHUD") {
                    MapFrameHUD(stats: frameStats)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            .onAppear {
                refreshLayers()
                updatePuckPin()
                if frameObserver == nil, let driver {
                    frameObserver = driver.addFrameObserver { frame in
                        camera.jump(to: position(for: frame))
                    }
                }
            }
            .onDisappear {
                if let frameObserver {
                    driver?.removeFrameObserver(frameObserver)
                    self.frameObserver = nil
                }
            }
            .onChange(of: route?.id) { _, _ in
                lastRouteIdentity = ""
                registeredPuck = false
                puckPinSet = false
                refreshLayers()
                updatePuckPin()
            }
            .onChange(of: progress) { _, _ in refreshLayers() }
            .onChange(of: puck?.latitude) { _, _ in updatePuckPin() }
            .onChange(of: puck?.longitude) { _, _ in updatePuckPin() }
    }

    private static var loggedUnusableArchive = false

    /// Prefer a validated local archive, then the downloaded one. A truncated
    /// file is skipped rather than shown as an empty map.
    private static var preferredTileArchive: URL {
        let candidates = [
            Bundle.main.url(forResource: "region", withExtension: "pmtiles"),
            ImmersiveMapTilesService.tileArchiveURL
        ].compactMap { $0 }
        for url in candidates where TileArchiveValidator.isUsable(url) {
            return url
        }
        if let first = candidates.first, !Self.loggedUnusableArchive {
            Self.loggedUnusableArchive = true
            RevertDiagnostics.log("tile archive unusable: \(first.lastPathComponent)")
        }
        return ImmersiveMapTilesService.tileArchiveURL
    }

    private var labelSettings: ImmersiveMapSettings.LabelSettings {
        var labels = ImmersiveMapSettings.default.labels
        labels.base.collisionSpacingPoints = 18
        labels.base.localDetailMaximumDistanceMeters = 260
        labels.landmarks.minimumZoom = 16
        return labels
    }

    private var initialCamera: ImmersiveMapCameraPosition {
        if let frame = cameraFrame { return position(for: frame) }
        if let coordinate = route?.points.first?.coordinate {
            return ImmersiveMapCameraPosition(latitudeDegrees: coordinate.latitude,
                                              longitudeDegrees: coordinate.longitude,
                                              zoom: 14, bearing: 0, pitch: 0)
        }
        // Never teleport to a hard-coded city. A rider who changes camera mode
        // sees the map they were looking at; only a cold map with no position at
        // all falls back to the package default.
        if let location = LocationHub.shared.lastLocation?.coordinate {
            return ImmersiveMapCameraPosition(latitudeDegrees: location.latitude,
                                              longitudeDegrees: location.longitude,
                                              zoom: 14, bearing: 0, pitch: 0)
        }
        return .city(.sanFrancisco)
    }

    private func position(for frame: RideCameraFrame) -> ImmersiveMapCameraPosition {
        // MapKit's metres-to-camera and ImmersiveMap's zoom are different
        // scales. This approximates the same field of view and keeps the
        // engine's pitch preserved in radians.
        let zoom = min(max(17.8 - log2(max(frame.distance, 80) / 220), 10), 19)
        return ImmersiveMapCameraPosition(
            latitudeDegrees: frame.latitude,
            longitudeDegrees: frame.longitude,
            zoom: zoom,
            bearing: Float(frame.heading * .pi / 180),
            pitch: Float(frame.pitch * .pi / 180)
        )
    }

    private func refreshLayers() {
        guard let route, route.points.count > 1 else {
            layers.set([])
            return
        }
        let ribbon = RouteRibbon(route: route, progress: progress)
        let progressBucket = Int(progress / 100)
        let identity = "\(route.id.uuidString)-\(progressBucket)"
        if lastRouteIdentity != identity {
            lastRouteIdentity = identity
            let felt = ribbon.travelled.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            let ahead = ribbon.remaining.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            layers.register("ride-travelled", identity: identity,
                            polylines: felt.count > 1 ? [ImmersiveMapPolyline(coordinates: felt)] : [])
            var casings: [ImmersiveMapPolyline] = []
            if felt.count > 1 { casings.append(ImmersiveMapPolyline(coordinates: felt)) }
            if ahead.count > 1 { casings.append(ImmersiveMapPolyline(coordinates: ahead)) }
            layers.register("ride-casing", identity: identity, polylines: casings)
            let paced = ribbon.remainingSegments
                .filter { $0.coordinates.count > 1 }
                .map { segment in
                    return ImmersiveMapPolyline(
                        coordinates: segment.coordinates.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
                        style: ImmersiveMapPolylineStyle(color: MapConfig.paceSIMD4(segment.merit), widthPoints: 5)
                    )
                }
            layers.register("ride-remaining", identity: identity, polylines: paced)
            layers.set([
                ImmersiveMapLayer(source: "ride-casing",
                                  polylineStyle: ImmersiveMapPolylineStyle(
                                    color: SIMD4<Float>(0.016, 0.035, 0.051, 1),
                                    widthPoints: 9
                                  ),
                                  zoomRange: 0...30),
                ImmersiveMapLayer(source: "ride-travelled",
                                  polylineStyle: ImmersiveMapPolylineStyle(
                                    color: SIMD4<Float>(0.396, 0.953, 0.875, 0.35),
                                    widthPoints: 5
                                  ),
                                  zoomRange: 0...30),
                ImmersiveMapLayer(source: "ride-remaining",
                                  polylineStyle: ImmersiveMapPolylineStyle(
                                    color: SIMD4<Float>(0.396, 0.953, 0.875, 1),
                                    widthPoints: 5
                                  ),
                                  zoomRange: 0...30)
            ])
        }
    }

    private func updatePuckPin() {
        guard let puck else { return }
        let coordinate = GeoCoordinate(latitude: puck.latitude, longitude: puck.longitude)
        if puckPinSet {
            pins.move(id: 1, to: coordinate)
        } else {
            pins.set([ImmersiveMapPin(id: 1, coordinate: coordinate, image: Self.puckImage)])
            puckPinSet = true
        }
    }

    private static let puckImage: CGImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { _ in
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
        return image.cgImage!
    }()
}
