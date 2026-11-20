import Testing
import Foundation
@testable import Revert

@MainActor
struct WidgetSnapshotTests {
    @Test func snapshotCarriesTheCurrentSchema() throws {
        let snapshot = CarWidgetSnapshot(mode: .driving)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CarWidgetSnapshot.self, from: data)
        #expect(decoded.schema == CarWidgetSnapshot.currentSchema)
    }

    @Test func aPayloadWrittenBeforeTheSchemaStillDecodes() throws {
        // Older builds wrote the same struct without `schema`. Losing the whole
        // cockpit card because of a missing key would be worse than ignoring it.
        let data = try JSONEncoder().encode(CarWidgetSnapshot(mode: .driving))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "schema")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CarWidgetSnapshot.self, from: legacy)
        #expect(decoded.schema == nil)
        #expect(decoded.mode == .driving)
    }
}
