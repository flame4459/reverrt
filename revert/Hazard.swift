import Foundation
import CoreLocation

enum HazardKind: String, Codable, CaseIterable {
    case stop, signal, speedCamera, redLightCamera, alertCamera, railCrossing, school, roundabout, userMark

    var title: String {
        switch self {
        case .stop: "STOP SIGN"
        case .signal: "TRAFFIC LIGHT"
        case .speedCamera: "SPEED CAMERA"
        case .redLightCamera: "RED LIGHT CAMERA"
        case .alertCamera: "PLATE CAMERA"
        case .railCrossing: "RAIL CROSSING"
        case .school: "SCHOOL ZONE"
        case .roundabout: "ROUNDABOUT"
        case .userMark: "RIDER MARK"
        }
    }

    /// Short noun for spoken warnings, e.g. "Stop sign in 300 feet".
    var approachName: String {
        switch self {
        case .stop: "Stop sign"
        case .signal: "Traffic light"
        case .speedCamera: "Speed camera"
        case .redLightCamera: "Red light camera"
        case .alertCamera: "License plate camera"
        case .railCrossing: "Railroad crossing"
        case .school: "School zone"
        case .roundabout: "Roundabout"
        case .userMark: "Rider mark"
        }
    }

    var symbol: String {
        switch self {
        case .stop: "octagon.fill"
        case .signal: "trafficlight"
        case .speedCamera, .redLightCamera: "camera.fill"
        case .alertCamera: "video.fill"
        case .railCrossing: "tram.fill"
        case .school: "figure.and.child.holdinghands"
        case .roundabout: "arrow.triangle.2.circlepath"
        case .userMark: "exclamationmark.triangle.fill"
        }
    }

    /// UserDefaults key for the on/off toggle in Settings
    var settingsKey: String {
        switch self {
        case .stop: "alert.stop"
        case .signal: "alert.signal"
        case .speedCamera: "alert.speedCameras"
        case .redLightCamera: "alert.redLightCameras"
        case .alertCamera: "alert.plateCameras"
        case .railCrossing: "alert.rail"
        case .school: "alert.school"
        case .roundabout: "alert.roundabout"
        case .userMark: "alert.userMark"
        }
    }

    /// Sideways tolerance, in metres, for the alert engine's corridor
    /// projection. The one place these numbers live; AlertManager reads them.
    var lateralTolerance: Double {
        switch self {
        case .school: 45       // schools sit back from the road
        case .roundabout: 30
        case .userMark: 22
        case .alertCamera: 16
        default: 14
        }
    }
    var maxLookahead: Double {
        switch self {
        case .school: 250
        case .userMark: 350
        case .alertCamera: 460
        default: 450
        }
    }

    /// Scales the speed-banded warning distance. Cameras want a little more
    /// notice than a stop sign; schools sit back from the road and get it late.
    var warningFactor: Double {
        switch self {
        case .school: 0.7
        case .roundabout: 0.85
        case .alertCamera: 1.1
        default: 1
        }
    }
    /// Seconds before the same kind can alert again (stops repeats on multi-part features)
    var kindCooldown: Double { self == .userMark ? 30 : ((self == .school || self == .roundabout) ? 25 : 0) }
}

nonisolated struct Hazard: Codable, Hashable, Identifiable, Sendable {
    let id: Int64          // OpenStreetMap id (ways are negative so they never collide with nodes)
    let kind: HazardKind
    let lat: Double
    let lon: Double
    /// OSM `direction` / `camera:direction`: the bearing the device looks
    /// along, degrees clockwise from north. Nil when the map does not say.
    var direction: Int? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    /// A camera tagged for the opposite carriageway should not fire. When the
    /// rider is travelling more than 90° away from the tagged bearing, this is
    /// the other direction's device (or a perpendicular one), not theirs.
    func facesAway(from bearing: Double?) -> Bool {
        guard let direction, let bearing else { return false }
        return abs(RouteGeometry.angleDelta(bearing, Double(direction))) > 90
    }
}

enum AlertSettings {
    /// Camera alerts used to share one `alert.cameras` switch. The three split
    /// keys fall back to it so an existing rider keeps their choice.
    static func enabled(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: key) as? Bool { return value }
        if key == "alert.speedCameras" || key == "alert.redLightCameras" || key == "alert.plateCameras" {
            if let legacy = defaults.object(forKey: "alert.cameras") as? Bool { return legacy }
        }
        return true
    }
}
