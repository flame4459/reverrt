import Testing
import Foundation
import CoreLocation
import SwiftData
#if canImport(CarPlay)
import CarPlay
#endif
@testable import Revert

@MainActor
struct CarPlayTests {
    // MARK: Helpers

    private static func route(name: String? = "Test loop",
                              kind: RouteKind = .loop,
                              twist: Double = 90) -> PlannedRoute {
        let points = (0..<8).map { index in
            RoutePoint(lat: 37.0 + Double(index) * 0.002, lon: -122.0, road: 1)
        }
        return PlannedRoute(points: points, roads: [:], twistPerKm: twist,
                            retraced: 0, bearing: 0, displayName: name, kind: kind)
    }

    // MARK: Text

    @Test func etaTextCoversEveryGlanceableRange() {
        #expect(CarPlayText.etaText(nil) == "—")
        #expect(CarPlayText.etaText(-1) == "—")
        #expect(CarPlayText.etaText(30) == "<1 min")
        #expect(CarPlayText.etaText(60) == "1 min")
        #expect(CarPlayText.etaText(900) == "15 min")
        #expect(CarPlayText.etaText(3_600) == "1 hr")
        #expect(CarPlayText.etaText(3_900) == "1 hr 5 min")
        #expect(CarPlayText.etaText(5_399) == "1 hr 30 min")
    }

    @Test func rideTitlesFallBackForUnnamedRoutes() {
        #expect(CarPlayText.rideTitle(Self.route(name: "Canyon run")) == "Canyon run")
        #expect(CarPlayText.rideTitle(Self.route(name: "   ")) == "Scenic loop")
        #expect(CarPlayText.rideTitle(Self.route(name: nil, kind: .directions)) == "Route")
    }

    @Test func rideDetailMentionsDistanceAndTwistForLoops() {
        let detail = CarPlayText.rideDetail(Self.route(name: "Loop", twist: 80))
        #expect(detail.contains("3/5 twist"))
        #expect(detail.contains("mi") || detail.contains("km"))
    }

    // MARK: Destinations

    @Test func recentsDecodeFromTheSameJSONThePhoneWrites() throws {
        let recents = [
            RecentDestination(title: "Coffee", latitude: 37.2, longitude: -122.2),
            RecentDestination(title: "Shop", latitude: 37.3, longitude: -122.3)
        ]
        let json = String(data: try JSONEncoder().encode(recents), encoding: .utf8) ?? ""
        #expect(CarPlayDestinations.recents(fromJSON: json).map(\.title) == ["Coffee", "Shop"])
        #expect(CarPlayDestinations.recents(fromJSON: "not json").isEmpty)
        #expect(CarPlayDestinations.recents(fromJSON: "").isEmpty)
    }

    @Test func placesPutHomeAndWorkBeforeRecentsAndDeduplicate() {
        let suite = "CarPlayTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(37.1, forKey: "saved.home.lat")
        defaults.set(-122.1, forKey: "saved.home.lon")
        defaults.set(37.2, forKey: "saved.work.lat")
        defaults.set(-122.2, forKey: "saved.work.lon")

        let recents = [
            RecentDestination(title: "Home", latitude: 37.1, longitude: -122.1),
            RecentDestination(title: "Coffee", latitude: 37.3, longitude: -122.3)
        ]
        defaults.set(String(data: try! JSONEncoder().encode(recents), encoding: .utf8),
                     forKey: CarPlayDestinations.recentsKey)

        let places = CarPlayDestinations.places(limit: 6, defaults: defaults)
        #expect(places.map(\.title) == ["Home", "Work", "Coffee"])
        #expect(places.first?.coordinate?.latitude == 37.1)
    }

    @Test func savedRidesComeFromTheSharedStoreNewestFirst() throws {
        let container = try ModelContainer(
            for: SavedRoute.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let older = SavedRoute(route: Self.route(name: "Older loop"), name: "Older loop")
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = SavedRoute(route: Self.route(name: "Newer loop"), name: "Newer loop")
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let rides = CarPlayDestinations.savedRides(limit: 10, context: context)
        #expect(rides.map(\.title) == ["Newer loop", "Older loop"])
        #expect(rides.allSatisfy { $0.route != nil })
        #expect(rides.first?.detail.contains("km") == true || rides.first?.detail.contains("mi") == true)
    }

    // MARK: Guidance snapshot

    @Test func guidanceMirrorsTheActiveRoute() {
        let voiceKey = "navigation.voice"
        let previousVoice = UserDefaults.standard.object(forKey: voiceKey)
        UserDefaults.standard.set(false, forKey: voiceKey)
        defer {
            if let previousVoice {
                UserDefaults.standard.set(previousVoice, forKey: voiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: voiceKey)
            }
        }

        let nav = NavigationManager()
        #expect(nav.carPlayGuidance == nil)

        let route = Self.route(name: "Guidance loop")
        nav.start(route, roads: [])
        let guidance = nav.carPlayGuidance
        #expect(guidance?.routeID == route.id)
        #expect(guidance?.arrived == false)
        #expect((guidance?.remaining ?? 0) == route.length)
        #expect(guidance?.instruction.isEmpty == false)

        nav.arrived = true
        #expect(nav.carPlayGuidance?.arrived == true)
        nav.stop()
        #expect(nav.carPlayGuidance == nil)
    }
}


#if canImport(CarPlay)
extension CarPlayTests {
    /// The scene delegate is referenced by name from Info.plist. If the module
    /// name or class name drifts, CarPlay silently shows nothing, so pin it.
    @Test func sceneDelegateResolvesFromTheSceneManifest() throws {
        let manifest = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
        )
        let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        let scenes = try #require(
            configurations["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]]
        )
        let scene = try #require(scenes.first)
        #expect(scene["UISceneClassName"] as? String == "CPTemplateApplicationScene")
        let delegateName = try #require(scene["UISceneDelegateClassName"] as? String)
        #expect(delegateName == "Revert.CarPlaySceneDelegate")
        #expect(NSClassFromString(delegateName) as? CarPlaySceneDelegate.Type != nil)
    }
}
#endif
