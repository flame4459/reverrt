import SwiftUI
import MapKit

/// Shown immediately after a ride is saved, so the rider sees the numbers
/// (especially max lean) before returning to the map.
struct RideSavedSummaryView: View {
    let ride: Ride
    let onDone: () -> Void

    @State private var camera: MapCameraPosition = .automatic

    private var averageSpeed: Double {
        ride.durationSeconds > 0 ? ride.distanceMeters / ride.durationSeconds : 0
    }

    private var leanFraction: Double {
        min(max(ride.maxLeanAngleDegrees / 60, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroMap
                    heading
                    statsCard

                    Button(action: onDone) {
                        Text("Done")
                    }
                    .buttonStyle(RiderPrimaryButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(MapUI.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Ride summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        RiderHaptics.tap()
                        onDone()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close ride summary")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var heroMap: some View {
        ZStack(alignment: .topLeading) {
            Map {
                MapPolyline(coordinates: ride.points.map(\.coordinate))
                    .stroke(MapUI.cyan, lineWidth: 5)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .frame(height: 236)

            LinearGradient(
                colors: [.black.opacity(0.68), .clear, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7) {
                RiderChip(title: "Ride complete", systemImage: "flag.checkered", isSelected: true, tint: MapUI.emerald)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Units.distanceText(ride.distanceMeters, decimals: 1))
                        .font(RiderType.number(24))
                        .foregroundStyle(.white)
                    Text(Units.clock(ride.durationSeconds))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(14)
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RIDE SAVED")
                .font(RiderType.eyebrow)
                .tracking(1.7)
                .foregroundStyle(MapUI.emerald)
            Text("Nice ride.")
                .font(RiderType.display(30, weight: .heavy))
                .foregroundStyle(MapUI.ink)
            Text(ride.startDate.formatted(date: .complete, time: .shortened))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .lineLimit(2)

            HStack(spacing: 5) {
                Image(systemName: "motorcycle")
                    .font(.system(size: 10, weight: .bold))
                Text(ride.bikeDisplayName)
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(MapUI.textTertiary)
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RiderSectionLabel(title: "Ride telemetry")

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(MapUI.magenta.opacity(0.18), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: leanFraction)
                        .stroke(MapUI.magenta, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(ride.maxLeanAngleDegrees.rounded()))°")
                            .font(RiderType.number(30))
                            .foregroundStyle(MapUI.magenta)
                        Text("MAX LEAN")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(MapUI.textTertiary)
                    }
                }
                .frame(width: 106, height: 106)
                .accessibilityLabel("Maximum lean \(Int(ride.maxLeanAngleDegrees.rounded())) degrees")

                VStack(spacing: 9) {
                    RiderKeyValueRow(label: "Distance", value: Units.distanceText(ride.distanceMeters, decimals: 1))
                    RiderKeyValueRow(label: "Time", value: Units.clock(ride.durationSeconds))
                    RiderKeyValueRow(label: "Avg speed", value: Units.speedText(averageSpeed, decimals: 1))
                    RiderKeyValueRow(label: "Top speed", value: Units.speedText(ride.maxSpeedMps))
                    RiderKeyValueRow(label: "Climbed", value: Units.elevationText(ride.elevationGainMeters))
                }
            }

            Rectangle().fill(MapUI.line).frame(height: 0.8)

            HStack(spacing: 0) {
                RiderStatTile(label: "Started", value: ride.startDate.formatted(date: .omitted, time: .shortened))
                Rectangle().fill(MapUI.line).frame(width: 1, height: 24).padding(.horizontal, 10)
                RiderStatTile(label: "Stored", value: "On device", tint: MapUI.emerald)
            }
        }
        .riderCard()
    }
}
