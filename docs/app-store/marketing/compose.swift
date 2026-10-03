import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let shots = root.appendingPathComponent("docs/app-store/screenshots")
let marketing = root.appendingPathComponent("docs/app-store/marketing")
let captions = try JSONDecoder().decode([String: [String: String]].self,
    from: Data(contentsOf: shots.appendingPathComponent("captions.json")))
let portrait = marketing.appendingPathComponent("artwork-portrait.png")
let landscape = marketing.appendingPathComponent("artwork-landscape.png")

func load(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot load \(url.path)")
    }
    return image
}

func canvas(_ width: Int, _ height: Int) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func save(_ context: CGContext, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL,
        UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot save \(url.path)")
}

func fillArtwork(_ context: CGContext, _ image: CGImage, _ size: CGSize, flipped: Bool) {
    context.saveGState()
    if flipped {
        context.translateBy(x: size.width, y: 0)
        context.scaleBy(x: -1, y: 1)
    }
    let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
    let width = CGFloat(image.width) * scale
    let height = CGFloat(image.height) * scale
    context.draw(image, in: CGRect(x: (size.width-width)/2, y: (size.height-height)/2,
        width: width, height: height))
    context.restoreGState()
}

func framedScreenshot(_ context: CGContext, _ image: CGImage, _ rect: CGRect, radius: CGFloat) {
    let bezel = max(12, rect.width * 0.018)
    let outer = rect.insetBy(dx: -bezel, dy: -bezel)
    let outerPath = CGPath(roundedRect: outer, cornerWidth: radius + bezel,
        cornerHeight: radius + bezel, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 60,
        color: CGColor(red: 0.07, green: 0.17, blue: 0.34, alpha: 0.23))
    context.addPath(outerPath)
    context.setFillColor(CGColor(red: 0.12, green: 0.19, blue: 0.31, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(outerPath)
    context.setStrokeColor(CGColor(red: 0.58, green: 0.75, blue: 0.94, alpha: 1))
    context.setLineWidth(2)
    context.strokePath()
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
        cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(image, in: rect)
    context.restoreGState()
}

func caption(_ context: CGContext, _ text: String, _ rect: CGRect, fontSize: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    let font = CTFontCreateWithName("SpaceGrotesk-SemiBold" as CFString, fontSize, nil)
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.33, alpha: 1),
        .paragraphStyle: paragraph
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(rect: rect, transform: nil)
    CTFrameDraw(CTFramesetterCreateFrame(framesetter,
        CFRangeMake(0, attributed.length), path, nil), context)
}

let fontURL = root.appendingPathComponent("MindMapAI/Resources/Fonts/SpaceGrotesk-SemiBold.ttf")
_ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let portraitImage = load(portrait)
let landscapeImage = load(landscape)

for platform in ["iphone", "ipad"] {
    let size = platform == "iphone" ? CGSize(width: 1320, height: 2868) : CGSize(width: 2064, height: 2752)
    for language in ["en", "vi"] {
        let sourceFolder = shots.appendingPathComponent("raw/\(platform)/\(language)")
        for (index, name) in ["01-canvas", "02-ai-suggestions", "03-outline", "04-ask-map", "05-privacy"].enumerated() {
            let screenshot = load(sourceFolder.appendingPathComponent("\(name).png"))
            let context = canvas(Int(size.width), Int(size.height))
            fillArtwork(context, portraitImage, size, flipped: index.isMultiple(of: 2) == false)
            let imageWidth: CGFloat = platform == "iphone" ? 870 : 1510
            let imageHeight = imageWidth * CGFloat(screenshot.height) / CGFloat(screenshot.width)
            let rect = CGRect(x: (size.width-imageWidth)/2,
                y: platform == "iphone" ? 285 : 200,
                width: imageWidth, height: imageHeight)
            framedScreenshot(context, screenshot, rect, radius: platform == "iphone" ? 60 : 45)
            caption(context, captions[language]![name]!,
                CGRect(x: 95, y: size.height - (platform == "iphone" ? 235 : 220),
                    width: size.width-190, height: 150),
                fontSize: platform == "iphone" ? 77 : 100)
            save(context, shots.appendingPathComponent("final/\(platform)/\(language)/\(name).png"))
        }
    }
}

for language in ["en", "vi"] {
    let folder = shots.appendingPathComponent("raw/mac/\(language)")
    for (index, name) in ["01-canvas", "02-ai-suggestions", "03-outline", "04-ask-map", "05-privacy"].enumerated() {
        let source = folder.appendingPathComponent("\(name).png")
        guard FileManager.default.fileExists(atPath: source.path) else { continue }
        let screenshot = load(source)
        let size = CGSize(width: 2880, height: 1800)
        let context = canvas(Int(size.width), Int(size.height))
        fillArtwork(context, landscapeImage, size, flipped: !index.isMultiple(of: 2))
        let imageWidth: CGFloat = 2240
        let imageHeight = imageWidth * CGFloat(screenshot.height) / CGFloat(screenshot.width)
        precondition(imageHeight < 1450, "Mac capture is too tall for this frame")
        framedScreenshot(context, screenshot,
            CGRect(x: (size.width-imageWidth)/2, y: 100,
                width: imageWidth, height: imageHeight), radius: 28)
        caption(context, captions[language]![name]!,
            CGRect(x: 180, y: 1570, width: size.width-360, height: 160), fontSize: 112)
        save(context, shots.appendingPathComponent("final/mac/\(language)/\(name).png"))
    }
}

let heroScreenshot = load(shots.appendingPathComponent("raw/ipad/en/01-canvas.png"))
for (name, width, height) in [("hero-2400x1260", 2400, 1260), ("open-graph-1200x630", 1200, 630)] {
    let size = CGSize(width: width, height: height)
    let context = canvas(width, height)
    fillArtwork(context, landscapeImage, size, flipped: false)
    let imageHeight = size.height * 0.82
    let imageWidth = imageHeight * CGFloat(heroScreenshot.width) / CGFloat(heroScreenshot.height)
    framedScreenshot(context, heroScreenshot,
        CGRect(x: size.width * 0.68 - imageWidth/2, y: size.height * 0.09,
            width: imageWidth, height: imageHeight), radius: size.height * 0.018)
    save(context, marketing.appendingPathComponent("\(name).png"))
}
