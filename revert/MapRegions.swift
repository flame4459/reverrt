import Foundation
import CoreLocation
import CryptoKit
import Observation
import ImmersiveMap

/// A rectangular map region. Longitudes are not wrapped: every region Revert
/// ships is far from the antimeridian.
nonisolated struct MapRegionBounds: Codable, Hashable, Sendable {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double

    var isValid: Bool {
        minLat.isFinite && maxLat.isFinite && minLon.isFinite && maxLon.isFinite
            && minLat < maxLat && minLon < maxLon
            && abs(minLat) <= 90 && abs(maxLat) <= 90
            && abs(minLon) <= 180 && abs(maxLon) <= 180
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLat && coordinate.latitude <= maxLat
            && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }

    /// Degrees squared. Only used to rank overlapping regions: the smaller box
    /// is the more specific download.
    var area: Double {
        max(0, maxLat - minLat) * max(0, maxLon - minLon)
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                               longitude: (minLon + maxLon) / 2)
    }

    /// The world, used by a bundled starter archive whose coverage the app
    /// cannot know: it is assumed to cover the rider's home area.
    static let world = MapRegionBounds(minLat: -85, minLon: -180, maxLat: 85, maxLon: 180)
}

/// One downloadable PMTiles region published in `MapRegions.json`.
nonisolated struct MapRegion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    /// File name inside the app's region folder. Unique per region.
    let fileName: String
    let byteSize: Int64
    /// Lower-case hex SHA-256 of the exact file that is downloaded.
    let sha256: String
    let bbox: MapRegionBounds
    let version: Int
    let downloadURL: URL

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

nonisolated struct MapRegionCatalog: Codable, Sendable {
    let version: Int
    let regions: [MapRegion]

    static let empty = MapRegionCatalog(version: 1, regions: [])

    /// Ships inside the app. A published catalog can replace it later without
    /// an app update; the format is the same.
    static func bundled() -> MapRegionCatalog {
        guard let url = Bundle.main.url(forResource: "MapRegions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(MapRegionCatalog.self, from: data),
              catalog.regions.allSatisfy({ !$0.id.isEmpty && !$0.fileName.isEmpty && $0.bbox.isValid })
        else { return .empty }
        return catalog
    }
}

/// What a route can actually do offline: tiles under every metre, and whether
/// the road/hazard data needed to ride it is installed too.
nonisolated struct MapRouteCoverage: Equatable, Sendable {
    var totalMeters: Double = 0
    var tileCoveredMeters: Double = 0
    var roadCoveredMeters: Double = 0
    var hazardCoveredMeters: Double = 0
    var regionIDs: [String] = []

    var isFullyTileCovered: Bool { totalMeters > 0 && tileCoveredMeters >= totalMeters - 1 }
    var isFullyRoadCovered: Bool { totalMeters > 0 && roadCoveredMeters >= totalMeters - 1 }
    var isFullyHazardCovered: Bool { totalMeters > 0 && hazardCoveredMeters >= totalMeters - 1 }

    var tileGapMeters: Double { max(totalMeters - tileCoveredMeters, 0) }

    var summary: String {
        guard totalMeters > 0 else { return "No route to check." }
        if isFullyTileCovered && isFullyRoadCovered {
            return isFullyHazardCovered
                ? "The whole route is available offline."
                : "Map and routing are offline; hazard data is missing for part of the route."
        }
        if isFullyTileCovered {
            return "Map coverage is complete, but offline routing data is missing for part of this route."
        }
        return "Part of this route is outside your downloaded map coverage."
    }
}

nonisolated struct InstalledRegionInfo: Codable, Equatable, Sendable {
    var version: Int
    var sha256: String
    var bytes: Int64
    var installedAt: Date
    /// Recorded when the matching road/hazard download finishes, so coverage
    /// checks are a pure lookup instead of a disk crawl per route.
    var hasRoads: Bool = false
    var hasHazards: Bool = false
}

nonisolated enum MapRegionError: LocalizedError, Equatable {
    case badResponse(Int)
    case checksumMismatch
    case notEnoughSpace
    case invalidRegion
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): "The region download failed (HTTP \(status))."
        case .checksumMismatch: "The downloaded region was damaged. Try again."
        case .notEnoughSpace: "Not enough free storage for this region."
        case .invalidRegion: "This region's definition is invalid."
        case .insufficientData: "The downloaded region is shorter than expected."
        }
    }
}

/// Where the map's tiles come from for the current position.
nonisolated enum MapArchiveSource: Equatable, Sendable {
    case bundledStarter
    case installedRegion(String)
    case hosted
}

/// Installs and removes offline map regions, and decides which tile archive the
/// immersive renderer should use for a coordinate.
///
/// Precedence: a downloaded region that covers the point (smallest first), then
/// the bundled starter archive, then the hosted stream. The hosted stream is
/// never silent: the cockpit says when a map needs a connection.
@MainActor
@Observable
final class MapRegionStore {
    static let shared = MapRegionStore()

    private(set) var catalog: MapRegionCatalog
    private(set) var installedIDs: Set<String> = []
    /// What version is on disk, so an update can be detected.
    private(set) var installedInfo: [String: InstalledRegionInfo] = [:]
    private(set) var progressByID: [String: Double] = [:]
    private(set) var failureByID: [String: String] = [:]
    private(set) var downloadingID: String?

    /// `Application Support/MapRegions`, where installed `.pmtiles` files live.
    let directory: URL

    /// The starter archive, if this build bundles one (`region.pmtiles`).
    private(set) var starter: MapRegion?

    init(directory: URL? = nil,
         catalog: MapRegionCatalog? = nil,
         bundledStarterURL: URL? = MapRegionStore.bundledStarterURL()) {
        let base = directory ?? URL.applicationSupportDirectory
            .appending(path: "MapRegions", directoryHint: .isDirectory)
        self.directory = base
        self.catalog = catalog ?? Self.bundledCatalog()
        self.starter = Self.makeStarter(from: bundledStarterURL)
        refresh()
    }

    // MARK: - Discovery

    nonisolated static func bundledCatalog() -> MapRegionCatalog {
        MapRegionCatalog.bundled()
    }

    nonisolated static func bundledStarterURL() -> URL? {
        Bundle.main.url(forResource: "region", withExtension: "pmtiles")
    }

    nonisolated private static func makeStarter(from url: URL?) -> MapRegion? {
        guard let url, TileArchiveValidator.isUsable(url),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return MapRegion(id: "starter",
                         name: "Starter map",
                         subtitle: "Included with Revert",
                         fileName: url.lastPathComponent,
                         byteSize: Int64(size),
                         sha256: "",
                         bbox: .world,
                         version: 1,
                         downloadURL: url)
    }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let present = Set(files.filter { $0.pathExtension == "pmtiles" }.map(\.lastPathComponent))
        installedIDs = Set(catalog.regions.filter { present.contains($0.fileName) }.map(\.id))
        installedInfo = Self.loadInstalledInfo(in: directory)
    }

    private var infoURL: URL { directory.appending(path: "installed.json") }

    nonisolated private static func loadInstalledInfo(in directory: URL) -> [String: InstalledRegionInfo] {
        let url = directory.appending(path: "installed.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: InstalledRegionInfo].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveInstalledInfo() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(installedInfo)
            try data.write(to: infoURL, options: .atomic)
        } catch {
            RevertDiagnostics.log("mapregion.manifest failed: \(error.localizedDescription)")
        }
    }

    /// The version on disk for a region, 0 when it was installed before the
    /// manifest existed.
    func installedVersion(_ region: MapRegion) -> Int {
        installedInfo[region.id]?.version ?? (installedIDs.contains(region.id) ? 0 : -1)
    }

    func updateAvailable(_ region: MapRegion) -> Bool {
        isInstalled(region) && installedVersion(region) < region.version
    }

    // MARK: - Queries

    var downloadableRegions: [MapRegion] {
        catalog.regions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var installedRegions: [MapRegion] {
        catalog.regions.filter { installedIDs.contains($0.id) }
    }

    var installedBytes: Int64 {
        installedRegions.reduce(0) { $0 + $1.byteSize }
    }

    var freeSpace: Int64? {
        (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    func fileURL(for region: MapRegion) -> URL {
        directory.appending(path: region.fileName)
    }

    func isInstalled(_ region: MapRegion) -> Bool {
        installedIDs.contains(region.id)
    }

    /// The most specific installed region that covers a point: the smallest
    /// bounding box, then the smaller download.
    func region(containing coordinate: CLLocationCoordinate2D) -> MapRegion? {
        installedRegions
            .filter { $0.bbox.contains(coordinate) }
            .min { lhs, rhs in
                if lhs.bbox.area != rhs.bbox.area { return lhs.bbox.area < rhs.bbox.area }
                return lhs.byteSize < rhs.byteSize
            }
    }

    /// The archive the renderer should read for `coordinate`, and where it came
    /// from. `nil` coordinate means "not moving yet": use the starter when one
    /// exists, otherwise stream.
    func archive(for coordinate: CLLocationCoordinate2D?) -> (url: URL, source: MapArchiveSource) {
        if let coordinate,
           let region = region(containing: coordinate),
           TileArchiveValidator.isUsable(fileURL(for: region)) {
            return (fileURL(for: region), .installedRegion(region.id))
        }
        if let starter, TileArchiveValidator.isUsable(starter.downloadURL) {
            return (starter.downloadURL, .bundledStarter)
        }
        return (ImmersiveMapTilesService.tileArchiveURL, .hosted)
    }

    // MARK: - Install / delete

    func install(_ region: MapRegion) async {
        guard downloadingID == nil, !region.sha256.isEmpty else { return }
        failureByID[region.id] = nil
        downloadingID = region.id
        progressByID[region.id] = 0
        defer {
            downloadingID = nil
            progressByID[region.id] = nil
        }

        do {
            try ensureSpace(for: region.byteSize)
            let temporary = directory.appending(path: ".\(region.fileName).download")
            // The download owns the delegate only for its lifetime, so a strong
            // reference cannot leak.
            let store = self
            let downloader = RegionDownloader(destination: temporary) { fraction in
                Task { @MainActor in
                    store.progressByID[region.id] = fraction
                }
            }
            try await downloader.start(from: region.downloadURL)
            try installDownloaded(temporary, region: region)
            RevertDiagnostics.log("mapregion.install ok id=\(region.id)")
        } catch {
            failureByID[region.id] = error.localizedDescription
            RevertDiagnostics.log("mapregion.install failed id=\(region.id) \(error.localizedDescription)")
        }
    }

    /// Verified installation from a file already on disk. Network downloads end
    /// here so the checksum and the move are the same code path in tests.
    func installDownloaded(_ source: URL, region: MapRegion) throws {
        guard region.bbox.isValid, !region.fileName.isEmpty else { throw MapRegionError.invalidRegion }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0 else { throw MapRegionError.insufficientData }
        if !region.sha256.isEmpty {
            let digest = try Self.sha256(of: source)
            guard digest == region.sha256.lowercased() else { throw MapRegionError.checksumMismatch }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = fileURL(for: region)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                               ofItemAtPath: destination.path)
        installedIDs.insert(region.id)
        installedInfo[region.id] = InstalledRegionInfo(version: region.version,
                                                       sha256: region.sha256,
                                                       bytes: Int64(size),
                                                       installedAt: Date())
        saveInstalledInfo()
    }

    /// Called after the region's road and hazard downloads finish. Coverage
    /// then reports the real offline capability without touching the stores.
    func markDatasets(for region: MapRegion, hasRoads: Bool, hasHazards: Bool) {
        guard var info = installedInfo[region.id] else { return }
        info.hasRoads = hasRoads
        info.hasHazards = hasHazards
        installedInfo[region.id] = info
        saveInstalledInfo()
    }

    func delete(_ region: MapRegion) {
        try? FileManager.default.removeItem(at: fileURL(for: region))
        installedIDs.remove(region.id)
        installedInfo[region.id] = nil
        saveInstalledInfo()
        failureByID[region.id] = nil
    }

    func deleteAll() {
        for region in installedRegions { delete(region) }
    }

    // MARK: - Whole-route coverage

    /// Samples the route every `stepMeters` (and at least once per segment) and
    /// asks whether tiles, road data and hazards are installed under each
    /// sample. Not just the endpoints: a route can start and end inside two
    /// regions while crossing uncovered ground between them.
    func coverage(forRoute coordinates: [CLLocationCoordinate2D],
                  stepMeters: Double = 100) -> MapRouteCoverage {
        guard coordinates.count > 1 else { return MapRouteCoverage() }
        let installed = installedRegions
        guard !installed.isEmpty else {
            var empty = MapRouteCoverage()
            for index in 1..<coordinates.count {
                empty.totalMeters += Self.meters(coordinates[index - 1], coordinates[index])
            }
            return empty
        }
        // Readiness is recorded by the installer; a route check must never
        // crawl the road/hazard stores or hit the network.
        let roadReady = Dictionary(uniqueKeysWithValues: installed.map { region in
            (region.id, installedInfo[region.id]?.hasRoads ?? false)
        })
        let hazardReady = Dictionary(uniqueKeysWithValues: installed.map { region in
            (region.id, installedInfo[region.id]?.hasHazards ?? false)
        })
        var result = MapRouteCoverage()
        result.regionIDs = installed.map(\.id)

        for index in 1..<coordinates.count {
            let a = coordinates[index - 1]
            let b = coordinates[index]
            let segment = Self.meters(a, b)
            guard segment > 0 else { continue }
            result.totalMeters += segment
            let steps = max(Int(ceil(segment / stepMeters)), 1)
            let slice = segment / Double(steps)
            for step in 0..<steps {
                let t = (Double(step) + 0.5) / Double(steps)
                let sample = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                    longitude: a.longitude + (b.longitude - a.longitude) * t)
                if let region = installed.first(where: { $0.bbox.contains(sample) }) {
                    result.tileCoveredMeters += slice
                    if roadReady[region.id] == true { result.roadCoveredMeters += slice }
                    if hazardReady[region.id] == true { result.hazardCoveredMeters += slice }
                }
            }
        }
        return result
    }

    private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat = (a.latitude + b.latitude) / 2 * .pi / 180
        let dx = (b.longitude - a.longitude) * 111_320 * cos(lat)
        let dy = (b.latitude - a.latitude) * 110_540
        return sqrt(dx * dx + dy * dy)
    }

    static func radius(for bounds: MapRegionBounds) -> Double {
        let lat = (bounds.minLat + bounds.maxLat) / 2 * .pi / 180
        let width = (bounds.maxLon - bounds.minLon) * 111_320 * cos(lat) / 2
        let height = (bounds.maxLat - bounds.minLat) * 110_540 / 2
        return max(sqrt(width * width + height * height), 1)
    }


    // MARK: - Helpers

    private func ensureSpace(for bytes: Int64) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let free = freeSpace else { return }
        // Keep a margin so an install cannot fill the phone.
        guard free > bytes + 200_000_000 else { throw MapRegionError.notEnoughSpace }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Downloads a region to a temporary file with progress, then hands it back.
/// Delegate-based because `URLSession.AsyncBytes` gives no usable chunk API for
/// a 100 MB file, and the async `download(from:)` gives no progress.
private final class RegionDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func start(from url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            finish(.failure(MapRegionError.badResponse(status)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}
