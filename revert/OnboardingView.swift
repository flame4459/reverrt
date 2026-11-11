import SwiftUI
import CoreLocation
import UIKit

/// First-run explanation before the system location alert. The app used to ask
/// for location from a singleton initializer, before the rider saw a single
/// screen. This gives the permission a reason and an explicit skip path.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var hub = LocationHub.shared
    @State private var appeared = false

    private var status: CLAuthorizationStatus { hub.authorizationStatus }

    private var statusTitle: String {
        switch status {
        case .notDetermined: "Location is off"
        case .authorizedAlways, .authorizedWhenInUse: "Location is on"
        case .denied, .restricted: "Location is blocked"
        @unknown default: "Location is off"
        }
    }

    private var statusDetail: String {
        switch status {
        case .notDetermined:
            "Revert uses location to centre the map, record rides and find loops near you."
        case .authorizedAlways, .authorizedWhenInUse:
            "You are ready to ride. Background access is requested when you start a recorded ride."
        case .denied, .restricted:
            "You can enable location later in iPhone Settings. The map and ride recording need it."
        @unknown default:
            "You can enable location later in iPhone Settings."
        }
    }

    private var primaryTitle: String {
        switch status {
        case .notDetermined: "Enable location"
        case .authorizedAlways, .authorizedWhenInUse: "Start riding"
        case .denied, .restricted: "Open Settings"
        @unknown default: "Continue"
        }
    }

    var body: some View {
        ZStack {
            MapUI.canvas.ignoresSafeArea()
            LinearGradient(colors: [MapUI.deepNavy, MapUI.canvas],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "motorcycle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Pulse.accentInk)
                            .frame(width: 46, height: 46)
                            .background(MapUI.cyan, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("REVERT")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .tracking(4)
                                .foregroundStyle(MapUI.ink)
                            Text("SCENIC RIDING COMPANION")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(1.6)
                                .foregroundStyle(MapUI.cyan)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find the bends.")
                            .font(RevertType.display(34, weight: .heavy))
                            .foregroundStyle(MapUI.ink)
                        Text("Plan twisty loops, follow turn-by-turn directions, record the ride and keep the good ones. Everything stays on this iPhone.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(MapUI.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        feature("map.fill", "Scenic loop planner", "Choose a start, distance and road style; Revert finds the bends.")
                        feature("location.north.line.fill", "Live cockpit", "Speed, lean angle, hazards and voice prompts on one screen.")
                        feature("clock.arrow.circlepath", "Ride history", "Replay the line, study corners, and share a story poster.")
                        feature("arrow.down.circle", "Offline riding data", "Save roads, hazards and fuel data before the signal drops.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 9) {
                            Image(systemName: status == .denied || status == .restricted
                                  ? "location.slash.fill" : "location.fill")
                                .foregroundStyle(
                                    status == .denied || status == .restricted
                                        ? MapUI.coral
                                        : (status == .notDetermined ? MapUI.amber : MapUI.emerald)
                                )
                            Text(statusTitle)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(MapUI.ink)
                        }
                        Text(statusDetail)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(MapUI.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(MapUI.surfaceHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(MapUI.lineStrong, lineWidth: 0.8)
                    }

                    VStack(spacing: 10) {
                        Button {
                            RevertHaptics.tap()
                            switch status {
                            case .notDetermined:
                                hub.requestWhenInUse()
                            case .denied, .restricted:
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            default:
                                onFinish()
                            }
                        } label: {
                            Label(primaryTitle, systemImage: "arrow.right")
                        }
                        .buttonStyle(RevertPrimaryButtonStyle())

                        Button("Not now") {
                            RevertHaptics.tap()
                            onFinish()
                        }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                    }

                    Text("Location is used on-device. No account, no tracking, no upload.")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(RevertMotion.smooth) { appeared = true }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MapUI.cyan)
                .frame(width: 30, height: 30)
                .background(MapUI.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
