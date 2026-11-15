import SwiftUI
import SwiftData

/// Ride analytics drawn from the real recorded rides: totals, personal
/// bests, the last ten outings and the machine that did most of the work.
struct PulseInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]

    private var totalDistance: Double { rides.reduce(0) { $0 + $1.distanceMeters } }
    private var totalTime: Double { rides.reduce(0) { $0 + $1.durationSeconds } }
    private var longest: Double { rides.map(\.distanceMeters).max() ?? 0 }
    private var bestLean: Double { rides.map(\.maxLeanAngleDegrees).max() ?? 0 }
    private var hasMotorcycle: Bool { rides.contains { $0.vehicleKind == .motorcycle } }
    private var averageDistance: Double {
        rides.isEmpty ? 0 : totalDistance / Double(rides.count)
    }
    private var bestAverageSpeed: Double {
        rides.map(\.averageSpeedMps).max() ?? 0
    }
    private var ridesThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return rides.filter {
            calendar.component(.year, from: $0.startDate) == calendar.component(.year, from: now)
                && calendar.component(.month, from: $0.startDate) == calendar.component(.month, from: now)
        }.count
    }
    private var favoriteBike: String? {
        Dictionary(grouping: rides, by: \.bikeDisplayName)
            .max { $0.value.count < $1.value.count }?.key
    }
    private var recentRides: [Ride] {
        Array(rides.prefix(10)).reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if rides.isEmpty {
                    PulseEmptyState(
                        systemImage: "chart.bar",
                        title: "No rides to analyse",
                        message: "Record a ride or import a GPX track and your distance, pace, lean and time will show up here."
                    )
                    .pulseCard()
                } else {
                    hero
                    metrics
                    activity
                    analysis
                }
            }
            .padding(.horizontal, PulseMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pulseBackground()
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        ScreenHeader(eyebrow: "",
                     title: "Your insights",
                     variant: .compact,
                     identifier: AccessibilityID.Insights.title) {
            PulseCircleButton(systemImage: "xmark",
                              tint: Pulse.mutedStrong,
                              label: "Close insights",
                              identifier: AccessibilityID.Insights.close) {
                dismiss()
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISTANCE EXPLORED")
                .font(PulseType.eyebrow)
                .tracking(2)
                .foregroundStyle(Pulse.accent)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Units.distanceText(totalDistance, decimals: 0)
                    .replacingOccurrences(of: " \(Units.distanceUnit)", with: ""))
                    .font(PulseType.number(44, weight: .heavy))
                    .tracking(-1.6)
                    .foregroundStyle(Pulse.ink)
                Text(Units.distanceUnit.uppercased())
                    .font(.scaledSystem(size: 12, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Pulse.accent)
            }
            Text("Across \(rides.count) saved ride\(rides.count == 1 ? "" : "s")")
                .font(.scaledSystem(size: 12))
                .foregroundStyle(Pulse.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.heroGradient)
                .overlay(alignment: .topTrailing) {
                    RadialGradient(
                        colors: [Pulse.accent.opacity(0.14), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 190
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.accentDeep.opacity(0.42), lineWidth: 0.8)
                }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            PulseMetric(label: "Average ride", value: distanceValue(averageDistance), unit: Units.distanceUnit)
            PulseMetric(label: "Longest ride", value: distanceValue(longest), unit: Units.distanceUnit)
            PulseMetric(label: "Total time", value: RevertFormat.duration(totalTime))
            if hasMotorcycle {
                PulseMetric(label: "Max lean", value: "\(Int(bestLean.rounded()))°", tint: Pulse.lean)
            } else {
                PulseMetric(label: "Cars", value: "\(rides.filter(\.isCar).count)", tint: MapUI.emerald)
            }
        }
    }

    private var activityRides: [Ride] {
        Array(rides.prefix(8))
    }

    private var maxActivityDistance: Double {
        max(activityRides.map(\.distanceMeters).max() ?? 0, 1)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionHeader(title: "Ride activity")
                .padding(.top, 2)

            if activityRides.isEmpty {
                Text("No rides to chart yet.")
                    .font(.scaledSystem(size: 12))
                    .foregroundStyle(Pulse.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pulseCard()
            } else {
                VStack(spacing: 11) {
                    ForEach(activityRides) { ride in
                        HStack(spacing: 9) {
                            Text(RevertFormat.shortDate(ride.startDate))
                                .font(.scaledSystem(size: 10, weight: .semibold))
                                .foregroundStyle(Pulse.mutedStrong)
                                .frame(width: 52, alignment: .leading)

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Pulse.line.opacity(0.55))
                                    Capsule()
                                        .fill(Pulse.accentGradient)
                                        .frame(width: max(6, proxy.size.width * min(ride.distanceMeters / maxActivityDistance, 1)))
                                }
                            }
                            .frame(height: 7)

                            Text(Units.distanceText(ride.distanceMeters, decimals: 1))
                                .font(.scaledSystem(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Pulse.ink)
                                .frame(width: 62, alignment: .trailing)

                            Text(RevertFormat.duration(ride.durationSeconds))
                                .font(.scaledSystem(size: 9.5))
                                .foregroundStyle(Pulse.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(RevertFormat.shortDate(ride.startDate)), \(Units.distanceText(ride.distanceMeters, decimals: 1)), \(RevertFormat.duration(ride.durationSeconds))")
                    }
                }
                .pulseCard()
            }
        }
    }

    private var analysis: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "More analysis")

            VStack(spacing: 0) {
                analysisRow(
                    icon: "speedometer",
                    title: "Best average speed",
                    detail: Units.speedText(bestAverageSpeed),
                    tint: Pulse.accent
                )
                divider
                analysisRow(
                    icon: "calendar",
                    title: "Rides this month",
                    detail: "\(ridesThisMonth)",
                    tint: Pulse.accent
                )
                divider
                analysisRow(
                    icon: "motorcycle",
                    title: "Most ridden machine",
                    detail: favoriteBike ?? "—",
                    tint: Pulse.warning
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Pulse.line, lineWidth: 0.8)
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.scaledSystem(size: 9, weight: .bold))
                    .padding(.top, 2)
                Text("Insights are calculated on this iPhone from the rides in History. Ride History is the only place they are stored.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.scaledSystem(size: 10))
            .foregroundStyle(Pulse.muted)
            .padding(.top, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Pulse.lineSoft)
            .frame(height: 0.8)
    }

    private func analysisRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.scaledSystem(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.scaledSystem(size: 12, weight: .medium))
                .foregroundStyle(Pulse.ink)
            Spacer(minLength: 8)
            Text(detail)
                .font(.scaledSystem(size: 12, weight: .bold))
                .foregroundStyle(Pulse.mutedStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func distanceValue(_ meters: Double) -> String {
        RevertFormat.number(Units.distanceValue(meters), decimals: 1)
    }

}
