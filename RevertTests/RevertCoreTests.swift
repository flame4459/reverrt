import Testing
import Foundation
import CoreLocation
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
        UserDefaults.standard.set(false, forKey: Units.metricKey)
        #expect(Units.distanceText(1_609.344, decimals: 1).contains("mi"))
        UserDefaults.standard.set(true, forKey: Units.metricKey)
        #expect(Units.distanceText(1_000, decimals: 1).contains("km"))
        UserDefaults.standard.set(false, forKey: Units.metricKey)
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

    @Test func voicePackProseBecomesClips() {
        #expect(Narrator.parse("Turn right onto Market Street")
                == [.clip(.turnRight, fallback: "Turn right"), .text("onto Market Street")])
        #expect(Narrator.parse("In 200 feet, keep left").first
                == .clip(.keepLeft, fallback: "Keep left"))
        #expect(Narrator.parse("Continue on Broadway").isEmpty)
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
