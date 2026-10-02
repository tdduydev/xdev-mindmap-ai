// Builds MindMapAI/Resources/Assets.xcassets/AppIcon.appiconset from one
// full-bleed 1024 x 1024 artwork PNG.
//
// iOS and iPadOS get the artwork as is, without an alpha channel (App Store
// Connect rejects transparent iOS icons; the system rounds the corners).
// macOS draws no mask of its own, so the Mac sizes follow Apple's icon grid:
// the artwork sits in an 824 pt rounded square centred on a transparent
// 1024 pt canvas.
//
// Usage: swift scripts/make-app-icon.swift docs/brand/mindmap-ai-icon-v1.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <artwork-1024.png>\n".utf8))
    exit(1)
}

let iconSet = URL(fileURLWithPath: "MindMapAI/Resources/Assets.xcassets/AppIcon.appiconset")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func writePNG(pixels: Int, opaque: Bool, to name: String, draw: (CGContext, CGFloat) -> Void) {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: alpha.rawValue
    ) else { fatalError("Could not create a \(pixels) px context") }
    context.interpolationQuality = .high
    draw(context, CGFloat(pixels))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              iconSet.appending(path: name) as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { fatalError("Could not encode \(name)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
}

struct Entry: Encodable {
    let filename: String
    let idiom: String
    let platform: String?
    let scale: String?
    let size: String
}

var images: [Entry] = []

writePNG(pixels: 1024, opaque: true, to: "icon-ios-1024.png") { context, size in
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
}
images.append(Entry(filename: "icon-ios-1024.png", idiom: "universal", platform: "ios", scale: nil, size: "1024x1024"))

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon-mac-\(points)@\(scale)x.png"
        writePNG(pixels: points * scale, opaque: false, to: name) { context, size in
            let unit = size / 1024
            let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
            let shape = CGPath(roundedRect: tile, cornerWidth: 185.4 * unit, cornerHeight: 185.4 * unit, transform: nil)
            // The grid's soft drop shadow, so the icon sits on the Dock like Apple's own.
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 20 * unit,
                              color: CGColor(gray: 0, alpha: 0.18))
            context.addPath(shape)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
            context.restoreGState()
            context.addPath(shape)
            context.clip()
            context.draw(artwork, in: tile)
        }
        images.append(Entry(filename: name, idiom: "mac", platform: nil, scale: "\(scale)x", size: "\(points)x\(points)"))
    }
}

struct Catalog: Encodable {
    struct Info: Encodable {
        let author = "xcode"
        let version = 1
    }
    let images: [Entry]
    let info = Info()
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(Catalog(images: images)).write(to: iconSet.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")
