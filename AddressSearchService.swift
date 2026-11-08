import Foundation
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class AddressSearchService: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    var suggestions: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Include named businesses, parks, viewpoints, and other places in addition to street addresses.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, region: MKCoordinateRegion?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            suggestions = []
            completer.queryFragment = ""
            return
        }

        if let region {
            completer.region = region
        }
        completer.queryFragment = trimmedQuery
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    /// Resolves free-form text (what the rider typed but did not tap in the
    /// suggestion list) into a single map coordinate.
    func coordinate(forQuery query: String, region: MKCoordinateRegion?) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region {
            request.region = region
        }
        let search = MKLocalSearch(request: request)

        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let coordinate = response?.mapItems.first?.location.coordinate,
                      CLLocationCoordinate2DIsValid(coordinate) else {
                    continuation.resume(throwing: AddressSearchError.noResult)
                    return
                }

                continuation.resume(returning: coordinate)
            }
        }
    }

    func coordinate(for suggestion: Suggestion) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let search = MKLocalSearch(request: request)

        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let coordinate = response?.mapItems.first?.location.coordinate,
                      CLLocationCoordinate2DIsValid(coordinate) else {
                    continuation.resume(throwing: AddressSearchError.noResult)
                    return
                }

                continuation.resume(returning: coordinate)
            }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.map {
            Suggestion(
                id: "\($0.title)|\($0.subtitle)",
                title: $0.title,
                subtitle: $0.subtitle,
                completion: $0
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

enum AddressSearchError: LocalizedError {
    case noResult

    var errorDescription: String? {
        switch self {
        case .noResult:
            "That address could not be found. Try a more complete address."
        }
    }
}
