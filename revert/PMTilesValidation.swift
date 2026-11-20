import Foundation

/// Preflight for a PMTiles v3 archive.
///
/// ImmersiveMap hands a broken archive to the renderer as "no tiles", which
/// looks exactly like a map with no data: a blank screen mid-ride. Magic bytes
/// alone are not enough — a download truncated after the header still starts
/// with `PMTiles` — so this reads the v3 header and checks that every section
/// it points at actually fits inside the file.
nonisolated enum TileArchiveValidator {
    static let magic = Data("PMTiles".utf8)
    static let version: UInt8 = 3
    /// Fixed size of the v3 header.
    static let headerBytes = 127

    static func isUsable(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        let fileSize = size.uint64Value
        guard fileSize >= UInt64(headerBytes) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: headerBytes),
              header.count == headerBytes else { return false }
        return isValidHeader(header, fileSize: fileSize)
    }

    /// Pure header check, so tests can build headers without touching disk.
    static func isValidHeader(_ header: Data, fileSize: UInt64) -> Bool {
        guard header.count >= headerBytes,
              header.prefix(magic.count) == magic else { return false }
        guard header[header.startIndex + 7] == version else { return false }

        func u64(at offset: Int) -> UInt64 {
            let start = header.startIndex + offset
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(header[start + index]) << (8 * index)
            }
            return value
        }

        // Offsets: root dir 8, metadata 24, leaf dirs 40, tile data 56.
        // Each is followed by its length.
        let sections = [8, 24, 40, 56]
        for offset in sections {
            let start = u64(at: offset)
            let length = u64(at: offset + 8)
            guard length <= UInt64.max - start else { return false }
            guard start + length <= fileSize else { return false }
        }

        // A usable archive must have a directory and some tile data. Metadata
        // and leaf directories are allowed to be empty.
        let rootLength = u64(at: 16)
        let tileDataLength = u64(at: 64)
        return rootLength > 0 && tileDataLength > 0
    }
}
