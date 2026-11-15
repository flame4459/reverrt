import SwiftUI
import MapKit
import CoreLocation

/// One point of a shared replay. Kept small because it travels inside a link.
nonisolated struct SharedRidePoint: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var elapsed: Double
    var speedMps: Double
    var leanDegrees: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Compact binary encoding of a ride track for sharing.
///
/// A full `RidePoint` record is mostly repeated JSON keys and Dates. A link
/// can carry the replay if the track is downsampled and quantised: a version
/// byte, a point count, then 15 bytes per point (5 decimal places of
/// latitude/longitude, seconds, speed and lean). Seventy-two points is about
/// 1.6 kB after base64, which is a link a messaging app can carry.
nonisolated enum RideTrackCodec {
    static let version: UInt8 = 1
    static let defaultLimit = 72

    static func encode(_ points: [RidePoint], limit: Int = defaultLimit) -> Data? {
        let valid = points.filter {
            $0.lat.isFinite && $0.lon.isFinite
                && abs($0.lat) <= 90 && abs($0.lon) <= 180
        }
        guard !valid.isEmpty else { return nil }
        let sampled = sample(valid, limit: max(2, limit))
        guard let first = sampled.first else { return nil }

        let stored = Array(sampled.prefix(Int(UInt16.max)))
        var data = Data()
        data.append(version)
        append(UInt16(stored.count), to: &data)

        let base = first.time
        for point in stored {
            append(Int32((point.lat * 100_000).rounded()), to: &data)
            append(Int32((point.lon * 100_000).rounded()), to: &data)

            let seconds = point.time.timeIntervalSince(base)
            let elapsed = UInt32(min(max(seconds, 0), Double(UInt32.max)).rounded())
            append(elapsed, to: &data)

            let speed = UInt16(min(max(point.speed * 10, 0), 6_553.5).rounded())
            append(speed, to: &data)

            let lean = Int8(min(max((point.lean ?? 0).rounded(), -90), 90))
            append(lean, to: &data)
        }
        return data
    }

    static func decode(_ data: Data) -> [SharedRidePoint]? {
        guard data.count >= 3 else { return nil }
        return data.withUnsafeBytes { raw -> [SharedRidePoint]? in
            var offset = 0
            func read<T: FixedWidthInteger>(_ type: T.Type) -> T? {
                let size = MemoryLayout<T>.size
                guard offset + size <= raw.count else { return nil }
                let value = raw.loadUnaligned(fromByteOffset: offset, as: T.self)
                offset += size
                return T(littleEndian: value)
            }

            guard let fileVersion: UInt8 = read(UInt8.self), fileVersion == version,
                  let count: UInt16 = read(UInt16.self), count > 0, count <= 4_096 else {
                return nil
            }

            var points: [SharedRidePoint] = []
            points.reserveCapacity(Int(count))
            for _ in 0..<count {
                guard let latitude: Int32 = read(Int32.self),
                      let longitude: Int32 = read(Int32.self),
                      let elapsed: UInt32 = read(UInt32.self),
                      let speed: UInt16 = read(UInt16.self),
                      let lean: Int8 = read(Int8.self) else { return nil }

                let lat = Double(latitude) / 100_000
                let lon = Double(longitude) / 100_000
                guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
                points.append(SharedRidePoint(
                    latitude: lat,
                    longitude: lon,
                    elapsed: Double(elapsed),
                    speedMps: Double(speed) / 10,
                    leanDegrees: Double(lean)
                ))
            }
            return points
        }
    }

    private static func sample(_ points: [RidePoint], limit: Int) -> [RidePoint] {
        guard points.count > limit, limit > 1 else { return points }
        var sampled: [RidePoint] = []
        var previous = -1
        for step in 0..<limit {
            let index = Int((Double(step) * Double(points.count - 1) / Double(limit - 1)).rounded())
            if index != previous {
                sampled.append(points[index])
                previous = index
            }
        }
        if let last = points.last, sampled.last?.time != last.time {
            sampled.append(last)
        }
        return sampled
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

// MARK: - Replay

/// Watch the route a friend sent in a Rivals link.
struct SharedRideReplayView: View {
    let result: RivalResult
    var isLocal = false

    @Environment(\.dismiss) private var dismiss
    @State private var points: [SharedRidePoint] = []
    @State private var index = 0
    @State private var playing = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var loaded = false

    private var current: SharedRidePoint? {
        points.indices.contains(index) ? points[index] : points.first
    }

    private var progress: Double {
        points.count > 1 ? Double(index) / Double(points.count - 1) : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mapCard
                    header
                    if points.isEmpty {
                        emptyState
                    } else {
                        playbackCard
                    }
                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .pulseBackground()
            .navigationTitle("Ride replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        RevertHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close replay")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { load() }
        .task(id: playing) { await runPlayback() }
        .onDisappear { playing = false }
    }

    private var mapCard: some View {
        Map(position: $camera) {
            if points.count > 1 {
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(MapUI.cyan.opacity(0.25), lineWidth: 9)
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(MapUI.aurora, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let first = points.first {
                Annotation("Start", coordinate: first.coordinate, anchor: .center) {
                    Circle()
                        .fill(MapUI.emerald)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 2))
                }
            }
            if let last = points.last, points.count > 1 {
                Annotation("Finish", coordinate: last.coordinate, anchor: .center) {
                    Image(systemName: "flag.checkered")
                        .font(.scaledSystem(size: 11, weight: .bold))
                        .foregroundStyle(MapUI.pitchBlack)
                        .frame(width: 22, height: 22)
                        .background(MapUI.amber, in: Circle())
                }
            }
            if let current {
                Annotation("Rider", coordinate: current.coordinate, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(MapUI.pitchBlack)
                            .frame(width: 34, height: 34)
                        Image(systemName: "motorcycle.fill")
                            .font(.scaledSystem(size: 15, weight: .bold))
                            .foregroundStyle(MapUI.cyan)
                        Circle()
                            .stroke(MapUI.cyan, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }
                    .shadow(color: MapUI.cyan.opacity(0.55), radius: 9)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .frame(height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MapUI.line, lineWidth: 0.8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: isLocal ? "motorcycle" : "person.2.fill")
                    .font(.scaledSystem(size: 10, weight: .bold))
                Text(isLocal ? "YOUR RIDE" : "SHARED BY \(result.rider.uppercased())")
                    .tracking(1.4)
            }
            .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(MapUI.cyan)

            Text(result.routeName)
                .font(RevertType.display(24, weight: .heavy))
                .foregroundStyle(MapUI.ink)
                .lineLimit(2)

            Text(result.date.formatted(date: .complete, time: .shortened))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
        }
    }

    private var playbackCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    RevertHaptics.tap()
                    if index >= points.count - 1 { index = 0 }
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.scaledSystem(size: 16, weight: .bold))
                        .foregroundStyle(MapUI.pitchBlack)
                        .frame(width: 44, height: 44)
                        .background(MapUI.aurora, in: Circle())
                }
                .accessibilityLabel(playing ? "Pause replay" : "Play replay")

                Slider(
                    value: Binding(
                        get: { Double(index) },
                        set: { value in
                            playing = false
                            index = min(max(Int(value.rounded()), 0), max(points.count - 1, 0))
                        }
                    ),
                    in: 0...Double(max(points.count - 1, 1))
                )
                .tint(MapUI.cyan)
                .accessibilityLabel("Replay position")

                Text(Units.clock(current?.elapsed ?? 0))
                    .font(RevertType.number(13))
                    .foregroundStyle(MapUI.ink)
                    .monospacedDigit()
                    .frame(minWidth: 52, alignment: .trailing)
            }

            RevertProgressBar(value: progress, tint: MapUI.aurora, height: 3)

            HStack(spacing: 0) {
                replayStat("SPEED", Units.speedText(current?.speedMps ?? 0, decimals: 0))
                replayStat("LEAN", "\(Int((current?.leanDegrees ?? 0).rounded()))°")
                replayStat("RIDE TIME", Units.clock(result.durationSeconds))
            }
        }
        .revertCard()
    }

    private func replayStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(MapUI.textTertiary)
            Text(value)
                .font(RevertType.number(15))
                .foregroundStyle(MapUI.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            RevertSectionLabel(title: isLocal ? "This ride" : "The ride they sent")

            RevertKeyValueRow(label: "Time", value: Units.clock(result.durationSeconds))
            RevertKeyValueRow(label: "Distance", value: Units.distanceText(result.distanceMeters, decimals: 1))
            RevertKeyValueRow(label: "Top speed", value: Units.speedText(result.maxSpeedMps, decimals: 0))
            RevertKeyValueRow(label: "Max lean", value: "\(Int(result.maxLeanDegrees.rounded()))°")

            Rectangle().fill(MapUI.line).frame(height: 0.8)

            Text(isLocal
                 ? "Rendered from the track recorded on this iPhone."
                 : "This is the GPS track the rider chose to include with the link. The replay never leaves this iPhone.")
                .font(.scaledSystem(size: 10, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .revertCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No replay in this link")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(MapUI.ink)
            Text("This result was shared as a time only. Ask the rider to resend it with the replay attached.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .revertCard()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let track = result.track else { return }
        points = RideTrackCodec.decode(track) ?? []
        fitCamera()
        if points.count > 1 {
            index = 0
            playing = true
        }
    }

    private func fitCamera() {
        guard let minLat = points.map(\.latitude).min(),
              let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(),
              let maxLon = points.map(\.longitude).max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.004)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func runPlayback() async {
        guard playing, points.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, playing else { return }
            if index >= points.count - 1 {
                playing = false
                return
            }
            index += 1
        }
    }
}
