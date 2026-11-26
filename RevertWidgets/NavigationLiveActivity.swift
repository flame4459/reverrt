import ActivityKit
import WidgetKit
import SwiftUI

/// iOS 18+ Live Activity. Declares the small activity family that the Watch
/// Smart Stack (and car dashboards showing iPhone widgets) use, so the card can
/// adapt to it.
@available(iOS 18.0, *)
struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            RideActivityCardHost(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            navigationDynamicIsland(context)
        }
        // The small family is what the Apple Watch Smart Stack uses, and what
        // car dashboards show when they display iPhone widgets. Declaring it is
        // what makes this Live Activity eligible for those surfaces.
        .supplementalActivityFamilies([.small])
    }
}

/// The Dynamic Island layout for the navigation activity.
private func navigationDynamicIsland<Attributes: ActivityAttributes>(
    _ context: ActivityViewContext<Attributes>
) -> DynamicIsland where Attributes.ContentState == NavigationActivityAttributes.ContentState {
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
            Image(systemName: context.state.turnSymbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(context.state.offRoute ? .orange : RideActivityCard.cyan)
        }
        DynamicIslandExpandedRegion(.center) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(2)
        }
        DynamicIslandExpandedRegion(.trailing) {
            Text(context.state.distance)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
            HStack(spacing: 10) {
                Text(context.state.speed)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link(destination: URL(string: "revert://end")!) {
                    Label("End route", systemImage: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .tint(.red)
            }
        }
    } compactLeading: {
        Image(systemName: context.state.turnSymbol)
            .foregroundStyle(RideActivityCard.cyan)
    } compactTrailing: {
        Text(context.state.distance)
            .font(.caption.weight(.bold))
            .monospacedDigit()
    } minimal: {
        Image(systemName: context.state.turnSymbol)
            .foregroundStyle(RideActivityCard.cyan)
    }
    .keylineTint(RideActivityCard.cyan)
}

/// Reads the iOS 18 activity family (Watch Smart Stack / car dashboard)
/// and hands the result to the shared card.
@available(iOS 18.0, *)
private struct RideActivityCardHost: View {
    @Environment(\.activityFamily) private var family
    let state: NavigationActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        RideActivityCard(state: state, isSmallFamily: family == .small, isStale: isStale)
    }
}

/// Two layouts for one activity: the phone gets the wide lock-screen card with
/// its End shortcut, the car gets a three-fact card it can be read at a glance.
private struct RideActivityCard: View {
    let state: NavigationActivityAttributes.ContentState
    /// Only ever true on iOS 18+, where the small family exists.
    var isSmallFamily = false
    /// True when the activity has not been updated for its stale interval —
    /// usually because Revert was force-quit mid-ride. Better an honest
    /// "not updating" card than a turn from ten minutes ago.
    var isStale = false

    static let cyan = Color(red: 0.15, green: 0.9, blue: 1.0)
    private var accent: Color { state.offRoute ? .orange : Self.cyan }

    var body: some View {
        if isStale {
            staleCard
        } else if isSmallFamily {
            carCard
        } else {
            phoneCard
        }
    }

    private var staleCard: some View {
        Link(destination: URL(string: "revert://drive")!) {
            VStack(alignment: .leading, spacing: 4) {
                Text("REVERT")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Self.cyan)
                Spacer(minLength: 0)
                Text("Not updating")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Open Revert to continue")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Dashboard card. Deliberately has no controls: most head units pass
    /// touches through badly or not at all, and an accidental "End ride" at
    /// speed is worse than reaching for the phone. Ending stays on the phone
    /// and the helmet audio cues.
    @ViewBuilder
    private var carCard: some View {
        if let name = state.mapImage, let image = LiveMapImage.load(name) {
            mapCard(image)
        } else {
            plainCarCard
        }
    }

    /// The map-first card. The image is a heading-up slice rendered by the app;
    /// the bars on top and bottom are the same information the plain card
    /// carries, so the dashboard reads like a navigation banner with a map
    /// instead of a list of facts.
    private func mapCard(_ image: UIImage) -> some View {
        Link(destination: URL(string: "revert://drive")!) {
            mapCardBody(image)
        }
    }

    private func mapCardBody(_ image: UIImage) -> some View {
        ZStack {
            // GeometryReader keeps the bitmap out of the layout: a 16:9 image
            // in a short dashboard slot otherwise stretches the card and clips
            // the bars at its edges.
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }

            LinearGradient(colors: [.black.opacity(0.62), .black.opacity(0.05), .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: state.turnSymbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                    Text(state.distance)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text("REVERT")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 9)
                .padding(.top, 6)

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(state.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white.opacity(0.95))
                    Spacer(minLength: 0)
                    if let hazard = state.hazard {
                        Text(hazard)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    HStack(spacing: 3) {
                        Text(state.remaining)
                        Text("·")
                        Text(state.eta)
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.14))
                    Rectangle()
                        .fill(accent)
                        .frame(width: geometry.size.width * max(0, min(state.progress, 1)))
                }
            }
            .frame(height: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var plainCarCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: state.turnSymbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                Text("REVERT")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(accent)
            }

            Text(state.distance)
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(state.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(0.92))

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Text(state.remaining)
                Text("·")
                Text(state.eta)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var phoneCard: some View {
        HStack(spacing: 14) {
            Image(systemName: state.offRoute ? "arrow.triangle.2.circlepath" : "location.north.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                Text("\(state.distance)  •  \(state.speed)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text("REVERT")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Self.cyan)
                Link(destination: URL(string: "revert://end")!) {
                    Label("End", systemImage: "xmark")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
    }
}
