import CoreGraphics
import Foundation
import ImageIO
import MindMapDomain
import UniformTypeIdentifiers

/// An image ready to store on a topic: scaled, re-encoded, without metadata.
public struct ProcessedImage: Hashable, Sendable {
    public let data: Data
    /// `public.heic`, `public.png` or `public.jpeg`.
    public let uniformType: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public var byteCount: Int { data.count }

    /// A new image record for a topic, bytes included, for `SetNodeImageCommand`.
    public func image(
        id: ImageID = ImageID(),
        mapID: MapID,
        nodeID: NodeID,
        displayWidth: Double? = nil,
        altText: String? = nil,
        createdAt: Date = .now
    ) -> MindImage {
        MindImage(
            id: id, mapID: mapID, nodeID: nodeID, data: data, uniformType: uniformType,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, byteCount: byteCount,
            displayWidth: displayWidth, altText: altText.flatMap(MindImage.normalizedAltText),
            createdAt: createdAt
        )
    }
}

public enum ImageProcessingError: Error, Hashable, Sendable {
    /// Not an image ImageIO can decode ("This file isn't an image the app can read").
    case unreadable
    /// The file, or the image once encoded, is over the limit ("This image is too large").
    case tooLarge
}

/// Turns any image file into what a topic stores (FR-ORG-28, "Images" in
/// docs/node-organization.md): orientation applied, longest side at most
/// `maximumPixelSize`, re-encoded as HEIC (PNG when transparent, JPEG when
/// HEIC cannot be written), at most `maximumByteCount`.
///
/// The output is encoded from pixels alone, never from the source's
/// properties, so GPS, EXIF, TIFF maker fields, IPTC and the file name are
/// gone. ImageIO and Core Graphics only, the same code on every platform.
public struct ImageProcessor: Hashable, Sendable {
    public static let standard = ImageProcessor()

    public var maximumPixelSize: Int
    public var maximumByteCount: Int
    /// Larger files are refused before decoding, so a huge file is not read
    /// into an image at all.
    public var maximumSourceByteCount: Int
    public var quality: Double

    public init(
        maximumPixelSize: Int = 2_048,
        maximumByteCount: Int = 5 * 1_024 * 1_024,
        maximumSourceByteCount: Int = 200 * 1_024 * 1_024,
        quality: Double = 0.8
    ) {
        self.maximumPixelSize = maximumPixelSize
        self.maximumByteCount = maximumByteCount
        self.maximumSourceByteCount = maximumSourceByteCount
        self.quality = quality
    }

    /// Off the caller's actor: decoding a 48-megapixel photo takes a while.
    @concurrent
    public func process(_ data: Data) async throws(ImageProcessingError) -> ProcessedImage {
        try processSynchronously(data)
    }

    public func processSynchronously(_ data: Data) throws(ImageProcessingError) -> ProcessedImage {
        guard data.count <= maximumSourceByteCount else { throw .tooLarge }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let longSide = Self.longSide(of: source)
        else { throw .unreadable }

        // The thumbnail call decodes at a reduced size (subsampling where the
        // codec can), applies the EXIF orientation, and takes the first frame
        // of an animated file.
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumPixelSize, longSide),
        ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
              let (pixels, isTransparent) = Self.redraw(decoded)
        else { throw .unreadable }

        let encoded: (Data, UTType)? = if isTransparent {
            Self.encode(pixels, as: .png, quality: nil).map { ($0, .png) }
        } else {
            Self.encode(pixels, as: .heic, quality: quality).map { ($0, .heic) }
                ?? Self.encode(pixels, as: .jpeg, quality: quality).map { ($0, .jpeg) }
        }
        guard let (output, type) = encoded else { throw .unreadable }
        guard output.count <= maximumByteCount else { throw .tooLarge }
        return ProcessedImage(data: output, uniformType: type.identifier, pixelWidth: pixels.width, pixelHeight: pixels.height)
    }

    private static func longSide(of source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return max(width, height)
    }

    /// Draws the decoded image into a plain 8-bit RGBA bitmap, so every
    /// source (CMYK, grey, 16-bit, indexed) encodes the same way, and tells
    /// whether any pixel is not opaque: a PNG with an alpha channel but no
    /// transparent pixel (most screenshots) still becomes a small HEIC.
    private static func redraw(_ image: CGImage) -> (CGImage, Bool)? {
        let width = image.width
        let height = image.height
        // Keep a wide-gamut RGB space (Display P3 photos); anything else is drawn into sRGB.
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? sRGB
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: bitmapInfo)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.makeImage() else { return nil }

        let hasAlphaChannel = switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
        guard hasAlphaChannel, let base = context.data else { return (pixels, false) }
        let rowBytes = context.bytesPerRow
        let buffer = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let row = buffer + y * rowBytes
            for x in 0..<width where row[x * 4 + 3] != 255 {
                return (pixels, true)
            }
        }
        return (pixels, false)
    }

    /// Nil when this OS cannot write the type (HEIC on some Simulators).
    /// Only the compression quality goes in: no source properties are copied.
    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else { return nil }
        return output as Data
    }
}
