import Foundation
import CoreLocation

enum HazardKind: String, Codable, CaseIterable {
    case stop, signal, speedCamera, redLightCamera, railCrossing, school, roundabout

    var title: String {
        switch self {
        case .stop: "STOP SIGN"
        case .signal: "TRAFFIC LIGHT"
        case .speedCamera: "SPEED CAMERA"
        case .redLightCamera: "RED LIGHT CAMERA"
        case .railCrossing: "RAIL CROSSING"
        case .school: "SCHOOL ZONE"
        case .roundabout: "ROUNDABOUT"
        }
    }

    /// Short noun for spoken warnings, e.g. "Stop sign in 300 feet".
    var approachName: String {
        switch self {
        case .stop: "Stop sign"
        case .signal: "Traffic light"
        case .speedCamera: "Speed camera"
        case .redLightCamera: "Red light camera"
        case .railCrossing: "Railroad crossing"
        case .school: "School zone"
        case .roundabout: "Roundabout"
        }
    }

    var symbol: String {
        switch self {
        case .stop: "octagon.fill"
        case .signal: "trafficlight"
        case .speedCamera, .redLightCamera: "camera.fill"
        case .railCrossing: "tram.fill"
        case .school: "figure.and.child.holdinghands"
        case .roundabout: "arrow.triangle.2.circlepath"
        }
    }

    /// UserDefaults key for the on/off toggle in Settings
    var settingsKey: String {
        switch self {
        case .stop: "alert.stop"
        case .signal: "alert.signal"
        case .speedCamera, .redLightCamera: "alert.cameras"
        case .railCrossing: "alert.rail"
        case .school: "alert.school"
        case .roundabout: "alert.roundabout"
        }
    }

    /// Sideways tolerance, in metres, for the alert engine's corridor
    /// projection. The one place these numbers live; AlertManager reads them.
    var lateralTolerance: Double {
        switch self {
        case .school: 45       // schools sit back from the road
        case .roundabout: 30
        default: 14
        }
    }
    var maxLookahead: Double { self == .school ? 250 : 450 }
    /// Seconds before the same kind can alert again (stops repeats on multi-part features)
    var kindCooldown: Double { (self == .school || self == .roundabout) ? 25 : 0 }
}

nonisolated struct Hazard: Codable, Hashable, Identifiable, Sendable {
    let id: Int64          // OpenStreetMap id (ways are negative so they never collide with nodes)
    let kind: HazardKind
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

enum AlertSettings {
    static func enabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
