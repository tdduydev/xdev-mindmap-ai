import CoreGraphics
import Foundation
import ImageIO
import MindMapDomain
@testable import MindMapImages
import Testing
import UniformTypeIdentifiers

@Suite("Image processing")
struct ImageProcessorTests {
    /// A gradient, so encoders cannot shrink it to nothing; `alpha` below 1
    /// makes every pixel see-through.
    static func picture(width: Int, height: Int, alpha: CGFloat = 1) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for x in stride(from: 0, to: width, by: max(width / 32, 1)) {
            let shade = CGFloat(x) / CGFloat(width)
            context.setFillColor(CGColor(srgbRed: shade, green: 1 - shade, blue: 0.5, alpha: alpha))
            context.fill(CGRect(x: x, y: 0, width: max(width / 32, 1), height: height))
        }
        // With alpha 1 it is opaque but still has an alpha channel, like most screenshots.
        return context.makeImage()!
    }

    static func file(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// A camera-like JPEG: GPS, maker, capture date and a 90° orientation.
    static func cameraPhoto(width: Int, height: Int) -> Data {
        file(picture(width: width, height: height), type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 21.0285, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 105.8542, kCGImagePropertyGPSLongitudeRef: "E",
            ] as CFDictionary,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Camera Maker", kCGImagePropertyTIFFModel: "Model 9"] as CFDictionary,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:02 10:00:00", kCGImagePropertyExifUserComment: "secret place"] as CFDictionary,
        ])
    }

    static func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    @Test func locationAndCameraMetadataAreGone() throws {
        let photo = Self.cameraPhoto(width: 400, height: 300)
        #expect(Self.properties(of: photo)[kCGImagePropertyGPSDictionary] != nil)

        let processed = try ImageProcessor.standard.processSynchronously(photo)
        let properties = Self.properties(of: processed.data)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifUserComment] == nil)
        let bytes = processed.data
        #expect(bytes.range(of: Data("secret place".utf8)) == nil)
        #expect(bytes.range(of: Data("Camera Maker".utf8)) == nil)
    }

    /// Orientation 6 stores the picture on its side: the result is upright,
    /// so it needs no orientation tag.
    @Test func orientationIsAppliedToThePixels() throws {
        let processed = try ImageProcessor.standard.processSynchronously(Self.cameraPhoto(width: 400, height: 300))
        #expect(processed.pixelWidth == 300)
        #expect(processed.pixelHeight == 400)
        let orientation = Self.properties(of: processed.data)[kCGImagePropertyOrientation] as? Int
        #expect(orientation == nil || orientation == 1)
    }

    @Test func aLargeImageIsScaledToTheLongestSide() throws {
        let photo = Self.file(Self.picture(width: 4_000, height: 3_000), type: .jpeg)
        let processed = try ImageProcessor.standard.processSynchronously(photo)
        #expect(processed.pixelWidth == 2_048)
        #expect(processed.pixelHeight == 1_536)
        #expect(processed.byteCount == processed.data.count)
        #expect(processed.byteCount <= ImageProcessor.standard.maximumByteCount)
        let properties = Self.properties(of: processed.data)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 2_048)
    }

    @Test func aSmallImageKeepsItsSize() throws {
        let processed = try ImageProcessor.standard.processSynchronously(Self.file(Self.picture(width: 120, height: 80), type: .png))
        #expect(processed.pixelWidth == 120)
        #expect(processed.pixelHeight == 80)
    }

    /// An opaque PNG with an alpha channel is a photo or screenshot: HEIC
    /// (JPEG where HEIC cannot be written). A see-through one stays PNG.
    @Test func onlyTransparentImagesStayPNG() throws {
        let opaque = try ImageProcessor.standard.processSynchronously(Self.file(Self.picture(width: 64, height: 64), type: .png))
        #expect([UTType.heic.identifier, UTType.jpeg.identifier].contains(opaque.uniformType))

        let clear = try ImageProcessor.standard.processSynchronously(Self.file(Self.picture(width: 64, height: 64, alpha: 0.5), type: .png))
        #expect(clear.uniformType == UTType.png.identifier)
    }

    @Test func theTypeMatchesTheBytes() throws {
        let processed = try ImageProcessor.standard.processSynchronously(Self.cameraPhoto(width: 200, height: 100))
        let source = try #require(CGImageSourceCreateWithData(processed.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == processed.uniformType)
    }

    @Test func notAnImageIsRefused() {
        #expect(throws: ImageProcessingError.unreadable) {
            try ImageProcessor.standard.processSynchronously(Data("plain text, not a picture".utf8))
        }
        #expect(throws: ImageProcessingError.unreadable) {
            try ImageProcessor.standard.processSynchronously(Data())
        }
    }

    @Test func overTheLimitIsRefused() {
        let photo = Self.file(Self.picture(width: 400, height: 300), type: .jpeg)
        #expect(throws: ImageProcessingError.tooLarge) {
            try ImageProcessor(maximumByteCount: 100).processSynchronously(photo)
        }
        #expect(throws: ImageProcessingError.tooLarge) {
            try ImageProcessor(maximumSourceByteCount: 100).processSynchronously(photo)
        }
    }

    @Test func theRecordCarriesTheBytesAndSizes() async throws {
        let processed = try await ImageProcessor.standard.process(Self.file(Self.picture(width: 300, height: 200), type: .jpeg))
        let mapID = MapID()
        let nodeID = NodeID()
        let image = processed.image(mapID: mapID, nodeID: nodeID, altText: "  Whiteboard  ")
        #expect(image.data == processed.data)
        #expect(image.pixelWidth == 300)
        #expect(image.pixelHeight == 200)
        #expect(image.byteCount == processed.data.count)
        #expect(image.uniformType == processed.uniformType)
        #expect(image.altText == "Whiteboard")
        #expect(image.nodeID == nodeID)
    }
}
