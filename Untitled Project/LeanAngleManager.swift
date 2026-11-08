import CoreMotion
import Observation
import UIKit

enum LeanAngleAxis {
    case roll
    case pitch

    var title: String {
        switch self {
        case .roll: "Portrait"
        case .pitch: "Landscape"
        }
    }
}

@MainActor
@Observable
final class LeanAngleManager {
    var angle: Double?
    var maxAngle = 0.0
    var isCalibrated = false
    var isAvailable = false
    private(set) var detectedAxis: LeanAngleAxis = .roll

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var baselineRoll: Double?
    @ObservationIgnored private var baselinePitch: Double?
    @ObservationIgnored private var orientationTask: Task<Void, Never>?

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        detectedAxis = Self.axisForCurrentDeviceOrientation()
        isAvailable = motion.isDeviceMotionAvailable

        orientationTask?.cancel()
        orientationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                guard !Task.isCancelled, let self else { return }
                let newAxis = Self.axisForCurrentDeviceOrientation()
                if self.detectedAxis != newAxis {
                    self.detectedAxis = newAxis
                    if let attitude = self.motion.deviceMotion?.attitude {
                        self.setBaseline(from: attitude)
                    }
                }
            }
        }

        guard isAvailable, !motion.isDeviceMotionActive else { return }

        motion.deviceMotionUpdateInterval = 1.0 / 10.0
        motion.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: OperationQueue.main
        ) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.update(motion.attitude)
        }
    }

    func calibrate() {
        guard let attitude = motion.deviceMotion?.attitude else { return }
        setBaseline(from: attitude)
    }

    func stop() {
        orientationTask?.cancel()
        orientationTask = nil
        motion.stopDeviceMotionUpdates()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        angle = nil
        maxAngle = 0
        isCalibrated = false
        baselineRoll = nil
        baselinePitch = nil
    }

    private func update(_ attitude: CMAttitude) {
        // The first stable attitude becomes the upright reference automatically.
        if baselineRoll == nil || baselinePitch == nil {
            setBaseline(from: attitude)
            return
        }

        guard let baselineRoll, let baselinePitch else { return }
        let current = detectedAxis == .roll ? attitude.roll : attitude.pitch
        let baseline = detectedAxis == .roll ? baselineRoll : baselinePitch
        var delta = current - baseline

        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }

        // Signed angle: positive is a right-hand lean, negative a left-hand
        // lean. Keeping the sign lets the dual-wing gauge show which side the
        // rider is actually on.
        let measured = min(max(delta * 180 / .pi, -90), 90)
        // Publish only meaningful changes so SwiftUI is not invalidated 10x a
        // second while the bike is upright.
        if angle == nil || abs((angle ?? 0) - measured) >= 0.5 {
            angle = measured
        }
        if abs(measured) > maxAngle { maxAngle = abs(measured) }
    }

    private func setBaseline(from attitude: CMAttitude) {
        baselineRoll = attitude.roll
        baselinePitch = attitude.pitch
        angle = 0
        maxAngle = 0
        isCalibrated = true
    }

    private static func axisForCurrentDeviceOrientation() -> LeanAngleAxis {
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            return .pitch
        default:
            return .roll
        }
    }
}
