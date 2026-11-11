#if DEBUG
import SwiftUI
import CoreLocation

/// Launch-argument screens used for visual verification on the simulator.
/// Never compiled into Release builds.
enum DebugScreens {
    static var isRide: Bool {
        CommandLine.arguments.contains("-debugRide")
            || CommandLine.arguments.contains("-debugRecord")
            || CommandLine.arguments.contains("-debugHud")
            || CommandLine.arguments.contains("-debugAlert")
    }

    static func samplePlannedRoute() -> PlannedRoute {
        var points: [RoutePoint] = []
        let corners: [(Double, Double)] = [
            (37.7750, -122.4194),
            (37.7850, -122.4150),
            (37.7880, -122.4010),
            (37.7760, -122.3980)
        ]
        for (index, corner) in corners.enumerated() {
            let next = corners[(index + 1) % corners.count]
            for step in 0..<40 {
                let t = Double(step) / 40
                points.append(RoutePoint(
                    lat: corner.0 + (next.0 - corner.0) * t,
                    lon: corner.1 + (next.1 - corner.1) * t,
                    road: Int64(index + 1)
                ))
            }
        }
        points.append(points[0])
        return PlannedRoute(points: points, roads: [:], twistPerKm: 95,
                            retraced: 0, bearing: 45, displayName: "Debug loop")
    }
    static var isBikePicker: Bool { CommandLine.arguments.contains("-debugBikePicker") }
    static var isVoicePacks: Bool { CommandLine.arguments.contains("-debugVoicePacks") }
    static var isVoicePackBrowser: Bool { CommandLine.arguments.contains("-debugVoicePackBrowser") }

    /// `-debugInstallPack <uuid>` installs a catalogue voice on launch so the
    /// download, unpack and playback path can be exercised on a simulator.
    static var installPackID: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "-debugInstallPack"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }
    static var isRideDetail: Bool { CommandLine.arguments.contains("-debugRideDetail") }
    static var isSummary: Bool { CommandLine.arguments.contains("-debugSummary") }
    static var isGarage: Bool { CommandLine.arguments.contains("-debugGarage") }
    static var isOffline: Bool { CommandLine.arguments.contains("-debugOffline") }
    static var isCarPlayMap: Bool { CommandLine.arguments.contains("-debugCarPlayMap") }
    static var menu: CentralMenuDestination? {
        if CommandLine.arguments.contains("-debugPlan") { return .plan }
        if CommandLine.arguments.contains("-debugSettings") { return .settings }
        if CommandLine.arguments.contains("-debugHistory") { return .history }
        return nil
    }

    static var recordedPreviewCoordinates: [CLLocationCoordinate2D] {
        let centerLat = 37.7749
        let centerLon = -122.4194
        return (0..<160).map { index in
            let angle = Double(index) / 160 * 2 * .pi
            return CLLocationCoordinate2D(
                latitude: centerLat + 0.012 * sin(angle),
                longitude: centerLon + 0.016 * cos(angle)
            )
        }
    }

    static func sampleRide() -> Ride {
        let start = Date().addingTimeInterval(-5_400)
        var points: [RidePoint] = []
        let centerLat = 37.7749
        let centerLon = -122.4194
        for index in 0..<420 {
            let angle = Double(index) / 420 * 2 * .pi
            let wobble = 0.02 * sin(angle * 7)
            let lat = centerLat + (0.018 + wobble) * sin(angle)
            let lon = centerLon + (0.024 + wobble) * cos(angle)
            let corner = abs(sin(angle * 5))
            points.append(RidePoint(
                lat: lat, lon: lon,
                alt: 40 + 180 * (0.5 + 0.5 * sin(angle * 2)),
                speed: 9 + 22 * corner,
                time: start.addingTimeInterval(Double(index) * 8),
                lean: (sin(angle * 5) > 0 ? 1 : -1) * (6 + 34 * corner)
            ))
        }
        return Ride(startDate: start,
                    endDate: start.addingTimeInterval(5_400),
                    distanceMeters: 92_000,
                    maxSpeedMps: 33,
                    elevationGainMeters: 1_240,
                    durationSeconds: 5_400,
                    points: points,
                    maxLeanAngleDegrees: 44,
                    bikeName: "Ducati Multistrada V4",
                    movingSeconds: 4_600,
                    stoppedSeconds: 800)
    }
}

struct DebugBikePickerRoot: View {
    @AppStorage("rider.selectedBike") private var selectedBike = BikeCatalog.defaultBike

    var body: some View {
        NavigationStack {
            BikePickerView(selectedBike: $selectedBike)
        }
        .preferredColorScheme(.dark)
    }
}

struct DebugVoicePacksRoot: View {
    var body: some View {
        NavigationStack {
            VoicePickerView()
        }
        .preferredColorScheme(.dark)
    }
}

struct DebugVoicePackBrowserRoot: View {
    var body: some View {
        NavigationStack {
            VoicePacksView()
        }
        .preferredColorScheme(.dark)
    }
}

struct DebugRideDetailRoot: View {
    var body: some View {
        NavigationStack {
            RideDetailView(ride: DebugScreens.sampleRide())
        }
        .preferredColorScheme(.dark)
    }
}

#if canImport(CarPlay)
/// Renders the same map controller the car screen uses, so the route line and
/// destination marker can be checked on the simulator without a vehicle.
struct DebugCarPlayMapRoot: View {
    private let route = DebugScreens.samplePlannedRoute()

    var body: some View {
        ZStack(alignment: .topLeading) {
            CarPlayMapPreview(route: route)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 2) {
                Text("CARPLAY MAP PREVIEW")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                Text("Route line and destination marker")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }
}

private struct CarPlayMapPreview: UIViewControllerRepresentable {
    let route: PlannedRoute

    func makeUIViewController(context: Context) -> CarPlayMapViewController {
        let controller = CarPlayMapViewController()
        controller.loadViewIfNeeded()
        controller.showRoute(route, overview: true)
        // The map is not laid out yet on the first call; frame again once it is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            controller.showRoute(route, overview: true)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: CarPlayMapViewController, context: Context) {}
}
#else
struct DebugCarPlayMapRoot: View {
    var body: some View {
        Text("CarPlay is unavailable on this platform.")
            .preferredColorScheme(.dark)
    }
}
#endif
#endif
