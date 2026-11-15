import WidgetKit
import SwiftUI

struct RevertQuickEntry: TimelineEntry {
    let date: Date
    let bikeName: String?
    let odometerKm: Double?
    let lastRideMeters: Double?
    let lastRideDate: Date?
    let lastRideName: String?
    let metric: Bool
    let rideActive: Bool
    let activeRouteName: String?
    let car: CarWidgetSnapshot?
    let vehicleKind: String?

    static func current() -> RevertQuickEntry {
        let defaults = UserDefaults(suiteName: "group.com.davidmolina.Revert")
        let stamp = defaults?.double(forKey: "widget.lastRideDate") ?? 0
        let odometer = defaults?.object(forKey: "widget.odometerKm") != nil
            ? defaults?.double(forKey: "widget.odometerKm") : nil
        let lastMeters = defaults?.object(forKey: "widget.lastRideMeters") != nil
            ? defaults?.double(forKey: "widget.lastRideMeters") : nil
        var car: CarWidgetSnapshot?
        if let data = defaults?.data(forKey: "widget.carState") {
            car = try? JSONDecoder().decode(CarWidgetSnapshot.self, from: data)
            if car == nil {
                WidgetDebugLog.log("decode-failed", ["bytes": "\(data.count)"])
            }
        }
        return RevertQuickEntry(
            date: Date(),
            bikeName: defaults?.string(forKey: "widget.bikeName"),
            odometerKm: odometer,
            lastRideMeters: lastMeters,
            lastRideDate: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil,
            lastRideName: defaults?.string(forKey: "widget.lastRideName"),
            metric: defaults?.bool(forKey: "widget.metric") ?? false,
            rideActive: defaults?.bool(forKey: "widget.rideActive") ?? false,
            activeRouteName: defaults?.string(forKey: "widget.activeRouteName"),
            car: car,
            vehicleKind: defaults?.string(forKey: "widget.vehicleKind")
        )
    }

    var debugFields: [String: String] {
        var fields: [String: String] = [
            "rideActive": rideActive ? "yes" : "no",
            "vehicle": vehicleKind ?? "—",
            "route": activeRouteName ?? "—",
            "bike": bikeName ?? "—"
        ]
        if let car {
            fields["mode"] = car.mode.rawValue
            fields["carTurn"] = car.turnSymbol
            fields["carDistance"] = car.turnDistance
            fields["carInstruction"] = car.instruction
            fields["carRemaining"] = car.remaining
            fields["carEta"] = car.eta
            fields["carSpeed"] = car.speed
            fields["carLimit"] = car.speedLimit ?? "—"
            fields["carLap"] = "\(car.lap)/\(car.totalLaps)"
            fields["carHazard"] = car.hazard ?? "—"
            fields["carSim"] = car.isSimulation ? "yes" : "no"
            fields["carUpdated"] = String(format: "%.1f", car.updatedAt.timeIntervalSince1970)
            fields["carStale"] = car.isStale ? "yes" : "no"
            fields["carProgress"] = String(format: "%.3f", car.progress)
            fields["carStepID"] = "\(car.stepID)"
            fields["carMap"] = car.mapImage ?? "—"
        } else {
            fields["carState"] = "nil"
        }
        return fields
    }
}

struct RevertQuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> RevertQuickEntry {
        RevertQuickEntry(date: Date(), bikeName: "Multistrada V4", odometerKm: 12_480,
                        lastRideMeters: 92_000, lastRideDate: Date(),
                        lastRideName: "Sunday loop", metric: false,
                        rideActive: false, activeRouteName: nil, car: nil,
                        vehicleKind: "motorcycle")
    }

    func getSnapshot(in context: Context, completion: @escaping (RevertQuickEntry) -> Void) {
        let entry = RevertQuickEntry.current()
        var fields = entry.debugFields
        fields["family"] = "\(context.family)"
        WidgetDebugLog.log("snapshot", fields)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RevertQuickEntry>) -> Void) {
        let entry = RevertQuickEntry.current()
        var fields = entry.debugFields
        fields["policy"] = "after300"
        fields["family"] = "\(context.family)"
        WidgetDebugLog.log("timeline", fields)
        completion(Timeline(entries: [entry],
                            policy: .after(Date().addingTimeInterval(300))))
    }
}

struct RevertQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RevertQuickWidget", provider: RevertQuickProvider()) { entry in
            RevertQuickWidgetView(entry: entry)
        }
        .configurationDisplayName("Revert")
        .description("Start a loop, or see the ride already running.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RevertQuickWidgetView: View {
    let entry: RevertQuickEntry
    private let cyan = Color(red: 0.15, green: 0.9, blue: 1.0)
    private var isCarEntry: Bool {
        entry.car?.isCar == true || entry.vehicleKind == "car"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("REVERT")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(cyan)
                Spacer(minLength: 0)
                Image(systemName: isCarEntry ? "car.fill" : "motorcycle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let car = entry.car, car.isLive, !car.isStale {
                liveDrive(car)
            } else if let car = entry.car, car.isLive {
                staleDrive
            } else if let car = entry.car, car.mode == .arrived {
                arrived(car)
            } else if entry.rideActive {
                riding
            } else {
                parked
            }

            Spacer(minLength: 0)

            if !(entry.car?.isLive == true || entry.car?.mode == .arrived) {
                actions
            }
        }
        .padding(13)
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: entry.car?.isLive == true ? "revert://drive" : "revert://plan"))
    }

    // Live Dashboard card. The Live Activity carries second-by-second turns;
    // this widget is the state snapshot the Dashboard shows when the activity
    // is not front and center.
    /// The app stopped updating this snapshot, usually because it was closed
    /// mid-ride. Say so rather than showing the last turn forever.
    private var staleDrive: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RIDE PAUSED")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(cyan)
            Spacer(minLength: 0)
            Text("Not updating")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("Open Revert to continue")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func liveDrive(_ car: CarWidgetSnapshot) -> some View {
        if let name = car.mapImage, let image = LiveMapImage.load(name) {
            mapDrive(car, image: image)
        } else {
            plainDrive(car)
        }
    }

    /// Overview map: the whole ride, north-up, so the strip stays useful for
    /// the entire route instead of ageing out between widget refreshes.
    private func mapDrive(_ car: CarWidgetSnapshot, image: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: car.turnSymbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(car.hazard == nil ? cyan : .orange)
                    Text(car.turnDistance)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Image(systemName: isCarEntry ? "car.fill" : "motorcycle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(car.instruction.isEmpty ? car.routeName : car.instruction)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text("\(car.remaining) · \(car.eta)")
                        .foregroundStyle(.white.opacity(0.65))
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
            }
            .padding(8)
        }
    }

    private func plainDrive(_ car: CarWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: car.turnSymbol)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(car.hazard == nil ? cyan : .orange)
                Spacer(minLength: 0)
                if car.isSimulation {
                    Text("SIM")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange, in: Capsule())
                }
                if let hazard = car.hazard {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(hazard)
                }
                if car.isCar {
                    Image(systemName: "car.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Text(car.turnDistance)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(.white)

            Text(car.instruction.isEmpty ? (car.routeName.isEmpty ? "On the route" : car.routeName) : car.instruction)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(car.speed)
                if let limit = car.speedLimit {
                    Text("· \(limit)")
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                if car.lap > 1 {
                    Text("LAP \(car.lap)/\(car.totalLaps)")
                        .foregroundStyle(cyan)
                }
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 5) {
                Text(car.remaining)
                Text("·")
                Text(car.eta)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
        }
    }

    private func arrived(_ car: CarWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(cyan)
                Spacer(minLength: 0)
                Image(systemName: isCarEntry ? "car.fill" : "motorcycle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(entry.car?.isCar == true || entry.vehicleKind == "car" ? "Drive complete" : "Ride complete")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(car.routeName.isEmpty ? "Back at the finish" : car.routeName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Tap to open")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // The one card CarPlay shows in the Dashboard strip when Revert is not on
    // the screen. It is a launcher, not a dashboard: the live turn data rides
    // the Live Activity, because widgets only get a handful of refreshes a day.
    private var parked: some View {
        VStack(alignment: .leading, spacing: 3) {
            Link(destination: URL(string: "revert://plan")!) {
                Text(isCarEntry ? "Start a drive" : "Start a loop")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let meters = entry.lastRideMeters, let date = entry.lastRideDate {
                Text("Last: \(distance(meters)) · \(date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else if let bike = entry.bikeName, !bike.isEmpty {
                Text(bike)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            } else {
                Text("No bike in the garage yet")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }

    private var riding: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(cyan)
                    .frame(width: 6, height: 6)
                Text("Ride in progress")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(entry.activeRouteName ?? "On the route")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if entry.rideActive {
                // No deep link mid-ride: a plain tap reopens Revert where the
                // rider left it (the cockpit), and there is no URL host that
                // lands on a live ride.
                Label("Tap to open", systemImage: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Link(destination: URL(string: "revert://plan")!) {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(cyan, in: Capsule())
                }
            }
            Spacer(minLength: 0)
            if let odometer = entry.odometerKm, !entry.rideActive {
                Text(distance(odometer * 1_000))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
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
