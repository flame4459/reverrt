import Foundation

/// What the rider wants to hear before they set off.
///
/// A profile is a preset over the alert toggles that already exist — it writes
/// the same `@AppStorage` keys the Settings switches use, so the manual switches
/// remain the source of truth and the profile is just a shortcut with a name.
enum RideProfile: String, CaseIterable, Identifiable, Sendable {
    case full
    case camerasOnly
    case quiet
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: "Everything"
        case .camerasOnly: "Cameras only"
        case .quiet: "Quiet"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .full: "Signs, lights, cameras, schools, corners, speed limits and surface."
        case .camerasOnly: "Speed, red-light and plate cameras. No stop signs, lights, schools or corners."
        case .quiet: "Hazards only when they are unavoidable. No spoken road chatter."
        case .custom: "Set by the switches below."
        }
    }

    var symbol: String {
        switch self {
        case .full: "checkmark.shield"
        case .camerasOnly: "camera.fill"
        case .quiet: "speaker.slash"
        case .custom: "slider.horizontal.3"
        }
    }

    /// The keys a profile owns. Everything else is left alone.
    static let keys = [
        "alert.stop", "alert.signal", "alert.rail", "alert.school", "alert.roundabout",
        "alert.speedCameras", "alert.redLightCameras", "alert.plateCameras",
        "alert.curves", "alert.overLimit", "alert.surface", "alert.userMark"
    ]

    func values() -> [String: Bool] {
        switch self {
        case .full:
            return ["alert.stop": true, "alert.signal": true, "alert.rail": true,
                    "alert.school": true, "alert.roundabout": true,
                    "alert.speedCameras": true, "alert.redLightCameras": true,
                    "alert.plateCameras": true, "alert.curves": true,
                    "alert.overLimit": true, "alert.surface": true, "alert.userMark": true]
        case .camerasOnly:
            return ["alert.stop": false, "alert.signal": false, "alert.rail": false,
                    "alert.school": false, "alert.roundabout": false,
                    "alert.speedCameras": true, "alert.redLightCameras": true,
                    "alert.plateCameras": true, "alert.curves": false,
                    "alert.overLimit": true, "alert.surface": false, "alert.userMark": true]
        case .quiet:
            return ["alert.stop": false, "alert.signal": false, "alert.rail": true,
                    "alert.school": false, "alert.roundabout": false,
                    "alert.speedCameras": false, "alert.redLightCameras": false,
                    "alert.plateCameras": false, "alert.curves": false,
                    "alert.overLimit": false, "alert.surface": false, "alert.userMark": true]
        case .custom:
            return [:]
        }
    }

    /// Apply the preset. `custom` writes nothing; it exists so the picker can
    /// show that the switches no longer match a preset.
    func apply(to defaults: UserDefaults = .standard) {
        for (key, value) in values() {
            defaults.set(value, forKey: key)
        }
        if self != .custom {
            defaults.set(rawValue, forKey: "alert.profile")
        }
    }

    /// The preset the current switches correspond to, if any.
    static func matching(_ defaults: UserDefaults = .standard) -> RideProfile {
        for profile in [RideProfile.full, .camerasOnly, .quiet] {
            let values = profile.values()
            let matches = values.allSatisfy { key, value in
                let stored = defaults.object(forKey: key) as? Bool
                return (stored ?? true) == value
            }
            if matches { return profile }
        }
        return .custom
    }
}
