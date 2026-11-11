import Foundation
import CoreLocation

nonisolated let tileDeg: Double = 0.05   // ~5.5 km per tile

/// Generic downloader + disk cache for map data split into tiles.
nonisolated final class TileStore<Item: Codable & Sendable>: @unchecked Sendable {
    nonisolated private struct CacheFile: Codable, Sendable { let fetched: Date; let items: [Item] }

    private let dir: URL
    private let pauseNs: UInt64
    private let cacheDays = 30.0
    private let fetchTile: @Sendable (Int, Int) async throws -> [Item]
    private let idOf: @Sendable (Item) -> Int64

    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "TileStore.io", qos: .utility)
    private var loadingFromDisk: Set<String> = []
    private var tiles: [String: [Item]] = [:]
    private var pending: [(x: Int, y: Int, keep: Bool)] = []
    private var queued: Set<String> = []
    private var failedAt: [String: Date] = [:]
    private var isDraining = false
    private var version = 0
    private var generation = 0
    private var assembled: (key: String, version: Int, items: [Item])?

    /// Tiles waiting to download (including the one in flight)
    var pendingCount: Int {
        lock.withLock { queued.count }
    }

    init(folder: String, pause: Double, idOf: @escaping @Sendable (Item) -> Int64,
         fetch: @escaping @Sendable (Int, Int) async throws -> [Item]) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent(folder, isDirectory: true)
        pauseNs = UInt64(pause * 1_000_000_000)
        self.idOf = idOf
        fetchTile = fetch
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: Riding: keep the 3x3 tiles around you loaded
    func ensureTiles(around c: CLLocationCoordinate2D) {
        let t = tile(of: c)
        var toReadFromDisk: [String] = []

        lock.withLock {
            if tiles.count > 25 {   // free memory: drop tiles far from the rider
                var near = Set<String>()
                for dx in -1...1 { for dy in -1...1 { near.insert(key(t.x + dx, t.y + dy)) } }
                tiles = tiles.filter { near.contains($0.key) }
                version += 1
                assembled = nil
            }
            for dx in -1...1 {
                for dy in -1...1 {
                    let x = t.x + dx, y = t.y + dy, k = key(x, y)
                    if tiles[k] != nil || queued.contains(k) || loadingFromDisk.contains(k) { continue }
                    if let failed = failedAt[k], Date().timeIntervalSince(failed) < 60 { continue }
                    // Disk decoding is I/O; do it on the background queue
                    loadingFromDisk.insert(k)
                    toReadFromDisk.append(k)
                }
            }
        }

        for k in toReadFromDisk {
            let folder = dir, days = cacheDays
            ioQueue.async { [weak self] in
                let cached = TileStore<Item>.readTile(folder, k, days)
                guard let self else { return }
                var needsDrain = false
                self.lock.withLock {
                    self.loadingFromDisk.remove(k)
                    if let cached {
                        self.tiles[k] = cached
                        self.version += 1
                    } else {
                        let parts = k.split(separator: "_")
                        if parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) {
                            self.enqueueLocked(x, y, keep: true, around: (t.x, t.y))
                            needsDrain = true
                        }
                    }
                }
                if needsDrain {
                    self.drain()
                }
            }
        }
    }

    private func enqueueLocked(_ x: Int, _ y: Int, keep: Bool, around center: (x: Int, y: Int)) {
        let k = key(x, y)
        guard tiles[k] == nil, !queued.contains(k) else { return }
        if let failed = failedAt[k], Date().timeIntervalSince(failed) < 60 { return }
        queued.insert(k)
        pending.append((x, y, keep))
        if !isDraining {
            pending.sort {
                abs($0.x - center.x) + abs($0.y - center.y)
                    > abs($1.x - center.x) + abs($1.y - center.y)
            }
        }
    }

    /// Items in the 3x3 tiles around the point (de-duplicated by id).
    func items(near c: CLLocationCoordinate2D) -> [Item] {
        let t = tile(of: c)
        let k = key(t.x, t.y)

        return lock.withLock {
            if let a = assembled, a.key == k, a.version == version {
                return a.items
            }
            var seen = Set<Int64>()
            var out: [Item] = []
            for dx in -1...1 {
                for dy in -1...1 {
                    for item in tiles[key(t.x + dx, t.y + dy)] ?? [] where seen.insert(idOf(item)).inserted {
                        out.append(item)
                    }
                }
            }
            assembled = (k, version, out)
            return out
        }
    }

    // MARK: Offline: download an area to disk only (not kept in memory)
    /// Returns the number of tiles queued.
    func prefetch(center c: CLLocationCoordinate2D, radiusKm: Double) -> Int {
        let dLat = radiusKm / 111.0
        let dLon = radiusKm / (111.0 * max(cos(c.latitude * .pi / 180), 0.2))
        let x0 = Int(floor((c.longitude - dLon) / tileDeg)), x1 = Int(floor((c.longitude + dLon) / tileDeg))
        let y0 = Int(floor((c.latitude - dLat) / tileDeg)), y1 = Int(floor((c.latitude + dLat) / tileDeg))
        let ct = tile(of: c)
        var added = 0

        lock.withLock {
            for x in x0...x1 {
                for y in y0...y1 {
                    let k = key(x, y)
                    if tiles[k] != nil || queued.contains(k) || diskFresh(k) { continue }
                    queued.insert(k)
                    pending.append((x, y, false))
                    added += 1
                }
            }
            pending.sort { abs($0.x - ct.x) + abs($0.y - ct.y) > abs($1.x - ct.x) + abs($1.y - ct.y) }
        }
        drain()
        return added
    }

    /// Stop queued/in-flight prefetches while preserving everything already
    /// downloaded. Used by the explicit Cancel action on the Offline screen.
    func cancelPending() {
        lock.withLock {
            pending = []
            queued = []
            version += 1
            generation += 1   // discard responses from in-flight prefetches
        }
    }

    func clear() {
        lock.withLock {
            pending = []
            queued = []
            tiles = [:]
            failedAt = [:]
            assembled = nil
            version += 1
            generation += 1   // invalidate in-flight downloads
        }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func diskBytes() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: Planning: read a whole area back from disk
    private func tileRange(_ c: CLLocationCoordinate2D, _ radiusKm: Double) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        let dLat = radiusKm / 111.0
        let dLon = radiusKm / (111.0 * max(cos(c.latitude * .pi / 180), 0.2))
        return (Int(floor((c.longitude - dLon) / tileDeg)), Int(floor((c.longitude + dLon) / tileDeg)),
                Int(floor((c.latitude - dLat) / tileDeg)), Int(floor((c.latitude + dLat) / tileDeg)))
    }

    /// How many tiles cover the area, and how many of them aren't saved (or are older than 30 days).
    func coverage(center c: CLLocationCoordinate2D, radiusKm: Double) -> (total: Int, missing: Int) {
        let r = tileRange(c, radiusKm)
        var total = 0, missing = 0
        for x in r.x0...r.x1 {
            for y in r.y0...r.y1 {
                total += 1
                if !diskFresh(key(x, y)) { missing += 1 }
            }
        }
        return (total, missing)
    }

    /// Everything saved for the area (de-duplicated). Decoding happens off the main thread.
    func loadArea(center c: CLLocationCoordinate2D, radiusKm: Double) async -> [Item] {
        let r = tileRange(c, radiusKm)
        var keys: [String] = []
        for x in r.x0...r.x1 { for y in r.y0...r.y1 { keys.append(key(x, y)) } }
        let folder = dir, days = cacheDays
        let tileItems: [[Item]] = await Task.detached(priority: .userInitiated) {
            keys.compactMap { TileStore<Item>.readTile(folder, $0, days) }
        }.value
        var seen = Set<Int64>()
        var out: [Item] = []
        for items in tileItems {
            for item in items where seen.insert(idOf(item)).inserted { out.append(item) }
        }
        return out
    }

    nonisolated private static func readTile(_ folder: URL, _ k: String, _ days: Double) -> [Item]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(k).json")),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data),
              Date().timeIntervalSince(file.fetched) < days * 86400 else { return nil }
        return file.items
    }

    // MARK: Internals
    nonisolated private func tryStartDrain() -> Bool {
        lock.withLock {
            guard !isDraining, !pending.isEmpty else { return false }
            isDraining = true
            return true
        }
    }

    nonisolated private func popPending() -> (key: String, next: (x: Int, y: Int, keep: Bool))? {
        lock.withLock {
            guard let next = self.pending.popLast() else { return nil }
            return (self.key(next.x, next.y), next)
        }
    }

    nonisolated private func recordSuccess(key: String, keep: Bool, items: [Item], generation: Int) {
        lock.withLock {
            guard self.generation == generation else { return }
            if keep {
                self.tiles[key] = items
                self.version += 1
            }
            self.queued.remove(key)
        }
    }

    nonisolated private func recordFailure(key: String, generation: Int) {
        lock.withLock {
            guard self.generation == generation else { return }
            self.failedAt[key] = Date()
            self.queued.remove(key)
        }
    }

    nonisolated private func finishDrain() -> Bool {
        lock.withLock {
            self.isDraining = false
            return !self.pending.isEmpty
        }
    }

    nonisolated private func drain() {
        guard tryStartDrain() else { return }
        let generation = lock.withLock { self.generation }

        Task {
            let concurrency = 4
            await withTaskGroup(of: (key: String, next: (x: Int, y: Int, keep: Bool), items: [Item]?).self) { group in
                var active = 0

                func addNextTask() -> Bool {
                    guard let item = self.popPending() else { return false }
                    let fetch = self.fetchTile
                    group.addTask {
                        do {
                            return (item.key, item.next, try await fetch(item.next.x, item.next.y))
                        } catch {
                            return (item.key, item.next, nil)
                        }
                    }
                    return true
                }

                while active < concurrency && addNextTask() {
                    active += 1
                }

                while active > 0 {
                    guard let result = await group.next() else { break }
                    active -= 1

                    if let items = result.items {
                        await self.storeToDisk(result.key, items, generation: generation)
                        self.recordSuccess(key: result.key, keep: result.next.keep,
                                           items: items, generation: generation)
                    } else {
                        self.recordFailure(key: result.key, generation: generation)
                    }

                    if addNextTask() {
                        active += 1
                    }
                }
            }

            if self.finishDrain() {
                self.drain()
            }
        }
    }

    nonisolated private func storeToDisk(_ k: String, _ items: [Item], generation: Int) async {
        // A kill mid-write used to leave a truncated tile that could never
        // decode. Write atomically and refuse to write if the cache was
        // cleared while this download was in flight.
        guard self.lock.withLock({ self.generation == generation }) else { return }
        let file = CacheFile(fetched: Date(), items: items)
        let url = dir.appendingPathComponent("\(k).json")
        await Task.detached(priority: .utility) { [weak self] in
            guard let self, self.lock.withLock({ self.generation == generation }) else { return }
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
    }

    nonisolated private func diskFresh(_ k: String) -> Bool {
        let path = dir.appendingPathComponent("\(k).json").path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < cacheDays * 86400
    }

    nonisolated private func key(_ x: Int, _ y: Int) -> String { "\(x)_\(y)" }
    nonisolated private func tile(of c: CLLocationCoordinate2D) -> (x: Int, y: Int) {
        (Int(floor(c.longitude / tileDeg)), Int(floor(c.latitude / tileDeg)))
    }
}
