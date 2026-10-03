import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage: swift ...swift raw.png output.png width height caption [background.png]
guard CommandLine.arguments.count == 6 || CommandLine.arguments.count == 7,
      let width = Int(CommandLine.arguments[3]), let height = Int(CommandLine.arguments[4]),
      width > 0, height > 0 else {
    fputs("usage: compose-app-store-screenshots.swift raw output width height caption [background]\n", stderr)
    exit(64)
}
let args = CommandLine.arguments
func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}
guard let screenshot = load(args[1]),
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fputs("cannot read screenshot or create canvas\n", stderr)
    exit(1)
}
let size = CGSize(width: width, height: height)
let canvas = CGRect(origin: .zero, size: size)
if args.count == 7, let background = load(args[6]) {
    // MM-74 can supply finished artwork without changing capture or captions.
    context.draw(background, in: canvas)
} else {
    context.setFillColor(CGColor(red: 0.055, green: 0.13, blue: 0.26, alpha: 1))
    context.fill(canvas)
    let colors = [CGColor(red: 0.12, green: 0.55, blue: 0.96, alpha: 0.7),
                  CGColor(red: 0.055, green: 0.13, blue: 0.26, alpha: 0)] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: width / 2, y: height),
                                   startRadius: 0, endCenter: CGPoint(x: width / 2, y: height),
                                   endRadius: CGFloat(max(width, height)), options: [.drawsAfterEndLocation])
    }
}
let margin = CGFloat(width) * 0.055
let headlineHeight = CGFloat(height) * (width > height ? 0.21 : 0.19)
let imageRect = CGRect(x: margin, y: margin, width: CGFloat(width) - margin * 2,
                       height: CGFloat(height) - headlineHeight - margin * 1.7)
context.saveGState()
let clip = CGPath(roundedRect: imageRect, cornerWidth: margin * 0.33,
                  cornerHeight: margin * 0.33, transform: nil)
context.addPath(clip)
context.clip()
context.setFillColor(CGColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1))
context.fill(imageRect)
let scale = max(imageRect.width / CGFloat(screenshot.width), imageRect.height / CGFloat(screenshot.height))
let drawSize = CGSize(width: CGFloat(screenshot.width) * scale, height: CGFloat(screenshot.height) * scale)
context.draw(screenshot, in: CGRect(x: imageRect.midX - drawSize.width / 2,
                                    y: imageRect.midY - drawSize.height / 2,
                                    width: drawSize.width, height: drawSize.height))
context.restoreGState()

let fontSize = CGFloat(width) * (width > height ? 0.033 : 0.062)
let font = CTFontCreateWithName("SFProDisplay-Bold" as CFString, fontSize, nil)
let style = NSMutableParagraphStyle()
style.alignment = .center
style.lineBreakMode = .byWordWrapping
let text = NSAttributedString(string: args[5], attributes: [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: style,
])
let framesetter = CTFramesetterCreateWithAttributedString(text)
let textRect = CGRect(x: margin, y: CGFloat(height) - headlineHeight + margin * 0.18,
                      width: CGFloat(width) - margin * 2, height: headlineHeight - margin * 0.4)
context.addPath(CGPath(rect: textRect, transform: nil))
CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRangeMake(0, text.length),
                                    CGPath(rect: textRect, transform: nil), nil), context)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
    fputs("cannot encode output\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
