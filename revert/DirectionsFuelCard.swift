import SwiftUI
import SwiftData
import CoreLocation

struct DirectionsFuelCard: View {
    let route: PlannedRoute
    let onAddStop: (CLLocationCoordinate2D) -> Void

    /// Fallback when no garage vehicle knows its range.
    private let rangeKm = 260.0
    @AppStorage("fuel.tankFraction") private var tankFraction = 0.8
    @Query(sort: \Bike.createdAt, order: .reverse) private var garageBikes: [Bike]
    @State private var plan: FuelPlan?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RevertCardHeader(
                icon: "fuelpump.fill",
                title: "Fuel range",
                tint: plan?.needsFuelStop == true ? MapUI.amber : MapUI.emerald,
                trailingText: loading
                    ? nil
                    : plan.map { $0.needsFuelStop ? "\($0.stopsNeeded) stop\($0.stopsNeeded == 1 ? "" : "s") needed" : "No stop needed" }
            )

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(MapUI.cyan)
                    Text("Checking stations along this route…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
            } else if let plan {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Units.distanceText(plan.routeKm * 1_000, decimals: 0)) route")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.textSecondary)
                    Spacer()
                    Text("\(Units.distanceText(plan.usableKm * 1_000, decimals: 0)) usable range")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }

                RevertProgressBar(
                    value: min(max(plan.routeKm / max(plan.usableKm, 1), 0), 1),
                    tint: plan.needsFuelStop ? MapUI.ember : MapUI.aurora,
                    height: 4
                )

                if plan.stationsFound > 0 {
                    Text("\(plan.stationsFound) station\(plan.stationsFound == 1 ? "" : "s") checked along this route")
                        .font(.scaledSystem(size: 10, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }

                if plan.needsFuelStop {
                    ForEach(plan.suggestions) { suggestion in
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.scaledSystem(size: 12, weight: .bold))
                                .foregroundStyle(MapUI.cyan)
                                .frame(width: 28, height: 28)
                                .background(MapUI.cyan.opacity(0.10), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.station.displayName)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(MapUI.ink)
                                    .lineLimit(1)
                                Text("at \(Units.distanceText(suggestion.distanceAlong, decimals: 0))  •  \(Units.shortDistanceText(suggestion.detourMeters)) off route")
                                    .font(.scaledSystem(size: 10, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                            }

                            Spacer(minLength: 4)

                            Button {
                                RevertHaptics.tap()
                                onAddStop(suggestion.station.coordinate)
                            } label: {
                                Text("Add")
                                    .font(.scaledSystem(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(MapUI.cyan)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(MapUI.cyan.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().stroke(MapUI.cyan.opacity(0.28), lineWidth: 0.7))
                            }
                            .buttonStyle(RevertCardButtonStyle())
                            .accessibilityLabel("Add \(suggestion.station.displayName) as a stop")
                        }
                        .padding(8)
                        .background(MapUI.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if plan.suggestions.isEmpty {
                        RevertInfoNote(
                            text: "No fuel stations were found within \(Units.distanceText(5_000, decimals: 0)) of this route. Plan a manual stop.",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text("Check fuel stations along this route.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                    Spacer(minLength: 6)
                    Button {
                        RevertHaptics.tap()
                        Task { await load() }
                    } label: {
                        Text("Check")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(MapUI.cyan)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(MapUI.cyan.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(RevertCardButtonStyle())
                }
            }
        }
        .padding(14)
        .background(MapUI.surfaceHigh.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MapUI.line, lineWidth: 0.8)
        }
        .task(id: route.id) { await load() }
        .onChange(of: tankFraction) { _, _ in
            // The file has been open while the rider changes the tank level in
            // Settings; recompute instead of keeping the old usable range.
            plan = nil
            Task { await load() }
        }
    }

    private var effectiveRangeKm: Double {
        // An explicitly chosen primary bike wins. With a single bike the
        // Garage may not have promoted it yet, so use the first bike rather
        // than silently falling back to the profile's default range.
        garageBikes.first(where: \.isPrimary)?.fuelRangeKm
            ?? garageBikes.first?.fuelRangeKm
            ?? rangeKm
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        let routeKm = route.length / 1_000
        let usable = max(effectiveRangeKm * min(max(tankFraction, 0.1), 1), 1)
        if routeKm <= usable {
            plan = FuelService.plan(route: route, rangeKm: effectiveRangeKm, tankFraction: tankFraction, stations: [])
            loading = false
            return
        }
        let stations = await FuelService.stations(along: route)
        guard !Task.isCancelled else { loading = false; return }
        plan = FuelService.plan(route: route, rangeKm: effectiveRangeKm, tankFraction: tankFraction, stations: stations)
        loading = false
    }
}
