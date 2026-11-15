import SwiftUI
import SwiftData

/// Story poster entry point. The preview shows the chosen theme with the
/// latest ride; the real renderer (and the share sheet) lives in the existing
/// StoryPosterStudio, which this screen opens with the ride's actual track.
struct PulsePostersView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]

    @State private var theme: StoryPosterTheme = .oled
    @State private var style: StoryPosterStyle = {
        #if DEBUG
        if CommandLine.arguments.contains("-debugPosterMinimal") { return .minimal }
        if CommandLine.arguments.contains("-debugPosterDashboard") { return .dashboard }
        #endif
        return .classic
    }()
    @State private var target: PosterTarget?

    private var featuredRide: Ride? { rides.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let ride = featuredRide {
                    Menu {
                        ForEach(StoryPosterTheme.allCases) { option in
                            Button {
                                RevertHaptics.select()
                                withAnimation(RevertMotion.snappy) { theme = option }
                            } label: {
                                if theme == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            LinearGradient(colors: theme.background,
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                                .frame(width: 20, height: 20)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(theme.ink.opacity(0.25), lineWidth: 0.7))

                            VStack(alignment: .leading, spacing: 1) {
                                Text("THEME")
                                    .font(.scaledSystem(size: 8, weight: .heavy, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundStyle(Pulse.muted)
                                Text(theme.title)
                                    .font(.scaledSystem(size: 12, weight: .semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.scaledSystem(size: 11, weight: .bold))
                                .foregroundStyle(Pulse.mutedStrong)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(Pulse.panelHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Pulse.lineSoft, lineWidth: 0.8)
                        }
                    }
                    .accessibilityLabel("Theme, \(theme.title)")

                    PulseSegmented(options: StoryPosterStyle.allCases, selection: $style) { $0.title }

                    Text(style.blurb)
                        .font(.scaledSystem(size: 10))
                        .foregroundStyle(Pulse.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    poster(ride: ride)
                        .frame(maxWidth: .infinity)

                    Button {
                        openStudio(for: ride)
                    } label: {
                        Label("Open studio", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(PulsePrimaryButtonStyle())

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
                    .font(.scaledSystem(size: 10))
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
            StoryPosterStudio(ride: target.ride, points: target.points, turns: target.turns,
                              initialTheme: theme, initialStyle: style)
        }
    }

    private var header: some View {
        ScreenHeader(eyebrow: "",
                     title: "Story posters",
                     variant: .compact,
                     identifier: AccessibilityID.Posters.title) {
            PulseCircleButton(systemImage: "xmark",
                              tint: Pulse.mutedStrong,
                              label: "Close story posters",
                              identifier: AccessibilityID.Posters.close) {
                dismiss()
            }
        }
    }

    private func poster(ride: Ride) -> some View {
        let turns = RideAnalysis.turns(from: ride.points)
        return StoryPosterView(ride: ride, points: ride.points, turns: turns,
                               theme: theme, style: style)
            .scaleEffect(0.30, anchor: .center)
            .frame(width: 1080 * 0.30, height: 1350 * 0.30)
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
                                .font(.scaledSystem(size: 15, weight: .semibold))
                                .foregroundStyle(Pulse.accent)
                                .frame(width: 38, height: 38)
                                .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(ride.routeName ?? "Recorded ride")
                                    .font(.scaledSystem(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Pulse.ink)
                                    .lineLimit(1)
                                Text("\(ride.startDate.formatted(date: .abbreviated, time: .omitted))  •  \(Units.distanceText(ride.distanceMeters, decimals: 1))")
                                    .font(.scaledSystem(size: 10))
                                    .foregroundStyle(Pulse.muted)
                            }

                            Spacer(minLength: 6)

                            Image(systemName: "chevron.right")
                                .font(.scaledSystem(size: 10, weight: .bold))
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
