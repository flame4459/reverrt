import Testing
import Foundation
@testable import Revert

@MainActor
struct UnitPreferenceTests {
    private func clean() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Units.systemKey)
        defaults.removeObject(forKey: Units.metricKey)
    }

    @Test func explicitPreferencesWin() {
        clean()
        defer { clean() }
        Units.setPreference(.metric)
        #expect(Units.isMetric)
        #expect(Units.preference == .metric)
        Units.setPreference(.imperial)
        #expect(!Units.isMetric)
        #expect(Units.preference == .imperial)
    }

    @Test func automaticFollowsRegion() {
        clean()
        defer { clean() }
        Units.setPreference(.automatic)
        #expect(Units.preference == .automatic)
        #expect(Units.isMetric == Units.autoIsMetric)
        #expect(Units.effectiveDescription.contains("Automatic"))
    }

    @Test func legacyToggleStillWorks() {
        clean()
        defer { clean() }
        UserDefaults.standard.set(true, forKey: Units.metricKey)
        #expect(Units.preference == .metric)
        #expect(Units.isMetric)
        UserDefaults.standard.set(false, forKey: Units.metricKey)
        #expect(Units.preference == .imperial)
        #expect(!Units.isMetric)
    }

    @Test func legacyMigratesToExplicitChoiceOnce() {
        clean()
        defer { clean() }
        UserDefaults.standard.set(true, forKey: Units.metricKey)
        Units.migrateLegacyPreferenceIfNeeded()
        #expect(UserDefaults.standard.string(forKey: Units.systemKey) == "metric")
        #expect(Units.preference == .metric)
        Units.setPreference(.automatic)
        #expect(UserDefaults.standard.string(forKey: Units.systemKey) == "automatic")
        #expect(UserDefaults.standard.object(forKey: Units.metricKey) == nil)
    }
}
