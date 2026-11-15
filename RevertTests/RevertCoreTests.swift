import Testing
import Foundation
import CoreLocation
import MapKit
import SwiftData
import UIKit
@testable import Revert

@MainActor
struct RevertCoreTests {
    @Test func unitConversionsAreStable() {
        #expect(abs(Units.feet(1) - 3.28084) < 0.0001)
        #expect(abs(Units.miles(1_609.344) - 1) < 0.0001)
        #expect(abs(Units.kilometers(1_000) - 1) < 0.0001)
    }

    @Test func distanceTextObeysUnitSetting() {
        // The units setting moved from a legacy on/off metric flag to a
        // three-way system preference. The test has to own both keys and put
        // them back, or it inherits whatever the host app last wrote and fails
        // depending on test order.
        let defaults = UserDefaults.standard
        let previousSystem = defaults.string(forKey: Units.systemKey)
        let previousMetric = defaults.object(forKey: Units.metricKey)
        defer {
            if let previousSystem { defaults.set(previousSystem, forKey: Units.systemKey) }
            else { defaults.removeObject(forKey: Units.systemKey) }
            if let previousMetric { defaults.set(previousMetric, forKey: Units.metricKey) }
            else { defaults.removeObject(forKey: Units.metricKey) }
        }

        defaults.set(UnitSystemPreference.imperial.rawValue, forKey: Units.systemKey)
        #expect(Units.distanceText(1_609.344, decimals: 1).contains("mi"))

        defaults.set(UnitSystemPreference.metric.rawValue, forKey: Units.systemKey)
        #expect(Units.distanceText(1_000, decimals: 1).contains("km"))
    }

    @Test func legacyMetricFlagStillDecidesWhenNoSystemPreferenceExists() {
        let defaults = UserDefaults.standard
        let previousSystem = defaults.string(forKey: Units.systemKey)
        let previousMetric = defaults.object(forKey: Units.metricKey)
        defer {
            if let previousSystem { defaults.set(previousSystem, forKey: Units.systemKey) }
            else { defaults.removeObject(forKey: Units.systemKey) }
            if let previousMetric { defaults.set(previousMetric, forKey: Units.metricKey) }
            else { defaults.removeObject(forKey: Units.metricKey) }
        }

        defaults.removeObject(forKey: Units.systemKey)
        defaults.set(true, forKey: Units.metricKey)
        #expect(Units.isMetric)
        defaults.set(false, forKey: Units.metricKey)
        #expect(!Units.isMetric)
    }

    @Test func speedLimitParserHandlesOsmValues() {
        func road(_ maxspeed: String?) -> Road {
            Road(id: 1, highway: "secondary", name: nil, maxspeed: maxspeed,
                 maxspeedForward: nil, maxspeedBackward: nil, surface: nil,
                 oneway: nil, ref: nil, coords: [37, -122, 37.001, -122.001],
                 minLat: 37, maxLat: 37.001, minLon: -122.001, maxLon: -122)
        }
        #expect(road("50 mph").speedLimitMph(forward: true) == 50)
        #expect(road("80 km/h").speedLimitMph(forward: true) == 50)
        #expect(road("50;70").speedLimitMph(forward: true) == 30)
        #expect(road("none").speedLimitMph(forward: true) == nil)
        #expect(road(nil).speedLimitMph(forward: true) == nil)
    }

    @Test func routeCorridorFindsPointOnRoute() {
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 1),
                RoutePoint(lat: 37.0, lon: -121.9995, road: 1),
                RoutePoint(lat: 37.0, lon: -121.999, road: 1)
            ],
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 90
        )
        let match = RouteCorridor.project(
            latitude: 37.0, longitude: -121.9995,
            route: route, near: 0, behind: 0, ahead: 200, maxLateral: 20
        )
        #expect(match != nil)
        #expect((match?.lateral ?? 99) < 2)
        #expect((match?.along ?? 0) > 20)
    }

    @Test func offlineTurnDetectionUsesNewRoadVertex() {
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 1),
                RoutePoint(lat: 37.0, lon: -121.9995, road: 1),
                RoutePoint(lat: 37.0, lon: -121.999, road: 2),
                RoutePoint(lat: 37.0005, lon: -121.999, road: 2)
            ],
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 90
        )
        #expect(route.steps.contains { $0.turn == .left || $0.turn == .right || $0.turn == .slightLeft || $0.turn == .slightRight })
    }

    @Test func routeCorridorRejectsDistantPoint() {
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 1),
                RoutePoint(lat: 37.0, lon: -121.999, road: 1)
            ],
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 90
        )
        let match = RouteCorridor.project(
            latitude: 37.01, longitude: -121.9995,
            route: route, near: 0, behind: 0, ahead: 200, maxLateral: 20
        )
        #expect(match == nil)
    }

    @Test func distanceScaleReachesOneAndOneThousandMiles() {
        #expect(RideDistanceScale.minimumMiles == 1)
        #expect(RideDistanceScale.maximumMiles == 1_000)
        #expect(RideDistanceScale.miles(for: 0) == 1)
        #expect(RideDistanceScale.miles(for: 1) == 1_000)
        #expect(abs(RideDistanceScale.fraction(for: 1)) < 0.0001)
        #expect(abs(RideDistanceScale.fraction(for: 1_000) - 1) < 0.0001)
        for value in [1.0, 2, 5, 15, 40, 100, 500, 1_000] {
            let roundTrip = RideDistanceScale.miles(for: RideDistanceScale.fraction(for: value))
            #expect(abs(roundTrip - value) < 0.51)
        }
    }

    @Test func mapkitStyleGeometryProducesTurnSteps() {
        // MapKit loops carry road id 0 on every vertex; turns must come from
        // geometry rather than way changes.
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 0),
                RoutePoint(lat: 37.0, lon: -121.9995, road: 0),
                RoutePoint(lat: 37.0005, lon: -121.9995, road: 0),
                RoutePoint(lat: 37.0010, lon: -121.9995, road: 0)
            ],
            roads: [:], twistPerKm: 0, retraced: 0, bearing: 90
        )
        #expect(route.steps.contains { $0.turn != .start && $0.turn != .arrive })
    }

    @Test func savedRouteRoundTripsGeometryAndSteps() {
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 1),
                RoutePoint(lat: 37.0, lon: -121.9995, road: 1),
                RoutePoint(lat: 37.0, lon: -121.999, road: 2)
            ],
            roads: [:], twistPerKm: 80, retraced: 0, bearing: 90, displayName: "Test loop"
        )
        let saved = SavedRoute(route: route, name: "Test loop")
        let restored = saved.plannedRoute()
        #expect(restored != nil)
        #expect(abs((restored?.length ?? 0) - route.length) < 1)
        #expect((restored?.steps.count ?? 0) == route.steps.count)
    }

    @Test func heatmapSplitsByMetricBucket() {
        let start = Date()
        let points = (0..<30).map { index in
            RidePoint(lat: 37.0 + Double(index) * 0.0001, lon: -122.0,
                      alt: 30, speed: Double(index), time: start.addingTimeInterval(Double(index)),
                      lean: Double(index) / 2)
        }
        #expect(!RideAnalysis.heatSegments(from: points, metric: .speed).isEmpty)
        #expect(!RideAnalysis.heatSegments(from: points, metric: .lean).isEmpty)
    }

    @Test func loopGeometryAcceptsCleanCircuit() {
        let square = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -121.996),
            CLLocationCoordinate2D(latitude: 37.0, longitude: -121.996),
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        ]
        let analysis = LoopGeometry.analyze(square)
        #expect(analysis.longestSpurMeters < 20)
        #expect(LoopGeometry.isLapable(analysis))
    }

    @Test func loopGeometryFindsCulDeSacOutAndBack() {
        let route = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -121.998),
            // 200 m up the dead-end street, then straight back down it.
            CLLocationCoordinate2D(latitude: 37.0054, longitude: -121.998),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -121.998),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -121.996),
            CLLocationCoordinate2D(latitude: 37.0, longitude: -121.996),
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        ]
        let analysis = LoopGeometry.analyze(route)
        #expect(analysis.longestSpurMeters > 100)
        #expect(!LoopGeometry.isLapable(analysis))
    }

    @Test func loopGeometryDoesNotFlagAHairpin() {
        // Two legs 33 m apart: a switchback, not a retrace of the same lane.
        let hairpin = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0036, longitude: -121.9997),
            CLLocationCoordinate2D(latitude: 37.0, longitude: -121.9997)
        ]
        let analysis = LoopGeometry.analyze(hairpin)
        #expect(analysis.longestSpurMeters < 20)
        #expect(LoopGeometry.isLapable(analysis))
    }

    @Test func loopGeometryIgnoresTheRidersOwnDeadEndAtTheStart() {
        let route = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            // 100 m out of a driveway, then the actual circuit begins.
            CLLocationCoordinate2D(latitude: 37.0009, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0009, longitude: -121.996),
            CLLocationCoordinate2D(latitude: 37.0045, longitude: -121.996),
            CLLocationCoordinate2D(latitude: 37.0045, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 37.0009, longitude: -122.0),
            // Back down the same 100 m stem to the start.
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        ]
        let withoutForgiveness = LoopGeometry.analyze(route)
        #expect(!LoopGeometry.isLapable(withoutForgiveness))
        let analysis = LoopGeometry.analyze(route, ignoreStartMeters: 250, ignoreEndMeters: 250)
        #expect(LoopGeometry.isLapable(analysis))
    }

    @Test func idleTimerKeepsScreenAwakeUntilLastOwnerLetsGo() {
        // The map screen holds a token for as long as it is up; downloads and
        // planning take one only while they work. Restore whatever the host
        // app already holds so this test leaves the screen as it found it.
        let existing = IdleTimer.activeOwners
        IdleTimer.releaseAll()
        defer {
            IdleTimer.releaseAll()
            for owner in existing { IdleTimer.acquire(owner) }
        }

        IdleTimer.acquire("test.map")
        IdleTimer.acquire("test.download")
        #expect(UIApplication.shared.isIdleTimerDisabled)

        // A finishing download must not re-enable the lock screen while the
        // map is still on.
        IdleTimer.release("test.download")
        #expect(IdleTimer.activeOwners == ["test.map"])
        #expect(UIApplication.shared.isIdleTimerDisabled)

        IdleTimer.release("test.map")
        #expect(!UIApplication.shared.isIdleTimerDisabled)
    }


    @Test func gpxExportImportRoundTripsTheTrack() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<12).map { index in
            RidePoint(lat: 37.0 + Double(index) * 0.0005,
                      lon: -122.0,
                      alt: 40 + Double(index) * 4,
                      speed: 10,
                      time: start.addingTimeInterval(Double(index) * 10),
                      lean: 12)
        }
        let xml = GPX.export(points: points, startDate: start)
        let imported = GPX.importRide(from: Data(xml.utf8))
        #expect(imported != nil)
        #expect(imported?.points.count == points.count)
        #expect((imported?.distanceMeters ?? 0) > 500)
        #expect((imported?.durationSeconds ?? 0) > 100)
        #expect((imported?.elevationGainMeters ?? 0) > 20)
        #expect(abs((imported?.points.first?.lean ?? 0) - 12) < 0.1)
    }

    @Test func fuelPlanDoesNotOverstateANearlyEmptyTank() {
        let points = (0..<10).map { index in
            RoutePoint(lat: 37.0 + Double(index) * 0.05, lon: -122.0, road: 1)
        }
        let route = PlannedRoute(points: points, roads: [:], twistPerKm: 40,
                                 retraced: 0, bearing: 0, displayName: "Test")
        let plan = FuelService.plan(route: route, rangeKm: 300,
                                    tankFraction: 0.1, stations: [])
        // 10% of a 300 km tank is 30 km, not a rounded-up 40 km.
        #expect(abs(plan.usableKm - 30) < 0.01)
        #expect(plan.stopsNeeded >= 1)
    }

    @Test func savedRoutePersistsTheRoadGraph() {
        let road = Road(id: 7, highway: "tertiary", name: "Test Road",
                        maxspeed: nil, maxspeedForward: nil, maxspeedBackward: nil,
                        surface: "asphalt", oneway: nil, ref: nil,
                        coords: [37.0, -122.0, 37.01, -122.0],
                        minLat: 37.0, maxLat: 37.01, minLon: -122.0, maxLon: -122.0)
        let points = (0..<6).map { index in
            RoutePoint(lat: 37.0 + Double(index) * 0.002, lon: -122.0, road: 7)
        }
        let route = PlannedRoute(points: points, roads: [7: road], twistPerKm: 40,
                                 retraced: 0, bearing: 0, displayName: "Graph loop")
        let saved = SavedRoute(route: route, name: "Graph loop", roads: [road])
        #expect(saved.roads.count == 1)
        #expect(saved.roads.first?.id == 7)
        #expect(saved.roads.first?.name == "Test Road")
    }

    @Test func widgetBridgeSharesOnlyCoarseSnapshot() {
        WidgetBridge.updateBike(name: "Test Bike", odometerKm: 12_345)
        WidgetBridge.updateRide(distanceMeters: 42_000, date: Date(timeIntervalSince1970: 1_700_000_000),
                                routeName: "Test loop", bikeName: "Test Bike")
        let defaults = UserDefaults(suiteName: WidgetBridge.suiteName)
        #expect(defaults?.string(forKey: "widget.bikeName") == "Test Bike")
        #expect(defaults?.double(forKey: "widget.odometerKm") == 12_345)
        #expect(defaults?.double(forKey: "widget.lastRideMeters") == 42_000)
        #expect(defaults?.string(forKey: "widget.lastRideName") == "Test loop")
    }

    @Test func bikeArtworkMappingTargetsCatalogEntries() {
        #expect(!BikeSprites.modelArtwork.isEmpty)

        let catalog = Set(BikeCatalog.all.map(\.name))
        let orphans = BikeSprites.modelArtwork.keys.filter { !catalog.contains($0) }
        #expect(orphans.isEmpty, "artwork mapped to unknown models: \(orphans)")

        for (model, asset) in BikeSprites.modelArtwork {
            #expect(UIImage(named: asset) != nil, "missing sprite for \(model)")
        }
    }

    @Test func defaultBikeHasArtwork() {
        #expect(BikeSprites.hasArtwork(for: BikeCatalog.defaultBike))
    }

    @Test func bikeCatalogCoversEveryWorkbookModel() {
        #expect(BikeCatalog.all.count > 1_000)
        #expect(Set(BikeCatalog.all.map(\.name)).count == BikeCatalog.all.count)
        #expect(Set(BikeCatalog.all.map(\.category)) == Set(BikeCategory.allCases))
        #expect(BikeCatalog.entry(named: BikeCatalog.defaultBike) != nil)
        #expect(BikeCatalog.all.allSatisfy { !$0.manufacturer.isEmpty })
    }

    @Test func bikeCatalogKeepsMultiWordBrandsTogether() {
        let royal = BikeCatalog.grouped.first { $0.0 == "Royal Enfield" }
        #expect(royal?.1.isEmpty == false)
        let agusta = BikeCatalog.grouped.first { $0.0 == "MV Agusta" }
        #expect(agusta?.1.isEmpty == false)
    }

    // MARK: Voice packs

    @Test func voicePackCatalogueIsComplete() {
        #expect(VoicePack.catalog.count > 150)
        #expect(Set(VoicePack.catalog.map(\.id)).count == VoicePack.catalog.count)
        #expect(VoicePack.catalog.contains { $0.name == "Geralt (The Witcher)" })
        #expect(VoicePack.catalog.allSatisfy { !$0.name.isEmpty && !$0.language.isEmpty })
    }

    @Test func voicePackArchiveIsReadable() throws {
        let archive = Data(base64Encoded: Self.archiveFixture, options: .ignoreUnknownCharacters)
        let data = try #require(archive)
        let files = try TarGzip.mp3Files(from: data)
        #expect(files["TurnLeft.mp3"].map { String(decoding: $0, as: UTF8.self) } == "TURNLEFT-CLIP")
        #expect(files["Arrive.mp3"].map { String(decoding: $0, as: UTF8.self) } == "ARRIVE-CLIP")
    }

    @Test func voicePackRejectsFilesThatAreNotPacks() {
        #expect(throws: TarGzip.Failure.self) {
            _ = try TarGzip.mp3Files(from: Data("not an archive".utf8))
        }
    }

    @Test func voicePackClipNamesMatchCaseInsensitively() {
        let clips = VoicePackLibrary.canonicalClips([
            "turnleft.MP3": Data([1]),
            "Arrive.mp3": Data([2]),
            "notes.txt": Data()
        ])
        #expect(clips[.turnLeft] != nil)
        #expect(clips[.arrive] != nil)
        #expect(clips.count == 2)
    }

    @Test func voicePackDistanceClipsFollowUnits() {
        #expect(VoiceClip.distanceClip(forMeters: 380, metric: false) == .distance400Imperial)
        #expect(VoiceClip.distanceClip(forMeters: 900, metric: true) == .distance1000)
        #expect(VoiceClip.distanceClip(forMeters: 0, metric: true) == nil)
    }

    @Test func roundaboutExitUsesTheRecordedOrdinal() {
        #expect(Narrator.parse("At the roundabout, take the 2nd exit onto Main Street")
                == [.clip(.roundabout, fallback: "At the roundabout"),
                    .clip(.secondExit, fallback: "take the second exit"),
                    .text("onto Main Street")])

        // Word ordinals and a bare instruction with no roundabout preamble.
        #expect(Narrator.parse("Take the first exit onto Elm Road").first
                == .clip(.firstExit, fallback: "take the first exit"))
        #expect(Narrator.parse("At the roundabout, take the 3rd exit")
                == [.clip(.roundabout, fallback: "At the roundabout"),
                    .clip(.thirdExit, fallback: "take the third exit")])
    }

    @Test func roundaboutWithoutAnOrdinalKeepsTheProse() {
        // "take the exit on the left" is a slip road, not a roundabout exit.
        #expect(Narrator.parse("Take the exit on the left")
                == [.clip(.exitLeft, fallback: "Take the exit on the left")])
        // An eighth exit has no recording, so the whole line stays synthesised.
        let eighth = Narrator.parse("At the roundabout, take the 8th exit onto Ring Road")
        #expect(eighth == [.clip(.roundabout, fallback: "At the roundabout"),
                           .text("take the Eighth exit onto Ring Road")])
    }

    @Test func voicePackProseBecomesClips() {
        #expect(Narrator.parse("Turn right onto Market Street")
                == [.clip(.turnRight, fallback: "Turn right"), .text("onto Market Street")])
        #expect(Narrator.parse("In 200 feet, keep left").first
                == .clip(.keepLeft, fallback: "Keep left"))
        #expect(Narrator.parse("Continue on Broadway")
                == [.clip(.straight, fallback: "Continue"), .text("on Broadway")])
    }

    @Test func voicePackInstructionComposesDistanceTurnAndRoad() {
        UserDefaults.standard.set(false, forKey: Units.metricKey)
        defer { UserDefaults.standard.set(false, forKey: Units.metricKey) }

        let step = NavStep(id: 1, turn: .right, road: "Market Street", at: 0, distance: 0)
        let prompt = Narrator.instruction(step, distance: 400)
        let clips = prompt.parts.compactMap { part -> VoiceClip? in
            switch part {
            case .clip(let clip, _), .optionalClip(let clip): return clip
            case .text: return nil
            }
        }
        #expect(clips == [.distance400Imperial, .turnRight])
        #expect(prompt.fallback.contains("Market Street"))
    }

    @Test func voicePackMissingClipOnlySynthesisesThatPhrase() {
        UserDefaults.standard.set(false, forKey: Units.metricKey)
        defer { UserDefaults.standard.set(false, forKey: Units.metricKey) }

        let step = NavStep(id: 1, turn: .right, road: "Market Street", at: 0, distance: 0)
        let prompt = Narrator.instruction(step, distance: 400)

        // A pack with the manoeuvre but no imperial distance clips (Geralt and
        // many others) should skip the distance rather than turn robotic.
        let plan = Speaker.plan(for: prompt, available: [.turnRight, .straight])
        #expect(plan.count == 2)
        #expect(plan[0] == .clip(.turnRight))
        guard case .speech(let tail) = plan[1] else {
            Issue.record("street name should be synthesised after the turn clip")
            return
        }
        #expect(tail == "onto Market Street")

        // With the distance clip present the whole prompt stays recorded except
        // for the street name.
        let complete = Speaker.plan(for: prompt, available: [.distance400Imperial, .turnRight])
        #expect(complete.count == 3)
        #expect(complete[0] == .clip(.distance400Imperial))
        #expect(complete[1] == .clip(.turnRight))

        // A pack with nothing useful still speaks the full sentence.
        #expect(Speaker.plan(for: prompt, available: []) == [.speech(prompt.fallback)])
    }

    @Test func voicePackContainerIsSniffed() {
        let m4a = Data([0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20])
        let mp3 = Data([0x49, 0x44, 0x33, 0x04, 0x00])
        #expect(VoicePackLibrary.audioExtension(for: m4a) == "m4a")
        #expect(VoicePackLibrary.audioExtension(for: mp3) == "mp3")
    }

    @Test func builtInVoicePacksShipPlayableAudio() throws {
        for entry in BuiltInVoicePacks.entries {
            let url = try #require(BuiltInVoicePacks.resourceURL(entry.resource))
            let files = try TarGzip.mp3Files(from: Data(contentsOf: url))
            let clips = VoicePackLibrary.canonicalClips(files)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            var playable = 0
            for (clip, data) in clips {
                let name = "\(clip.rawValue).\(VoicePackLibrary.audioExtension(for: data))"
                let file = directory.appendingPathComponent(name)
                try data.write(to: file)
                if VoicePackLibrary.isPlayableAudio(file) { playable += 1 }
            }
            #expect(playable >= 40, "\(entry.resource) ships \(playable) playable clips")
        }
    }

    @Test func builtInVoicePacksShipCompleteArchives() throws {
        #expect(BuiltInVoicePacks.entries.count >= 3)

        for entry in BuiltInVoicePacks.entries {
            let url = try #require(BuiltInVoicePacks.resourceURL(entry.resource),
                                   "missing bundled archive for \(entry.resource)")
            let data = try Data(contentsOf: url)
            let files = try TarGzip.mp3Files(from: data)
            let clips = VoicePackLibrary.canonicalClips(files)
            #expect(clips.count >= 40, "\(entry.resource) ships \(clips.count) clips")
            #expect(VoiceClip.requiredForInstall.isSubset(of: Set(clips.keys)))
            #expect(VoicePack.catalog.contains { $0.id == entry.id })
        }
    }

    @Test func routeFingerprintIsStableAndOpaque() {
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.7750, lon: -122.4194, road: 1),
                RoutePoint(lat: 37.7850, lon: -122.4150, road: 1),
                RoutePoint(lat: 37.7880, lon: -122.4010, road: 1)
            ],
            roads: [:], twistPerKm: 80, retraced: 0, bearing: 45
        )
        let key = RouteFingerprint.key(for: route)
        #expect(!key.isEmpty)
        #expect(key.hasPrefix("r"))
        #expect(key == RouteFingerprint.key(for: route))
        // The token must not leak the coordinates it was derived from.
        #expect(!key.contains("37.775"))
        #expect(!key.contains("122.419"))
        #expect(key.count < 24)

        let other = PlannedRoute(
            points: [
                RoutePoint(lat: 37.9000, lon: -122.5000, road: 1),
                RoutePoint(lat: 37.9100, lon: -122.4900, road: 1)
            ],
            roads: [:], twistPerKm: 80, retraced: 0, bearing: 45
        )
        #expect(RouteFingerprint.key(for: other) != key)
    }

    @Test func rivalLinkRoundTripsThroughAURL() throws {
        let result = RivalResult(
            rider: "Sam",
            routeName: "Ridge loop",
            routeKey: "r1234abcd",
            durationSeconds: 3_723,
            distanceMeters: 42_000,
            maxLeanDegrees: 38,
            maxSpeedMps: 33,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let url = try #require(RivalLink.url(for: result))
        #expect(url.scheme == "revert")
        #expect(url.host == "rival")
        let decoded = try #require(RivalLink.result(from: url))
        #expect(decoded.id == result.id)
        #expect(decoded.rider == "Sam")
        #expect(decoded.routeKey == "r1234abcd")
        #expect(decoded.routeName == "Ridge loop")
        #expect(abs(decoded.durationSeconds - 3_723) < 0.001)
        #expect(abs(decoded.maxLeanDegrees - 38) < 0.001)
        #expect(abs(decoded.date.timeIntervalSince1970 - 1_700_000_000) < 0.5)

        #expect(RivalLink.result(from: URL(string: "revert://plan")!) == nil)
        #expect(RivalLink.result(from: URL(string: "https://example.com/rival?d=nope")!) == nil)
    }

    @Test func rivalBoardDeduplicatesAndSortsByTime() {
        let suiteName = "rival-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let board = RivalBoard(defaults: defaults)

        let slow = RivalResult(rider: "A", routeName: "Loop", routeKey: "rkey",
                               durationSeconds: 900, distanceMeters: 20_000,
                               maxLeanDegrees: 30, maxSpeedMps: 30, date: Date())
        let fast = RivalResult(rider: "B", routeName: "Loop", routeKey: "rkey",
                               durationSeconds: 800, distanceMeters: 20_000,
                               maxLeanDegrees: 35, maxSpeedMps: 32, date: Date())

        #expect(board.add(slow))
        #expect(!board.add(slow))
        let resend = RivalResult(
            rider: "A", routeName: "Loop", routeKey: "rkey",
            durationSeconds: 900, distanceMeters: 20_000,
            maxLeanDegrees: 30, maxSpeedMps: 30, date: slow.date
        )
        #expect(!board.add(resend), "The same ride shared twice should not stack")
        #expect(board.add(fast))
        #expect(board.results(for: "rkey").map(\.rider) == ["B", "A"])

        // A second board reads the same store back.
        let reloaded = RivalBoard(defaults: defaults)
        #expect(reloaded.results(for: "rkey").count == 2)
    }

    @Test func savedLoopReplaysAndKeepsItsIdentity() {
        let route = PlannedRoute(
            points: [
                RoutePoint(lat: 37.0, lon: -122.0, road: 1),
                RoutePoint(lat: 37.001, lon: -122.001, road: 1),
                RoutePoint(lat: 37.002, lon: -122.0, road: 2)
            ],
            roads: [:], twistPerKm: 80, retraced: 0, bearing: 90, displayName: "Test loop"
        )
        let saved = SavedRoute(route: route, name: "Test loop")
        let replay = saved.plannedRoute()
        #expect(replay?.savedRouteID == saved.id)
        #expect(saved.fingerprintKey == RouteFingerprint.key(for: route))
        #expect(saved.fingerprintKey == RouteFingerprint.key(for: saved))
    }

    @Test func sharedRideTrackSurvivesACompactLink() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<240).map { index in
            RidePoint(
                lat: 37.7700 + Double(index) * 0.00005,
                lon: -122.4200 + Double(index) * 0.00004,
                alt: 30,
                speed: 12.5,
                time: start.addingTimeInterval(Double(index) * 2),
                lean: Double(index % 40) - 20
            )
        }

        let track = try #require(RideTrackCodec.encode(points))
        let decoded = try #require(RideTrackCodec.decode(track))
        #expect(decoded.count > 2)
        #expect(decoded.count <= RideTrackCodec.defaultLimit)
        #expect(abs(decoded[0].latitude - 37.77) < 0.00002)
        #expect(abs(decoded[0].longitude + 122.42) < 0.00002)
        #expect(abs(decoded[0].speedMps - 12.5) < 0.2)
        #expect(abs(decoded[0].leanDegrees + 20) < 1.1)
        #expect(abs((decoded.last?.elapsed ?? 0) - Double((points.count - 1) * 2)) < 4)

        var result = RivalResult(
            rider: "Sam",
            routeName: "Ridge loop",
            routeKey: "r1234abcd",
            durationSeconds: 3_723,
            distanceMeters: 42_000,
            maxLeanDegrees: 38,
            maxSpeedMps: 33,
            date: start,
            laps: 3,
            isSprint: true
        )
        result.track = track

        let url = try #require(RivalLink.url(for: result))
        #expect(url.absoluteString.count < 5_000, "A replay link must stay emailable")
        let back = try #require(RivalLink.result(from: url))
        #expect(back.hasReplay)
        #expect(back.laps == 3)
        #expect(back.isSprint == true)
        let backTrack = try #require(RideTrackCodec.decode(back.track ?? Data()))
        #expect(backTrack.count == decoded.count)
        #expect(abs((backTrack.last?.elapsed ?? 0) - (decoded.last?.elapsed ?? 0)) < 1.1)

        // A time-only result still round-trips and stays small.
        result.track = nil
        let timeURL = try #require(RivalLink.url(for: result))
        let timeOnly = try #require(RivalLink.result(from: timeURL))
        #expect(!timeOnly.hasReplay)
        #expect(timeURL.absoluteString.count < 500)
    }

    @Test func malformedSharedTrackIsRejected() {
        #expect(RideTrackCodec.decode(Data()) == nil)
        #expect(RideTrackCodec.decode(Data([1, 2])) == nil)
        #expect(RideTrackCodec.decode(Data([99, 1, 0])) == nil)
    }

    @Test func loopsDefaultToThreeLapsAndSavedRoutesKeepThem() {
        let points = (0..<4).map {
            RoutePoint(lat: 37.0 + Double($0) * 0.0005, lon: -122.0, road: 1)
        }
        var loop = PlannedRoute(points: points, roads: [:], twistPerKm: 0, retraced: 0, bearing: 0)
        #expect(loop.laps == 3)

        let saved = SavedRoute(route: loop, name: "Three laps")
        #expect(saved.laps == 3)
        #expect(saved.plannedRoute()?.laps == 3)

        loop.laps = 5
        let five = SavedRoute(route: loop, name: "Five laps")
        #expect(five.laps == 5)
        #expect(five.plannedRoute()?.laps == 5)

        let key3 = RouteFingerprint.key(for: SavedRoute(route: { var r = loop; r.laps = 3; return r }(), name: "3"))
        let key5 = RouteFingerprint.key(for: five)
        #expect(key3 != key5, "A three-lap result must not compete with a five-lap result")
    }

    @Test func multiLapLoopBanksLapsBeforeArriving() {
        let points = (0..<5).map {
            RoutePoint(lat: 37.0 + Double($0) * 0.0005, lon: -122.0, road: 1)
        }
        var route = PlannedRoute(points: points, roads: [:], twistPerKm: 0, retraced: 0, bearing: 0)
        route.laps = 2

        let nav = NavigationManager()
        nav.start(route, roads: [])
        nav.handle(CLLocation(latitude: points[0].lat, longitude: points[0].lon))
        #expect(nav.joined)
        #expect(nav.totalLaps == 2)
        #expect(nav.lap == 1)

        let finish = points[4]
        nav.handle(CLLocation(latitude: finish.lat, longitude: finish.lon))
        #expect(nav.lap == 2, "Crossing the line should bank lap one, not finish")
        #expect(!nav.arrived)
        #expect(nav.lastLapDuration != nil)

        nav.handle(CLLocation(latitude: finish.lat, longitude: finish.lon))
        #expect(nav.arrived, "Crossing the line on the last lap should finish")
        #expect(nav.lap == 2)
        nav.stop()
    }

    @Test func sprintRoutesAreOneLapAndHaveTheirOwnBoard() {
        let points = (0..<4).map {
            RoutePoint(lat: 37.0 + Double($0) * 0.0005, lon: -122.0, road: 1)
        }
        var loop = PlannedRoute(points: points, roads: [:], twistPerKm: 0, retraced: 0, bearing: 0)
        loop.laps = 3
        let sprint = PlannedRoute(points: points, roads: [:], twistPerKm: 0, retraced: 0,
                                  bearing: 0, kind: .sprint)
        #expect(sprint.kind == .sprint)
        #expect(sprint.laps == 1)

        let saved = SavedRoute(route: sprint, name: "Sprint")
        #expect(saved.isSprint)
        #expect(!saved.isLoop)
        #expect(saved.laps == 1)
        let replay = saved.plannedRoute()
        #expect(replay?.kind == .sprint)
        #expect(replay?.laps == 1)

        #expect(RouteFingerprint.key(for: sprint) != RouteFingerprint.key(for: loop),
                "A sprint must not be ranked against the same road as a circuit")
    }

    @Test func locationHubPublishesSimulatedFixes() {
        let hub = LocationHub.shared
        final class Box: @unchecked Sendable { var location: CLLocation? }
        let box = Box()
        let token = hub.addSubscriber { box.location = $0 }
        hub.beginSimulation()
        defer {
            hub.removeSubscriber(token)
            hub.endSimulation()
        }
        let location = CLLocation(latitude: 37.123, longitude: -122.456)
        hub.inject(location)
        #expect(box.location?.coordinate.latitude == 37.123)
        #expect(box.location?.coordinate.longitude == -122.456)
    }

    @Test func recorderMarksFixesFromTheSimulator() {
        let hub = LocationHub.shared
        let recorder = RideRecorder()
        recorder.start()
        hub.beginSimulation()
        hub.inject(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: -122.5),
                              altitude: 30, horizontalAccuracy: 5, verticalAccuracy: 5,
                              course: 90, speed: 15, timestamp: Date()))
        #expect(recorder.wasSimulated)
        recorder.discard()
        hub.endSimulation()
    }

    @Test func vehiclePreferencesApplyToMapKitDirections() {
        let defaults = UserDefaults.standard
        let oldKind = defaults.string(forKey: VehiclePreferences.primaryKindKey)
        let oldActive = defaults.string(forKey: VehiclePreferences.activeKindKey)
        let oldTolls = defaults.object(forKey: VehiclePreferences.avoidTollsKey) as? Bool
        let oldHighways = defaults.object(forKey: VehiclePreferences.avoidHighwaysKey) as? Bool
        defer {
            if let oldKind { defaults.set(oldKind, forKey: VehiclePreferences.primaryKindKey) }
            else { defaults.removeObject(forKey: VehiclePreferences.primaryKindKey) }
            if let oldActive { defaults.set(oldActive, forKey: VehiclePreferences.activeKindKey) }
            else { defaults.removeObject(forKey: VehiclePreferences.activeKindKey) }
            if let oldTolls { defaults.set(oldTolls, forKey: VehiclePreferences.avoidTollsKey) }
            else { defaults.removeObject(forKey: VehiclePreferences.avoidTollsKey) }
            if let oldHighways { defaults.set(oldHighways, forKey: VehiclePreferences.avoidHighwaysKey) }
            else { defaults.removeObject(forKey: VehiclePreferences.avoidHighwaysKey) }
        }

        VehiclePreferences.sync(primaryKind: .car, avoidTolls: true, avoidHighways: true)
        let carRequest = MKDirections.Request()
        VehiclePreferences.apply(to: carRequest)
        #expect(carRequest.tollPreference == .avoid)
        #expect(carRequest.highwayPreference == .avoid)

        VehiclePreferences.sync(primaryKind: .motorcycle, avoidTolls: false, avoidHighways: false)
        let bikeRequest = MKDirections.Request()
        VehiclePreferences.apply(to: bikeRequest)
        #expect(bikeRequest.tollPreference == .any)
        #expect(bikeRequest.highwayPreference == .any)
    }

    @Test func streetNamesExpandOrdinalsAndSuffixes() {
        #expect(StreetNames.instruction("Turn right onto South 5th Street")
                == "Turn right onto South Fifth Street")
        #expect(StreetNames.road("S 5th St") == "South Fifth Street")
        #expect(StreetNames.road("125th Avenue") == "One Hundred Twenty-Fifth Avenue")
        #expect(StreetNames.instruction("Take the 2nd exit onto Main St")
                == "Take the Second exit onto Main Street")
        #expect(StreetNames.roadName(from: "Turn right onto S 5th St")
                == "South Fifth Street")
    }

    @Test func proseParsesSlightSharpAndForkManoeuvres() {
        #expect(Narrator.parse("Slight right onto South 5th Street")
                == [.clip(.keepRight, fallback: "Slight right"),
                    .text("onto South Fifth Street")])
        #expect(Narrator.parse("Sharp left onto Main St")
                == [.clip(.turnLeft, fallback: "Sharp left"),
                    .text("onto Main Street")])
        #expect(Narrator.parse("Keep right at the fork")
                == [.clip(.keepRight, fallback: "Keep right"),
                    .text("at the fork")])
    }

    @Test func navStepNormalizesRoadNames() {
        let roadStep = NavStep(id: 0, turn: .right, road: "S 5th St", at: 0, distance: 0)
        #expect(roadStep.instruction == "Turn right onto South Fifth Street")
        let textStep = NavStep(id: 0, turn: .right, road: nil, at: 0, distance: 0,
                               text: "Turn right onto South 5th Street")
        #expect(textStep.instruction == "Turn right onto South Fifth Street")
        let straight = Narrator.straight(road: "S 5th St", distance: 1_609.344)
        #expect(straight.fallback.contains("Continue on South Fifth Street"))
    }

    @Test func navigationStartKeepsChosenVehicle() {
        let defaults = UserDefaults.standard
        let oldActive = defaults.string(forKey: VehiclePreferences.activeKindKey)
        defer {
            if let oldActive { defaults.set(oldActive, forKey: VehiclePreferences.activeKindKey) }
            else { defaults.removeObject(forKey: VehiclePreferences.activeKindKey) }
        }
        let nav = NavigationManager()
        nav.start(DebugScreens.samplePlannedRoute(), roads: [], vehicleKind: .car)
        #expect(nav.vehicleKind == .car)
        #expect(VehiclePreferences.activeKind == .car)
        nav.stop()
    }

    @Test func renamingSavedRouteUpdatesLinkedRides() throws {
        let schema = Schema([SavedRoute.self, Ride.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let route = DebugScreens.samplePlannedRoute()
        let saved = SavedRoute(route: route, name: "Old loop")
        context.insert(saved)
        let ride = DebugScreens.sampleRide()
        ride.savedRouteID = saved.id
        ride.routeKey = saved.fingerprintKey
        ride.routeName = "Old loop"
        context.insert(ride)
        try context.save()

        saved.rename(to: "New loop", rides: [ride], context: context)
        #expect(saved.name == "New loop")
        #expect(ride.routeName == "New loop")
    }

    @Test func vehicleKindDefaultsAndCarRideStoresKind() {
        let bike = Bike(name: "Golf GTI", kind: .car)
        #expect(bike.kind == .car)
        #expect(bike.isCar)
        let ride = DebugScreens.sampleRide()
        ride.vehicleKind = .car
        #expect(ride.isCar)
        #expect(ride.vehicleKindRaw == VehicleKind.car.rawValue)
    }

    @Test func rivalLinkCarriesVehicleKind() {
        let ride = DebugScreens.sampleRide()
        ride.routeKey = "rTEST"
        ride.vehicleKind = .car
        let result = RivalResult.from(ride: ride, rider: "A", routeName: "Loop",
                                      includeTrack: false)
        #expect(result?.vehicle == .car)
        guard let result, let url = RivalLink.url(for: result),
              let decoded = RivalLink.result(from: url) else {
            Issue.record("Could not encode/decode rival link")
            return
        }
        #expect(decoded.vehicle == .car)
    }

    @Test func carWidgetSnapshotRoundTrips() {
        var snapshot = CarWidgetSnapshot()
        snapshot.mode = .simulation
        snapshot.vehicleKind = "car"
        snapshot.speed = "62 mph"
        snapshot.speedLimit = "55 mph"
        snapshot.lap = 2
        snapshot.totalLaps = 3
        snapshot.hazard = "Pothole"
        snapshot.isSimulation = true
        snapshot.updatedAt = Date()
        let data = try? JSONEncoder().encode(snapshot)
        let decoded = data.flatMap { try? JSONDecoder().decode(CarWidgetSnapshot.self, from: $0) }
        #expect(decoded?.mode == .simulation)
        #expect(decoded?.isCar == true)
        #expect(decoded?.isLive == true)
        #expect(decoded?.isSimulation == true)
        #expect(decoded?.lap == 2)
    }

    @Test func posterCatalogHasThemeAndLayoutVariations() {
        #expect(StoryPosterTheme.allCases.count >= 10)
        #expect(StoryPosterStyle.allCases.count == 3)
        #expect(StoryPosterTheme.paper.isLight)
        #expect(StoryPosterTheme.desert.isLight)
        #expect(StoryPosterTheme.alpine.isLight)
        #expect(!StoryPosterTheme.oled.isLight)
        #expect(!StoryPosterTheme.neon.isLight)
        #expect(StoryPosterStyle.allCases.map(\.title).contains("Dashboard"))
    }

    @Test func voicePackArrivalUsesTheArriveClip() {
        let step = NavStep(id: 2, turn: .arrive, road: nil, at: 0, distance: 0)
        #expect(Narrator.instruction(step, distance: 0) == Narrator.arrival)
    }

    private static let archiveFixture = """
        H4sIACHz8GoAA+2YwW7bIBzGaaVpWnbeduUFRsAGEx96cKtMdeWumetO26lCDtMsxU7K7CyPsnvvPe/xhqtWadO0XqXgSDU/CWGQgT9IH3yAzhEwDcaYMwav
        c49f55rbHGOHupAwh1PCCaUEYuJi4gCIjUemqX6VQulQxmKejfPpJCvE2v9+/5Ry8kQ/9ycFjcRqglfvX4NdAI5FCk9O4Td4Q10H3ujk6HShU12+/L8ugySJ
        bz7rFn90ervyy86y/l06zZGYzSYSzdR0LgtRpBLs7AJ4dDX6e4U/bGCSlscYicWhFGOp+mmllCzKcaY2PUaj/gle0b/HPArgYtOBrKPj+ncxzMssl3uE+3r9
        GeccOZT4lLqc9RiHUbgfxAeH4dchWoiyVGidXPeCL2EQDi+qsyirjvfTHvXhqW4UfX+q0R2N97a9Dl0F9c2P0aT/unBf/47HMIDMfGid1z/qo/NAqWwuUT5z
        zYyh18Oj9Dn+j3KXWf/XCtb/dRrUXzpAU/tAo/4xX/V/lBPr/9rA8df7v4HHfWv/Xj7ImOqXNOkfkwfnPyOuPf/bIIhjre2PB1E42nYoli1Q+/+kUkUkf5Sm
        9oDn+3/m1Pc/q/8WsP6/09z1/6b2gUb9P3z/5dyz/r8NHnn/HbDBgHv2AvDiQcZUv6TZ/7PV8x+79vxvheQs/hwNPyX2BmCxWCzd4h+cuh6XACYAAA==
        """
}
