import Testing
import Foundation
import CoreLocation
@testable import Revert

@MainActor
struct UserMarksTests {
    @Test func duplicateReportsCollapseIntoOne() {
        let store = UserMarksStore.shared
        let saved = store.hazards
        defer {
            store.clear()
            for mark in saved {
                store.addHazard(kind: mark.kind, coordinate: mark.coordinate, road: mark.road)
            }
        }
        store.clear()

        let base = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.5)
        store.addHazard(kind: "pothole", coordinate: base, road: nil)
        // Same kind, ~11 m away: one hazard, not two alerts.
        store.addHazard(kind: "pothole",
                        coordinate: CLLocationCoordinate2D(latitude: 40.7001, longitude: -73.5),
                        road: nil)
        #expect(store.hazards.count == 1)

        // A different kind at the same place is still its own hazard.
        store.addHazard(kind: "gravel", coordinate: base, road: nil)
        #expect(store.hazards.count == 2)

        // A kilometre away is a different pothole.
        store.addHazard(kind: "pothole",
                        coordinate: CLLocationCoordinate2D(latitude: 40.71, longitude: -73.5),
                        road: nil)
        #expect(store.hazards.count == 3)
    }

    @Test func riderMarksExpireAfterNinetyDays() {
        let fresh = UserHazard(id: UUID(), kind: "pothole", lat: 40.7, lon: -73.5,
                               createdAt: Date(), road: nil)
        let old = UserHazard(id: UUID(), kind: "pothole", lat: 40.7, lon: -73.5,
                             createdAt: Date().addingTimeInterval(-91 * 86_400), road: nil)
        #expect(!UserMarksStore.isExpired(fresh))
        #expect(UserMarksStore.isExpired(old))
    }
}
