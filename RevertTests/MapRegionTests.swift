import Testing
import Foundation
import CoreLocation
@testable import Revert

/// The app-side contract of offline map regions: manifest shape, checksum,
/// install/delete, and which archive the renderer picks.
@MainActor
struct MapRegionTests {

    // MARK: - Fixtures

    /// A file that passes `TileArchiveValidator` without carrying real tiles.
    private func makeArchive(at url: URL) throws {
        var header = Data(repeating: 0, count: 127)
        header.replaceSubrange(0..<7, with: Data("PMTiles".utf8))
        header[7] = 3
        func put(_ value: UInt64, at offset: Int) {
            for index in 0..<8 {
                header[offset + index] = UInt8((value >> (8 * UInt64(index))) & 0xff)
            }
        }
        put(127, at: 8); put(1, at: 16)     // root directory: 1 byte at 127
        put(0, at: 24); put(0, at: 32)      // no metadata
        put(0, at: 40); put(0, at: 48)      // no leaf directories
        put(129, at: 56); put(1, at: 64)    // one byte of tile data at 129
        var data = header
        data.append(contentsOf: [0x1f, 0x8b, 0x00])
        try data.write(to: url)
    }

    private func region(id: String, bounds: MapRegionBounds, fileName: String? = nil) -> MapRegion {
        MapRegion(id: id, name: id, subtitle: "Test", fileName: fileName ?? "\(id).pmtiles",
                  byteSize: 130, sha256: "", bbox: bounds, version: 1,
                  downloadURL: URL(string: "https://example.com/\(id).pmtiles")!)
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "revert-regions-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private let smallBox = MapRegionBounds(minLat: 40.5, minLon: -74.1, maxLat: 41.0, maxLon: -73.3)
    private let bigBox = MapRegionBounds(minLat: 40.0, minLon: -75.0, maxLat: 42.0, maxLon: -72.0)
    private let outside = CLLocationCoordinate2D(latitude: 35.0, longitude: -120.0)

    // MARK: - Manifest

    @Test func boundsContainOnlyTheirRectangle() {
        #expect(smallBox.contains(CLLocationCoordinate2D(latitude: 40.7, longitude: -73.8)))
        #expect(!smallBox.contains(outside))
        #expect(smallBox.isValid)
        #expect(!MapRegionBounds(minLat: 41, minLon: -74, maxLat: 40, maxLon: -73).isValid)
    }

    @Test func catalogDecodesAPublishedManifest() throws {
        let json = """
        {"version":1,"regions":[{
          "id":"long-island","name":"Long Island","subtitle":"New York",
          "fileName":"Revert-long-island.pmtiles","byteSize":150000000,
          "sha256":"abc","bbox":{"minLat":40.55,"minLon":-73.95,"maxLat":41.2,"maxLon":-71.85},
          "version":1,"downloadURL":"https://example.com/Revert-long-island.pmtiles"}]}
        """
        let catalog = try JSONDecoder().decode(MapRegionCatalog.self, from: Data(json.utf8))
        #expect(catalog.regions.count == 1)
        #expect(catalog.regions[0].formattedSize.isEmpty == false)
        #expect(catalog.regions[0].bbox.isValid)
    }

    // MARK: - Install

    @Test func installsAValidRegionAndDeletesIt() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = region(id: "small", bounds: smallBox)
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [item]),
                                   bundledStarterURL: nil)
        let source = directory.appending(path: "source.pmtiles")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeArchive(at: source)

        let hashed = MapRegion(id: item.id, name: item.name, subtitle: item.subtitle,
                               fileName: item.fileName, byteSize: item.byteSize,
                               sha256: try MapRegionStore.sha256(of: source),
                               bbox: item.bbox, version: item.version, downloadURL: item.downloadURL)

        try store.installDownloaded(source, region: hashed)
        #expect(store.isInstalled(hashed))
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: hashed).path))
        #expect(store.installedBytes == hashed.byteSize)

        store.delete(hashed)
        #expect(!store.isInstalled(hashed))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: item).path))
    }

    @Test func rejectsAChecksumMismatch() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MapRegionStore(directory: directory, catalog: .empty, bundledStarterURL: nil)
        let source = directory.appending(path: "source.pmtiles")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeArchive(at: source)

        var item = region(id: "small", bounds: smallBox)
        item = MapRegion(id: item.id, name: item.name, subtitle: item.subtitle,
                         fileName: item.fileName, byteSize: item.byteSize,
                         sha256: String(repeating: "0", count: 64),
                         bbox: item.bbox, version: item.version, downloadURL: item.downloadURL)

        #expect(throws: MapRegionError.checksumMismatch) {
            try store.installDownloaded(source, region: item)
        }
        #expect(!store.isInstalled(item))
    }

    // MARK: - Archive choice

    @Test func theSmallestInstalledRegionCoveringTheRiderWins() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let small = region(id: "small", bounds: smallBox)
        let big = region(id: "big", bounds: bigBox)
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [big, small]),
                                   bundledStarterURL: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in [big, small] {
            let source = directory.appending(path: "\(item.id)-source.pmtiles")
            try makeArchive(at: source)
            let hashed = MapRegion(id: item.id, name: item.name, subtitle: item.subtitle,
                                   fileName: item.fileName, byteSize: item.byteSize,
                                   sha256: try MapRegionStore.sha256(of: source),
                                   bbox: item.bbox, version: item.version,
                                   downloadURL: item.downloadURL)
            try store.installDownloaded(source, region: hashed)
        }

        let inside = CLLocationCoordinate2D(latitude: 40.7, longitude: -73.8)
        let choice = store.archive(for: inside)
        #expect(choice.source == .installedRegion("small"))
        #expect(choice.url.lastPathComponent == "small.pmtiles")

        #expect(store.archive(for: outside).source == .hosted)
    }

    @Test func theBundledStarterIsUsedWhenNoRegionCoversTheRider() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let starterFile = directory.appending(path: "region.pmtiles")
        try makeArchive(at: starterFile)

        let store = MapRegionStore(directory: directory, catalog: .empty,
                                   bundledStarterURL: starterFile)
        #expect(store.starter != nil)
        #expect(store.archive(for: outside).source == .bundledStarter)
        #expect(store.archive(for: nil).source == .bundledStarter)
    }

    @Test func streamsWhenNothingIsInstalled() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MapRegionStore(directory: directory, catalog: .empty, bundledStarterURL: nil)
        let choice = store.archive(for: CLLocationCoordinate2D(latitude: 40.7, longitude: -73.8))
        #expect(choice.source == .hosted)
        #expect(choice.url.host() == "tiles.immersivemap.dev")
    }
}

// MARK: - Whole-route coverage and updates

@MainActor
struct MapCoverageTests {

    private func archive(at url: URL) throws {
        var header = Data(repeating: 0, count: 127)
        header.replaceSubrange(0..<7, with: Data("PMTiles".utf8))
        header[7] = 3
        func put(_ value: UInt64, at offset: Int) {
            for index in 0..<8 {
                header[offset + index] = UInt8((value >> (8 * UInt64(index))) & 0xff)
            }
        }
        put(127, at: 8); put(1, at: 16)
        put(129, at: 56); put(1, at: 64)
        var data = header
        data.append(contentsOf: [0x1f, 0x8b, 0x00])
        try data.write(to: url)
    }

    private func region(_ id: String, bounds: MapRegionBounds, version: Int = 1) -> MapRegion {
        MapRegion(id: id, name: id, subtitle: "", fileName: "\(id).pmtiles",
                  byteSize: 130, sha256: "", bbox: bounds, version: version,
                  downloadURL: URL(string: "https://example.com/\(id).pmtiles")!)
    }

    private func install(_ store: MapRegionStore, _ item: MapRegion,
                         in directory: URL) throws {
        let source = directory.appending(path: "\(UUID().uuidString).pmtiles")
        try archive(at: source)
        let hashed = MapRegion(id: item.id, name: item.name, subtitle: item.subtitle,
                               fileName: item.fileName, byteSize: item.byteSize,
                               sha256: try MapRegionStore.sha256(of: source),
                               bbox: item.bbox, version: item.version,
                               downloadURL: item.downloadURL)
        try store.installDownloaded(source, region: hashed)
    }

    private var route: [CLLocationCoordinate2D] {
        [CLLocationCoordinate2D(latitude: 40.70, longitude: -74.00),
         CLLocationCoordinate2D(latitude: 40.70, longitude: -73.80)]
    }

    @Test func partialCoverageIsDetected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "coverage-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Only the western half of the route.
        let west = MapRegionBounds(minLat: 40.69, minLon: -74.01, maxLat: 40.71, maxLon: -73.90)
        let item = region("west", bounds: west)
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [item]),
                                   bundledStarterURL: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try install(store, item, in: directory)

        let coverage = store.coverage(forRoute: route)
        #expect(coverage.totalMeters > 1_000)
        #expect(coverage.tileCoveredMeters > 0)
        #expect(coverage.tileCoveredMeters < coverage.totalMeters)
        #expect(!coverage.isFullyTileCovered)
        #expect(!coverage.isFullyRoadCovered)
        #expect(coverage.summary.contains("outside"))
    }

    @Test func adjacentRegionsCoverACrossingRoute() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "coverage-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let west = region("west", bounds: MapRegionBounds(minLat: 40.69, minLon: -74.02,
                                                          maxLat: 40.71, maxLon: -73.90))
        let east = region("east", bounds: MapRegionBounds(minLat: 40.69, minLon: -73.90,
                                                          maxLat: 40.71, maxLon: -73.78))
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [west, east]),
                                   bundledStarterURL: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try install(store, west, in: directory)
        try install(store, east, in: directory)

        let coverage = store.coverage(forRoute: route)
        #expect(coverage.isFullyTileCovered)
        #expect(coverage.regionIDs.count == 2)
    }

    @Test func datasetReadinessIsReportedAfterInstall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "coverage-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bounds = MapRegionBounds(minLat: 40.69, minLon: -74.02, maxLat: 40.71, maxLon: -73.78)
        let item = region("full", bounds: bounds)
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [item]),
                                   bundledStarterURL: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try install(store, item, in: directory)

        let tilesOnly = store.coverage(forRoute: route)
        #expect(tilesOnly.isFullyTileCovered)
        #expect(!tilesOnly.isFullyRoadCovered)
        #expect(tilesOnly.summary.contains("routing"))

        store.markDatasets(for: item, hasRoads: true, hasHazards: false)
        let withRoads = store.coverage(forRoute: route)
        #expect(withRoads.isFullyTileCovered)
        #expect(withRoads.isFullyRoadCovered)
        #expect(!withRoads.isFullyHazardCovered)
    }

    @Test func coverageWithoutInstalledRegionsStillMeasuresTheRoute() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "coverage-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MapRegionStore(directory: directory, catalog: .empty, bundledStarterURL: nil)
        let coverage = store.coverage(forRoute: route)
        #expect(coverage.totalMeters > 1_000)
        #expect(coverage.tileCoveredMeters == 0)
        #expect(!coverage.isFullyTileCovered)
    }

    @Test func aNewerCatalogVersionIsAnUpdate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "update-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bounds = MapRegionBounds(minLat: 40.69, minLon: -74.02, maxLat: 40.71, maxLon: -73.78)
        let v1 = region("island", bounds: bounds, version: 1)
        let v2 = region("island", bounds: bounds, version: 2)
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [v2]),
                                   bundledStarterURL: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try install(store, v1, in: directory)

        #expect(store.installedVersion(v1) == 1)
        #expect(store.updateAvailable(v2))

        try install(store, v2, in: directory)
        #expect(store.installedVersion(v2) == 2)
        #expect(!store.updateAvailable(v2))
    }

    @Test func aFailedUpdateLeavesTheWorkingRegion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "update-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bounds = MapRegionBounds(minLat: 40.69, minLon: -74.02, maxLat: 40.71, maxLon: -73.78)
        let v1 = region("island", bounds: bounds, version: 1)
        let store = MapRegionStore(directory: directory,
                                   catalog: MapRegionCatalog(version: 1, regions: [v1]),
                                   bundledStarterURL: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try install(store, v1, in: directory)

        let source = directory.appending(path: "broken.pmtiles")
        try archive(at: source)
        let bad = MapRegion(id: "island", name: "island", subtitle: "", fileName: "island.pmtiles",
                            byteSize: 130, sha256: String(repeating: "0", count: 64),
                            bbox: bounds, version: 9, downloadURL: v1.downloadURL)
        #expect(throws: MapRegionError.checksumMismatch) {
            try store.installDownloaded(source, region: bad)
        }
        #expect(store.isInstalled(v1))
        #expect(store.installedVersion(v1) == 1)
    }
}
