import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import MindMapInterchange

/// Writes ZIP archives for the XMind tests, laid out as PKWARE APPNOTE.TXT
/// describes (local headers, central directory, end record). Small and
/// test-only: the app never writes ZIP files.
struct ZipFixture {
    struct File {
        var path: String
        var data: Data
        var deflate = true
        /// Overrides the size written in both headers, for lying archives.
        var declaredSize: Int?
        /// Overrides the CRC, for damaged ones.
        var crc: UInt32?
    }

    var files: [File] = []

    init(_ files: [(String, Data)] = [], deflate: Bool = true) {
        self.files = files.map { File(path: $0.0, data: $0.1, deflate: deflate) }
    }

    static func xmindJSON(_ json: String, extra: [(String, Data)] = []) -> Data {
        ZipFixture([("content.json", Data(json.utf8)), ("metadata.json", Data("{}".utf8))] + extra).data
    }

    static func xmindXML(_ xml: String, extra: [(String, Data)] = []) -> Data {
        ZipFixture([("content.xml", Data(xml.utf8)), ("META-INF/manifest.xml", Data("<manifest/>".utf8))] + extra).data
    }

    var data: Data {
        var archive = Data()
        var directory = Data()
        for file in files {
            let offset = archive.count
            let compressed = file.deflate ? Self.deflate(file.data) : file.data
            let method: UInt16 = file.deflate ? 8 : 0
            let crc = file.crc ?? ZipArchive.crc32(file.data)
            let size = file.declaredSize ?? file.data.count
            let name = Data(file.path.utf8)

            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)
            archive.append(le16: 0x0800)
            archive.append(le16: method)
            archive.append(le32: 0)
            archive.append(le32: crc)
            archive.append(le32: UInt32(compressed.count))
            archive.append(le32: UInt32(size))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(compressed)

            directory.append(le32: 0x0201_4B50)
            directory.append(le16: 20)
            directory.append(le16: 20)
            directory.append(le16: 0x0800)
            directory.append(le16: method)
            directory.append(le32: 0)
            directory.append(le32: crc)
            directory.append(le32: UInt32(compressed.count))
            directory.append(le32: UInt32(size))
            directory.append(le16: UInt16(name.count))
            directory.append(le16: 0)
            directory.append(le16: 0)
            directory.append(le16: 0)
            directory.append(le16: 0)
            directory.append(le32: 0)
            directory.append(le32: UInt32(offset))
            directory.append(name)
        }
        let directoryOffset = archive.count
        archive.append(directory)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(files.count))
        archive.append(le16: UInt16(files.count))
        archive.append(le32: UInt32(directory.count))
        archive.append(le32: UInt32(directoryOffset))
        archive.append(le16: 0)
        return archive
    }

    /// Raw DEFLATE, as ZIP stores it.
    static func deflate(_ data: Data) -> Data {
        let capacity = data.count + 1_024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return output.prefix(written)
    }

    /// A small opaque PNG, for topic pictures.
    static func png(width: Int = 8, height: Int = 6) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: (0 ..< 4).map { UInt8((value >> (8 * $0)) & 0xFF) })
    }
}
