import AVFoundation
import Foundation
import Observation

/// Owns the voice packs installed on this iPhone and the pack the rider picked.
///
/// Packs live in Application Support so they survive launches without being
/// visible to the Files app. Each folder holds the MP3 clips plus a small
/// `Pack.json` with the name, language and origin shown in Settings.
@MainActor
@Observable
final class VoicePackLibrary {
    static let shared = VoicePackLibrary()
    static let selectionKey = "voice.packID"

    enum InstallState: Equatable {
        case downloading
        case installing
        case failed(String)
    }

    private(set) var installed: [InstalledVoicePack] = []
    private(set) var states: [String: InstallState] = [:]
    private(set) var isImporting = false
    private(set) var importError: String?

    /// The selected pack's id, or `nil` when the system voice is in use.
    var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID ?? "", forKey: Self.selectionKey)
        }
    }

    var selectedPack: InstalledVoicePack? {
        guard let selectedID else { return nil }
        return installed.first { $0.id == selectedID }
    }

    var installedIDs: Set<String> {
        Set(installed.map(\.id))
    }

    private var clipCache: [String: [VoiceClip: URL]] = [:]
    private let fileManager = FileManager.default
    private let session: URLSession
    /// Whether a narrator choice existed before this launch. `selectedID`'s
    /// observer writes the key, so it cannot be used to tell.
    private let hadStoredSelection: Bool

    private struct Metadata: Codable {
        var id: String
        var name: String
        var language: String
        var author: String?
        var source: VoicePack.Source
        var installedAt: Date
        /// Optional so Pack.json files written before built-in packs existed
        /// still decode.
        var builtIn: Bool?
    }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)

        let stored = UserDefaults.standard.string(forKey: Self.selectionKey)
        hadStoredSelection = stored != nil
        selectedID = (stored?.isEmpty == false) ? stored : nil
        reload()
    }

    // MARK: Public state

    func isInstalled(_ pack: VoicePack) -> Bool {
        installed.contains { $0.id == pack.id }
    }

    func clips(for pack: InstalledVoicePack) -> [VoiceClip: URL] {
        if let cached = clipCache[pack.id] { return cached }

        let directory = rootDirectory.appendingPathComponent(pack.id, isDirectory: true)
        let lookup = Dictionary(uniqueKeysWithValues: VoiceClip.allCases.map {
            ($0.rawValue.lowercased(), $0)
        })
        var map: [VoiceClip: URL] = [:]
        if let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in urls where Self.audioExtensions.contains(url.pathExtension.lowercased()) {
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if let clip = lookup[stem] { map[clip] = url }
            }
        }
        clipCache[pack.id] = map
        return map
    }

    /// True when the pack has every clip a navigation prompt can need.
    func hasRequiredClips(_ pack: InstalledVoicePack) -> Bool {
        VoiceClip.requiredForInstall.isSubset(of: Set(clips(for: pack).keys))
    }

    func select(_ pack: InstalledVoicePack) {
        selectedID = pack.id
    }

    func selectSystemVoice() {
        selectedID = nil
    }

    /// Reloads the installed list from disk.
    func reload() {
        clipCache.removeAll()

        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            installed = []
            return
        }

        installed = urls.compactMap { url -> InstalledVoicePack? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let metadata = try? Data(contentsOf: url.appendingPathComponent("Pack.json")),
                  let meta = try? JSONDecoder().decode(Metadata.self, from: metadata) else {
                return nil
            }
            let clipCount = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
                .filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }.count ?? 0
            return InstalledVoicePack(
                id: meta.id,
                name: meta.name,
                language: meta.language,
                author: meta.author,
                source: meta.source,
                installedAt: meta.installedAt,
                clipCount: clipCount,
                isBuiltIn: meta.builtIn ?? false
            )
        }
        .sorted { lhs, rhs in
            // Complete packs first: they keep one voice for the whole ride.
            if lhs.isComplete != rhs.isComplete { return lhs.isComplete }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if let selectedID, !installed.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    // MARK: Catalogue installs

    func install(_ pack: VoicePack) {
        switch states[pack.id] {
        case .downloading, .installing: return
        default: break
        }

        states[pack.id] = .downloading
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await session.data(from: pack.downloadURL)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw VoicePackError.notServed(http.statusCode)
                }
                states[pack.id] = .installing

                let files = try await Task.detached(priority: .utility) {
                    try TarGzip.mp3Files(from: data)
                }.value

                let clips = Self.canonicalClips(files)
                guard clips.count >= 4 else { throw VoicePackError.notAVoicePack }

                try store(clips: clips, id: pack.id, name: pack.name,
                          language: pack.language, author: pack.author, source: pack.source)
                states[pack.id] = nil
                reload()
                selectedID = pack.id
            } catch {
                states[pack.id] = .failed(Self.message(for: error))
            }
        }
    }

    func retry(_ pack: VoicePack) {
        states[pack.id] = nil
        install(pack)
    }

    // MARK: Built-in packs

    /// Installs a pack that ships inside the app bundle. No network involved.
    func installBuiltIn(_ pack: VoicePack, data: Data) {
        guard !isInstalled(pack),
              let files = try? TarGzip.mp3Files(from: data) else { return }
        let clips = Self.canonicalClips(files)
        guard clips.count >= 4 else { return }
        try? store(clips: clips, id: pack.id, name: pack.name, language: pack.language,
                   author: pack.author, source: pack.source, builtIn: true)
        reload()
    }

    /// Copies the bundled voices in on first launch so at least one complete
    /// voice works without a download.
    func installBuiltInsIfNeeded() {
        repairInstalledPacks()

        // On a genuinely fresh install, start on a complete bundled voice
        // instead of the system synthesiser. An explicit choice — including
        // "system voice" — is never overridden.
        let hadPacks = !installed.isEmpty
        BuiltInVoicePacks.installIfNeeded(into: self)
        if !hadStoredSelection, !hadPacks, let first = installed.first(where: \.isBuiltIn) {
            selectedID = first.id
        }
    }

    /// Packs installed before audio-container sniffing existed may hold AAC
    /// files named `.mp3`. Renaming them in place makes those voices work
    /// without asking the rider to reinstall.
    func repairInstalledPacks() {
        guard let packs = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        var repaired = false
        for pack in packs where (try? pack.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard let files = try? fileManager.contentsOfDirectory(
                at: pack,
                includingPropertiesForKeys: nil
            ) else { continue }

            for file in files {
                let ext = file.pathExtension.lowercased()
                guard ext == "mp3" || ext == "m4a" else { continue }

                if ext == "mp3",
                   let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                   Self.audioExtension(for: data) == "m4a" {
                    let target = file.deletingPathExtension().appendingPathExtension("m4a")
                    try? fileManager.removeItem(at: target)
                    if (try? fileManager.moveItem(at: file, to: target)) != nil {
                        repaired = true
                    }
                    continue
                }

                if !Self.isPlayableAudio(file) {
                    try? fileManager.removeItem(at: file)
                    repaired = true
                }
            }
        }
        if repaired { reload() }
    }

    // MARK: Imports

    /// Imports one or more files or folders picked from Files.
    func importPacks(from urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        importError = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let collected = try await Task.detached(priority: .userInitiated) {
                    try Self.collect(from: urls)
                }.value

                let clips = Self.canonicalClips(collected.files)
                guard clips.count >= 4 else { throw VoicePackError.notAVoicePack }

                let id = "import-\(UUID().uuidString)"
                try store(clips: clips, id: id, name: collected.name,
                          language: "Imported", author: nil, source: .community)
                importError = nil
                reload()
                selectedID = id
            } catch {
                importError = Self.message(for: error)
            }
            isImporting = false
        }
    }

    func delete(_ pack: InstalledVoicePack) {
        let directory = rootDirectory.appendingPathComponent(pack.id, isDirectory: true)
        try? fileManager.removeItem(at: directory)
        clipCache.removeValue(forKey: pack.id)
        states[pack.id] = nil
        if selectedID == pack.id { selectedID = nil }
        reload()
    }

    // MARK: Storage

    private var rootDirectory: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("VoicePacks", isDirectory: true)
    }

    private func store(clips: [VoiceClip: Data], id: String, name: String,
                       language: String, author: String?, source: VoicePack.Source,
                       builtIn: Bool = false) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let target = rootDirectory.appendingPathComponent(id, isDirectory: true)
        let temporary = rootDirectory.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)

        do {
            for (clip, data) in clips {
                // Older Waze uploads occasionally label AAC audio as `.mp3`.
                // Storing it with the container's real extension keeps
                // AVAudioPlayer from decoding it as 50ms of noise.
                let fileName = "\(clip.rawValue).\(Self.audioExtension(for: data))"
                let url = temporary.appendingPathComponent(fileName)
                try data.write(to: url, options: .atomic)
                if !Self.isPlayableAudio(url) {
                    try? fileManager.removeItem(at: url)
                }
            }
            let playable = (try? fileManager.contentsOfDirectory(
                at: temporary, includingPropertiesForKeys: nil))?
                .filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }.count ?? 0
            guard playable >= 4 else { throw VoicePackError.notAVoicePack }

            let metadata = Metadata(id: id, name: name, language: language,
                                    author: author, source: source,
                                    installedAt: Date(), builtIn: builtIn)
            let encoded = try JSONEncoder().encode(metadata)
            try encoded.write(to: temporary.appendingPathComponent("Pack.json"), options: .atomic)

            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: temporary, to: target)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        clipCache.removeValue(forKey: id)
    }

    private nonisolated static let audioExtensions: Set<String> = ["mp3", "m4a"]

    /// The file extension that matches the actual container. Waze packs are
    /// usually MP3, but some community uploads are AAC in an MP4 container with
    /// an `.mp3` name.
    nonisolated static func audioExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {  // "ftyp"
            return "m4a"
        }
        return "mp3"
    }

    /// Rejects empty or undecodable clips so a broken file cannot become a
    /// burst of noise or silently silence a prompt.
    nonisolated static func isPlayableAudio(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return false }
        return Double(file.length) / file.processingFormat.sampleRate > 0.05
    }

    /// Maps arbitrary MP3 file names onto Waze's fixed prompt names.
    nonisolated static func canonicalClips(_ files: [String: Data]) -> [VoiceClip: Data] {
        let lookup = Dictionary(uniqueKeysWithValues: VoiceClip.allCases.map {
            ($0.rawValue.lowercased(), $0)
        })
        var clips: [VoiceClip: Data] = [:]
        for (name, data) in files {
            let base = (name as NSString).lastPathComponent
            let stem = (base as NSString).deletingPathExtension.lowercased()
            if let clip = lookup[stem] { clips[clip] = data }
        }
        return clips
    }

    nonisolated static func collect(from urls: [URL]) throws -> (files: [String: Data], name: String) {
        var files: [String: Data] = [:]
        var suggestedName = "Imported voice"

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                if suggestedName == "Imported voice" { suggestedName = url.lastPathComponent }
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
                while let file = enumerator?.nextObject() as? URL {
                    guard audioExtensions.contains(file.pathExtension.lowercased()),
                          let data = try? Data(contentsOf: file) else { continue }
                    files[file.lastPathComponent] = data
                }
                continue
            }

            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "mp3", "m4a":
                let data = try Data(contentsOf: url)
                files[url.lastPathComponent] = data
                if suggestedName == "Imported voice" {
                    suggestedName = url.deletingPathExtension().lastPathComponent
                }
            case "gz", "tgz", "tar":
                let data = try Data(contentsOf: url)
                for (name, payload) in try TarGzip.mp3Files(from: data) {
                    files[name] = payload
                }
                var name = url.deletingPathExtension().lastPathComponent
                if name.lowercased().hasSuffix(".tar") {
                    name = String(name.dropLast(4))
                }
                suggestedName = name
            case "zip":
                throw VoicePackError.unsupportedArchive
            default:
                throw VoicePackError.unsupportedArchive
            }
        }

        guard !files.isEmpty else { throw VoicePackError.notAVoicePack }
        return (files, suggestedName)
    }

    private static func message(for error: Error) -> String {
        if let error = error as? VoicePackError {
            return error.errorDescription ?? "The voice pack could not be installed."
        }
        if let error = error as? TarGzip.Failure {
            return error.errorDescription ?? "The voice pack could not be read."
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Couldn't reach Waze. Check the connection and try again, or import the pack's files."
        }
        return error.localizedDescription
    }
}

nonisolated enum VoicePackError: LocalizedError {
    case notServed(Int)
    case notAVoicePack
    case unsupportedArchive

    var errorDescription: String? {
        switch self {
        case .notServed(403):
            "Waze no longer serves this classic pack. Import its MP3 files instead."
        case .notServed(let status):
            "Waze returned an error (\(status)) for this pack."
        case .notAVoicePack:
            "That file does not contain playable Waze voice clips. Packs contain clips such as TurnLeft.mp3 and Arrive.mp3."
        case .unsupportedArchive:
            "This archive type is not supported. Use a Waze .tar.gz pack, or unzip it and import the folder."
        }
    }
}
