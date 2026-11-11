import CoreLocation
import Observation

@MainActor
@Observable
final class RideRecorder {
    @ObservationIgnored private let hub = LocationHub.shared
    @ObservationIgnored private var hubToken: UUID?
    @ObservationIgnored private var authToken: UUID?
    /// Claims on the hub's accuracy tiers. Leases are idempotent, so finishing
    /// a ride and leaving the screen can both clean up without stepping on
    /// navigation's claim.
    @ObservationIgnored private var preciseLease: LocationHub.Lease?
    @ObservationIgnored private var backgroundLease: LocationHub.Lease?
    @ObservationIgnored private var autoPauseTimer: Timer?

    var isRecording = false
    var isPaused = false
    var points: [RidePoint] = []
    var currentSpeedMps = 0.0
    var currentLean = 0.0
    var maxLeanAngle = 0.0
    var distanceMeters = 0.0
    var maxSpeedMps = 0.0
    var elevationGain = 0.0
    var authStatus: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored var onLocation: ((CLLocation) -> Void)?

    /// True while the recorder paused itself because the bike stopped moving.
    var isAutoPaused: Bool { autoPaused }

    private var startDate: Date?
    private var pauseStart: Date?
    private var pausedTotal: TimeInterval = 0
    private var frozenDuration: TimeInterval?
    private var lastLocation: CLLocation?
    private var altitudeRef: Double?
    private var journalBuffer: [RidePoint] = []
    private var lastJournalFlush = Date.distantPast
    private var stationarySince: Date?
    private var autoPaused = false

    init() {
        authStatus = hub.authorizationStatus
        attach()
    }

    // MARK: Permissions
    func requestPermission() {
        attach()
        hub.requestWhenInUse()
    }

    private func attach() {
        if hubToken == nil {
            hubToken = hub.addSubscriber { [weak self] location in
                self?.ingest(location)
            }
        }
        if authToken == nil {
            authToken = hub.addAuthorizationSubscriber { [weak self] status in
                self?.authStatus = status
            }
        }
    }

    // MARK: Controls
    func start() {
        guard !isRecording else { return }
        points = []
        distanceMeters = 0
        maxSpeedMps = 0
        maxLeanAngle = 0
        currentLean = 0
        elevationGain = 0
        pausedTotal = 0
        frozenDuration = nil
        pauseStart = nil
        lastLocation = nil
        altitudeRef = nil
        stationarySince = nil
        autoPaused = false
        startDate = Date()
        journalBuffer = []
        lastJournalFlush = Date()
        if let startDate { RideJournal.shared.begin(startDate: startDate) }
        isPaused = false
        isRecording = true
        attach()
        preciseLease = hub.acquirePrecise()
        backgroundLease = hub.acquireBackground()
        hub.requestAlwaysIfNeeded()
        startAutoPauseTimer()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        autoPaused = false
        pauseStart = Date()
    }

    func resume() {
        guard isRecording, isPaused else { return }
        if let p = pauseStart { pausedTotal += Date().timeIntervalSince(p) }
        pauseStart = nil
        isPaused = false
        autoPaused = false
        stationarySince = nil
    }

    func stop() -> Ride? {
        guard isRecording, let start = startDate else { return nil }
        let now = Date()
        let duration = elapsed(at: now)
        finishRecording()
        guard points.count > 1 else {
            RideJournal.shared.finish()
            return nil
        }
        // The saved ride comes from the same stats the recovery journal uses,
        // so a ride saved now and the same ride recovered after a crash agree.
        let stats = RideStats.compute(points: points)
        return Ride(startDate: start, endDate: now,
                    distanceMeters: stats.distanceMeters,
                    maxSpeedMps: stats.maxSpeedMps,
                    elevationGainMeters: stats.elevationGainMeters,
                    durationSeconds: duration, points: points,
                    maxLeanAngleDegrees: stats.maxLeanAngleDegrees,
                    movingSeconds: max(duration - stats.stoppedSeconds, 0),
                    stoppedSeconds: stats.stoppedSeconds)
    }

    func discard() {
        guard isRecording else { return }
        finishRecording()
        RideJournal.shared.finish()
        journalBuffer.removeAll(keepingCapacity: false)
        points.removeAll(keepingCapacity: false)
    }

    /// Stops recording without throwing the track away.
    ///
    /// The ride screen calls this when it disappears. The journal stays on disk
    /// so the existing "Recover unfinished ride?" prompt can still offer it;
    /// only `discard()` deletes it.
    func suspend() {
        if isRecording { finishRecording() }
        stopUpdates()
    }

    /// Stops this recorder's interest in GPS when the ride screen goes away.
    func stopUpdates() {
        stopAutoPauseTimer()
        releaseLocationClaims()
        if let hubToken {
            hub.removeSubscriber(hubToken)
            self.hubToken = nil
        }
        if let authToken {
            hub.removeAuthorizationSubscriber(authToken)
            self.authToken = nil
        }
    }

    private func finishRecording() {
        flushJournal()
        frozenDuration = elapsed(at: Date())
        isRecording = false
        isPaused = false
        pauseStart = nil
        stopAutoPauseTimer()
        releaseLocationClaims()
    }

    /// Hands back both accuracy claims. A lease releases at most once, so this
    /// is safe to call from `finishRecording()` and again from `stopUpdates()`.
    private func releaseLocationClaims() {
        preciseLease?.release()
        preciseLease = nil
        backgroundLease?.release()
        backgroundLease = nil
    }

    // MARK: Auto-pause

    private func startAutoPauseTimer() {
        autoPauseTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickAutoPause() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoPauseTimer = timer
    }

    private func stopAutoPauseTimer() {
        autoPauseTimer?.invalidate()
        autoPauseTimer = nil
    }

    /// Pauses the clock after two minutes without movement.
    ///
    /// This runs on a timer, not from `ingest`: with `distanceFilter = 5` a
    /// parked phone receives almost no fixes, so a fix-driven check would never
    /// fire. The stationary clock is anchored to `CLLocation.timestamp`, so a
    /// fix delivered late does not postpone the pause.
    func tickAutoPause() {
        guard isRecording, !isPaused, let since = stationarySince else { return }
        // Riders who want the clock to keep running at a long stop can turn
        // auto-pause off; the default preserves the existing behaviour.
        guard UserDefaults.standard.object(forKey: "ride.autoPause") == nil
                || UserDefaults.standard.bool(forKey: "ride.autoPause") else { return }
        guard Date().timeIntervalSince(since) >= 120 else { return }
        isPaused = true
        autoPaused = true
        pauseStart = Date()
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard let start = startDate else { return 0 }
        guard isRecording else { return frozenDuration ?? 0 }
        var paused = pausedTotal
        if let p = pauseStart { paused += now.timeIntervalSince(p) }
        return max(now.timeIntervalSince(start) - paused, 0)
    }

    // MARK: Location updates

    /// Feeds a fix through the same path the GPS subscription uses. Internal so
    /// tests can drive scripted sequences without Core Location.
    func ingest(_ loc: CLLocation) {
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 20 else { return }
        currentSpeedMps = max(loc.speed, 0)
        onLocation?(loc)

        guard isRecording else { return }

        if isPaused {
            // A pit stop, fuel stop or traffic jam should pause the clock, but
            // the ride must resume automatically when the wheels move again.
            if autoPaused, currentSpeedMps > 2 {
                resume()
            } else {
                lastLocation = loc
                return
            }
        }

        if currentSpeedMps < 0.5 {
            // Only start the clock here; `tickAutoPause()` owns the decision so
            // it still fires when no further fixes arrive.
            if stationarySince == nil { stationarySince = loc.timestamp }
        } else {
            stationarySince = nil
        }

        if let last = lastLocation,
           let meters = RideStats.segmentMeters(from: last.coordinate, at: last.timestamp,
                                               to: loc.coordinate, at: loc.timestamp,
                                               nextSpeed: currentSpeedMps) {
            // A rejected fix still advances `lastLocation` so the next good fix
            // is measured from here rather than bridging the jump.
            distanceMeters += meters
        }
        lastLocation = loc
        maxSpeedMps = max(maxSpeedMps, currentSpeedMps)
        maxLeanAngle = max(maxLeanAngle, abs(currentLean))

        if loc.verticalAccuracy > 0, loc.verticalAccuracy <= 15 {
            elevationGain += RideStats.elevationGain(altitude: loc.altitude, reference: &altitudeRef)
        }

        let point = RidePoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                              alt: loc.altitude, speed: currentSpeedMps, time: loc.timestamp,
                              lean: currentLean)
        points.append(point)
        journalBuffer.append(point)
        if journalBuffer.count >= 5 || Date().timeIntervalSince(lastJournalFlush) > 10 {
            flushJournal()
        }
    }

    private func flushJournal() {
        guard !journalBuffer.isEmpty else { return }
        RideJournal.shared.append(journalBuffer)
        journalBuffer.removeAll(keepingCapacity: true)
        lastJournalFlush = Date()
    }
}
