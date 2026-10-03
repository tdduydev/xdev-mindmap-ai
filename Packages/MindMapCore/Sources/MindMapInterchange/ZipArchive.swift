import Compression
import Foundation

/// Reads files out of a ZIP archive held in memory, for formats that are one
/// (XMind, MM-103). Only what those files use: stored and deflated entries,
/// no encryption, no ZIP64, one disk. Format: PKWARE APPNOTE.TXT, sections
/// 4.3.7 (local header), 4.3.12 (central directory), 4.3.16 (end record).
///
/// The central directory is read once; an entry is inflated only when asked
/// for. Sizes are checked against `limits` before anything is allocated, and
/// inflating never writes past the size the directory declared, so a small
/// file that claims or expands to gigabytes (a zip bomb) is refused instead
/// of filling memory. The CRC catches an entry whose bytes do not match.
struct ZipArchive {
    struct Limits: Hashable, Sendable {
        /// The most one entry may expand to.
        var maximumEntrySize: Int
        /// The most all entries read from one archive may expand to together.
        var maximumTotalSize: Int
        var maximumEntryCount: Int

        /// Generous for a mind map: XMind's own files are a few megabytes, and
        /// a picture is scaled down to 5 MB after import anyway.
        static let standard = Limits(
            maximumEntrySize: 64 * 1_024 * 1_024,
            maximumTotalSize: 256 * 1_024 * 1_024,
            maximumEntryCount: 10_000
        )
    }

    enum Error: Swift.Error, Hashable {
        /// No end of central directory record: not a ZIP file at all.
        case notAnArchive
        /// A ZIP file with a broken record, an unknown compression or a wrong CRC.
        case damaged
        /// An entry, or the entries read so far, would expand beyond the limits.
        case tooLarge
    }

    struct Entry: Hashable {
        let path: String
        let method: UInt16
        let flags: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private let limits: Limits
    /// By path; a path listed twice keeps its first entry.
    private(set) var entries: [String: Entry] = [:]
    private var bytesRead = 0

    init(_ data: Data, limits: Limits = .standard) throws(Error) {
        // Indexing from 0 below; a slice of a larger Data would start elsewhere.
        self.data = Data(data)
        self.limits = limits
        try readDirectory()
    }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    /// The entry's bytes, inflated and checked. Nil when the archive has no such path.
    mutating func read(_ path: String) throws(Error) -> Data? {
        guard let entry = entries[path] else { return nil }
        guard entry.size <= limits.maximumEntrySize, bytesRead + entry.size <= limits.maximumTotalSize else {
            throw .tooLarge
        }
        // Encrypted entries (bit 0) cannot be read without a password.
        guard entry.flags & 1 == 0 else { throw .damaged }

        let header = entry.localHeaderOffset
        guard header >= 0, header + 30 <= data.count, uint32(at: header) == 0x0403_4B50 else { throw .damaged }
        let start = header + 30 + Int(uint16(at: header + 26)) + Int(uint16(at: header + 28))
        guard start + entry.compressedSize <= data.count else { throw .damaged }
        let compressed = data[start ..< start + entry.compressedSize]

        let output: Data
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.size else { throw .damaged }
            output = Data(compressed)
        case 8:
            output = try Self.inflate(compressed, size: entry.size)
        default:
            throw .damaged
        }
        guard Self.crc32(output) == entry.crc else { throw .damaged }
        bytesRead += output.count
        return output
    }

    // MARK: Directory

    private mutating func readDirectory() throws(Error) {
        // The end record is 22 bytes plus a comment of at most 65,535.
        let lowest = max(0, data.count - 22 - 65_535)
        var end: Int?
        var offset = data.count - 22
        while offset >= lowest {
            if uint32(at: offset) == 0x0605_4B50 {
                end = offset
                break
            }
            offset -= 1
        }
        guard let end else { throw .notAnArchive }

        let count = Int(uint16(at: end + 10))
        // 0xFFFF and 0xFFFFFFFF mean the real values are in a ZIP64 record.
        // Compared and converted as UInt32: Int has 32 bits on Apple Watch
        // (arm64_32), where 0xFFFFFFFF does not fit and Int(_:) would trap.
        let rawOffset = uint32(at: end + 16)
        guard count != 0xFFFF, rawOffset != 0xFFFF_FFFF,
              let directorySize = Int(exactly: uint32(at: end + 12)),
              let directoryOffset = Int(exactly: rawOffset) else { throw .damaged }
        guard count <= limits.maximumEntryCount else { throw .tooLarge }
        guard directoryOffset + directorySize <= end else { throw .damaged }

        var position = directoryOffset
        for _ in 0 ..< count {
            guard position + 46 <= end, uint32(at: position) == 0x0201_4B50 else { throw .damaged }
            let nameLength = Int(uint16(at: position + 28))
            let extraLength = Int(uint16(at: position + 30))
            let commentLength = Int(uint16(at: position + 32))
            let nameStart = position + 46
            guard nameStart + nameLength <= end else { throw .damaged }
            let compressedSize = uint32(at: position + 20)
            let size = uint32(at: position + 24)
            let localOffset = uint32(at: position + 42)
            guard compressedSize != 0xFFFF_FFFF, size != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF,
                  let compressedLength = Int(exactly: compressedSize), let length = Int(exactly: size),
                  let localHeaderOffset = Int(exactly: localOffset) else { throw .damaged }

            // XMind writes ASCII paths; bit 11 says UTF-8 and most tools use it anyway.
            let path = String(decoding: data[nameStart ..< nameStart + nameLength], as: UTF8.self)
            if entries[path] == nil {
                entries[path] = Entry(
                    path: path,
                    method: uint16(at: position + 10),
                    flags: uint16(at: position + 8),
                    crc: uint32(at: position + 16),
                    compressedSize: compressedLength,
                    size: length,
                    localHeaderOffset: localHeaderOffset
                )
            }
            position = nameStart + nameLength + extraLength + commentLength
        }
    }

    private func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    // MARK: Inflate and CRC

    /// Raw DEFLATE (RFC 1951), which is what `COMPRESSION_ZLIB` decodes. The
    /// output buffer is exactly `size` bytes: data that expands further is cut
    /// off there and then fails the CRC, so the declared size bounds memory.
    private static func inflate(_ compressed: Data, size: Int) throws(Error) -> Data {
        guard size > 0 else { return Data() }
        guard !compressed.isEmpty else { throw .damaged }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            compressed.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw .damaged }
        return output
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
