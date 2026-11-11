import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Picks who speaks: an installed Waze voice pack or one of the system voices.
struct VoicePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alert.voiceName") private var voiceName = "System default"
    @AppStorage("navigation.voice") private var navigationVoice = true

    @State private var library = VoicePackLibrary.shared
    @State private var cachedVoices: [AVSpeechSynthesisVoice] = []
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RevertScreenHeader(
                    eyebrow: "NARRATOR",
                    title: "Choose a voice",
                    subtitle: "Voice packs play recorded Waze-style prompts. Street names and alerts the pack does not contain are spoken by the system voice.",
                    systemImage: "person.wave.2"
                )

                if !navigationVoice {
                    RevertInfoNote(
                        text: "Spoken turn directions are currently off. Turn them back on in Settings to hear this voice while riding.",
                        systemImage: "speaker.slash.fill",
                        tint: MapUI.amber
                    )
                }

                voicePackCard
                systemVoiceCard

                if let error = library.importError {
                    RevertInfoNote(text: error, systemImage: "exclamationmark.triangle.fill",
                                  tint: MapUI.coral)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle("Narrator voice")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MapUI.accent)
        .onAppear(perform: loadVoices)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: VoicePackImport.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                library.importPacks(from: urls)
            case .failure:
                break
            }
        }
    }

    // MARK: Voice packs

    private var voicePackCard: some View {
        SettingsCard(
            title: "Voice packs",
            icon: "square.stack.3d.up",
            footer: "Packs stay on this iPhone. Tap a pack to use it, or the speaker to hear a sample."
        ) {
            if library.installed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No voice packs installed")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                    Text("Browse the Waze archive or import a pack you already have.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(library.installed.enumerated()), id: \.element.id) { index, pack in
                    if index > 0 {
                        Rectangle().fill(MapUI.line).frame(height: 0.8)
                    }
                    packRow(pack)
                }
            }

            if let selected = library.selectedPack, !selected.isComplete {
                RevertInfoNote(
                    text: "\(selected.name) is missing \(VoiceClip.standardClipCount - selected.clipCount) prompts. Those lines are spoken by the system voice — pick a full pack to keep one consistent voice.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: MapUI.amber
                )
            }

            Rectangle().fill(MapUI.line).frame(height: 0.8)

            NavigationLink {
                VoicePacksView()
            } label: {
                HStack(spacing: 9) {
                    Label("Browse voice packs", systemImage: "arrow.down.circle")
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MapUI.textTertiary)
                }
            }

            Button {
                showImporter = true
            } label: {
                Label("Import MP3 pack…", systemImage: "folder.badge.plus")
            }
            .disabled(library.isImporting)

            if library.isImporting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Importing pack…")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                }
            }
        }
    }

    private func packRow(_ pack: InstalledVoicePack) -> some View {        let selected = library.selectedID == pack.id
        return HStack(spacing: 10) {
            Button {
                RevertHaptics.select()
                library.select(pack)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pack.name)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                            .multilineTextAlignment(.leading)
                        if pack.isBuiltIn {
                            Text("BUILT-IN")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(MapUI.emerald)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MapUI.emerald.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(detail(for: pack))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(pack.isComplete ? MapUI.textTertiary : MapUI.amber.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                Speaker.shared.say(Narrator.previewInstruction, kind: .navigation, pack: pack)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(MapUI.cyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(pack.name)")

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected ? MapUI.emerald : MapUI.textTertiary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .contextMenu {
            Button(role: .destructive) {
                library.delete(pack)
            } label: {
                Label("Delete pack", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The clip count only turns amber when the pack is genuinely incomplete,
    /// so a missing prompt is visible before a ride instead of surprising the
    /// rider with a different voice mid-route.
    private func detail(for pack: InstalledVoicePack) -> String {
        if pack.isComplete {
            return "\(pack.subtitle) · \(pack.clipCount) clips"
        }
        return "\(pack.subtitle) · \(pack.clipCount) of \(VoiceClip.standardClipCount) clips"
    }

    // MARK: System voices

    private var systemVoiceCard: some View {
        SettingsCard(
            title: "System voices",
            icon: "waveform",
            footer: "Enhanced voices can be downloaded in iPhone Settings. The system voice is also used for street names when a pack is selected."
        ) {
            systemRow("System default", detail: "Best installed voice")

            ForEach(availableVoices) { voice in
                Rectangle().fill(MapUI.line).frame(height: 0.8)
                systemRow(voice.name, detail: voice.language)
            }
        }
    }

    private func systemRow(_ name: String, detail: String) -> some View {
        let selected = library.selectedPack == nil && voiceName == name
        return Button {
            RevertHaptics.select()
            voiceName = name
            library.selectSystemVoice()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(MapUI.ink)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? MapUI.emerald : MapUI.textTertiary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private struct VoiceItem: Identifiable {
        let id: String
        let name: String
        let language: String
    }

    private var availableVoices: [VoiceItem] {
        cachedVoices.map {
            VoiceItem(id: $0.identifier, name: $0.name, language: $0.language)
        }
    }

    private func loadVoices() {
        guard cachedVoices.isEmpty else { return }
        let currentLang = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matching = all.filter { $0.language.starts(with: currentLang) }
        let candidates = matching.isEmpty ? all.filter { $0.language.starts(with: "en") } : matching
        var seen = Set<String>()
        cachedVoices = candidates.filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum VoicePackImport {
    static var contentTypes: [UTType] {
        var types: [UTType] = [.folder, .mp3]
        for extensionName in ["gz", "tgz", "tar"] {
            if let type = UTType(filenameExtension: extensionName) {
                types.append(type)
            }
        }
        return types
    }
}
