import ActivityKit
import WidgetKit
import SwiftUI

struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.offRoute ? "arrow.triangle.2.circlepath" : "location.north.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(context.state.offRoute ? .orange : Color(red: 0.15, green: 0.9, blue: 1.0))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                    Text("\(context.state.distance)  •  \(context.state.speed)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("RIDER")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.15, green: 0.9, blue: 1.0))
                    Link(destination: URL(string: "rider://end")!) {
                        Label("End", systemImage: "xmark")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.offRoute ? "arrow.triangle.2.circlepath" : "location.north.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(context.state.offRoute ? .orange : Color(red: 0.15, green: 0.9, blue: 1.0))
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
                        Link(destination: URL(string: "rider://end")!) {
                            Label("End route", systemImage: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(Color(red: 0.15, green: 0.9, blue: 1.0))
            } compactTrailing: {
                Text(context.state.distance)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(Color(red: 0.15, green: 0.9, blue: 1.0))
            }
            .keylineTint(Color(red: 0.15, green: 0.9, blue: 1.0))
        }
    }
}
