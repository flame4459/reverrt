import SwiftUI

struct AboutView: View {
    @State private var confirmingClear = false

    private var versionText: String {
        "\(RiderDiagnostics.appVersion) (\(RiderDiagnostics.appBuild))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RiderScreenHeader(
                    eyebrow: "ABOUT",
                    title: "Rider",
                    subtitle: "A scenic riding companion built around the bends.",
                    systemImage: "motorcycle"
                )

                SettingsCard(title: "This build", icon: "info.circle") {
                    HStack {
                        Text("Version").foregroundStyle(MapUI.ink)
                        Spacer()
                        Text(versionText).foregroundStyle(MapUI.secondaryInk)
                    }
                    HStack {
                        Text("Storage").foregroundStyle(MapUI.ink)
                        Spacer()
                        Text("On this iPhone").foregroundStyle(MapUI.emerald)
                    }
                }

                SettingsCard(
                    title: "Privacy",
                    icon: "lock.shield",
                    footer: "Rider does not create an account or upload rides. Diagnostics contain only coarse events and error text, never coordinates or place names."
                ) {
                    Text("Location is used to plan routes, record rides and provide navigation. Saved places, rides, the garage and downloaded road data stay in this app's sandbox.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(
                    title: "Data sources",
                    icon: "server.rack",
                    footer: "Always check signage and road conditions; map data can be incomplete."
                ) {
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        HStack {
                            Label("OpenStreetMap contributors", systemImage: "map")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    Link(destination: URL(string: "https://www.apple.com/legal/internet-services/maps/")!) {
                        HStack {
                            Label("Apple Maps", systemImage: "apple.logo")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                }

                SettingsCard(
                    title: "Diagnostics",
                    icon: "stethoscope",
                    footer: "Share this file with support if a route, download or voice command fails. It contains no location history."
                ) {
                    if let url = RiderDiagnostics.exportURL() {
                        ShareLink(item: url) {
                            Label("Share diagnostics", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Text("No diagnostics recorded yet.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(MapUI.textSecondary)
                    }

                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Clear diagnostics", systemImage: "trash")
                    }
                    .disabled(RiderDiagnostics.text().isEmpty)
                }

                Text("Ride within your limits. Rider is a planning aid, not a substitute for attention, road signs or local law.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(MapUI.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("About Rider")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MapUI.cyan)
        .confirmationDialog("Clear diagnostics?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                RiderDiagnostics.clear()
                RiderHaptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
