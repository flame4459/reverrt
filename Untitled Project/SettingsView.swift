import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alert.voice") private var voice = true
    @AppStorage("navigation.voice") private var navigationVoice = true
    @AppStorage("alert.voiceName") private var voiceName = "System default"
    @AppStorage("alert.stop") private var stop = true
    @AppStorage("alert.signal") private var signal = true
    @AppStorage("alert.rail") private var rail = true
    @AppStorage("alert.school") private var school = true
    @AppStorage("alert.roundabout") private var roundabout = true
    @AppStorage("alert.cameras") private var cameras = true
    @AppStorage("alert.curves") private var curves = true
    @AppStorage("alert.curveAccel") private var curveAccel = 3.5
    @AppStorage("alert.overLimit") private var overLimit = true
    @AppStorage("alert.limitTolerance") private var tolerance = 5
    @AppStorage("alert.surface") private var surface = true
    @AppStorage("alert.hazardSpeedThreshold") private var hazardSpeedThreshold = 0
    @AppStorage("alert.reactionTime") private var reactionTime = 1.5
    @AppStorage("rider.selectedBike") private var selectedBike = BikeCatalog.defaultBike
    @AppStorage("units.metric") private var metric = false
    @AppStorage("voice.commands") private var voiceCommands = false
    @AppStorage("helmet.binaural") private var binaural = true
    @AppStorage("remote.enabled") private var remoteEnabled = true
    @AppStorage("fuel.tankFraction") private var tankFraction = 0.8
    @State private var cachedVoices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RiderScreenHeader(
                        eyebrow: "RIDER CONTROL",
                        title: "Make it yours",
                        subtitle: "Tune navigation, voice and safety alerts for every ride.",
                        systemImage: "slider.horizontal.3"
                    )

                    RiderSectionLabel(title: "Ride & units")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Your bike",
                        icon: "motorcycle",
                        footer: "Choose the bike shown for your rider profile. Your selection is saved automatically."
                    ) {
                        NavigationLink {
                            BikePickerView(selectedBike: $selectedBike)
                        } label: {
                            HStack {
                                Label("Bike model", systemImage: "motorcycle")
                                Spacer()
                                Text(selectedBike)
                                    .foregroundStyle(MapUI.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                        Divider()
                        NavigationLink {
                            GarageView()
                        } label: {
                            Label("Garage, fuel range & maintenance", systemImage: "wrench.and.screwdriver")
                        }
                    }

                    SettingsCard(
                        title: "Units",
                        icon: "ruler",
                        footer: "Every speed, distance and elevation in the app follows this setting."
                    ) {
                        Toggle("Metric (km, km/h, metres)", isOn: $metric)
                            .onChange(of: metric) { _, value in
                                Units.setMetric(value)
                                WidgetBridge.updateUnits()
                            }
                    }

                    SettingsCard(
                        title: "Fuel",
                        icon: "fuelpump",
                        footer: "The fuel-stop plan uses this tank level. Set it before a ride so the usable range matches what is actually in the tank."
                    ) {
                        HStack {
                            Text("Fuel in tank")
                                .foregroundStyle(MapUI.ink)
                            Spacer()
                            Text("\(Int((tankFraction * 100).rounded()))%")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(MapUI.emerald)
                        }
                        Slider(value: $tankFraction, in: 0.1...1, step: 0.05)
                            .tint(MapUI.emerald)
                            .accessibilityLabel("Fuel in tank")
                            .accessibilityValue("\(Int((tankFraction * 100).rounded())) percent")
                    }

                    RiderSectionLabel(title: "Voice & awareness")
                        .padding(.top, 4)

                    SettingsCard(title: "Voice", icon: "waveform") {
                        Toggle("Spoken alerts", isOn: $voice)
                        Toggle("Spoken turn directions", isOn: $navigationVoice)
                        Toggle("On-device voice commands", isOn: $voiceCommands)

                        RiderInfoNote(
                            text: "Say “pause ride”, “resume ride”, “end route” or “repeat”. Recognition runs entirely on this iPhone.",
                            systemImage: "waveform"
                        )

                        Rectangle().fill(MapUI.line).frame(height: 0.8)

                        RiderMenuPicker(
                            title: "Narrator voice",
                            systemImage: "person.wave.2",
                            options: voiceOptions,
                            selection: $voiceName
                        )

                        RiderInfoNote(
                            text: "Choose an installed voice. Enhanced voices can be downloaded in iPhone Settings.",
                            systemImage: "arrow.down.circle"
                        )

                        HStack(spacing: 9) {
                            Button {
                                Speaker.shared.say("Stop sign in 300 feet")
                            } label: {
                                Label("Alert voice", systemImage: "speaker.wave.2.fill")
                            }
                            .buttonStyle(RiderSecondaryButtonStyle(minHeight: 44))

                            Button {
                                Speaker.shared.say("In half a mile, turn right onto Market Street", kind: .navigation)
                            } label: {
                                Label("Navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            }
                            .buttonStyle(RiderSecondaryButtonStyle(minHeight: 44))
                        }
                    }

                    SettingsCard(
                        title: "Lean angle",
                        icon: "gauge.with.dots.needle.67percent",
                        footer: "The phone position is detected automatically. Keep the bike upright for the first moment of a ride."
                    ) {
                        Label("Automatic phone-position detection", systemImage: "iphone")
                            .foregroundStyle(MapUI.ink)
                        Label("Max lean is tracked in the ride summary.", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                            .foregroundStyle(MapUI.secondaryInk)
                    }

                    RiderSectionLabel(title: "Safety alerts")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Ahead of you",
                        icon: "exclamationmark.triangle",
                        footer: "Stop-sign and traffic-light distance uses your speed, reaction time, and estimated braking distance."
                    ) {
                        Toggle("Stop signs", isOn: $stop)
                        Toggle("Traffic lights", isOn: $signal)
                        Toggle("Speed and red-light cameras", isOn: $cameras)
                        RiderInfoNote(
                            text: "Camera alerts may be restricted where you ride. Check local laws.",
                            systemImage: "info.circle",
                            tint: MapUI.textTertiary
                        )

                        RiderMenuPicker(
                            title: "Warn only above",
                            systemImage: "gauge.with.dots.needle.50percent",
                            options: [
                                ("Any speed", 0),
                                (Units.speedTextFromMph(30), 30),
                                (Units.speedTextFromMph(40), 40),
                                (Units.speedTextFromMph(50), 50),
                                (Units.speedTextFromMph(60), 60)
                            ],
                            selection: $hazardSpeedThreshold
                        )

                        RiderSectionLabel(title: "Reaction time")
                        RiderOptionPicker(
                            options: [1.0, 1.5, 2.0, 2.5],
                            selection: $reactionTime,
                            title: { String(format: "%.1f s", $0) }
                        )

                        Toggle("Railroad crossings", isOn: $rail)
                        Toggle("School zones", isOn: $school)
                        Toggle("Roundabouts", isOn: $roundabout)

                        RiderInfoNote(
                            text: "Device alerts only use signs on the active route and start above walking speed, so they never fire for a parallel road or repeat while you creep up to a junction.",
                            systemImage: "checkmark.shield"
                        )
                    }

                    SettingsCard(
                        title: "Cornering",
                        icon: "arrow.turn.up.right",
                        footer: "Relaxed warns earlier. Sport only warns when a curve is tight for your speed."
                    ) {
                        Toggle("Curve warnings", isOn: $curves)

                        RiderSectionLabel(title: "Riding style")
                        RiderOptionPicker(
                            options: [2.5, 3.5, 4.5],
                            selection: $curveAccel,
                            title: { curveStyleLabel($0) },
                            tint: MapUI.amber
                        )
                        .disabled(!curves)
                        .opacity(curves ? 1 : 0.5)
                    }

                    SettingsCard(
                        title: "Speed discipline",
                        icon: "speedometer",
                        footer: "The limit sign appears when OpenStreetMap has a posted limit. Spoken alerts wait until you remain over the limit."
                    ) {
                        Toggle("Over-limit alert", isOn: $overLimit)

                        RiderSectionLabel(title: "Alert when over by")
                        RiderOptionPicker(
                            options: [0, 5, 10],
                            selection: $tolerance,
                            title: { value in
                                value == 0 ? "Any" : "+" + Units.speedTextFromMph(Double(value))
                            },
                            tint: MapUI.coral
                        )
                        .disabled(!overLimit)
                        .opacity(overLimit ? 1 : 0.5)
                    }

                    SettingsCard(title: "Road surface", icon: "road.lanes") {
                        Toggle("Unpaved road warning", isOn: $surface)
                    }

                    RiderSectionLabel(title: "Audio & data")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Helmet audio",
                        icon: "airpodspro",
                        footer: "Spatial cues put hazard and turn alerts on the side of the road they belong to. Your Bluetooth helmet must be connected as the audio route."
                    ) {
                        Toggle("Binaural helmet cues", isOn: $binaural)
                        Toggle("Handlebar remote / controller", isOn: $remoteEnabled)
                    }

                    SettingsCard(title: "Data & privacy", icon: "externaldrive") {
                        NavigationLink {
                            SavedPlacesView(showsDone: false)
                        } label: {
                            HStack {
                                Label("Saved places", systemImage: "star")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                        Divider()
                        NavigationLink {
                            OfflineView()
                        } label: {
                            HStack {
                                Label("Offline riding data", systemImage: "arrow.down.circle")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                        Divider()
                        NavigationLink {
                            AboutView()
                        } label: {
                            HStack {
                                Label("About, privacy & diagnostics", systemImage: "info.circle")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(MapUI.groupedBackground)
            .scrollIndicators(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.semibold))
                }
            }
            .tint(MapUI.accent)
            .onAppear(perform: loadVoices)
        }
    }

    private var availableVoices: [AVSpeechSynthesisVoice] { cachedVoices }

    private var voiceOptions: [(label: String, value: String)] {
        var options = [("System default", "System default")]
            + availableVoices.map { ($0.name, $0.name) }
        // Keep an already-saved voice visible even if it is no longer
        // installed, instead of showing the menu's "—" placeholder.
        if voiceName != "System default",
           !availableVoices.contains(where: { $0.name == voiceName }) {
            options.append(("\(voiceName) (unavailable)", voiceName))
        }
        return options
    }

    private func curveStyleLabel(_ value: Double) -> String {
        switch value {
        case 2.5: return "Relaxed"
        case 4.5: return "Sport"
        default: return "Normal"
        }
    }

    private func loadVoices() {
        guard cachedVoices.isEmpty else { return }
        let currentLang = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matching = all.filter { $0.language.starts(with: currentLang) }
        let candidateList = matching.isEmpty ? all.filter { $0.language.starts(with: "en") } : matching
        var seen = Set<String>()
        cachedVoices = candidateList.filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let footer: String?
    let content: Content

    init(title: String, icon: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.content = content()
    }

    private var tint: Color {
        switch icon {
        case "waveform", "airpodspro":
            return MapUI.emerald
        case "exclamationmark.triangle", "arrow.turn.up.right", "speedometer", "road.lanes":
            return MapUI.amber
        case "gauge.with.dots.needle.67percent":
            return MapUI.magenta
        case "externaldrive":
            return MapUI.violet
        default:
            return MapUI.cyan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                RiderIconBadge(systemImage: icon, tint: tint, size: 34, radius: 11)
                Text(title)
                    .font(RiderType.headline)
                    .foregroundStyle(MapUI.ink)
                Spacer(minLength: 0)
            }

            content

            if let footer {
                RiderInfoNote(text: footer, systemImage: "info.circle")
            }
        }
        .riderCard()
    }
}
