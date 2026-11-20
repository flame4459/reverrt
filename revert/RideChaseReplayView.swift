import SwiftUI
import MapKit
import CoreLocation

/// A cinematic chase replay: the map camera sits behind and above the rider,
/// moving with the recorded heading, while the supplied pixel rider leans and
/// tucks with the telemetry.
struct RideChaseReplayView: View {
    let ride: Ride
    @Environment(\.dismiss) private var dismiss

    @State private var elapsed: TimeInterval = 0
    @State private var isPlaying = false
    @State private var playbackRate = 8.0
    @State private var camera: MapCameraPosition = .automatic
    @State private var playbackTask: Task<Void, Never>?
    @State private var didStart = false

    private var points: [RidePoint] { ride.points }
    private var duration: TimeInterval {
        guard let first = points.first?.time, let last = points.last?.time else { return 1 }
        return max(last.timeIntervalSince(first), 1)
    }
    private var sample: ChaseReplaySample? {
        ChaseReplaySample.at(points: points, elapsed: elapsed)
    }
    private var spriteName: String {
        guard let sample else { return "chase-rider-straight" }
        if sample.lean > 10 { return "chase-rider-right" }
        if sample.lean < -10 { return "chase-rider-left" }
        if sample.speed > 22 { return "chase-rider-tuck" }
        return "chase-rider-straight"
    }
    var body: some View {
        ZStack {
            if points.count > 1 {
                Map(position: $camera) {
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(Color.black.opacity(0.38), lineWidth: 10)
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(MapUI.cyan.opacity(0.32), style: StrokeStyle(lineWidth: 4,
                                                                            lineCap: .round,
                                                                            lineJoin: .round))
                    if let sample {
                        let ahead = Array(points[sample.index..<min(points.count, sample.index + 55)])
                        if ahead.count > 1 {
                            MapPolyline(coordinates: ahead.map(\.coordinate))
                                .stroke(LinearGradient(colors: [MapUI.cyan, MapUI.emerald],
                                                       startPoint: .leading, endPoint: .trailing),
                                        style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat,
                                    emphasis: .muted,
                                    pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    ChaseRiderSprite(name: spriteName)
                        .padding(.bottom, 142)
                        .allowsHitTesting(false)
                }
                .overlay { cinematicOverlay }
                .overlay(alignment: .top) { topBar }
                .overlay(alignment: .bottom) { bottomBar }
            } else {
                emptyState
            }
        }
        .background(MapUI.pitchBlack)
        .preferredColorScheme(.dark)
        .onAppear {
            guard points.count > 1 else { return }
            if !didStart {
                didStart = true
                if elapsed >= duration { elapsed = 0 }
                updateCamera(animated: false)
                start()
            }
        }
        .onDisappear { pause() }
    }

    private var cinematicOverlay: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.62), .clear, .clear, .black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.clear, .black.opacity(0.42)],
                           center: .center, startRadius: 150, endRadius: 520)
                .blendMode(.multiply)
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    RevertHaptics.tap()
                    pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.8))
                }
                .accessibilityLabel("Close drone replay")

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("DRONE REPLAY")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(alignment: .top, spacing: 0) {
                telemetry(Units.speedText(sample?.speed ?? 0), "SPEED")
                telemetry("\(Int(abs(sample?.lean ?? 0).rounded()))°", "LEAN")
                telemetry(Units.elevationText(sample?.altitude ?? 0), "ELEVATION")
            }
            .padding(12)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.8)
            }

            HStack(spacing: 5) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("CHASING \(ride.routeName ?? "RIDE")")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .lineLimit(1)
            }
            .foregroundStyle(MapUI.cyan.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    isPlaying ? pause() : start()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(MapUI.cyan, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause replay" : "Play replay")

                VStack(alignment: .leading, spacing: 1) {
                    Text("LIVE CHASE")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(MapUI.cyan)
                    Text("\(Units.clock(elapsed)) / \(Units.clock(duration))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    playbackRate = nextRate(playbackRate)
                    RevertHaptics.tap()
                } label: {
                    Text("\(Int(playbackRate))×")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 34)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .accessibilityLabel("Playback speed \(Int(playbackRate)) times")
            }

            Slider(value: Binding(
                get: { elapsed },
                set: { value in
                    elapsed = value
                    updateCamera(animated: false)
                }
            ), in: 0...duration, onEditingChanged: { editing in
                if editing { pause() }
            })
            .tint(MapUI.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(MapUI.textTertiary)
            Text("Not enough track for a chase")
                .font(PulseType.display(24))
                .foregroundStyle(.white)
            Button("Close") { dismiss() }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
        }
        .pulseBackground()
    }

    private func telemetry(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start() {
        guard points.count > 1 else { return }
        if elapsed >= duration { elapsed = 0 }
        isPlaying = true
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            var last = Date()
            while !Task.isCancelled, isPlaying {
                let now = Date()
                let delta = min(max(now.timeIntervalSince(last), 0), 0.12)
                last = now
                elapsed = min(elapsed + delta * playbackRate, duration)
                updateCamera(animated: true)
                if elapsed >= duration {
                    isPlaying = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func nextRate(_ current: Double) -> Double {
        switch current {
        case ..<2: 4
        case ..<6: 8
        case ..<12: 16
        default: 1
        }
    }

    private func updateCamera(animated: Bool) {
        guard let sample else { return }
        let center = ChaseReplaySample.destination(from: sample.coordinate,
                                                  meters: 55,
                                                  heading: sample.heading)
        let distance = 560 + min(max(sample.speed, 0) * 3.0, 160)
        let next = MapCameraPosition.camera(MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: sample.heading,
            pitch: 45
        ))
        if animated {
            withAnimation(.linear(duration: 0.1)) { camera = next }
        } else {
            camera = next
        }
    }
}

private struct ChaseRiderSprite: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(height: 128)
            .accessibilityLabel("Top-down rider")
    }
}

private struct ChaseReplaySample {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let lean: Double
    let speed: Double
    let altitude: Double
    let index: Int

    static func at(points: [RidePoint], elapsed: TimeInterval) -> ChaseReplaySample? {
        guard let first = points.first else { return nil }
        let target = first.time.addingTimeInterval(max(elapsed, 0))
        if target <= first.time {
            return sample(points: points, index: 0, next: min(1, points.count - 1), t: 0)
        }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            if target <= b.time {
                let span = max(b.time.timeIntervalSince(a.time), 0.001)
                let t = min(max(target.timeIntervalSince(a.time) / span, 0), 1)
                return sample(points: points, index: index - 1, next: index, t: t)
            }
        }
        return sample(points: points, index: max(points.count - 1, 0),
                      next: max(points.count - 1, 0), t: 0)
    }

    private static func sample(points: [RidePoint], index: Int, next: Int, t: Double) -> ChaseReplaySample {
        let a = points[index], b = points[next]
        let coordinate = CLLocationCoordinate2D(
            latitude: a.lat + (b.lat - a.lat) * t,
            longitude: a.lon + (b.lon - a.lon) * t
        )
        let heading = bearing(from: a.coordinate, to: b.coordinate)
        return ChaseReplaySample(
            coordinate: coordinate,
            heading: heading,
            lean: (a.lean ?? 0) + ((b.lean ?? 0) - (a.lean ?? 0)) * t,
            speed: a.speed + (b.speed - a.speed) * t,
            altitude: a.alt + (b.alt - a.alt) * t,
            index: t >= 0.5 ? next : index
        )
    }

    static func destination(from coordinate: CLLocationCoordinate2D,
                            meters: Double, heading: Double) -> CLLocationCoordinate2D {
        let radians = heading * .pi / 180
        let latitudeRadians = coordinate.latitude * .pi / 180
        let dLat = meters / 111_320 * cos(radians)
        let dLon = meters / (111_320 * max(cos(latitudeRadians), 0.01)) * sin(radians)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat,
                                      longitude: coordinate.longitude + dLon)
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
