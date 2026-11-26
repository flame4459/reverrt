import CoreLocation
import Foundation
import ImmersiveMap

/// Fits a set of coordinates into a map viewport with a real Mercator
/// projection, rather than guessing a zoom from a distance.
nonisolated enum RevertMapFit {
    /// The engine's tile size in points at zoom 0. ImmersiveMap uses 512-point
    /// tiles; assuming 256 put every fitted camera one zoom level too close.
    static let tileSize: Double = 512
    /// The hosted archive ships z0–z15; deeper zooms have no tiles.
    static let archiveMaxZoom: Double = 15
    static let worldMaxLatitude: Double = 85.051_128_78

    struct Result: Equatable {
        let latitude: Double
        let longitude: Double
        let zoom: Double

        var position: ImmersiveMapCameraPosition {
            ImmersiveMapCameraPosition(latitudeDegrees: latitude,
                                       longitudeDegrees: longitude,
                                       zoom: zoom, bearing: 0, pitch: 0)
        }
    }

    /// All coordinates inside `viewport`, with `padding` points of margin.
    ///
    /// - Returns: `nil` when there is nothing to frame or the viewport is too
    ///   small to hold the padding.
    static func fit(_ coordinates: [CLLocationCoordinate2D],
                    viewport: CGSize,
                    padding: CGFloat = 24,
                    minZoom: Double = 4,
                    maxZoom: Double = archiveMaxZoom) -> Result? {
        let valid = coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite
                && abs($0.latitude) <= worldMaxLatitude
                && abs($0.longitude) <= 180
        }
        guard !valid.isEmpty else { return nil }

        let usableWidth = Double(viewport.width) - 2 * Double(padding)
        let usableHeight = Double(viewport.height) - 2 * Double(padding)
        guard usableWidth > 1, usableHeight > 1 else { return nil }

        let latitudes = valid.map(\.latitude)
        var longitudes = valid.map(\.longitude)

        // A route that crosses the antimeridian has a longitude span over 180°.
        // Frame it by shifting its western half into 0…360, then wrap the
        // centre back.
        if (longitudes.max()! - longitudes.min()!) > 180 {
            longitudes = longitudes.map { $0 < 0 ? $0 + 360 : $0 }
        }
        let minLat = latitudes.min()!
        let maxLat = latitudes.max()!
        let minLon = longitudes.min()!
        let maxLon = longitudes.max()!
        let lonSpan = maxLon - minLon
        let rawCenterLon = (minLon + maxLon) / 2
        let centerLon = normalizedLongitude(rawCenterLon)

        let yMin = mercatorY(minLat)
        let yMax = mercatorY(maxLat)
        let ySpan = abs(yMax - yMin)

        var zoom = maxZoom
        if lonSpan > 1e-9 {
            zoom = min(zoom, log2(usableWidth * 360 / (tileSize * lonSpan)))
        }
        if ySpan > 1e-9 {
            zoom = min(zoom, log2(usableHeight / (tileSize * ySpan)))
        }
        if !zoom.isFinite { zoom = minZoom }

        return Result(latitude: (minLat + maxLat) / 2,
                      longitude: centerLon,
                      zoom: min(max(zoom, minZoom), maxZoom))
    }

    /// Web Mercator's normalized y, 0 at the north edge and 1 at the south.
    static func mercatorY(_ latitude: Double) -> Double {
        let radians = max(min(latitude, worldMaxLatitude), -worldMaxLatitude) * .pi / 180
        let y = log(tan(radians) + 1 / cos(radians)) / .pi
        return (1 - y) / 2
    }

    static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}
