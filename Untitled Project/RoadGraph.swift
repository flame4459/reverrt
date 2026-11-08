import Foundation
import CoreLocation

/// Small binary min-heap used by the route search.
nonisolated struct MinHeap {
    private var a: [(key: Double, value: Int)] = []

    mutating func push(_ key: Double, _ value: Int) {
        a.append((key, value))
        var i = a.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if a[p].key <= a[i].key { break }
            a.swapAt(p, i)
            i = p
        }
    }

    mutating func pop() -> (key: Double, value: Int)? {
        guard !a.isEmpty else { return nil }
        let top = a[0]
        let last = a.removeLast()
        if !a.isEmpty {
            a[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < a.count && a[l].key < a[m].key { m = l }
                if r < a.count && a[r].key < a[m].key { m = r }
                if m == i { break }
                a.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}

/// Road network built from the cached OpenStreetMap ways.
/// Nodes are junctions and chunk boundaries; edges are short stretches of road.
nonisolated final class RoadGraph {
    struct Edge {
        let from: Int
        let to: Int
        let road: Int        // index into `roads`
        let i0: Int          // first vertex on that road (may be larger than i1 when travelling backwards)
        let i1: Int
        let length: Double   // meters
        /// Absolute heading change per kilometre, measured over this chunk.
        let twist: Double
        /// 0...100 riding value from radius-based curvature.
        let value: Double
        /// Fraction of the chunk spent in corners under 150 m.
        let cornerShare: Double
        /// Fraction in 70...250 m sweepers.
        let sweeperShare: Double
        /// Fraction in corners under 70 m.
        let tightShare: Double
        /// Comfortable speed through the tightest part, metres per second.
        let comfortableMps: Double
        /// Shared by the two directions of the same stretch of road.
        let seg: Int
    }

    /// Long stretches are split so the router can see the good part of a road
    /// instead of averaging it away over the whole junction-to-junction span.
    /// Boundaries always land on existing OSM vertices, so geometry and turn
    /// instructions are unchanged.
    static let chunkMeters = 220.0

    /// Lower bound on any cost per metre produced by RouteBuilder. Used by A*
    /// so its straight-line heuristic can never overestimate.
    static let minimumCostPerMeter = 0.11

    let roads: [Road]
    private(set) var nodeLat: [Double] = []
    private(set) var nodeLon: [Double] = []
    private(set) var edges: [Edge] = []
    private(set) var twin: [Int] = []          // opposite-direction edge, or -1 for one-way roads
    private(set) var outEdges: [[Int]] = []
    private(set) var inEdges: [[Int]] = []
    private var nodeOfKey: [Int64: Int] = [:]

    /// Same OSM node always has identical coordinates, so rounding gives a stable id.
    static func key(_ lat: Double, _ lon: Double) -> Int64 {
        let la = Int64((lat * 1e6).rounded()) + 90_000_000
        let lo = Int64((lon * 1e6).rounded()) + 180_000_000
        return la * 400_000_000 + lo
    }

    /// Flat-earth distance (m) and heading (degrees, 0 = north) between two nearby points.
    static func flat(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> (dist: Double, heading: Double) {
        let kx = 111_320.0 * cos((la1 + la2) / 2 * .pi / 180)
        let dx = (lo2 - lo1) * kx
        let dy = (la2 - la1) * 110_540.0
        let d = (dx * dx + dy * dy).squareRoot()
        let h = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (d, h)
    }

    /// `forced` are vertex keys that must become nodes even if no other road meets there (start point, rejoin point).
    init(roads: [Road], forced: Set<Int64> = [], includeUnpaved: Bool = false) {
        self.roads = roads

        // A vertex shared by two ways (or twice by one way) is a junction.
        var occ: [Int64: UInt8] = [:]
        for r in roads where includeUnpaved || !r.isUnpaved {
            for i in 0..<r.count {
                let k = RoadGraph.key(r.lat(i), r.lon(i))
                occ[k] = occ[k] == nil ? 1 : 2
            }
        }

        var seg = 0
        for (ri, r) in roads.enumerated() where r.count >= 2 && (includeUnpaved || !r.isUnpaved) {
            var a = 0
            var chunkLength = 0.0
            for i in 1..<r.count {
                chunkLength += RoadGraph.flat(
                    r.lat(i - 1), r.lon(i - 1),
                    r.lat(i), r.lon(i)
                ).dist
                let k = RoadGraph.key(r.lat(i), r.lon(i))
                let boundary = i == r.count - 1
                    || occ[k] == 2
                    || forced.contains(k)
                    || chunkLength >= Self.chunkMeters
                if boundary {
                    addSegment(road: ri, from: a, to: i, id: seg)
                    seg += 1
                    a = i
                    chunkLength = 0
                }
            }
        }
    }

    private func node(_ lat: Double, _ lon: Double) -> Int {
        let k = RoadGraph.key(lat, lon)
        if let n = nodeOfKey[k] { return n }
        let n = nodeLat.count
        nodeOfKey[k] = n
        nodeLat.append(lat)
        nodeLon.append(lon)
        outEdges.append([])
        inEdges.append([])
        return n
    }

    func node(forKey k: Int64) -> Int? { nodeOfKey[k] }

    private func addSegment(road ri: Int, from i0: Int, to i1: Int, id: Int) {
        let r = roads[ri]
        var len = 0.0
        for i in i0..<i1 {
            len += RoadGraph.flat(r.lat(i), r.lon(i), r.lat(i + 1), r.lon(i + 1)).dist
        }
        guard len >= 1 else { return }

        // Curvature over exactly this chunk. Radius-based, so a 90-degree
        // junction approach does not read as a corner and a hairpin does.
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(i1 - i0 + 1)
        for i in i0...i1 {
            coordinates.append(CLLocationCoordinate2D(latitude: r.lat(i), longitude: r.lon(i)))
        }
        let stats = Curvature.measure(coordinates)

        let a = node(r.lat(i0), r.lon(i0))
        let b = node(r.lat(i1), r.lon(i1))
        let ow = r.oneway?.lowercased()
        let canForward = !(ow == "-1" || ow == "reverse")
        let canBack = !(ow == "yes" || ow == "true" || ow == "1")

        var fe = -1, be = -1
        if canForward {
            fe = edges.count
            edges.append(Edge(
                from: a, to: b, road: ri, i0: i0, i1: i1,
                length: len, twist: stats.degreesPerKm, value: stats.value,
                cornerShare: stats.cornerShare, sweeperShare: stats.sweeperShare,
                tightShare: stats.tightShare,
                comfortableMps: stats.comfortableMps, seg: id
            ))
            twin.append(-1)
            outEdges[a].append(fe)
            inEdges[b].append(fe)
        }
        if canBack {
            be = edges.count
            edges.append(Edge(
                from: b, to: a, road: ri, i0: i1, i1: i0,
                length: len, twist: stats.degreesPerKm, value: stats.value,
                cornerShare: stats.cornerShare, sweeperShare: stats.sweeperShare,
                tightShare: stats.tightShare,
                comfortableMps: stats.comfortableMps, seg: id
            ))
            twin.append(-1)
            outEdges[b].append(be)
            inEdges[a].append(be)
        }
        if fe >= 0 && be >= 0 { twin[fe] = be; twin[be] = fe }
    }

    /// Nodes you can get to from `s` (or, with `reverse`, nodes that can get to `s`).
    func reachable(from s: Int, reverse: Bool = false) -> [Bool] {
        var seen = [Bool](repeating: false, count: nodeLat.count)
        var stack = [s]
        seen[s] = true
        while let u = stack.popLast() {
            for ei in (reverse ? inEdges[u] : outEdges[u]) {
                let v = reverse ? edges[ei].from : edges[ei].to
                if !seen[v] { seen[v] = true; stack.append(v) }
            }
        }
        return seen
    }

    /// Cheapest path as a list of edge indices. `costs` is indexed like `edges`.
    ///
    /// A* with a straight-line heuristic. Every caller's cost function has a
    /// per-metre floor above `minimumCostPerMeter`, so the heuristic is
    /// admissible and consistent. On a chunked graph this is the difference
    /// between evaluating a handful of loops and evaluating dozens.
    func shortestPath(
        from s: Int,
        to t: Int,
        costs: [Double],
        deadline: Date? = nil,
        heuristic: Bool = true
    ) -> [Int]? {
        if s == t { return [] }
        let n = nodeLat.count
        let targetLat = nodeLat[t]
        let targetLon = nodeLon[t]
        var dist = [Double](repeating: .infinity, count: n)
        var prev = [Int](repeating: -1, count: n)
        var settled = [Bool](repeating: false, count: n)
        var heap = MinHeap()

        func estimate(_ node: Int) -> Double {
            guard heuristic else { return 0 }
            return RoadGraph.flat(nodeLat[node], nodeLon[node], targetLat, targetLon).dist
                * Self.minimumCostPerMeter
        }

        dist[s] = 0
        heap.push(estimate(s), s)
        var iterations = 0
        while let (_, u) = heap.pop() {
            iterations += 1
            if iterations.isMultiple(of: 256), Task.isCancelled || deadline.map({ Date() >= $0 }) == true {
                return nil
            }
            if settled[u] { continue }
            settled[u] = true
            if u == t { break }
            let base = dist[u]
            for ei in outEdges[u] {
                let v = edges[ei].to
                let nd = base + costs[ei]
                if nd < dist[v] {
                    dist[v] = nd
                    prev[v] = ei
                    heap.push(nd + estimate(v), v)
                }
            }
        }
        guard prev[t] >= 0 else { return nil }
        var path: [Int] = []
        var cur = t
        while cur != s {
            let e = prev[cur]
            if e < 0 { return nil }
            path.append(e)
            cur = edges[e].from
        }
        return path.reversed()
    }

    /// The road geometry for a path of edges, one point per OSM vertex.
    func points(for path: [Int]) -> [RoutePoint] {
        var pts: [RoutePoint] = []
        for (n, ei) in path.enumerated() {
            let e = edges[ei]
            let r = roads[e.road]
            let step = e.i1 >= e.i0 ? 1 : -1
            var i = n == 0 ? e.i0 : e.i0 + step     // the first vertex repeats the previous edge's last one
            while true {
                pts.append(RoutePoint(lat: r.lat(i), lon: r.lon(i), road: r.id))
                if i == e.i1 { break }
                i += step
            }
        }
        return pts
    }
}
