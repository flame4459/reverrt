import Foundation
import CoreLocation
import UniformTypeIdentifiers

enum GPX {
    static var contentTypes: [UTType] {
        [UTType(filenameExtension: "gpx"), UTType.xml].compactMap { $0 }
    }

    // MARK: Export
    static func export(_ ride: Ride) -> String {
        export(points: ride.points, startDate: ride.startDate)
    }

    /// Pure formatter so it can run off the main actor for long tracks.
    nonisolated static func export(points: [RidePoint], startDate: Date) -> String {
        let f = ISO8601DateFormatter()
        let title = startDate.formatted(date: .abbreviated, time: .shortened)
        var lines: [String] = []
        lines.reserveCapacity(points.count + 6)
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        lines.append("<gpx version=\"1.1\" creator=\"RevertApp\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:revert=\"https://revert.app/gpx/1\">\n")
        lines.append("  <metadata><time>\(f.string(from: startDate))</time></metadata>\n")
        lines.append("  <trk>\n    <name>\(escape(title))</name>\n    <trkseg>\n")
        for p in points {
            let ele = String(format: "%.1f", p.alt)
            var line = "      <trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(ele)</ele><time>\(f.string(from: p.time))</time>"
            if let lean = p.lean, lean.isFinite {
                line += "<extensions><revert:lean>\(String(format: "%.1f", lean))</revert:lean></extensions>"
            }
            line += "</trkpt>\n"
            lines.append(line)
        }
        lines.append("    </trkseg>\n  </trk>\n</gpx>\n")
        return lines.joined()
    }

    static func writeTempFile(for ride: Ride) -> URL? {
        writeTempFile(points: ride.points, startDate: ride.startDate)
    }

    nonisolated static func writeTempFile(points: [RidePoint], startDate: Date) -> URL? {
        removeOldTempFiles()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ride \(df.string(from: startDate)).gpx")
        do {
            try export(points: points, startDate: startDate).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    /// Previous versions left one .gpx per ride-detail visit in tmp forever.
    /// Keep the newest day's files and remove the rest.
    nonisolated static func removeOldTempFiles() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: fm.temporaryDirectory,
                                                     includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        for url in urls where url.pathExtension.lowercased() == "gpx" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    nonisolated private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Import

    /// A parsed track, free of SwiftData so the XML work can run off-main.
    nonisolated struct ImportedTrack: Sendable {
        let points: [RidePoint]
        let distanceMeters: Double
        let maxSpeedMps: Double
        let elevationGainMeters: Double
        let durationSeconds: Double

        var startDate: Date { points.first?.time ?? Date() }
        var endDate: Date { points.last?.time ?? startDate }

        func makeRide() -> Ride {
            Ride(startDate: startDate,
                 endDate: endDate,
                 distanceMeters: distanceMeters,
                 maxSpeedMps: maxSpeedMps,
                 elevationGainMeters: elevationGainMeters,
                 durationSeconds: durationSeconds,
                 points: points)
        }
    }

    /// Parses the XML only. Safe to call from a background task.
    nonisolated static func parseTrack(from data: Data) -> ImportedTrack? {
        let parser = GPXParser()
        guard parser.parse(data), parser.points.count > 1 else { return nil }
        let raw = parser.points
        let hasTimes = raw.allSatisfy { $0.time != nil }
        let base = Date()

        var points: [RidePoint] = []
        var distance = 0.0, maxSpeed = 0.0, gain = 0.0
        var altRef: Double?
        var prev: CLLocation?
        var prevTime: Date?

        for p in raw {
            let time = p.time ?? base
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            var speed = 0.0
            if let pl = prev, let pt = prevTime {
                let d = loc.distance(from: pl)
                distance += d
                let dt = time.timeIntervalSince(pt)
                if hasTimes, dt >= 0.5 { speed = min(d / dt, 90) }
            }
            maxSpeed = max(maxSpeed, speed)
            if let ele = p.ele {
                if let ref = altRef {
                    let diff = ele - ref
                    if diff >= 3 { gain += diff; altRef = ele }
                    else if diff <= -3 { altRef = ele }
                } else { altRef = ele }
            }
            points.append(RidePoint(lat: p.lat, lon: p.lon, alt: p.ele ?? 0,
                                    speed: speed, time: time, lean: p.lean))
            prev = loc
            prevTime = time
        }

        guard let start = points.first?.time, let end = points.last?.time else { return nil }
        return ImportedTrack(
            points: points,
            distanceMeters: distance,
            maxSpeedMps: maxSpeed,
            elevationGainMeters: gain,
            durationSeconds: hasTimes ? max(end.timeIntervalSince(start), 0) : 0
        )
    }

    static func importRide(from data: Data) -> Ride? {
        parseTrack(from: data)?.makeRide()
    }
}

/// Parsing runs on a background task, so the delegate is deliberately opted
/// out of the project's default main-actor isolation. `XMLParser` calls every
/// delegate method synchronously on the thread that started `parse(_:)`.
nonisolated final class GPXParser: NSObject, XMLParserDelegate {
    struct Pt { var lat: Double; var lon: Double; var ele: Double?; var time: Date?; var lean: Double? }

    private(set) var points: [Pt] = []
    private var current: Pt?
    private var text = ""
    private let plain = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func parse(_ data: Data) -> Bool {
        let p = XMLParser(data: data)
        p.delegate = self
        return p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "trkpt" || elementName == "rtept",
           let lat = Double(attributeDict["lat"] ?? ""), let lon = Double(attributeDict["lon"] ?? "") {
            current = Pt(lat: lat, lon: lon)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Extension elements are written with the `revert:` prefix. XMLParser
        // reports the qualified name, so `revert:lean` never matched "lean" and
        // the lean angle was silently dropped on import.
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch localName {
        case "ele": current?.ele = Double(t)
        case "lean": current?.lean = Double(t)
        case "time": if current != nil { current?.time = fractional.date(from: t) ?? plain.date(from: t) }
        case "trkpt", "rtept":
            if let c = current { points.append(c) }
            current = nil
        default: break
        }
    }
}
