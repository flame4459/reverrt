import Foundation

/// Persisted road graphs, so planning does not rebuild nodes, edges and
/// curvature every time the rider nudges a distance slider.
///
/// The cache is keyed by a deterministic hash of the road set, and the stored
/// snapshot is validated against the roads handed back in. A start point that
/// is not a node of the cached graph snaps to the nearest node instead of
/// forcing a rebuild: chunk boundaries put a node every ~220 m, so that lands
/// within half a chunk of the pin.
nonisolated enum GraphCache {
    private static let maxFiles = 8

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("graph_cache", isDirectory: true)
    }

    static func key(roads: [Road], includeUnpaved: Bool) -> String {
        "g_\(RoadGraph.roadsHash(roads))_\(includeUnpaved ? 1 : 0)"
    }

    private static func url(roads: [Road], includeUnpaved: Bool) -> URL {
        directory.appendingPathComponent(key(roads: roads, includeUnpaved: includeUnpaved) + ".plist")
    }

    static func load(roads: [Road], includeUnpaved: Bool) -> RoadGraph? {
        let url = url(roads: roads, includeUnpaved: includeUnpaved)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? PropertyListDecoder().decode(RoadGraph.Snapshot.self, from: data),
              let graph = RoadGraph(snapshot: snapshot, roads: roads) else { return nil }
        return graph
    }

    static func save(_ graph: RoadGraph, includeUnpaved: Bool) {
        let url = url(roads: graph.roads, includeUnpaved: includeUnpaved)
        let dir = directory
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(graph.snapshot()) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        prune()
    }

    private static func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: keys),
              urls.count > maxFiles else { return }
        let sorted = urls.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return l < r
        }
        for url in sorted.prefix(urls.count - maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func diskBytes() -> Int64 {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return urls.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
