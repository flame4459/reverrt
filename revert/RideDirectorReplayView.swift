import SwiftUI
import MapKit
import SwiftData
import CoreLocation

/// Director mode: a short, auto-cut film made from the recorded ride.
struct RideDirectorReplayView: View {
    let ride: Ride
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ride.startDate, order: .reverse) private var pastRides: [Ride]

    @State private var film: ReplayFilm
    @State private var filmTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var playbackRate = 1.0
    @State private var camera: MapCameraPosition = .automatic
    @State private var playbackTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var didStart = false
    @State private var soundOn = false
    @State private var ghost: GhostTrack?
    @State private var showExportError = false
    @State private var exporting = false
    @State private var cutFlash = false
    @State private var lastShotID = -1
    @State private var lastFrameAt = Date()
    @State private var smoothed: SmoothedCamera?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var satellite = false
    @State private var audio: ReplayAudioEngine?
    @StateObject private var exporter = ReplayExporter()

    private let rideStart: Date
    private let cumulative: [Double]

    init(ride: Ride) {
        self.ride = ride
        _film = State(initialValue: ReplayFilm.make(ride: ride))
        let points = ride.points
        self.rideStart = points.first?.time ?? ride.startDate
        var running = 0.0
        var distances: [Double] = [0]
        for index in 1..<max(points.count, 1) {
            let a = points[index - 1], b = points[index]
            running += CLLocation(latitude: a.lat, longitude: a.lon)
                .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
            distances.append(running)
        }
        self.cumulative = distances
    }

    var body: some View {
        ZStack {
            if film.shots.isEmpty {
                emptyState
            } else {
                mapView
                if let current, !current.shot.kind.isOverview {
                    VStack {
                        Spacer()
                        ZStack {
                            DirectorRiderSprite(assetName: current.assetName, height: 116)
                                .id(current.assetName)
                                .transition(.opacity)
                        }
                        .animation(.easeInOut(duration: 0.18), value: current.assetName)
                        .offset(x: min(max(current.sample.lean, -30), 30) * 0.35)
                        .scaleEffect(1 + min(max(current.sample.speed - 5, 0) / 180, 0.06))
                        .animation(.easeOut(duration: 0.18), value: current.sample.lean)
                        .animation(.easeOut(duration: 0.25), value: current.sample.speed)
                        .padding(.bottom, 154)
                    }
                    .allowsHitTesting(false)
                }
                DirectorFilmOverlay(filmTime: filmTime,
                                    speed: current?.sample.speed ?? 0,
                                    shot: current?.shot)
                cutFlashOverlay
                if !controlsVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { showControls() }
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "eye")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.38))
                                .padding(.trailing, 18)
                                .padding(.bottom, 20)
                        }
                    }
                    .allowsHitTesting(false)
                }
                if exporting {
                    recordingBadge
                }
            }
        }
        .overlay(alignment: .top) {
            if !film.shots.isEmpty {
                topBar
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
            }
        }
        .overlay(alignment: .bottom) {
            if !film.shots.isEmpty {
                bottomBar
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
            }
        }
        .overlay(alignment: .center) {
            if !film.shots.isEmpty {
                titleCard
                    .padding(.bottom, 190)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !film.shots.isEmpty {
                shotCaption
                    .padding(.leading, 16)
                    .padding(.bottom, 216)
            }
        }
        .background(MapUI.pitchBlack)
        .preferredColorScheme(.dark)
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        .onChange(of: soundOn) { _, on in
            if on { startAudio() } else { stopAudio() }
        }
        .sheet(item: $exporter.preview, onDismiss: { exporter.preview = nil }) { item in
            ReplayPreviewSheet(controller: item.controller)
                .ignoresSafeArea()
        }
        .alert("Couldn’t export the film", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exporter.error ?? "Screen recording is unavailable.")
        }
    }

    // MARK: Map

    private var mapView: some View {
        Map(position: $camera) {
            MapPolyline(coordinates: ride.points.map(\.coordinate))
                .stroke(Color.black.opacity(0.42), lineWidth: 13)
            MapPolyline(coordinates: ride.points.map(\.coordinate))
                .stroke(MapUI.cyan.opacity(0.23), style: StrokeStyle(lineWidth: 4,
                                                                     lineCap: .round,
                                                                     lineJoin: .round))
            if let current {
                let start = max(0, current.sample.index - 30)
                let end = min(ride.points.count, current.sample.index + 70)
                if start < end {
                    let behind = Array(ride.points[start..<min(current.sample.index + 1, end)])
                    let ahead = Array(ride.points[min(current.sample.index, end - 1)..<end])
                    if behind.count > 1 {
                        MapPolyline(coordinates: behind.map(\.coordinate))
                            .stroke(MapUI.emerald.opacity(0.32), lineWidth: 3)
                    }
                    if ahead.count > 1 {
                        MapPolyline(coordinates: ahead.map(\.coordinate))
                            .stroke(LinearGradient(colors: [MapUI.cyan, MapUI.emerald],
                                                   startPoint: .leading, endPoint: .trailing),
                                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    }
                }

                if let moment = current.shot.moment {
                    Annotation("Apex", coordinate: moment.coordinate, anchor: .center) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MapUI.amber)
                            .padding(4)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .annotationTitles(.hidden)
                }
            }

        }
        .mapStyle(satellite
                  ? .imagery(elevation: .flat)
                  : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
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
                .accessibilityLabel("Close director film")

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("DIRECTOR MODE")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                }
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.ultraThinMaterial, in: Capsule())

                Button {
                    satellite.toggle()
                } label: {
                    Image(systemName: satellite ? "globe.americas.fill" : "map")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(satellite ? "Use the dark map" : "Use satellite imagery")

                Button {
                    soundOn.toggle()
                } label: {
                    Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(soundOn ? "Mute replay sound" : "Enable replay sound")
            }

            if let current {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: current.shot.kind.icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MapUI.cyan)
                    Text(current.shot.title.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let delta = ghostDelta {
                        Text(delta >= 0 ? "GHOST +\(Units.distanceText(abs(delta), decimals: 1))"
                             : "GHOST -\(Units.distanceText(abs(delta), decimals: 1))")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(delta >= 0 ? MapUI.emerald : MapUI.amber)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(.black.opacity(0.30), in: Capsule())
            }

            if let current {
                HStack(alignment: .top, spacing: 0) {
                    metric(Units.speedText(current.sample.speed), "SPEED")
                    metric("\(Int(abs(current.sample.lean).rounded()))°", "LEAN")
                    metric(Units.elevationText(current.sample.altitude), "ELEVATION")
                }
                .padding(11)
                .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func metric(_ value: String, _ label: String) -> some View {
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

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 7) {
            if let current {
                HStack(spacing: 8) {
                    Button {
                        isPlaying ? pause() : start()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 46, height: 46)
                            .background(MapUI.cyan, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause film" : "Play film")

                    VStack(alignment: .leading, spacing: 1) {
                        Text(current.shot.kind == .establishing ? "OPENING" : "FILM")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(MapUI.cyan)
                        Text("\(Units.clock(filmTime)) / \(Units.clock(film.duration))")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 4)

                    Button {
                        playbackRate = nextRate(playbackRate)
                    } label: {
                        Text("\(playbackRate == 0.5 ? "½" : String(format: "%.0f", playbackRate))×")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 32)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("Film speed \(playbackRate) times")

                    Menu {
                        Button("Play from the start") { seek(to: 0); start() }
                        Divider()
                        ForEach(film.shots) { shot in
                            Button {
                                seek(to: film.startTime(of: shot))
                            } label: {
                                Label(shot.title, systemImage: shot.kind.icon)
                            }
                        }
                        if !film.highlights.isEmpty {
                            Divider()
                            ForEach(Array(film.highlights.enumerated()), id: \.element.id) { index, moment in
                                Button {
                                    if let shot = film.shots.first(where: { $0.moment?.id == moment.id }) {
                                        seek(to: film.startTime(of: shot))
                                    }
                                } label: {
                                    Label("Corner \(index + 1) · \(moment.label)", systemImage: "scope")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 32)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .accessibilityLabel("Film chapters")

                    Button {
                        exportFilm()
                    } label: {
                        Image(systemName: exporting ? "record.circle.fill" : "square.and.arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(exporting ? MapUI.amber : .white)
                            .frame(width: 36, height: 32)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .disabled(exporting)
                    .accessibilityLabel("Export film")
                }

                DirectorTelemetryTrace(ride: ride, film: film, elapsed: current.elapsed)
                    .frame(height: 32)
                    .padding(.horizontal, 2)

                DirectorScrubber(film: film, filmTime: $filmTime) { time in
                    seek(to: time)
                }
                .frame(height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var shotCaption: some View {
        Group {
            if let current, !current.shot.kind.isOverview {
                let start = film.startTime(of: current.shot)
                let age = filmTime - start
                let opacity = min(min(1, age / 0.18), min(1, max(0, (2.2 - age) / 0.45)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: current.shot.kind.icon)
                            .font(.system(size: 8, weight: .bold))
                        Text(current.shot.kind.title.uppercased())
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                    }
                    .foregroundStyle(MapUI.cyan)
                    Text(current.shot.moment?.label ?? film.routeName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var titleCard: some View {
        Group {
            if let current, current.shot.kind.isOverview {
                DirectorTitleCard(film: film, shot: current.shot, progress: current.progress)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var cutFlashOverlay: some View {
        Color.black.opacity(cutFlash ? 0.22 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.14), value: cutFlash)
    }

    private var recordingBadge: some View {
        VStack {
            HStack(spacing: 5) {
                Circle().fill(MapUI.danger).frame(width: 6, height: 6)
                Text("REC")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.top, 58)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.slash")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(MapUI.textTertiary)
            Text("No track to direct")
                .font(PulseType.display(24))
                .foregroundStyle(.white)
            Button("Close") { dismiss() }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
        }
        .pulseBackground()
    }

    // MARK: Current frame

    private struct SmoothedCamera {
        var center: CLLocationCoordinate2D
        var heading: Double
        var distance: Double
        var pitch: Double
    }

    private struct CurrentFrame {
        let shot: FilmShot
        let progress: Double
        let elapsed: TimeInterval
        let sample: DirectorSample
        let plan: DirectorCameraPlan
        let assetName: String
    }

    private var current: CurrentFrame? {
        guard let found = film.shot(at: filmTime),
              let sample = DirectorSample.at(points: ride.points, elapsed: found.elapsed) else {
            return nil
        }
        let plan: DirectorCameraPlan
        if found.shot.kind.isOverview {
            let overview = routeOverview
            plan = DirectorCamera.overview(center: overview.center,
                                           distance: overview.distance,
                                           heading: sample.heading)
        } else {
            plan = DirectorCamera.plan(shot: found.shot, sample: sample,
                                       progress: found.progress, route: nil,
                                       ahead: lookAheadCoordinate(after: sample))
        }
        let asset = RiderSpriteAtlas.assetName(forRiderHeading: sample.heading,
                                               cameraHeading: plan.heading,
                                               lean: sample.lean)
        return CurrentFrame(shot: found.shot, progress: found.progress,
                            elapsed: found.elapsed, sample: sample,
                            plan: plan, assetName: asset)
    }

    private var routeOverview: (center: CLLocationCoordinate2D, distance: Double) {
        let points = ride.points
        guard let first = points.first?.coordinate else {
            return (CLLocationCoordinate2D(latitude: 0, longitude: 0), 1_000)
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2)
        let span = CLLocation(latitude: minLat, longitude: minLon)
            .distance(from: CLLocation(latitude: maxLat, longitude: maxLon))
        return (center, min(max(span * 0.9, 1_200), 2_800))
    }

    private func lookAheadCoordinate(after sample: DirectorSample) -> CLLocationCoordinate2D {
        let points = ride.points
        guard points.count > 1, points.indices.contains(sample.index) else {
            return sample.coordinate
        }
        var travelled = 0.0
        var index = sample.index
        while index < points.count - 1, travelled < 38 {
            let a = points[index].coordinate, b = points[index + 1].coordinate
            travelled += CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            index += 1
        }
        return points[min(index, points.count - 1)].coordinate
    }

    private var ghostDelta: Double? {
        guard let ghost, let current else { return nil }
        return distanceCovered(at: current.elapsed) - ghost.distance(at: current.elapsed)
    }

    private func distanceCovered(at elapsed: TimeInterval) -> Double {
        let points = ride.points
        guard points.count > 1, cumulative.count == points.count else { return 0 }
        let target = rideStart.addingTimeInterval(max(elapsed, 0))
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            if target <= b.time {
                let span = max(b.time.timeIntervalSince(a.time), 0.001)
                let t = min(max(target.timeIntervalSince(a.time) / span, 0), 1)
                return cumulative[index - 1] + (cumulative[index] - cumulative[index - 1]) * t
            }
        }
        return cumulative.last ?? 0
    }

    // MARK: Playback

    private func begin() {
        guard !didStart else { return }
        didStart = true
        ghost = loadGhost()
        updateFrame(delta: 0, snap: true)
        if soundOn { startAudio() }
        start()
    }

    private func end() {
        pause()
        stopAudio()
        // The export task owns the screen recorder; cancelling it lets it stop
        // the recording instead of leaving RPScreenRecorder running after the
        // film is closed.
        exportTask?.cancel()
    }

    private func start() {
        guard !film.shots.isEmpty else { return }
        if filmTime >= film.duration - 0.01 { filmTime = 0 }
        isPlaying = true
        lastFrameAt = Date()
        scheduleHide()
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            while !Task.isCancelled, isPlaying {
                let now = Date()
                let delta = min(max(now.timeIntervalSince(lastFrameAt), 0), 0.12)
                lastFrameAt = now
                filmTime = min(filmTime + delta * playbackRate, film.duration)
                updateFrame(delta: delta)
                if filmTime >= film.duration {
                    isPlaying = false
                    audio?.update(speed: 0, lean: 0)
                    showControls()
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
        showControls()
    }

    private func seek(to time: TimeInterval) {
        pause()
        filmTime = min(max(time, 0), film.duration)
        updateFrame(delta: 0, snap: true)
    }

    private func updateFrame(delta: TimeInterval = 0.033, snap: Bool = false) {
        guard let current else { return }
        let target = SmoothedCamera(center: current.plan.center,
                                    heading: current.plan.heading,
                                    distance: current.plan.distance,
                                    pitch: current.plan.pitch)
        let cut = current.shot.id != lastShotID
        if snap || cut || smoothed == nil {
            smoothed = target
        } else if let previous = smoothed {
            let factor = 1 - exp(-max(delta, 0.001) * 5.5)
            var headingDelta = (target.heading - previous.heading + 540)
                .truncatingRemainder(dividingBy: 360) - 180
            if headingDelta < -180 { headingDelta += 360 }
            smoothed = SmoothedCamera(
                center: CLLocationCoordinate2D(
                    latitude: previous.center.latitude + (target.center.latitude - previous.center.latitude) * factor,
                    longitude: previous.center.longitude + (target.center.longitude - previous.center.longitude) * factor
                ),
                heading: (previous.heading + headingDelta * factor + 360).truncatingRemainder(dividingBy: 360),
                distance: previous.distance + (target.distance - previous.distance) * factor,
                pitch: previous.pitch + (target.pitch - previous.pitch) * factor
            )
        }
        if let smoothed {
            camera = .camera(MapCamera(centerCoordinate: smoothed.center,
                                       distance: smoothed.distance,
                                       heading: smoothed.heading,
                                       pitch: smoothed.pitch))
        }
        audio?.update(speed: current.sample.speed, lean: current.sample.lean)
        if cut {
            lastShotID = current.shot.id
            cutFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                cutFlash = false
            }
        }
    }

    private func startAudio() {
        guard soundOn else { return }
        if let audio {
            audio.start()
        } else {
            let engine = ReplayAudioEngine()
            engine.start()
            audio = engine
        }
    }

    private func stopAudio() {
        audio?.stop()
        audio = nil
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled, isPlaying else { return }
            withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false }
        }
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
        if isPlaying { scheduleHide() }
    }

    private func nextRate(_ rate: Double) -> Double {
        switch rate {
        case ..<0.75: 1
        case ..<1.5: 2
        default: 0.5
        }
    }

    private func loadGhost() -> GhostTrack? {
        guard let key = ride.routeKey, !key.isEmpty else { return nil }
        // The ghost is the rider's fastest earlier run on this route, not just
        // the most recent one: a slow lap after a good one used to become the
        // pace to beat. Distance is checked so a shortened or extended version
        // of the route cannot be used as a reference.
        let comparable = pastRides.filter { other in
            other.routeKey == key
                && other.id != ride.id
                && other.startDate < ride.startDate
                && other.durationSeconds > 0
                && abs(other.distanceMeters - ride.distanceMeters) < max(ride.distanceMeters * 0.1, 500)
        }
        guard let fastest = comparable.min(by: { $0.durationSeconds < $1.durationSeconds }) else {
            return nil
        }
        return GhostTrack(ride: fastest)
    }

    // MARK: Export

    private func exportFilm() {
        guard !exporting else { return }
        exporting = true
        pause()
        filmTime = 0
        playbackRate = 1
        if !soundOn { soundOn = true }
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            let started = await exporter.start()
            guard started else {
                exporting = false
                showExportError = true
                return
            }
            start()
            // Wait for playback to actually reach the end: a fixed sleep
            // truncates the film whenever the device drops frames.
            let deadline = Date().addingTimeInterval(film.duration * 1.5 + 2)
            while !Task.isCancelled, filmTime < film.duration - 0.02, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            pause()
            await exporter.stop()
            exporting = false
            showControls()
            exportTask = nil
        }
    }
}
