import Compression
import Foundation

/// Reads the MP3 files out of a Waze voice-pack download.
///
/// Waze serves packs as `.tar.gz` archives, but iOS has no public archive
/// reader, so this file contains the small amount that is needed: a gzip
/// header skipper (the payload is plain DEFLATE, which `Compression` can
/// inflate) and a tar reader that understands the regular, GNU long-name and
/// PAX extended headers Waze's GNU tar writes.
nonisolated enum TarGzip {
    enum Failure: LocalizedError {
        case corruptArchive
        case noAudio

        var errorDescription: String? {
            switch self {
            case .corruptArchive: "The voice pack download was damaged."
            case .noAudio: "That file does not contain any voice clips."
            }
        }
    }

    /// Every MP3 in the archive, keyed by the file's base name.
    static func mp3Files(from data: Data) throws -> [String: Data] {
        let tar: Data
        do {
            tar = try gunzip(data)
        } catch {
            // A plain `.tar` is also accepted.
            tar = data
        }
        let entries = try tarEntries(tar)
        var files: [String: Data] = [:]
        for (name, payload) in entries {
            let base = (name as NSString).lastPathComponent
            guard ["mp3", "m4a"].contains((base as NSString).pathExtension.lowercased()),
                  !payload.isEmpty, payload.count <= 4_000_000 else { continue }
            files[base] = payload
        }
        guard !files.isEmpty else { throw Failure.noAudio }
        return files
    }

    // MARK: gzip

    /// Decompress a gzip stream. Falls back to treating the data as a raw
    /// DEFLATE payload for servers that omit the gzip wrapper.
    static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw Failure.corruptArchive }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else {
            return try inflate(data)
        }
        guard bytes.count > 10 else { throw Failure.corruptArchive }

        var offset = 10
        let flags = bytes[3]
        if flags & 0x04 != 0 {                                  // FEXTRA
            guard offset + 2 <= bytes.count else { throw Failure.corruptArchive }
            let extra = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            offset += 2 + extra
        }
        if flags & 0x08 != 0 {                                  // FNAME
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {                                  // FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }                     // FHCRC
        guard offset > 0, offset < bytes.count else { throw Failure.corruptArchive }
        return try inflate(data.subdata(in: offset..<data.count))
    }

    private static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw Failure.corruptArchive }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.corruptArchive
        }
        defer { compression_stream_destroy(&stream) }

        let chunk = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }

        var output = Data()
        let status = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> compression_status in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return COMPRESSION_STATUS_ERROR
            }
            stream.src_ptr = base
            stream.src_size = data.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = chunk
                let result = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                if result == COMPRESSION_STATUS_ERROR { return COMPRESSION_STATUS_ERROR }
                let produced = chunk - stream.dst_size
                output.append(destination, count: produced)
                if result == COMPRESSION_STATUS_END { return COMPRESSION_STATUS_OK }
                // No progress means the stream is truncated; stop instead of spinning.
                if produced == 0, stream.src_size == 0 { return COMPRESSION_STATUS_ERROR }
                if output.count > 40_000_000 { return COMPRESSION_STATUS_ERROR }
            }
        }
        guard status == COMPRESSION_STATUS_OK else { throw Failure.corruptArchive }
        return output
    }

    // MARK: tar

    private static func tarEntries(_ tar: Data) throws -> [(String, Data)] {
        let bytes = [UInt8](tar)
        guard bytes.count >= 512 else { throw Failure.corruptArchive }

        var entries: [(String, Data)] = []
        var offset = 0
        var pendingName: String?

        while offset + 512 <= bytes.count {
            let header = bytes[offset..<(offset + 512)]
            if header.allSatisfy({ $0 == 0 }) { break }

            let type = bytes[offset + 156]
            let size = number(bytes, offset + 124, offset + 136)
            guard size >= 0, offset + 512 + size <= bytes.count else { break }

            let payload = Data(bytes[(offset + 512)..<(offset + 512 + size)])

            switch type {
            case 0x78:                                          // 'x' — PAX extended header
                if let path = paxPath(payload) { pendingName = path }
            case 0x67:                                          // 'g' — PAX global header
                break
            case 0x4c:                                          // 'L' — GNU long name
                pendingName = String(decoding: payload.prefix { $0 != 0 }, as: UTF8.self)
            case 0x4b:                                          // 'K' — GNU long link
                break
            case 0x30, 0x37, 0x00:                              // regular file
                var name = cString(bytes, offset, offset + 100)
                let prefix = cString(bytes, offset + 345, offset + 500)
                if !prefix.isEmpty { name = prefix + "/" + name }
                entries.append((pendingName ?? name, payload))
            default:
                break
            }

            // A PAX/long-name header only applies to the entry that follows it.
            if type != 0x78, type != 0x67 { pendingName = nil }
            offset += 512 + ((size + 511) / 512) * 512
        }
        return entries
    }

    private static func cString(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
        let slice = bytes[start..<end]
        let stop = slice.firstIndex(of: 0) ?? slice.endIndex
        return String(decoding: slice[..<stop], as: UTF8.self)
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Int {
        // GNU's base-256 representation for very large values.
        if bytes[start] & 0x80 != 0 {
            var value = Int(bytes[start] & 0x7f)
            for index in (start + 1)..<end { value = (value << 8) | Int(bytes[index]) }
            return value
        }
        var value = 0
        for index in start..<end {
            let byte = bytes[index]
            guard byte >= 0x30, byte <= 0x37 else {
                if value == 0, byte == 0x20 || byte == 0 { continue }
                break
            }
            value = value * 8 + Int(byte - 0x30)
        }
        return value
    }

    /// PAX records are `<length> <key>=<value>\n`, where length covers the whole record.
    private static func paxPath(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            var length = 0
            var cursor = index
            while cursor < bytes.count, bytes[cursor] >= 0x30, bytes[cursor] <= 0x39 {
                length = length * 10 + Int(bytes[cursor] - 0x30)
                cursor += 1
            }
            guard length > 0, index + length <= bytes.count else { break }
            if cursor < bytes.count, bytes[cursor] == 0x20 {
                let record = bytes[(cursor + 1)..<(index + length)]
                if let equals = record.firstIndex(of: 0x3d) {
                    let key = String(decoding: record[..<equals], as: UTF8.self)
                    var value = Array(record[(equals + 1)...])
                    if value.last == 0x0a { value.removeLast() }
                    if key == "path" {
                        return String(decoding: value, as: UTF8.self)
                    }
                }
            }
            index += length
        }
        return nil
    }
}
