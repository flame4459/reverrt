import WidgetKit
import SwiftUI

struct RiderQuickEntry: TimelineEntry {
    let date: Date
    let bikeName: String?
    let odometerKm: Double?
    let lastRideMeters: Double?
    let lastRideDate: Date?
    let lastRideName: String?
    let metric: Bool

    static func current() -> RiderQuickEntry {
        let defaults = UserDefaults(suiteName: "group.com.davidmolina.MyApp")
        let stamp = defaults?.double(forKey: "widget.lastRideDate") ?? 0
        let odometer = defaults?.object(forKey: "widget.odometerKm") != nil
            ? defaults?.double(forKey: "widget.odometerKm") : nil
        let lastMeters = defaults?.object(forKey: "widget.lastRideMeters") != nil
            ? defaults?.double(forKey: "widget.lastRideMeters") : nil
        return RiderQuickEntry(
            date: Date(),
            bikeName: defaults?.string(forKey: "widget.bikeName"),
            odometerKm: odometer,
            lastRideMeters: lastMeters,
            lastRideDate: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil,
            lastRideName: defaults?.string(forKey: "widget.lastRideName"),
            metric: defaults?.bool(forKey: "widget.metric") ?? false
        )
    }
}

struct RiderQuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> RiderQuickEntry {
        RiderQuickEntry(date: Date(), bikeName: "Multistrada V4", odometerKm: 12_480,
                        lastRideMeters: 92_000, lastRideDate: Date(),
                        lastRideName: "Sunday loop", metric: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (RiderQuickEntry) -> Void) {
        completion(RiderQuickEntry.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RiderQuickEntry>) -> Void) {
        completion(Timeline(entries: [RiderQuickEntry.current()], policy: .never))
    }
}

struct RiderQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RiderQuickWidget", provider: RiderQuickProvider()) { entry in
            RiderQuickWidgetView(entry: entry)
        }
        .configurationDisplayName("Rider")
        .description("Your bike, last ride and quick links.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RiderQuickWidgetView: View {
    let entry: RiderQuickEntry
    private let cyan = Color(red: 0.15, green: 0.9, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("RIDER")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(cyan)
                Spacer(minLength: 0)
                Image(systemName: "motorcycle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let bike = entry.bikeName, !bike.isEmpty {
                Text(bike)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let odometer = entry.odometerKm {
                    Text("\(distance(odometer * 1_000)) on the clock")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            } else {
                Text("No bike in the garage yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }

            if let meters = entry.lastRideMeters, let date = entry.lastRideDate {
                Text("Last: \(distance(meters)) · \(date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Link(destination: URL(string: "rider://plan")!) {
                    Label("Plan", systemImage: "map.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(cyan, in: Capsule())
                }
                Link(destination: URL(string: "rider://garage")!) {
                    Label("Garage", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(.white.opacity(0.10), in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .containerBackground(.black, for: .widget)
    }

    private func distance(_ meters: Double) -> String {
        if entry.metric {
            let km = meters / 1_000
            return km >= 10 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
        }
        let miles = meters / 1_609.344
        return miles >= 10 ? "\(Int(miles.rounded())) mi" : String(format: "%.1f mi", miles)
    }
}
