import Foundation
import CoreLocation
import MapKit
import UIKit

/// Draws the map card the Live Activity shows on the Watch Smart Stack and on
/// car dashboards that display iPhone widgets.
///
/// A Live Activity cannot host a live map view, but it can host an image. So the
/// app renders a heading-up slice of the route around the rider and hands the
/// file to the extension through the app group; only the file name travels in
/// the activity state.
@MainActor
enum LiveActivityMap {
    private static let maxFiles = 3

    static func render(rider: CLLocation,
                       course: Double,
                       route: [CLLocationCoordinate2D],
                       nextManeuver: CLLocationCoordinate2D?,
                       size: CGSize = CGSize(width: 320, height: 176)) async -> String? {
        guard let image = await makeImage(rider: rider, course: course, route: route,
                                          nextManeuver: nextManeuver, size: size) else { return nil }
        return write(image, prefix: "map")
    }

    /// North-up overview of the whole route. Rendered once per ride: the widget
    /// strip shows it when the live card is not in front.
    static func renderOverview(route: [CLLocationCoordinate2D],
                               size: CGSize = CGSize(width: 320, height: 240)) async -> String? {
        guard let image = await makeOverviewImage(route: route, size: size) else { return nil }
        return write(image, prefix: "overview")
    }

    static func makeOverviewImage(route: [CLLocationCoordinate2D],
                                  size: CGSize = CGSize(width: 320, height: 240)) async -> UIImage? {
        guard route.count > 1 else { return nil }
        let lats = route.map(\.latitude)
        let lons = route.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let centre = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let latMetres = (maxLat - minLat) * 111_000
        let lonMetres = (maxLon - minLon) * 111_000 * max(cos(centre.latitude * .pi / 180), 0.2)
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(lookingAtCenter: centre,
                                     fromDistance: max(latMetres, lonMetres) * 1.35 + 900,
                                     pitch: 0, heading: 0)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await start(options) else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            drawRoute(route, snapshot: snapshot, size: size)
            if let first = route.first { drawMarker(first, snapshot: snapshot, size: size) }
        }
        return image
    }

    /// True when the image is essentially one colour: a tile-less snapshot.
    private static func isBlank(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        let width = 24, height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var colours = Set<UInt32>()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = UInt32(pixels[index] >> 3)
            let green = UInt32(pixels[index + 1] >> 3)
            let blue = UInt32(pixels[index + 2] >> 3)
            colours.insert(red << 10 | green << 5 | blue)
        }
        return colours.count < 6
    }

    private static func write(_ image: UIImage, prefix: String) -> String? {
        guard let folder = LiveMapImage.folderURL() else {
            RevertDiagnostics.log("mapcard: app group unavailable")
            return nil
        }
        guard let data = image.pngData() else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1_000)).png"
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        prune(folder)
        return name
    }

    /// The drawing half, separated so it can be rendered without an app group
    /// (simulator builds without entitlements cannot reach the shared folder).
    static func makeImage(rider: CLLocation,
                          course: Double,
                          route: [CLLocationCoordinate2D],
                          nextManeuver: CLLocationCoordinate2D?,
                          size: CGSize = CGSize(width: 320, height: 176)) async -> UIImage? {
        // Within a turn's approach the card becomes a close-up of the junction,
        // looking along the rider's line to it. Further out it is a speed-scaled
        // view ahead: tight in town, wide at motorway speed.
        let approachDistance: Double? = nextManeuver.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: rider)
        }
        let approaching = (approachDistance ?? .infinity) <= 320 ? nextManeuver : nil
        let heading: Double
        let centre: CLLocationCoordinate2D
        let fromDistance: CLLocationDistance
        if let approaching, let metres = approachDistance {
            heading = Geo.bearing(from: rider.coordinate, to: approaching)
            // Bias towards the junction, not onto it: centring the turn pushes
            // the rider off the bottom of the card just when they need both.
            let bias = 0.6
            centre = CLLocationCoordinate2D(
                latitude: rider.coordinate.latitude + (approaching.latitude - rider.coordinate.latitude) * bias,
                longitude: rider.coordinate.longitude + (approaching.longitude - rider.coordinate.longitude) * bias
            )
            fromDistance = min(max(metres * 2.2 + 160, 300), 900)
        } else {
            heading = course >= 0 ? course : (rider.course >= 0 ? rider.course : 0)
            // The rider sits low in the frame, as in a nav app.
            centre = ahead(rider.coordinate, metres: 120, bearing: heading)
            fromDistance = min(max(240 + max(rider.speed, 0) * 12, 320), 1_100)
        }

        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(lookingAtCenter: centre, fromDistance: fromDistance, pitch: 0, heading: heading)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await start(options)
        } catch {
            RevertDiagnostics.log("mapcard render failed: \(error.localizedDescription)")
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            drawRoute(route, snapshot: snapshot, size: size)
            if let nextManeuver { drawMarker(nextManeuver, snapshot: snapshot, size: size) }
            drawRider(rider.coordinate, heading: heading, snapshot: snapshot)
        }
        // A snapshot taken with no tiles available comes back as flat grey.
        // Publishing it puts a grey rectangle on the car screen; better to fall
        // back to the text card until there is a map to show.
        if isBlank(image) {
            RevertDiagnostics.log("mapcard blank snapshot discarded")
            return nil
        }
        return image
    }

    private static func start(_ options: MKMapSnapshotter.Options) async throws -> MKMapSnapshotter.Snapshot {
        try await withCheckedThrowingContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, error in
                if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: error ?? URLError(.unknown))
                }
            }
        }
    }

    private static func drawRoute(_ coordinates: [CLLocationCoordinate2D],
                                  snapshot: MKMapSnapshotter.Snapshot,
                                  size: CGSize) {
        guard coordinates.count > 1 else { return }
        let path = UIBezierPath()
        var started = false
        for coordinate in coordinates {
            let point = snapshot.point(for: coordinate)
            guard point.x.isFinite, point.y.isFinite else { continue }
            // Points far outside the frame break the line rather than dragging
            // it across the card from a corner.
            guard point.x > -240, point.x < size.width + 240,
                  point.y > -240, point.y < size.height + 240 else {
                started = false
                continue
            }
            if started { path.addLine(to: point) } else { path.move(to: point); started = true }
        }
        guard !path.isEmpty else { return }
        UIColor(red: 0.15, green: 0.9, blue: 1.0, alpha: 1).setStroke()
        path.lineWidth = 6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawMarker(_ coordinate: CLLocationCoordinate2D,
                                   snapshot: MKMapSnapshotter.Snapshot,
                                   size: CGSize) {
        let point = snapshot.point(for: coordinate)
        guard point.x.isFinite, point.y.isFinite,
              point.x > -20, point.x < size.width + 20,
              point.y > -20, point.y < size.height + 20 else { return }
        let rect = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
        let dot = UIBezierPath(ovalIn: rect)
        UIColor.white.setFill()
        dot.fill()
        UIColor.black.withAlphaComponent(0.35).setStroke()
        dot.lineWidth = 2.5
        dot.stroke()
    }

    private static func drawRider(_ coordinate: CLLocationCoordinate2D,
                                  heading: Double,
                                  snapshot: MKMapSnapshotter.Snapshot) {
        let point = snapshot.point(for: coordinate)
        guard point.x.isFinite, point.y.isFinite else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: CGFloat(heading * .pi / 180))

        // Heading wedge, so the card reads as heading-up at a glance.
        let wedge = UIBezierPath()
        wedge.move(to: CGPoint(x: 0, y: -17))
        wedge.addLine(to: CGPoint(x: 9, y: 6))
        wedge.addLine(to: CGPoint(x: 0, y: 2))
        wedge.addLine(to: CGPoint(x: -9, y: 6))
        wedge.close()
        UIColor(red: 0.15, green: 0.9, blue: 1.0, alpha: 1).setFill()
        wedge.fill()

        let dot = UIBezierPath(ovalIn: CGRect(x: -5, y: -5, width: 10, height: 10))
        UIColor.white.setFill()
        dot.fill()
        UIColor.black.withAlphaComponent(0.4).setStroke()
        dot.lineWidth = 2
        dot.stroke()

        context.restoreGState()
    }

    private static func ahead(_ origin: CLLocationCoordinate2D,
                              metres: Double,
                              bearing: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let dLat = metres / 111_000 * cos(radians)
        let dLon = metres / (111_000 * max(cos(origin.latitude * .pi / 180), 0.2)) * sin(radians)
        return CLLocationCoordinate2D(latitude: origin.latitude + dLat,
                                      longitude: origin.longitude + dLon)
    }

    private static func prune(_ folder: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder,
                                                                     includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        let sorted = urls.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for url in sorted.dropFirst(maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
