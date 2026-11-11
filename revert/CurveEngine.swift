import Foundation
import CoreLocation

struct CurveWarning: Equatable {
    enum Dir { case left, right }
    enum Level { case curve, sharp, hairpin }

    var dir: Dir
    var level: Level
    var tightening: Bool
    var radius: Double        // meters at the tightest point
    var advisoryMph: Int      // comfortable speed for this curve
    var distance: Double      // meters to the tightest point
    var apexLat: Double
    var apexLon: Double
    var since: Date

    private var side: String { dir == .left ? "left" : "right" }

    var title: String {
        if tightening { return "TIGHTENING \(side.uppercased())" }
        switch level {
        case .hairpin: return "HAIRPIN \(side.uppercased())"
        case .sharp: return "SHARP \(side.uppercased())"
        case .curve: return "\(side.uppercased()) CURVE"
        }
    }

    var spoken: String {
        var s: String
        if tightening { s = "Tightening \(side) ahead" }
        else {
            switch level {
            case .hairpin: s = "Hairpin \(side) ahead"
            case .sharp: s = "Sharp \(side) ahead"
            case .curve: s = "Curve \(side) ahead"
            }
        }
        if level != .curve { s += ". Slow to \(Units.speedTextFromMph(Double(advisoryMph), decimals: 0))" }
        return s
    }

    var symbol: String {
        let l = dir == .left
        if level == .hairpin { return l ? "arrow.uturn.left" : "arrow.uturn.right" }
        return l ? "arrow.turn.up.left" : "arrow.turn.up.right"
    }
}

/// Matches the rider to a road, reads the geometry ahead, and finds curves that are tight for the current speed.
final class CurveEngine {
    private var matched: (road: Road, seg: Int)?
    /// The road the rider is currently on (updated by every evaluate call)
    private(set) var current: (road: Road, forward: Bool)?
    private var recent: [(lat: Double, lon: Double, at: Date)] = []

    /// Spatial hash of road segments so a GPS fix only tests segments in the
    /// rider's 3×3 cells instead of every vertex in the 9-tile road set.
    private struct SegmentRef: Hashable {
        let road: Int
        let seg: Int
    }

    private struct IndexKey: Equatable {
        let roads: Int
        let vertices: Int
        let firstID: Int64
        let lastID: Int64
    }

    private struct RoadSpatialIndex {
        static let cellDegrees = 0.002      // ~220 m at mid latitudes
        private(set) var cells: [Int64: [SegmentRef]] = [:]
        private(set) var key: IndexKey

        init(roads: [Road]) {
            key = IndexKey(roads: roads.count,
                           vertices: roads.reduce(0) { $0 + $1.count },
                           firstID: roads.first?.id ?? 0,
                           lastID: roads.last?.id ?? 0)
            for (roadIndex, road) in roads.enumerated() where road.count >= 2 {
                for seg in 0..<(road.count - 1) {
                    let minLat = min(road.lat(seg), road.lat(seg + 1))
                    let maxLat = max(road.lat(seg), road.lat(seg + 1))
                    let minLon = min(road.lon(seg), road.lon(seg + 1))
                    let maxLon = max(road.lon(seg), road.lon(seg + 1))
                    let x0 = Int(floor(minLon / Self.cellDegrees))
                    let x1 = Int(floor(maxLon / Self.cellDegrees))
                    let y0 = Int(floor(minLat / Self.cellDegrees))
                    let y1 = Int(floor(maxLat / Self.cellDegrees))
                    let ref = SegmentRef(road: roadIndex, seg: seg)
                    for x in x0...x1 {
                        for y in y0...y1 {
                            cells[Self.key(x, y), default: []].append(ref)
                        }
                    }
                }
            }
        }

        static func key(_ x: Int, _ y: Int) -> Int64 {
            Int64(x + 200_000) * 1_000_000 + Int64(y + 100_000)
        }

        func candidates(latitude: Double, longitude: Double) -> [SegmentRef] {
            let x = Int(floor(longitude / Self.cellDegrees))
            let y = Int(floor(latitude / Self.cellDegrees))
            var seen = Set<SegmentRef>()
            var output: [SegmentRef] = []
            for dx in -1...1 {
                for dy in -1...1 {
                    for ref in cells[Self.key(x + dx, y + dy)] ?? [] where seen.insert(ref).inserted {
                        output.append(ref)
                    }
                }
            }
            return output
        }
    }

    private var spatialIndex: RoadSpatialIndex?

    private func index(for roads: [Road]) -> RoadSpatialIndex {
        let key = IndexKey(roads: roads.count,
                           vertices: roads.reduce(0) { $0 + $1.count },
                           firstID: roads.first?.id ?? 0,
                           lastID: roads.last?.id ?? 0)
        if let spatialIndex, spatialIndex.key == key { return spatialIndex }
        let built = RoadSpatialIndex(roads: roads)
        spatialIndex = built
        return built
    }

    private struct Proj {
        let lat0: Double, lon0: Double, kx: Double
        static let ky = 110_540.0
        init(_ c: CLLocationCoordinate2D) {
            lat0 = c.latitude; lon0 = c.longitude
            kx = 111_320.0 * cos(c.latitude * .pi / 180)
        }
        func xy(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            ((lon - lon0) * kx, (lat - lat0) * Self.ky)
        }
        func latlon(_ x: Double, _ y: Double) -> (lat: Double, lon: Double) {
            (lat0 + y / Self.ky, lon0 + x / kx)
        }
    }

    private struct Sample { let s: Double; let r: Double; let left: Bool }

    func evaluate(_ loc: CLLocation, roads: [Road], detectCurves: Bool = true) -> CurveWarning? {
        let v = loc.speed
        guard !roads.isEmpty else { return nil }
        let p = Proj(loc.coordinate)
        guard let m = locate(loc, roads, p) else { matched = nil; current = nil; return nil }
        matched = (m.road, m.seg)
        current = (m.road, m.forward)

        // Matching continues at any speed so speed limits and surface
        // warnings stay live at a red light. Curve detection still needs a
        // moving rider with a valid heading.
        guard detectCurves, v > 5, loc.course >= 0 else { return nil }
        let road = m.road
        let lookahead = min(max(v * 10, 200), 600)

        // 1. Path along the road ahead of the rider (meters, rider at origin)
        let a = p.xy(road.lat(m.seg), road.lon(m.seg))
        let b = p.xy(road.lat(m.seg + 1), road.lon(m.seg + 1))
        var pts = [(x: a.x + (b.x - a.x) * m.t, y: a.y + (b.y - a.y) * m.t)]
        var cum = [0.0]
        var i = m.forward ? m.seg + 1 : m.seg
        while i >= 0, i < road.count, cum[cum.count - 1] < lookahead + 20 {
            let q = p.xy(road.lat(i), road.lon(i))
            let last = pts[pts.count - 1]
            let d = hypot(q.x - last.x, q.y - last.y)
            if d > 0.5 { pts.append(q); cum.append(cum[cum.count - 1] + d) }
            i += m.forward ? 1 : -1
        }
        let total = cum[cum.count - 1]
        guard total >= 45 else { return nil }
        let P = pts, C = cum

        func pointAt(_ s: Double) -> (x: Double, y: Double) {
            var k = 1
            while k < C.count - 1 && C[k] < s { k += 1 }
            let len = C[k] - C[k - 1]
            let f = len > 0 ? min(max((s - C[k - 1]) / len, 0), 1) : 0
            return (P[k - 1].x + (P[k].x - P[k - 1].x) * f, P[k - 1].y + (P[k].y - P[k - 1].y) * f)
        }

        // 2. Radius of curvature every 10 m (circle through points 15 m before / at / 15 m after)
        var samples: [Sample] = []
        var s = 15.0
        while s + 15 <= total {
            let p0 = pointAt(s - 15), p1 = pointAt(s), p2 = pointAt(s + 15)
            let cross = (p1.x - p0.x) * (p2.y - p1.y) - (p1.y - p0.y) * (p2.x - p1.x)
            let la = hypot(p1.x - p0.x, p1.y - p0.y)
            let lb = hypot(p2.x - p1.x, p2.y - p1.y)
            let lc = hypot(p2.x - p0.x, p2.y - p0.y)
            let r = abs(cross) < 1e-3 ? 9999 : min(la * lb * lc / (2 * abs(cross)), 9999)
            samples.append(Sample(s: s, r: r, left: cross > 0))
            s += 10
        }

        // 3. Find curve regions (radius < 150 m) and check them against current speed
        let aLat = UserDefaults.standard.object(forKey: "alert.curveAccel") as? Double ?? 3.5   // m/s^2 lateral
        let now = Date()
        recent.removeAll { now.timeIntervalSince($0.at) > 120 }
        let threshold = 150.0
        var idx = 0
        while idx < samples.count {
            guard samples[idx].r < threshold else { idx += 1; continue }
            var j = idx, minI = idx
            while j < samples.count, samples[j].r < threshold {
                if samples[j].r < samples[minI].r { minI = j }
                j += 1
            }
            defer { idx = j }

            let rmin = samples[minI].r
            let regionLen = j - idx
            let tightening = regionLen >= 6 && minI >= idx + regionLen * 2 / 3
                && rmin < 0.6 * samples[(idx + minI) / 2].r
            let insideAtStart = idx == 0
            if insideAtStart && !(tightening && minI > 2) { continue }

            let vSafe = (aLat * rmin).squareRoot()
            guard v > vSafe * 0.85 else { continue }

            let dStart = insideAtStart ? samples[minI].s : samples[idx].s
            let dBrake = max(0, (v * v - vSafe * vSafe) / 6)          // ~3 m/s^2 braking
            let warnDist = min(max(dBrake + v * 4, 80), 450)
            guard dStart <= warnDist else { return nil }              // later regions are even farther

            let apexPt = pointAt(samples[minI].s)
            let apex = p.latlon(apexPt.x, apexPt.y)
            let isRepeat = recent.contains { r in
                let q = p.xy(r.lat, r.lon)
                return hypot(q.x - apexPt.x, q.y - apexPt.y) < 80
            }
            if isRepeat { continue }

            recent.append((apex.lat, apex.lon, now))
            let level: CurveWarning.Level = rmin < 30 ? .hairpin : (rmin < 70 ? .sharp : .curve)
            let mph = max(10, Int((vSafe * 2.23694 / 5).rounded()) * 5)
            return CurveWarning(dir: samples[minI].left ? .left : .right, level: level,
                                tightening: tightening, radius: rmin, advisoryMph: mph,
                                distance: samples[minI].s, apexLat: apex.lat, apexLon: apex.lon, since: now)
        }
        return nil
    }

    // MARK: Map matching
    private func locate(_ loc: CLLocation, _ roads: [Road], _ p: Proj)
        -> (road: Road, seg: Int, forward: Bool, t: Double)? {

        func score(_ road: Road, _ i: Int) -> (d: Double, t: Double, forward: Bool)? {
            let a = p.xy(road.lat(i), road.lon(i)), b = p.xy(road.lat(i + 1), road.lon(i + 1))
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            guard len2 > 0.01 else { return nil }
            let t = min(max(-(a.x * dx + a.y * dy) / len2, 0), 1)       // rider is at (0,0)
            let px = a.x + t * dx, py = a.y + t * dy
            let d = (px * px + py * py).squareRoot()
            // A stopped rider often has course == -1. Distance is enough in
            // that case; direction only disambiguates when we have a heading.
            guard loc.course >= 0 else { return (d, t, true) }
            let bearing = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let diff = Geo.angleDiff(bearing, loc.course)
            if diff <= 50 { return (d, t, true) }
            if diff >= 130 { return (d, t, false) }
            return nil
        }

        // Stay on the road we were already matched to when possible
        if let m = matched, m.road.count >= 2 {
            var best: (seg: Int, d: Double, t: Double, fwd: Bool)?
            for i in max(0, m.seg - 2)...min(m.road.count - 2, m.seg + 3) {
                if let s = score(m.road, i), s.d < 30, best == nil || s.d < best!.d { best = (i, s.d, s.t, s.forward) }
            }
            if let b = best { return (m.road, b.seg, b.fwd, b.t) }
        }

        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        let index = index(for: roads)
        var best: (road: Road, seg: Int, d: Double, t: Double, fwd: Bool)?
        for ref in index.candidates(latitude: lat, longitude: lon) {
            guard ref.road < roads.count else { continue }
            let road = roads[ref.road]
            guard ref.seg + 1 < road.count else { continue }
            if let s = score(road, ref.seg), s.d < 25, best == nil || s.d < best!.d {
                best = (road, ref.seg, s.d, s.t, s.forward)
            }
        }
        guard let b = best else { return nil }
        return (b.road, b.seg, b.fwd, b.t)
    }
}
