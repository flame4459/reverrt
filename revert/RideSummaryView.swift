import SwiftUI
import MapKit

/// Shown immediately after a ride is saved, so the rider sees the numbers
/// (especially max lean) before returning to the map.
struct RideSavedSummaryView: View {
    let ride: Ride
    let onDone: () -> Void

    @AppStorage("rider.name") private var riderName = ""
    @AppStorage("share.includeReplay") private var includeReplay = true
    @State private var showingLeaderboard = false

    private var averageSpeed: Double {
        ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
    }

    private let leanScale = 60.0

    private var leanFraction: Double {
        min(max(ride.maxLeanAngleDegrees / leanScale, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroMap
                    heading
                    statsCard
                    rivalsCard

                    Button(action: onDone) {
                        Text("Done")
                    }
                    .buttonStyle(RevertPrimaryButtonStyle())
                    .accessibilityIdentifier(AccessibilityID.Summary.done)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .pulseBackground()
            .scrollIndicators(.hidden)
            .navigationTitle(ride.isCar ? "Drive summary" : "Ride summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        RevertHaptics.tap()
                        onDone()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close ride summary")
                    .accessibilityIdentifier(AccessibilityID.Summary.close)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingLeaderboard) {
            RouteLeaderboardView(
                title: ride.routeName ?? "This loop",
                routeKey: ride.routeKey ?? "",
                savedRouteID: ride.savedRouteID,
                routeName: ride.routeName,
                laps: max(ride.laps, 1),
                isSprint: ride.isSprint
            )
        }
    }

    private var shareResult: RivalResult? {
        RivalResult.from(ride: ride, rider: riderName, routeName: ride.routeName,
                         includeTrack: includeReplay)
    }

    private var shareURL: URL? {
        shareResult.flatMap(RivalLink.url)
    }

    @ViewBuilder
    private var rivalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RevertSectionLabel(title: "Rivals")

            Text(shareURL == nil
                 ? "Save this loop to keep a leaderboard for it, then share your time with the people you ride with."
                 : "Send this ride as a link. When a friend sends theirs back, both names sort into the leaderboard for this loop.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if shareURL != nil {
                Toggle("Include the ride replay", isOn: $includeReplay)
                    .tint(MapUI.cyan)
                    .font(.system(.subheadline, design: .rounded))
                Text(includeReplay
                     ? "The GPS trace travels with the link so they can watch the ride."
                     : "Time only. No coordinates travel with this link.")
                    .font(.scaledSystem(size: 10, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                Button {
                    RevertHaptics.tap()
                    showingLeaderboard = true
                } label: {
                    Label("Leaderboard", systemImage: "trophy")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 46))

                if let shareURL, let shareResult {
                    ShareLink(
                        item: shareURL,
                        subject: Text("Revert time on \(ride.routeName ?? "this loop")"),
                        message: Text("Beat my time on \(ride.routeName ?? "this loop"): \(Units.clock(shareResult.durationSeconds))")
                    ) {
                        Label(ride.isCar
                              ? (includeReplay ? "Share drive" : "Share time")
                              : (includeReplay ? "Share ride" : "Share time"),
                              systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(RevertPrimaryButtonStyle(minHeight: 46))
                }
            }
        }
        .revertCard()
    }

    private var heroMap: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Map {
                    // A dark casing keeps the route readable over city labels.
                    MapPolyline(coordinates: ride.points.map(\.coordinate))
                        .stroke(.black.opacity(0.55), lineWidth: 9)
                    MapPolyline(coordinates: ride.points.map(\.coordinate))
                        .stroke(MapUI.cyan, lineWidth: 5)
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
                .frame(height: 200)
                .overlay {
                    Color.black.opacity(0.12)
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.black.opacity(0.62), .clear, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                RevertChip(title: ride.isCar ? "Drive complete" : "Ride complete",
                           systemImage: "flag.checkered", isSelected: true, tint: MapUI.emerald)
                    .padding(14)
            }

            HStack(spacing: 0) {
                summaryStat("Distance", Units.distanceText(ride.distanceMeters, decimals: 1))
                summaryDivider
                summaryStat("Time", Units.clock(ride.durationSeconds))
                summaryDivider
                summaryStat("Avg speed", Units.speedText(averageSpeed, decimals: 1))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(MapUI.panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [MapUI.cyan.opacity(0.40), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.45), radius: 20, y: 9)
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(MapUI.textTertiary)
            Text(value)
                .font(.scaledSystem(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MapUI.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(MapUI.line)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ride.isCar ? "DRIVE SAVED" : "RIDE SAVED")
                .font(RevertType.eyebrow)
                .tracking(1.7)
                .foregroundStyle(MapUI.emerald)
            Text(ride.isCar ? "Nice drive." : "Nice ride.")
                .font(RevertType.display(30, weight: .heavy))
                .foregroundStyle(MapUI.ink)
            Text(RevertFormat.fullDateTime(ride.startDate))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .lineLimit(2)

            HStack(spacing: 5) {
                Image(systemName: ride.vehicleKind.icon)
                    .font(.scaledSystem(size: 10, weight: .bold))
                Text(ride.bikeDisplayName)
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(MapUI.textTertiary)
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RevertSectionLabel(title: ride.isCar ? "Drive telemetry" : "Ride telemetry")

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke((ride.isCar ? MapUI.emerald : Pulse.lean).opacity(0.18), lineWidth: 9)
                    if ride.isCar {
                        Circle()
                            .stroke(MapUI.emerald.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        VStack(spacing: 3) {
                            Image(systemName: "car.fill")
                                .font(.scaledSystem(size: 25, weight: .bold))
                                .foregroundStyle(MapUI.emerald)
                            Text("CAR")
                                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(MapUI.textTertiary)
                        }
                    } else {
                        Circle()
                            .trim(from: 0, to: leanFraction)
                            .stroke(Pulse.lean, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(Int(ride.maxLeanAngleDegrees.rounded()))°")
                                    .font(RevertType.number(30))
                                    .foregroundStyle(Pulse.lean)
                                Text("/ \(Int(leanScale))°")
                                    .font(.scaledSystem(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                            Text("MAX LEAN")
                                .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(MapUI.textTertiary)
                        }
                    }
                }
                .frame(width: 106, height: 106)
                .accessibilityLabel(ride.isCar
                                    ? "Car drive"
                                    : "Maximum lean \(Int(ride.maxLeanAngleDegrees.rounded())) degrees")

                VStack(spacing: 9) {
                    if ride.isSprint {
                        RevertKeyValueRow(label: "Type", value: "Sprint")
                    } else {
                        RevertKeyValueRow(label: "Laps", value: "\(max(ride.laps, 1))")
                    }
                    RevertKeyValueRow(label: "Top speed", value: Units.speedText(ride.maxSpeedMps))
                    RevertKeyValueRow(label: "Climbed", value: Units.elevationText(ride.elevationGainMeters))
                }
            }

            Rectangle().fill(MapUI.line).frame(height: 0.8)

            HStack(spacing: 0) {
                RevertStatTile(label: "Started", value: ride.startDate.formatted(date: .omitted, time: .shortened))
                Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 10)
                RevertStatTile(label: "Stored", value: "On device", tint: MapUI.emerald)
            }
        }
        .revertCard()
    }
}
