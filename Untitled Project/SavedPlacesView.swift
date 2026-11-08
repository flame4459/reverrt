import SwiftUI
import CoreLocation

/// Editor for the two places the planner can launch with one tap.
///
/// The Home/Work chips on the map used to be the only place these coordinates
/// could be created (by saving wherever the bike happened to be), and the
/// "Saved places" tile in the menu opened Settings instead. This screen makes
/// the saved coordinates visible, editable and removable.
struct SavedPlacesView: View {
    var showsDone = true
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var nav

    @AppStorage("saved.home.lat") private var homeLat = 0.0
    @AppStorage("saved.home.lon") private var homeLon = 0.0
    @AppStorage("saved.work.lat") private var workLat = 0.0
    @AppStorage("saved.work.lon") private var workLon = 0.0

    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RiderScreenHeader(
                    eyebrow: "SAVED PLACES",
                    title: "Home and work",
                    subtitle: "Set the two addresses you use most. The map chips will route here in one tap.",
                    systemImage: "star.fill"
                )

                if nav.locationDenied { LocationOffBanner() }

                placeCard(.home)
                placeCard(.work)

                RiderInfoNote(
                    text: "Set these from wherever the bike is parked. Saved places stay on this iPhone and are never uploaded.",
                    systemImage: "iphone",
                    tint: MapUI.textTertiary
                )

                if let message {
                    RiderInfoNote(text: message, systemImage: "checkmark.circle.fill", tint: MapUI.emerald)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(MapUI.groupedBackground)
        .scrollIndicators(.hidden)
        .navigationTitle("Saved places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline.weight(.semibold))
                }
            }
        }
        .tint(MapUI.accent)
    }

    private func coordinate(for place: SavedPlace) -> CLLocationCoordinate2D? {
        switch place {
        case .home:
            return (homeLat != 0 || homeLon != 0)
                ? CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)
                : nil
        case .work:
            return (workLat != 0 || workLon != 0)
                ? CLLocationCoordinate2D(latitude: workLat, longitude: workLon)
                : nil
        }
    }

    private func placeCard(_ place: SavedPlace) -> some View {
        let saved = coordinate(for: place)
        return SettingsCard(
            title: place.title,
            icon: place.icon,
            footer: saved == nil
                ? "Not set yet. Use the button above to save your current location."
                : "Saved on this iPhone. Tap the \(place.title) chip on the map to preview the route."
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(saved == nil ? "No location saved" : "Saved location")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                if let saved {
                    Text(String(format: "%.4f, %.4f", saved.latitude, saved.longitude))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MapUI.textTertiary)
                } else {
                    Text("Set it once and it is always one tap away.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 9) {
                Button {
                    saveCurrentLocation(for: place)
                } label: {
                    Label(saved == nil ? "Use my location" : "Replace",
                          systemImage: "location.fill")
                }
                .buttonStyle(RiderSecondaryButtonStyle(minHeight: 44))
                .disabled(nav.currentLocation == nil)
                .opacity(nav.currentLocation == nil ? 0.55 : 1)

                if saved != nil {
                    Button(role: .destructive) {
                        clear(place)
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(RiderSecondaryButtonStyle(tint: MapUI.coral, minHeight: 44))
                }
            }
        }
    }

    private func saveCurrentLocation(for place: SavedPlace) {
        guard let current = nav.currentLocation else {
            message = "Waiting for a GPS fix. Try again in a moment."
            return
        }
        switch place {
        case .home:
            homeLat = current.coordinate.latitude
            homeLon = current.coordinate.longitude
        case .work:
            workLat = current.coordinate.latitude
            workLon = current.coordinate.longitude
        }
        RiderHaptics.success()
        message = "\(place.title) saved at your current location."
    }

    private func clear(_ place: SavedPlace) {
        switch place {
        case .home:
            homeLat = 0
            homeLon = 0
        case .work:
            workLat = 0
            workLon = 0
        }
        RiderHaptics.warning()
        message = "\(place.title) removed."
    }
}
