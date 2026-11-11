import SwiftUI
import UniformTypeIdentifiers

/// Browses the community Waze voice archive and installs packs on this iPhone.
struct VoicePacksView: View {
    @State private var library = VoicePackLibrary.shared
    @State private var query = ""
    @State private var showArchived = false
    @State private var showImporter = false

    private var allPacks: [VoicePack] { VoicePack.catalog }

    private var filteredPacks: [VoicePack] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allPacks.filter { pack in
            let installed = library.isInstalled(pack)
            let matchesSearch = search.isEmpty
                || pack.name.lowercased().contains(search)
                || pack.language.lowercased().contains(search)
                || (pack.author?.lowercased().contains(search) ?? false)
            guard matchesSearch else { return false }
            // Searching always reaches the archive; browsing hides dead links.
            if search.isEmpty, !showArchived, !installed {
                return pack.downloadable
            }
            return true
        }
    }

    private var availableCount: Int {
        allPacks.filter(\.downloadable).count
    }

    private var archivedCount: Int {
        allPacks.count - availableCount
    }

    private var catalogueSummary: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(filteredPacks.count) matches"
        }
        return "\(availableCount) available · \(archivedCount) archived · links checked \(checkedLabel)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RevertScreenHeader(
                    eyebrow: "VOICE ARCHIVE",
                    title: "Voice packs",
                    subtitle: "Classic Waze voices, recorded once and played back on this iPhone. Street names still use the system voice.",
                    systemImage: "square.stack.3d.up"
                )

                searchField

                HStack(spacing: 8) {
                    Toggle("Show archived packs", isOn: $showArchived)
                        .toggleStyle(.switch)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                        .tint(MapUI.cyan)
                }
                .padding(.horizontal, 2)

                Text(catalogueSummary)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)

                if !library.installed.isEmpty {
                    installedCard
                }

                LazyVStack(spacing: 8) {
                    ForEach(filteredPacks) { pack in
                        catalogRow(pack)
                    }
                }

                if filteredPacks.isEmpty {
                    RevertInfoNote(
                        text: "No voice matches “\(query)”. Try a language or a character name.",
                        systemImage: "magnifyingglass",
                        tint: MapUI.textTertiary
                    )
                    .padding(.top, 4)
                }

                if let error = library.importError {
                    RevertInfoNote(text: error, systemImage: "exclamationmark.triangle.fill",
                                  tint: MapUI.coral)
                }

                RevertInfoNote(
                    text: "Waze retired most of these download links in 2026. Archived packs stay listed in case a link returns; if yours is gone, import its MP3 files instead — Revert recognises the same clip names.",
                    systemImage: "clock.arrow.circlepath",
                    tint: MapUI.textTertiary
                )
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle("Voice packs")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MapUI.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("Import a voice pack")
                .disabled(library.isImporting)
            }
        }
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

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MapUI.textTertiary)
            TextField("Search by name, language or author", text: $query)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MapUI.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MapUI.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(MapUI.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(MapUI.line, lineWidth: 0.8)
        )
    }

    private var installedCard: some View {
        SettingsCard(title: "On this iPhone", icon: "checkmark.seal") {
            ForEach(Array(library.installed.enumerated()), id: \.element.id) { index, pack in
                if index > 0 {
                    Rectangle().fill(MapUI.line).frame(height: 0.8)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(pack.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
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
                        Text(pack.isComplete
                             ? "\(pack.subtitle) · \(pack.clipCount) clips"
                             : "\(pack.subtitle) · \(pack.clipCount) of \(VoiceClip.standardClipCount) clips")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(pack.isComplete ? MapUI.textTertiary : MapUI.amber.opacity(0.85))
                    }
                    Spacer(minLength: 8)

                    if library.selectedID == pack.id {
                        Text("Speaking")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(MapUI.emerald)
                    } else {
                        Button("Use") {
                            RevertHaptics.select()
                            library.select(pack)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MapUI.cyan)
                    }

                    Button {
                        Speaker.shared.say(Narrator.previewInstruction, kind: .navigation, pack: pack)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(MapUI.cyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview \(pack.name)")

                    Menu {
                        Button(role: .destructive) {
                            library.delete(pack)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                }
            }
        }
    }

    private func catalogRow(_ pack: VoicePack) -> some View {
        let state = library.states[pack.id]
        let installed = library.isInstalled(pack)
        let selected = library.selectedID == pack.id

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pack.name)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if pack.source == .official {
                            Text("OFFICIAL")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(MapUI.cyan)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MapUI.cyan.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(pack.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                }

                Spacer(minLength: 8)

                trailingControl(pack, state: state, installed: installed, selected: selected)
            }

            if case .failed(let message) = state {
                RevertInfoNote(text: message, systemImage: "exclamationmark.triangle.fill",
                              tint: MapUI.coral)
            } else if !pack.downloadable, !installed {
                RevertInfoNote(
                    text: "Archived: Waze no longer answers for this link.",
                    systemImage: "clock.arrow.circlepath",
                    tint: MapUI.textTertiary
                )
            }
        }
        .padding(12)
        .background(MapUI.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? MapUI.emerald.opacity(0.7) : MapUI.line, lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func trailingControl(_ pack: VoicePack, state: VoicePackLibrary.InstallState?,
                                 installed: Bool, selected: Bool) -> some View {
        if let state {
            switch state {
            case .downloading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Getting")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                }
            case .installing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Installing")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(MapUI.textSecondary)
                }
            case .failed:
                Button("Retry") {
                    library.retry(pack)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(MapUI.cyan)
            }
        } else if installed {
            Button {
                RevertHaptics.select()
                if let installedPack = library.installed.first(where: { $0.id == pack.id }) {
                    library.select(installedPack)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(selected ? MapUI.emerald : MapUI.textTertiary)
                    Text(selected ? "Speaking" : "Use")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? MapUI.emerald : MapUI.textSecondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                library.install(pack)
            } label: {
                Text(pack.downloadable ? "Get" : "Try")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MapUI.cyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Install \(pack.name)")
        }
    }

    private var checkedLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: VoicePack.catalogCheckedAt) else {
            return VoicePack.catalogCheckedAt
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
