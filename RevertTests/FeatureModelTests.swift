import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import Revert

@MainActor
struct FeatureModelTests {
    @Test func tripsDaysSegmentsAndSetupNotesRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Trip.self, TripDay.self,
                                           SetupNote.self, SegmentRecord.self,
                                           configurations: config)
        let context = container.mainContext

        let trip = Trip(title: "Alps week", notes: "Two passes")
        context.insert(trip)
        let day = TripDay(order: 0, title: "Day 1", startLabel: "A", endLabel: "B",
                          distanceKm: 180, savedRouteID: UUID())
        day.trip = trip
        context.insert(day)

        let bikeID = UUID()
        let note = SetupNote(bikeID: bikeID, title: "Soft rear",
                             frontPressure: 32, rearPressure: 36, notes: "3 clicks")
        context.insert(note)

        let candidate = SegmentCandidate(id: 0, name: "Segment 1",
                                         coordinates: [CLLocationCoordinate2D(latitude: 37.7, longitude: -122.4),
                                                       CLLocationCoordinate2D(latitude: 37.8, longitude: -122.5)],
                                         lengthMeters: 1_200, cornerCount: 3, bestSpeed: 18)
        let segment = SegmentRecord(rideIDString: "ride-key", candidate: candidate)
        context.insert(segment)
        try context.save()

        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
        #expect(trips.first?.sortedDays.count == 1)
        #expect(trips.first?.notes == "Two passes")

        let notes = try context.fetch(FetchDescriptor<SetupNote>())
        #expect(notes.first?.bikeID == bikeID)
        #expect(notes.first?.frontPressure == 32)

        let segments = try context.fetch(FetchDescriptor<SegmentRecord>())
        #expect(segments.first?.rideIDString == "ride-key")
        #expect(segments.first?.coordinates.count == 2)
    }

    @Test func deletingATripCascadesItsDays() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Trip.self, TripDay.self,
                                           configurations: config)
        let context = container.mainContext
        let trip = Trip(title: "Weekend")
        context.insert(trip)
        let day = TripDay(order: 0, title: "Day 1")
        day.trip = trip
        context.insert(day)
        try context.save()
        context.delete(trip)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TripDay>()).isEmpty)
    }
}
