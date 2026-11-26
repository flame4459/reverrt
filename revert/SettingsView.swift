import SwiftUI
import AVFoundation
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alert.voice") private var voice = true
    @AppStorage("voice.muted") private var voiceMuted = false
    @AppStorage("navigation.voice") private var navigationVoice = true
    @AppStorage("alert.voiceName") private var voiceName = "System default"
    @AppStorage("alert.stop") private var stop = true
    @AppStorage("alert.signal") private var signal = true
    @AppStorage("alert.rail") private var rail = true
    @AppStorage("alert.school") private var school = true
    @AppStorage("alert.roundabout") private var roundabout = true
    @AppStorage("alert.speedCameras") private var speedCameras = true
    @AppStorage("alert.redLightCameras") private var redLightCameras = true
    @AppStorage("alert.plateCameras") private var plateCameras = true
    @AppStorage("alert.profile") private var rideProfile = RideProfile.full.rawValue
    @AppStorage("alert.curves") private var curves = true
    @AppStorage("alert.curveAccel") private var curveAccel = 3.5
    @AppStorage("alert.overLimit") private var overLimit = true
    @AppStorage("alert.limitTolerance") private var tolerance = 5
    @AppStorage("alert.surface") private var surface = true
    @AppStorage("alert.hazardSpeedThreshold") private var hazardSpeedThreshold = 0
    @AppStorage("alert.reactionTime") private var reactionTime = 1.5
    @AppStorage("rider.selectedBike") private var selectedBike = BikeCatalog.defaultBike
    @Query(sort: \Bike.createdAt) private var garageBikes: [Bike]
    @AppStorage("units.system") private var unitSystem = UnitSystemPreference.automatic.rawValue
    @AppStorage("ride.autoPause") private var autoPause = true
    @AppStorage("ride.launchCountdown") private var launchCountdown = true
    @AppStorage("rider.name") private var riderName = ""
    @AppStorage("alert.haptics") private var haptics = true
    @AppStorage("voice.commands") private var voiceCommands = false
    @AppStorage("helmet.binaural") private var binaural = true
    @AppStorage("fuel.tankFraction") private var tankFraction = 0.8
    @State private var voicePacks = VoicePackLibrary.shared
    @State private var showingFeatureLab = false
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(
                        eyebrow: "",
                        title: "Make it yours",
                        variant: .compact,
                        identifier: AccessibilityID.Settings.title
                    ) {
                        Button("Done") {
                            dismiss()
                        }
                        .font(.headline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier(AccessibilityID.Settings.done)
                    }

                    RevertSectionLabel(title: "Appearance")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Color scheme",
                        icon: "paintpalette.fill",
                        footer: "Every screen recolours immediately. Your choice is saved on this iPhone."
                    ) {
                        ColorSchemePicker()
                    }

                    SettingsCard(
                        title: "Ride Lab",
                        icon: "flask.fill",
                        footer: "Conditions, touring, route links, voice marks, ghost chase, reports, setup notes and the feature experiments."
                    ) {
                        Button {
                            RevertHaptics.tap()
                            showingFeatureLab = true
                        } label: {
                            Label("Open Ride Lab", systemImage: "flask.fill")
                        }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
                    }

                    SettingsCard(
                        title: "Companion",
                        icon: "waveform",
                        footer: "Ace answers questions and keeps you company on-device. Off stops listening and never mutes navigation."
                    ) {
                        NavigationLink {
                            CompanionSettingsView()
                        } label: {
                            HStack {
                                Label("Companion settings", systemImage: "waveform")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                    }

                    RevertSectionLabel(title: "Ride & units")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Your bike",
                        icon: "motorcycle",
                        footer: primaryGarageBike == nil
                            ? "No vehicle in your Garage yet. This catalog model is used for artwork and defaults until you add one; the Garage then becomes the single source of truth."
                            : "Rides, the widget and the Live Activity use the primary vehicle from your Garage. Change it there, not here."
                    ) {
                        if let primary = primaryGarageBike {
                            NavigationLink {
                                GarageView()
                            } label: {
                                HStack(spacing: 10) {
                                    BikeArtworkView(bikeName: primary.displayName, width: 42, height: 26)
                                    Text("Primary vehicle")
                                        .fixedSize()
                                    Spacer(minLength: 8)
                                    Text(primary.displayName)
                                        .foregroundStyle(MapUI.secondaryInk)
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        } else {
                            NavigationLink {
                                BikePickerView(selectedBike: $selectedBike)
                            } label: {
                                HStack(spacing: 10) {
                                    BikeArtworkView(bikeName: selectedBike, width: 42, height: 26)
                                    Text("Bike model")
                                        .fixedSize()
                                    Spacer(minLength: 8)
                                    Text(selectedBike)
                                        .foregroundStyle(MapUI.secondaryInk)
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
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
                        footer: "Automatic follows the iPhone region: US and UK get miles, most other regions get kilometres. Pin Metric or Imperial if you travel or prefer one system."
                    ) {
                        Picker("Units", selection: $unitSystem) {
                            ForEach(UnitSystemPreference.allCases) { preference in
                                Text(preference.title).tag(preference.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(MapUI.accent)
                        .onChange(of: unitSystem) { _, raw in
                            Units.setPreference(UnitSystemPreference(rawValue: raw) ?? .automatic)
                            WidgetBridge.updateUnits()
                        }

                        Text(Units.effectiveDescription)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(MapUI.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsCard(
                        title: "Ride recording",
                        icon: "record.circle",
                        footer: "Auto-pause stops the clock after two minutes without movement and resumes as soon as you pull away. The loop countdown runs when you reach the loop start and begins the timer at GO, so the ride there is not part of the time."
                    ) {
                        Toggle("Ride auto-pause", isOn: $autoPause)
                        Toggle("3 · 2 · 1 at the loop start", isOn: $launchCountdown)
                    }

                    SettingsCard(
                        title: "Rivals",
                        icon: "trophy",
                        footer: "This name travels with a shared time link. Leaderboards are built from links you and your friends send; nothing is uploaded."
                    ) {
                        TextField("Your rider name", text: $riderName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .foregroundStyle(MapUI.ink)
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

                    SettingsCard(
                        title: "Road preferences",
                        icon: "road.lanes",
                        footer: "Loops nudge towards roads you like and away from ones you don't. Applied on the next plan; everything stays on this iPhone."
                    ) {
                        NavigationLink {
                            RoadPreferencesView()
                        } label: {
                            HStack {
                                Label("Roads to prefer or avoid", systemImage: "arrow.triangle.branch")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                    }

                    RevertSectionLabel(title: "Voice & awareness")
                        .padding(.top, 4)

                    SettingsCard(title: "Voice", icon: "waveform") {
                        Toggle("Spoken alerts", isOn: $voice)
                        Toggle("Spoken turn directions", isOn: $navigationVoice)
                        Toggle("On-device voice commands", isOn: $voiceCommands)

                        RevertInfoNote(
                            text: "Say “pause ride”, “resume ride”, “end route” or “repeat”. Recognition runs entirely on this iPhone.",
                            systemImage: "waveform"
                        )

                        Rectangle().fill(MapUI.line).frame(height: 0.8)

                        NavigationLink {
                            VoicePickerView()
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "person.wave.2")
                                    .font(.scaledSystem(size: 12, weight: .semibold))
                                    .foregroundStyle(MapUI.emerald)
                                    .frame(width: 26, height: 26)
                                    .background(MapUI.emerald.opacity(0.10), in: Circle())
                                Text("Narrator voice")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(MapUI.ink)
                                Spacer(minLength: 6)
                                Text(narratorLabel)
                                    .font(.scaledSystem(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(MapUI.emerald)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }

                        if let pack = voicePacks.selectedPack, !pack.isComplete {
                            RevertInfoNote(
                                text: "\(pack.name) is missing \(VoiceClip.standardClipCount - pack.clipCount) prompts, so those lines fall back to the system voice. Choose a complete pack — the built-in ones are marked — for one consistent voice.",
                                systemImage: "exclamationmark.triangle.fill",
                                tint: MapUI.amber
                            )
                        } else {
                            RevertInfoNote(
                                text: "Voice packs play recorded Waze-style prompts. Street names and anything the pack lacks are spoken by the system voice.",
                                systemImage: "square.stack.3d.up"
                            )
                        }

                        HStack(spacing: 9) {
                            Button {
                                Speaker.shared.say(Narrator.exampleAlert)
                            } label: {
                                Label("Alert voice", systemImage: "speaker.wave.2.fill")
                            }
                            .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))

                            Button {
                                Speaker.shared.say(Narrator.exampleInstruction, kind: .navigation)
                            } label: {
                                Label("Navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            }
                            .buttonStyle(RevertSecondaryButtonStyle(minHeight: 44))
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

                    RevertSectionLabel(title: "Safety alerts")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Ahead of you",
                        icon: "exclamationmark.triangle",
                        footer: "Stop-sign and traffic-light distance uses your speed, reaction time, and estimated braking distance."
                    ) {
                        RevertMenuPicker(
                            title: "Ride profile",
                            systemImage: "slider.horizontal.3",
                            options: RideProfile.allCases
                                .filter { $0 != .custom }
                                .map { ($0.title, $0.rawValue) },
                            selection: $rideProfile
                        )
                        .onChange(of: rideProfile) { _, raw in
                            guard let profile = RideProfile(rawValue: raw) else { return }
                            profile.apply()
                        }
                        RevertInfoNote(
                            text: RideProfile(rawValue: rideProfile)?.detail
                                ?? RideProfile.custom.detail,
                            systemImage: "slider.horizontal.3"
                        )

                        Toggle("Haptic feedback", isOn: $haptics)
                        Toggle("Stop signs", isOn: $stop)
                        Toggle("Traffic lights", isOn: $signal)
                        Toggle("Speed cameras", isOn: $speedCameras)
                        Toggle("Red-light cameras", isOn: $redLightCameras)
                        Toggle("License plate readers", isOn: $plateCameras)
                        RevertInfoNote(
                            text: "Plate readers are Flock-style ALPR cameras mapped in OpenStreetMap. Camera alerts may be restricted where you ride; check local laws.",
                            systemImage: "info.circle",
                            tint: MapUI.textTertiary
                        )

                        RevertMenuPicker(
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

                        RevertSectionLabel(title: "Reaction time")
                        RevertOptionPicker(
                            options: [1.0, 1.5, 2.0, 2.5],
                            selection: $reactionTime,
                            title: { "\(RevertFormat.number($0, decimals: 1)) s" }
                        )

                        Toggle("Railroad crossings", isOn: $rail)
                        Toggle("School zones", isOn: $school)
                        Toggle("Roundabouts", isOn: $roundabout)

                        RevertInfoNote(
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

                        RevertSectionLabel(title: "Riding style")
                        RevertOptionPicker(
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

                        RevertSectionLabel(title: "Alert when over by")
                        RevertOptionPicker(
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

                    RevertSectionLabel(title: "Audio & data")
                        .padding(.top, 4)

                    SettingsCard(
                        title: "Mute all voice",
                        icon: "speaker.slash",
                        footer: "Silences turn-by-turn and hazard prompts at once. The cockpit has a one-tap toggle for this on the map dock."
                    ) {
                        Toggle("Mute every spoken prompt", isOn: $voiceMuted)
                    }

                    SettingsCard(
                        title: "Helmet audio",
                        icon: "airpodspro",
                        footer: "Spatial cues put hazard and turn alerts on the side of the road they belong to. Your Bluetooth helmet must be connected as the audio route."
                    ) {
                        Toggle("Binaural helmet cues", isOn: $binaural)
                    }

                    SettingsCard(title: "Data & privacy", icon: "externaldrive") {
                        NavigationLink {
                            SavedPlacesView(showsDone: false)
                        } label: {
                            HStack {
                                Label("Saved places", systemImage: "star")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                        Divider()
                        NavigationLink {
                            BackupView()
                        } label: {
                            HStack {
                                Label("Backup & restore", systemImage: "externaldrive.badge.icloud")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
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
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                        Divider()
                        NavigationLink {
                            RideDebugView()
                        } label: {
                            HStack {
                                Label("Ride debug files", systemImage: "doc.text.magnifyingglass")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
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
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(MapUI.textTertiary)
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Label("Reset preferences", systemImage: "arrow.counterclockwise")
                        }
                        .accessibilityHint("Restores the default units, camera, alerts and voice choices. Rides, places and the garage are kept.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .pulseBackground()
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .tint(MapUI.accent)
        }
        .sheet(isPresented: $showingFeatureLab) {
            FeatureHubView()
        }
        .alert("Reset preferences?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetPreferences() }
        } message: {
            Text("Units, camera, alerts, voice and companion choices return to their defaults. Rides, saved places and the garage are kept.")
        }
    }

    /// The single authoritative vehicle: whatever the Garage marks primary.
    private var primaryGarageBike: Bike? {
        garageBikes.first(where: \.isPrimary) ?? garageBikes.first
    }

    private var narratorLabel: String {
        if let pack = voicePacks.selectedPack { return pack.name }
        return voiceName
    }

    private func curveStyleLabel(_ value: Double) -> String {
        switch value {
        case 2.5: return "Relaxed"
        case 4.5: return "Sport"
        default: return "Normal"
        }
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
            return Pulse.lean
        case "externaldrive":
            return MapUI.violet
        default:
            return MapUI.cyan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                RevertIconBadge(systemImage: icon, tint: tint, size: 34, radius: 11)
                Text(title)
                    .font(RevertType.headline)
                    .foregroundStyle(MapUI.ink)
                Spacer(minLength: 0)
            }

            content

            if let footer {
                RevertInfoNote(text: footer, systemImage: "info.circle")
            }
        }
        .revertCard()
    }
}


    /// Clears behavioural preferences but never touches rides, places, the
    /// garage or onboarding. Keys are grouped by prefix so a new preference in
    /// one of these areas resets with the rest.
    private func resetPreferences() {
        let prefixes = ["ride.", "alert.", "units.", "voice.", "navigation.",
                        "helmet.", "companion.", "weather.", "map.",
                        "vehicle.", "conditions."]
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: { key.hasPrefix($0) }) {
            // Companion memory is rider data, not a preference: the dialog
            // promises rides are kept, and this is the record of them.
            guard key != "companion.memory.v1" else { continue }
            defaults.removeObject(forKey: key)
        }
        RevertHaptics.success()
    }
