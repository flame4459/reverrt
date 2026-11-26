import SwiftUI
import MapKit

/// Banner distance: feet/meters when close, miles/km otherwise. Delegates to
/// the unit-aware formatter so the HUD obeys the rider's unit setting.
func navDistance(_ meters: Double) -> String {
    Units.shortDistanceText(meters)
}

/// Glassmorphic aero-HUD banner for the next maneuver.
struct NavBanner: View {
    let nav: NavigationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingStopConfirmation = false

    private var isNearJunction: Bool {
        nav.stepDistance > 0 && nav.stepDistance <= 91.5
    }

    /// Fraction of the 300 m approach still to run. To the start, measure the
    /// approach maneuver; on the route, the next turn.
    private var turnProgressFraction: Double {
        let meters = nav.joined ? nav.stepDistance : nav.approachStepDistance
        return min(max(meters / 300, 0), 1)
    }

    /// Waze-style lane reveal: the strip appears at highway range, then on
    /// shorter approach on slower roads. The instruction still arrives on the
    /// speed-band schedule; the drawing just waits until it is useful.
    private var laneGuidance: LaneGuidance? {
        guard nav.joined, !nav.arrived, let lanes = nav.step?.laneGuidance else { return nil }
        let reveal = LaneGuidance.revealDistance(forSpeed: nav.currentSpeedMps)
        return nav.stepDistance <= reveal ? lanes : nil
    }

    private var alertTint: Color {
        if nav.offRoute || nav.rerouting { return MapUI.orange }
        if nav.arrived { return MapUI.emerald }
        return MapUI.cyan
    }

    var body: some View {
        HStack(spacing: 14) {
            maneuverBadge

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(eyebrow)
                        .font(.scaledSystem(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(alertTint.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if nav.joined, nav.totalLaps > 1 {
                        Text("LAP \(nav.lap)/\(nav.totalLaps)")
                            .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.9)
                            .foregroundStyle(alertTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(alertTint.opacity(0.14), in: Capsule())
                            .overlay(Capsule().stroke(alertTint.opacity(0.25), lineWidth: 0.6))
                            .lineLimit(1)
                    }
                }
                Text(title)
                    .font(.scaledSystem(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                if let lanes = laneGuidance {
                    LaneStrip(guidance: lanes)
                }
                if let next = nextLine {
                    Text(next)
                        .font(.scaledSystem(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MapUI.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(primaryDistance)
                    .font(.scaledSystem(size: nav.arrived ? 18 : 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(distanceCaption)
                    .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(MapUI.secondaryInk)
                if !nav.arrived, nav.remaining > 0 {
                    Text(nav.joined
                         ? "\(navDistance(nav.remaining)) left"
                         : "\(navDistance(nav.remaining)) loop")
                        .font(.scaledSystem(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alertTint.opacity(0.85))
                        .lineLimit(1)
                }
            }

            if !nav.joined, !nav.approachActive, let c = nav.startCoordinate {
                Button { openMaps(to: c) } label: {
                    Image(systemName: "map.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MapUI.cyan)
                        .frame(width: 34, height: 34)
                        .background(MapUI.pitchBlack.opacity(0.5), in: Circle())
                        .overlay(Circle().stroke(MapUI.hairline, lineWidth: 0.8))
                }
                .accessibilityLabel("Open route start in Maps")
            }

            Button { showingStopConfirmation = true } label: {
                Image(systemName: "xmark")
                    .font(.scaledSystem(size: 12, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("End navigation")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background {
            GlassHUDBackground()
                .shadow(color: alertTint.opacity(0.22), radius: 18, y: 5)
        }
        // An alert keeps a visible "Keep navigating" button; a confirmation
        // dialog presented as a popover drops the cancel role on iOS 27.
        .alert("End navigation?", isPresented: $showingStopConfirmation) {
            Button("End route", role: .destructive) { nav.endNavigation() }
            Button("Keep navigating", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var maneuverBadge: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .frame(width: 54, height: 54)

            Circle()
                .trim(from: 0, to: CGFloat(turnProgressFraction))
                .stroke(
                    AngularGradient(colors: [alertTint, MapUI.emerald, alertTint],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 54, height: 54)
                .animation(.easeOut(duration: 0.22), value: turnProgressFraction)

            Circle()
                .fill(MapUI.pitchBlack.opacity(0.55))
                .frame(width: 42, height: 42)

            Image(systemName: icon)
                .font(.scaledSystem(size: 24, weight: .heavy))
                .foregroundStyle(alertTint)
                .symbolEffect(.pulse, options: .repeating, isActive: isNearJunction && !nav.arrived && !reduceMotion)
                .shadow(color: alertTint.opacity(0.55), radius: 7)
        }
        .frame(width: 56, height: 56)
    }

    private var eyebrow: String {
        // The lap chip shares this row on a circuit, so keep the label short
        // enough that it is not truncated on a phone mount.
        if nav.arrived { return nav.totalLaps > 1 ? "FINISH" : "RIDE COMPLETE" }
        if !nav.joined { return "TO THE START" }
        if nav.rerouting { return nav.totalLaps > 1 ? "REROUTE" : "RECALCULATING" }
        if nav.offRoute { return "OFF ROUTE" }
        if isNearJunction { return "TURN NOW" }
        return nav.totalLaps > 1 ? "NEXT" : "NEXT MANEUVER"
    }

    private var icon: String {
        if nav.arrived { return "flag.checkered" }
        if !nav.joined {
            return nav.approachActive ? nav.approachSymbol : "location.north.line"
        }
        if nav.rerouting || nav.offRoute { return "arrow.triangle.2.circlepath" }
        return nav.step?.symbol ?? "arrow.up"
    }

    private var title: String {
        if nav.arrived { return "Route complete" }
        if !nav.joined {
            if nav.approachActive, let instruction = nav.approachInstruction {
                return instruction
            }
            return "Head to the start"
        }
        if nav.rerouting { return "Finding a way back…" }
        if nav.offRoute { return "Off route" }
        return nav.step?.instruction ?? "Follow the route"
    }

    private var nextLine: String? {
        if !nav.arrived, !nav.joined, nav.approachActive {
            return "\(navDistance(nav.approachRemaining)) to the start"
        }
        guard !nav.arrived, nav.joined, !nav.offRoute, !nav.rerouting else { return nil }
        if isNearJunction, let next = nav.nextStep, next.turn != .arrive {
            return "Then \(next.instruction)"
        }
        if let expected = nav.estimatedTimeRemaining, expected > 0 {
            let formatted = Duration.seconds(expected)
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            return "ETA \(formatted)"
        }
        return nil
    }

    private var primaryDistance: String {
        if nav.arrived { return "DONE" }
        if !nav.joined {
            return navDistance(nav.approachActive ? nav.approachStepDistance : nav.distanceToStart)
        }
        if nav.offRoute || nav.rerouting { return navDistance(nav.remaining) }
        return navDistance(nav.stepDistance)
    }

    private var distanceCaption: String {
        if nav.arrived { return "NICE RIDE" }
        if !nav.joined { return nav.approachActive ? "TO TURN" : "AWAY" }
        if nav.offRoute || nav.rerouting { return "ROUTE LEFT" }
        return "TO TURN"
    }

    private func openMaps(to c: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let item = MKMapItem.revert(location: location)
        item.name = "Route start"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}


/// Lane strip: one arrow per lane, left to right, with the ones that serve the
/// coming manoeuvre lit. Hidden when OSM has no `turn:lanes` for the approach.
struct LaneStrip: View {
    let guidance: LaneGuidance

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(guidance.lanes.enumerated()), id: \.offset) { index, lane in
                Image(systemName: lane.symbol)
                    .font(.scaledSystem(size: 12, weight: .bold))
                    .foregroundStyle(guidance.recommended.contains(index)
                                     ? MapUI.cyan
                                     : MapUI.textTertiary.opacity(0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(guidance.phrase)
    }
}
