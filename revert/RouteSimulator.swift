import SwiftUI
import SwiftData
import CoreLocation
import Observation

/// Drives synthetic GPS fixes along the active route so the whole app — map,
/// navigation, alerts, recorder and debug logs — behaves as if the rider is
/// moving. Nothing leaves the phone and the app never asks for a real fix while
/// a simulation is running.
@MainActor
@Observable
final class RouteSimulator {
    static let shared = RouteSimulator()
    static let multipliers: [Double] = [1, 2, 3, 4, 5, 10]

    private(set) var route: PlannedRoute?
    private(set) var vehicleKind: VehicleKind = .motorcycle
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var finished = false
    private(set) var multiplier: Double = 1
    private(set) var progress: Double = 0
    private(set) var totalDistance: Double = 0
    private(set) var lap = 1
    private(set) var totalLaps = 1
    private(set) var currentSpeedMps: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var baseSpeedMps: Double = 20
    private(set) var startedAt: Date?
    private(set) var completedAt: Date?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var holdUntil: Date?
    @ObservationIgnored private var pendingWrap = false
    @ObservationIgnored private var lastCourse: Double = 0

    var routeName: String { route?.displayName ?? "Active route" }
    var length: Double { max(route?.length ?? 0, 1) }
    var progressFraction: Double { min(max(progress / length, 0), 1) }
    var simulatedSpeedMps: Double { baseSpeedMps * multiplier }

    var speedText: String {
        "\(Int(Units.speedValue(currentSpeedMps).rounded())) \(Units.speedUnit)"
    }

    var baseSpeedText: String {
        "\(Int(Units.speedValue(baseSpeedMps).rounded())) \(Units.speedUnit)"
    }

    var summaryDistance: String {
        Units.distanceText(totalDistance, decimals: 1)
    }

    // MARK: Control

    func start(route: PlannedRoute, holdAtStart: TimeInterval,
               vehicleKind: VehicleKind = .motorcycle) {
        stop(reset: true, report: false)
        guard route.points.count > 1 else { return }

        self.route = route
        self.vehicleKind = vehicleKind
        totalLaps = route.kind.isLoop ? max(route.laps, 1) : 1
        baseSpeedMps = Self.baseSpeed(for: route)
        progress = 0
        totalDistance = 0
        lap = 1
        elapsed = 0
        currentSpeedMps = 0
        pendingWrap = false
        finished = false
        isPaused = false
        isRunning = true
        startedAt = Date()
        completedAt = nil
        lastTick = Date()
        holdUntil = Date().addingTimeInterval(max(holdAtStart, 0))

        LocationHub.shared.beginSimulation()
        RideDebug.shared.beginSimulation(route: route, multiplier: multiplier,
                                         vehicle: vehicleKind.title)
        inject(speed: 0)
        RevertDiagnostics.log("sim.start route=\(route.displayName ?? "—") kind=\(route.kind) "
                              + "laps=\(totalLaps) speed=\(Int(multiplier))x")

        task?.cancel()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                self.tick()
            }
        }
    }

    func setMultiplier(_ value: Double) {
        guard value > 0 else { return }
        multiplier = value
        if isRunning || isPaused {
            RideDebug.shared.event("SIM SPEED", [("speed", "\(Int(value))x")])
        }
    }

    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
        if isPaused {
            currentSpeedMps = 0
            inject(speed: 0)
            RideDebug.shared.event("SIM PAUSE")
        } else {
            lastTick = Date()
            RideDebug.shared.event("SIM RESUME")
        }
    }

    func stop() {
        stop(reset: false, report: true)
    }

    // MARK: Tick

    private func tick() {
        guard isRunning, let route else { return }
        let now = Date()
        guard let last = lastTick else { lastTick = now; return }
        let dt = min(max(now.timeIntervalSince(last), 0), 0.5)
        lastTick = now
        guard !isPaused else { return }

        if let hold = holdUntil {
            if now < hold {
                inject(speed: 0)
                return
            }
            holdUntil = nil
            lastTick = now
        }

        if pendingWrap {
            pendingWrap = false
            lap += 1
            progress = 0
            inject(speed: simulatedSpeedMps)
            RideDebug.shared.event("SIM LAP", [
                ("lap", "\(lap)/\(totalLaps)"),
                ("distance", Units.distanceText(totalDistance, decimals: 1))
            ])
            return
        }

        let speed = simulatedSpeedMps
        let length = route.length
        let travel = speed * dt
        let next = progress + travel
        elapsed += dt

        if next >= length {
            let segment = max(length - progress, 0)
            totalDistance += segment
            progress = length
            inject(speed: speed)

            if lap < totalLaps {
                pendingWrap = true
                return
            }
            finish(completed: true)
            return
        }

        totalDistance += travel
        progress = next
        inject(speed: speed)
    }

    // MARK: Finish

    private func stop(reset: Bool, report: Bool) {
        let wasLive = isRunning || isPaused
        task?.cancel()
        task = nil
        isRunning = false
        isPaused = false
        currentSpeedMps = 0
        holdUntil = nil
        pendingWrap = false
        LocationHub.shared.endSimulation()
        if wasLive, report {
            writeReport(completed: false)
            RevertDiagnostics.log("sim.stop route=\(route?.displayName ?? "—") "
                                  + "distance=\(Int(totalDistance))m elapsed=\(Int(elapsed))s")
        }
        if reset {
            route = nil
            progress = 0
            totalDistance = 0
            lap = 1
            totalLaps = 1
            elapsed = 0
            startedAt = nil
            completedAt = nil
            finished = false
            lastTick = nil
        }
    }

    private func finish(completed: Bool) {
        guard isRunning else { return }
        let recordedLap = lap
        let recordedDistance = totalDistance
        task?.cancel()
        task = nil
        isRunning = false
        isPaused = false
        currentSpeedMps = 0
        finished = completed
        completedAt = Date()
        holdUntil = nil
        LocationHub.shared.endSimulation()
        RideDebug.shared.endSimulation(distance: recordedDistance,
                                       duration: elapsed,
                                       multiplier: multiplier,
                                       lap: recordedLap,
                                       totalLaps: totalLaps)
        writeReport(completed: completed)
        RevertDiagnostics.log("sim.finish route=\(route?.displayName ?? "—") "
                              + "completed=\(completed) distance=\(Int(recordedDistance))m "
                              + "elapsed=\(Int(elapsed))s speed=\(Int(multiplier))x")
    }

    private func writeReport(completed: Bool) {
        let name = route?.displayName ?? "Route simulator"
        var body = """
        Mode: SIMULATION
        Vehicle: \(vehicleKind.title)
        Route: \(name)
        Kind: \(route.map { "\($0.kind)" } ?? "—")
        Laps: \(lap)/\(totalLaps)
        Speed: \(Int(multiplier))x (base \(baseSpeedText))
        Distance: \(Units.distanceText(totalDistance, decimals: 1))
        Simulated ride time: \(Units.clock(totalDistance / max(baseSpeedMps, 1)))
        Real elapsed: \(Units.clock(elapsed))
        Result: \(completed ? "completed the route" : "stopped by the rider")
        Started: \(startedAt?.formatted(date: .complete, time: .standard) ?? "—")
        Ended: \((completedAt ?? Date()).formatted(date: .complete, time: .standard))

        The per-ride transcript in RideDebug is marked Mode: SIMULATION.
        No real GPS fix was used while this simulator ran.
        """
        if let route {
            body += "\nRoute length: \(Units.distanceText(route.length, decimals: 1))"
        }
        DebugReports.write(kind: "Simulation",
                           title: "\(name) · \(Int(multiplier))x",
                           body: body)
    }

    // MARK: Injection

    private func inject(speed: Double) {
        guard let route, route.points.count > 1 else { return }
        let coordinate = point(at: progress)
        let ahead = point(at: min(progress + 12, route.length))
        if coordinate.latitude != ahead.latitude || coordinate.longitude != ahead.longitude {
            lastCourse = Self.bearing(from: coordinate, to: ahead)
        } else if progress > 0 {
            let behind = point(at: max(progress - 12, 0))
            if behind.latitude != coordinate.latitude || behind.longitude != coordinate.longitude {
                lastCourse = Self.bearing(from: behind, to: coordinate)
            }
        }

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 30,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: lastCourse,
            speed: max(speed, 0),
            timestamp: Date()
        )
        currentSpeedMps = speed
        LocationHub.shared.inject(location)
        RideDebug.shared.sample(location,
                                progress: progress,
                                remaining: max(route.length - progress, 0))
    }

    private func point(at distance: Double) -> CLLocationCoordinate2D {
        guard let route, route.points.count > 1 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let d = min(max(distance, 0), route.length)
        var index = 0
        while index < route.points.count - 2,
              route.cumulative[index + 1] <= d {
            index += 1
        }
        let a = route.points[index]
        let b = route.points[index + 1]
        let span = route.cumulative[index + 1] - route.cumulative[index]
        let t = span > 0 ? min(max((d - route.cumulative[index]) / span, 0), 1) : 0
        return CLLocationCoordinate2D(
            latitude: a.lat + (b.lat - a.lat) * t,
            longitude: a.lon + (b.lon - a.lon) * t
        )
    }

    private static func baseSpeed(for route: PlannedRoute) -> Double {
        if let expected = route.expectedTravelTime, expected > 0, route.length > 0 {
            return min(max(route.length / expected, 12), 28)
        }
        return 20
    }

    private static func bearing(from a: CLLocationCoordinate2D,
                                to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - HUD

/// Small cockpit badge so a simulated ride can never be mistaken for a real
/// one, and so the panel can be reopened after it is dismissed.
struct SimulationHUD: View {
    let simulator: RouteSimulator
    let onOpen: () -> Void

    var body: some View {
        Button {
            RevertHaptics.tap()
            onOpen()
        } label: {
            HStack(spacing: 7) {
                Text("SIM")
                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(MapUI.pitchBlack)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(MapUI.amber, in: Capsule())

                Text("\(Int(simulator.multiplier))×")
                    .font(.scaledSystem(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(MapUI.amber)

                if simulator.totalLaps > 1 {
                    Text("LAP \(simulator.lap)/\(simulator.totalLaps)")
                        .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(MapUI.ink)
                }

                ProgressView(value: simulator.progressFraction)
                    .tint(MapUI.amber)
                    .frame(width: 46)

                Text(simulator.isPaused ? "PAUSED" : simulator.speedText)
                    .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(simulator.isPaused ? MapUI.amber : MapUI.textSecondary)
                    .monospacedDigit()

                Image(systemName: "chevron.up")
                    .font(.scaledSystem(size: 8, weight: .bold))
                    .foregroundStyle(MapUI.textTertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(MapUI.panel.opacity(0.94), in: Capsule())
            .overlay {
                Capsule().stroke(MapUI.amber.opacity(0.35), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route simulator \(Int(simulator.multiplier)) times. Open controls.")
    }
}

// MARK: - Panel

struct RouteSimulatorView: View {
    let holdAtStart: TimeInterval

    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var nav
    @Query(sort: \Bike.createdAt, order: .reverse) private var garageVehicles: [Bike]
    @State private var simulator = RouteSimulator.shared

    private var route: PlannedRoute? { nav.route }
    private var isCar: Bool {
        if nav.route != nil { return nav.vehicleKind.isCar }
        return (garageVehicles.first(where: \.isPrimary) ?? garageVehicles.first)?.isCar == true
    }
    private var canStart: Bool { route != nil && !simulator.isRunning && !simulator.isPaused }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let route {
                        routeCard(route)
                        speedCard
                        controls(route)
                        liveCard
                    } else {
                        emptyState
                    }

                    RevertInfoNote(
                        text: "The simulator feeds synthetic fixes through the same GPS stream as a real ride. Start navigation first; then the map, turns, alerts, recorder and debug files all behave as if you were riding.",
                        systemImage: "location.fill",
                        tint: MapUI.textTertiary
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .pulseBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        RevertHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close route simulator")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DEBUG TOOL")
                .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(MapUI.amber)
            Text("Route simulator")
                .font(RevertType.display(30, weight: .heavy))
                .foregroundStyle(MapUI.ink)
            Text("Move the app's location along the active route. No real GPS is used while the simulation runs.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routeCard(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RevertIconBadge(systemImage: route.kind.isLoop
                                ? "arrow.triangle.2.circlepath"
                                : (route.kind.isSprint ? "flag.checkered" : "arrow.triangle.turn.up.right.diamond"),
                                tint: MapUI.amber, size: 34, radius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.displayName ?? "Active route")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(2)
                    Text("\(Units.distanceText(route.length, decimals: 1))  •  "
                         + (route.kind.isLoop
                            ? "\(max(route.laps, 1)) lap\(route.laps == 1 ? "" : "s")"
                            : (route.kind.isSprint ? "Sprint" : "Point to point")))
                        .font(.scaledSystem(size: 10, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
                Spacer(minLength: 4)
            }
            if simulator.isRunning || simulator.isPaused {
                Text("Simulation is running. Stop it before starting a different route.")
                    .font(.scaledSystem(size: 10, design: .rounded))
                    .foregroundStyle(MapUI.amber)
            }
        }
        .revertCard()
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            RevertSectionLabel(title: "Speed", detail: "\(Int(simulator.multiplier))×")

            HStack(spacing: 6) {
                ForEach(RouteSimulator.multipliers, id: \.self) { value in
                    RevertChip(
                        title: "\(Int(value))×",
                        isSelected: simulator.multiplier == value,
                        tint: MapUI.amber,
                        action: {
                            RevertHaptics.select()
                            simulator.setMultiplier(value)
                        }
                    )
                }
            }

            Text("\(simulator.baseSpeedText) base  •  \(Int(Units.speedValue(simulator.simulatedSpeedMps).rounded())) \(Units.speedUnit) at this multiplier")
                .font(.scaledSystem(size: 10, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
        }
        .revertCard()
    }

    private func controls(_ route: PlannedRoute) -> some View {
        HStack(spacing: 9) {
            Button {
                RevertHaptics.success()
                simulator.start(route: route, holdAtStart: holdAtStart,
                                vehicleKind: isCar ? .car : .motorcycle)
            } label: {
                Label(simulator.isRunning || simulator.isPaused ? "Restart" : "Start simulation",
                      systemImage: "play.fill")
            }
            .buttonStyle(RevertPrimaryButtonStyle(minHeight: 48))
            .disabled(simulator.isRunning || simulator.isPaused ? false : !canStart)
            .opacity((simulator.isRunning || simulator.isPaused) || canStart ? 1 : 0.5)

            if simulator.isRunning || simulator.isPaused {
                Button {
                    RevertHaptics.tap()
                    simulator.togglePause()
                } label: {
                    Label(simulator.isPaused ? "Resume" : "Pause",
                          systemImage: simulator.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 48))
                .frame(width: 112)

                Button {
                    RevertHaptics.warning()
                    simulator.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(RevertIconButtonStyle(tint: MapUI.danger, diameter: 48))
                .accessibilityLabel("Stop simulation")
            }
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RevertSectionLabel(
                title: "Live",
                detail: simulator.isRunning ? "SIMULATING" : (simulator.isPaused ? "PAUSED" : (simulator.finished ? "FINISHED" : "READY"))
            )

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Units.clock(simulator.totalDistance / max(simulator.baseSpeedMps, 1)))
                    .font(RevertType.number(24))
                    .foregroundStyle(MapUI.ink)
                Text("sim ride time")
                    .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                Spacer()
                if simulator.totalLaps > 1 {
                    Text("LAP \(simulator.lap)/\(simulator.totalLaps)")
                        .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(MapUI.amber)
                }
            }

            RevertProgressBar(value: simulator.progressFraction, tint: MapUI.ember, height: 5)

            HStack(spacing: 0) {
                simStat("SPEED", simulator.speedText)
                simStat("DISTANCE", simulator.summaryDistance)
                simStat("ELAPSED", Units.clock(simulator.elapsed))
            }
        }
        .revertCard()
    }

    private func simStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(MapUI.textTertiary)
            Text(value)
                .font(RevertType.number(14))
                .foregroundStyle(MapUI.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start navigation first")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(MapUI.ink)
            Text("Plan a route, loop or sprint, tap Start navigation, then come back here to drive the app along it without leaving home.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(MapUI.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .revertCard()
    }
}
