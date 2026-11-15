import MapKit

/// iOS 26 replaced `MKMapItem(placemark:)` with `MKMapItem(location:address:)`
/// and introduced `location` and `addressRepresentations`. The app supports
/// iOS 17.4 and later, so these helpers keep the modern calls on iOS 26 and
/// fall back to the placemark API below it.
nonisolated extension MKMapItem {
    /// A bare map item for a coordinate, used for routing requests.
    static func revert(location: CLLocation) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(location: location, address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
    }

    /// The coordinate of this item, without the iOS 26-only `location`.
    var revertLocation: CLLocation {
        if #available(iOS 26.0, *) {
            return location
        }
        let coordinate = placemark.coordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// One-line address for lists and CarPlay search rows.
    var revertAddressLine: String {
        if #available(iOS 26.0, *) {
            if let text = addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) {
                return text
            }
            if let text = address?.fullAddress { return text }
        }
        return placemark.title ?? ""
    }
}
