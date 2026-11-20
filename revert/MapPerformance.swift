import Foundation
import os
import QuartzCore
import SwiftUI
import ImmersiveMap

/// Lightweight signposts for the map path. They are inert when no Instruments
/// session is attached, so they cost almost nothing in a ride.
enum MapPerformance {
    private static let signposter = OSSignposter(subsystem: "com.davidmolina.Revert", category: "Map")
    static func camera<T>(_ body: () -> T) -> T {
        let state = signposter.beginInterval("CameraStep")
        defer { signposter.endInterval("CameraStep", state) }
        return body()
    }

    static func overlay<T>(_ body: () -> T) -> T {
        let state = signposter.beginInterval("OverlayUpdate")
        defer { signposter.endInterval("OverlayUpdate", state) }
        return body()
    }

    static func search<T>(_ body: () -> T) -> T {
        let state = signposter.beginInterval("InstantSearch")
        defer { signposter.endInterval("InstantSearch", state) }
        return body()
    }
}

/// Detects a main-thread hitch by comparing wall-clock gaps between short
/// watchdog ticks. A normal 0.5 s sleep resumes near 0.5 s; a stall leaves a
/// measurable gap. This is deliberately cheap and logs only real >100 ms gaps.
@MainActor
final class MapHangMonitor {
    static let shared = MapHangMonitor()
    private var task: Task<Void, Never>?
    private var last = CACurrentMediaTime()

    private init() {}

    func start() {
        guard task == nil else { return }
        last = CACurrentMediaTime()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                let now = CACurrentMediaTime()
                let gap = now - self.last
                self.last = now
                // The watchdog wakes every 0.5 s; a normal wake is ~0.5 s, so
                // anything under 0.62 s is timer drift, not a hang. The old
                // 0.12 s threshold logged every single tick as a 500 ms hang.
                if gap > 0.62 {
                    let line = "MAP-HANG \(Int(gap * 1000)) ms"
                    RevertDiagnostics.log(line)
                    RideDebug.shared.note("MAP-HANG", key: "gap", [("ms", "\(Int(gap * 1000))")])
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

@MainActor
@Observable
final class MapFrameStats {
    private(set) var p50Milliseconds = 0.0
    private(set) var p95Milliseconds = 0.0
    private(set) var framesPerSecond = 0
    private(set) var frameCount = 0
    @ObservationIgnored private var samples: [Double] = []
    @ObservationIgnored private var presentationTimes: [Double] = []
    @ObservationIgnored private var lastCompute = 0.0

    func record(_ frame: ImmersiveMapRenderedFrame) {
        frameCount = Int(frame.frameIndex) + 1
        samples.append(frame.cpuDuration * 1_000)
        if samples.count > 180 { samples.removeFirst(samples.count - 180) }
        presentationTimes.append(frame.targetPresentationTimestamp)
        if presentationTimes.count > 120 { presentationTimes.removeFirst() }
        let now = CACurrentMediaTime()
        guard now - lastCompute >= 1 else { return }
        lastCompute = now
        let sorted = samples.sorted()
        if !sorted.isEmpty {
            p50Milliseconds = sorted[sorted.count / 2]
            p95Milliseconds = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        }
        if let first = presentationTimes.first, let last = presentationTimes.last, last > first {
            framesPerSecond = Int((Double(presentationTimes.count - 1) / (last - first)).rounded())
        }
    }
}

struct MapFrameHUD: View {
    let stats: MapFrameStats

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("MAP \(stats.framesPerSecond) FPS")
            Text(String(format: "cpu %.1f / %.1f ms", stats.p50Milliseconds, stats.p95Milliseconds))
            Text("frames \(stats.frameCount)")
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.8))
        .padding(6)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}
