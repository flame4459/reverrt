import Foundation

/// Voices that ship inside the app, so a complete pack works before any
/// network download.
///
/// These are four complete 43-clip packs from the community archive. They are
/// copied into Application Support on first launch and can be deleted like any
/// other pack. Bump `seedVersion` if the bundled set changes.
@MainActor
enum BuiltInVoicePacks {
    struct Entry: Identifiable {
        /// Catalogue UUID, used as the installed folder name.
        let id: String
        /// Bundle resource name without the `.tar.gz` extension.
        let resource: String
    }

    static let entries: [Entry] = [
        Entry(id: "d600f88e-cfdf-46ea-9a5a-8d9c5d3a22c4", resource: "voicepack-glasgow-jim"),
        Entry(id: "12DE1A6A-831A-4717-A6FC-C7D99633635E", resource: "voicepack-mark-pilgrim"),
        Entry(id: "3AF908A5-D798-44B3-9BAB-8F4DB7625E9B", resource: "voicepack-jamaican"),
        Entry(id: "CB6BA079-93EB-46E4-A8F0-C6BC78EEC877", resource: "voicepack-union-co")
    ]

    private static let seedKey = "voice.builtIn.seed"
    private static let seedVersion = "1"

    /// Finds the bundled archive whether Xcode copied it flat or kept the
    /// source folder.
    static func resourceURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "tar.gz")
            ?? Bundle.main.url(forResource: name, withExtension: "tar.gz",
                               subdirectory: "BuiltInVoicePacks")
    }

    static func installIfNeeded(into library: VoicePackLibrary) {
        guard UserDefaults.standard.string(forKey: seedKey) != seedVersion else { return }
        // Only mark the seed if every archive is present; otherwise try again
        // next launch instead of leaving the app without voices.
        guard entries.allSatisfy({ resourceURL($0.resource) != nil }) else { return }

        for entry in entries {
            guard let pack = VoicePack.catalog.first(where: { $0.id == entry.id }),
                  !library.isInstalled(pack),
                  let url = resourceURL(entry.resource),
                  let data = try? Data(contentsOf: url) else { continue }
            library.installBuiltIn(pack, data: data)
        }
        UserDefaults.standard.set(seedVersion, forKey: seedKey)
    }
}
