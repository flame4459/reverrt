import CoreLocation

enum SavedPlace: String, CaseIterable, Identifiable {
    case home
    case work

    var id: String { rawValue }
    var title: String { self == .home ? "Home" : "Work" }
    var icon: String { self == .home ? "house.fill" : "briefcase.fill" }
}

struct RecentDestination: Codable, Identifiable, Equatable {
    let title: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(title)|\(latitude)|\(longitude)" }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum CentralMenuDestination: String, Identifiable {
    case plan
    case history
    case settings
    case offline
    case savedPlaces

    var id: String { rawValue }
}

