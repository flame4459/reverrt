import CoreLocation
import Observation

@Observable
final class RideRecorder {
    @ObservationIgnored private let hub = LocationHub.shared
    @ObservationIgnored private var hubToken: UUID?
    @ObservationIgnored private var authToken: UUID?

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
                self?.process(location)
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
        hub.beginPrecise()
        hub.beginBackground()
        hub.requestAlwaysIfNeeded()
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
        let stopped = stoppedTime(in: points)
        finishRecording()
        guard points.count > 1 else {
            RideJournal.shared.finish()
            return nil
        }
        return Ride(startDate: start, endDate: now, distanceMeters: distanceMeters,
                    maxSpeedMps: maxSpeedMps, elevationGainMeters: elevationGain,
                    durationSeconds: duration, points: points,
                    maxLeanAngleDegrees: maxLeanAngle,
                    movingSeconds: max(duration - stopped, 0),
                    stoppedSeconds: stopped)
    }

    func discard() {
        guard isRecording else { return }
        finishRecording()
        RideJournal.shared.finish()
        journalBuffer.removeAll(keepingCapacity: false)
        points.removeAll(keepingCapacity: false)
    }

    /// Stops this recorder's interest in GPS when the ride screen goes away.
    func stopUpdates() {
        hub.endPrecise()
        hub.endBackground()
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
        hub.endPrecise()
        hub.endBackground()
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard let start = startDate else { return 0 }
        guard isRecording else { return frozenDuration ?? 0 }
        var paused = pausedTotal
        if let p = pauseStart { paused += now.timeIntervalSince(p) }
        return max(now.timeIntervalSince(start) - paused, 0)
    }

    private func stoppedTime(in points: [RidePoint]) -> TimeInterval {
        guard points.count > 1 else { return 0 }
        var stopped = 0.0
        for index in 1..<points.count {
            let gap = points[index].time.timeIntervalSince(points[index - 1].time)
            guard gap > 0, gap < 60 else { continue }
            if points[index - 1].speed < 1.5 { stopped += gap }
        }
        return stopped
    }

    // MARK: Location updates
    private func process(_ loc: CLLocation) {
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
            if stationarySince == nil { stationarySince = Date() }
            if let since = stationarySince, Date().timeIntervalSince(since) >= 120 {
                isPaused = true
                autoPaused = true
                pauseStart = Date()
                lastLocation = loc
                return
            }
        } else {
            stationarySince = nil
        }

        if let last = lastLocation {
            let delta = loc.distance(from: last)
            let gap = max(loc.timestamp.timeIntervalSince(last.timestamp), 0)
            let impliedSpeed = gap > 0 ? delta / gap : .infinity
            // Reject multipath jumps, stationary drift and fixes on either
            // side of a long tunnel gap. A rejected fix still advances
            // `lastLocation` so the next good fix is measured from here.
            let isJump = delta > 30 && (loc.speed < 1 || impliedSpeed > 60)
            let isGap = gap > 15
            if !isJump, !isGap {
                distanceMeters += delta
            }
        }
        lastLocation = loc
        maxSpeedMps = max(maxSpeedMps, currentSpeedMps)
        maxLeanAngle = max(maxLeanAngle, abs(currentLean))

        if loc.verticalAccuracy > 0, loc.verticalAccuracy <= 15 {
            if let ref = altitudeRef {
                let diff = loc.altitude - ref
                if diff >= 3 { elevationGain += diff; altitudeRef = loc.altitude }
                else if diff <= -3 { altitudeRef = loc.altitude }
            } else {
                altitudeRef = loc.altitude
            }
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
