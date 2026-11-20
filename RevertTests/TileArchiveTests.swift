import Testing
import Foundation
@testable import Revert

@MainActor
struct TileArchiveTests {
    /// Build a 127-byte v3 header. Offsets may be overridden to model damage.
    private func header(fileSize: UInt64 = 1_000,
                        root: (UInt64, UInt64) = (127, 32),
                        metadata: (UInt64, UInt64) = (159, 16),
                        leaf: (UInt64, UInt64) = (0, 0),
                        tileData: (UInt64, UInt64) = (175, 800),
                        version: UInt8 = 3) -> Data {
        var bytes = [UInt8](repeating: 0, count: TileArchiveValidator.headerBytes)
        for (index, byte) in TileArchiveValidator.magic.enumerated() {
            bytes[index] = byte
        }
        bytes[7] = version
        func put(_ value: UInt64, at offset: Int) {
            for index in 0..<8 {
                bytes[offset + index] = UInt8((value >> (8 * index)) & 0xff)
            }
        }
        put(root.0, at: 8); put(root.1, at: 16)
        put(metadata.0, at: 24); put(metadata.1, at: 32)
        put(leaf.0, at: 40); put(leaf.1, at: 48)
        put(tileData.0, at: 56); put(tileData.1, at: 64)
        return Data(bytes)
    }

    @Test func consistentHeaderIsUsable() {
        #expect(TileArchiveValidator.isValidHeader(header(), fileSize: 1_000))
    }

    @Test func truncatedDownloadFailsEvenWithMagicBytes() {
        // Header says tile data runs to 975, but the file stops at 400: exactly
        // the mid-download case magic bytes alone could not catch.
        #expect(!TileArchiveValidator.isValidHeader(header(), fileSize: 400))
    }

    @Test func wrongVersionIsRejected() {
        #expect(!TileArchiveValidator.isValidHeader(header(version: 2), fileSize: 1_000))
    }

    @Test func missingDirectoryOrTilesIsRejected() {
        #expect(!TileArchiveValidator.isValidHeader(header(root: (127, 0)), fileSize: 1_000))
        #expect(!TileArchiveValidator.isValidHeader(header(tileData: (175, 0)), fileSize: 1_000))
    }

    @Test func overflowDoesNotWrapIntoAValidRange() {
        // start + length overflows UInt64; a naive comparison would accept it.
        #expect(!TileArchiveValidator.isValidHeader(
            header(tileData: (UInt64.max - 4, 16)), fileSize: 1_000))
    }

    @Test func shortFileAndMissingPathAreRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString).pmtiles")
        try Data("PMTi".utf8).write(to: url)
        #expect(!TileArchiveValidator.isUsable(url))
        #expect(!TileArchiveValidator.isUsable(URL(fileURLWithPath: "/tmp/none-\(UUID()).pmtiles")))
    }

    @Test func aRealHeaderPassesOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString).pmtiles")
        var bytes = [UInt8](header(fileSize: 1_000))
        bytes += [UInt8](repeating: 0xAB, count: 1_000 - 127)
        try Data(bytes).write(to: url)
        #expect(TileArchiveValidator.isUsable(url))
    }
}
