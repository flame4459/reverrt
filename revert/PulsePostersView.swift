import SwiftUI
import SwiftData

/// Story poster entry point. The preview shows the chosen theme with the
/// latest ride; the real renderer (and the share sheet) lives in the existing
/// StoryPosterStudio, which this screen opens with the ride's actual track.
struct PulsePostersView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]

    @State private var theme: StoryPosterTheme = .oled
    @State private var target: PosterTarget?

    private var featuredRide: Ride? { rides.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let ride = featuredRide {
                    PulseSegmented(options: StoryPosterTheme.allCases, selection: $theme) { theme in
                        switch theme {
                        case .oled: "Midnight"
                        case .sunset: "Sunset"
                        case .topo: "Topo"
                        case .paper: "Journal"
                        }
                    }

                    poster(ride: ride)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 9) {
                        Button {
                            openStudio(for: ride)
                        } label: {
                            Label("Open studio", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(PulsePrimaryButtonStyle())

                        Button {
                            dismiss()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .buttonStyle(PulseGhostButtonStyle())
                    }

                    moreRides
                } else {
                    PulseEmptyState(
                        systemImage: "photo.artframe",
                        title: "No ride to turn into a poster",
                        message: "Record a ride first, then come back to render it as a 1080 × 1350 story image."
                    )
                    .pulseCard()
                }

                Text("Posters are rendered on this iPhone from the recorded track. Nothing is uploaded, and the export is a normal image in your share sheet.")
                    .font(.system(size: 10))
                    .foregroundStyle(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, PulseMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pulseBackground()
        .presentationDragIndicator(.visible)
        .sheet(item: $target) { target in
            StoryPosterStudio(ride: target.ride, points: target.points, turns: target.turns)
        }
    }

    private var header: some View {
        PulseScreenHeader(eyebrow: "SHARE THE RIDE", title: "Story posters") {
            PulseCircleButton(systemImage: "xmark", tint: Pulse.mutedStrong, label: "Close story posters") {
                dismiss()
            }
        }
    }

    private func poster(ride: Ride) -> some View {
        ZStack {
            LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing)

            // The same route silhouette the real poster draws, kept coarse so
            // it stays light in the preview.
            Canvas { context, size in
                var grid = Path()
                stride(from: 0.0, through: size.width, by: 28).forEach { x in
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: 0.0, through: size.height, by: 28).forEach { y in
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(theme.ink.opacity(0.03)), lineWidth: 0.6)

                // The ride's own silhouette. This is the same geometry the
                // real poster renders, normalized into the card's centre so
                // the preview is about this ride, not a stock illustration.
                let track = ride.points
                guard track.count > 1 else { return }
                var minLat = track[0].lat, maxLat = track[0].lat
                var minLon = track[0].lon, maxLon = track[0].lon
                for point in track {
                    minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
                    minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
                }
                let inset: CGFloat = size.width * 0.12
                let usable = CGRect(
                    x: inset,
                    y: size.height * 0.15,
                    width: size.width - inset * 2,
                    height: size.height * 0.20
                )
                let lonSpan = max(maxLon - minLon, 1e-6)
                let latSpan = max(maxLat - minLat, 1e-6)
                let scale = min(usable.width / lonSpan, usable.height / latSpan)
                let centerLon = (minLon + maxLon) / 2
                let centerLat = (minLat + maxLat) / 2
                func point(_ p: RidePoint) -> CGPoint {
                    CGPoint(
                        x: usable.midX + (p.lon - centerLon) * scale,
                        y: usable.midY - (p.lat - centerLat) * scale
                    )
                }
                var routePath = Path()
                routePath.move(to: point(track[0]))
                for p in track.dropFirst() { routePath.addLine(to: point(p)) }
                context.stroke(
                    routePath,
                    with: .color(theme.accent.opacity(0.10)),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    routePath,
                    with: .color(theme.accent.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                if let start = track.first {
                    let p = point(start)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                        with: .color(theme.accent)
                    )
                }
                if let end = track.last {
                    let p = point(end)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                        with: .color(theme.secondaryAccent)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("REVERT / STORY")
                            .font(.system(size: 10, weight: .black))
                            .tracking(3)
                            .foregroundStyle(theme.accent)
                        Text(ride.startDate.formatted(date: .abbreviated, time: .omitted).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(theme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "motorcycle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.secondaryAccent)
                }

                Spacer(minLength: 18)

                Text(ride.routeName ?? "A ride worth remembering")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(theme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)

                Rectangle()
                    .fill(theme.ink.opacity(0.22))
                    .frame(height: 1)
                    .padding(.vertical, 12)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.1f", Units.distanceValue(ride.distanceMeters)))
                        .font(.system(size: 29, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(theme.ink)
                    Text("\(Units.distanceUnit.uppercased()) EXPLORED")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryInk)
                    Spacer()
                    Text("\(Int(ride.maxLeanAngleDegrees.rounded()))° LEAN")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryAccent)
                }

                Spacer(minLength: 12)

                Text("KEEP MOVING  •  KEEP EXPLORING")
                    .font(.system(size: 8, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(theme.secondaryInk)
            }
            .padding(18)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: 290)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Pulse.lineBright, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Story poster preview for \(ride.routeName ?? "your ride")")
    }

    private var moreRides: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "More rides")

            VStack(spacing: 8) {
                ForEach(rides.prefix(6)) { ride in
                    Button {
                        openStudio(for: ride)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Pulse.accent)
                                .frame(width: 38, height: 38)
                                .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(ride.routeName ?? "Recorded ride")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                                Text("\(ride.startDate.formatted(date: .abbreviated, time: .omitted))  •  \(Units.distanceText(ride.distanceMeters, decimals: 1))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Pulse.muted)
                            }

                            Spacer(minLength: 6)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Pulse.muted)
                        }
                        .padding(11)
                        .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Pulse.line, lineWidth: 0.8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RevertCardButtonStyle())
                }
            }
        }
    }

    private func openStudio(for ride: Ride) {
        RevertHaptics.tap()
        let points = ride.points
        target = PosterTarget(
            ride: ride,
            points: points,
            turns: RideAnalysis.turns(from: points)
        )
    }
}

private struct PosterTarget: Identifiable {
    let ride: Ride
    let points: [RidePoint]
    let turns: [RideTurn]

    var id: String { String(describing: ride.persistentModelID) }
}
