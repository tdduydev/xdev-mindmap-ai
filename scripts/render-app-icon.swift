// Renders MindMapAI/AppIcon.icon in every appearance, the way the system
// draws it, and tiles the results into one PNG, so the icon can be reviewed
// without opening Icon Composer.
//
// Rows: iOS, macOS. Columns: Default, Dark, Clear Light, Clear Dark,
// Tinted Light, Tinted Dark. Tinted uses a blue tint at 75 % strength; the
// real tint is the user's choice.
//
// Usage: swift scripts/render-app-icon.swift [output.png]
// (default docs/brand/mindmap-ai-app-icon-appearances.png)
import AppKit

let icon = "MindMapAI/AppIcon.icon"
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/brand/mindmap-ai-app-icon-appearances.png"
// ictool ships inside Icon Composer, not on xcrun's path; the copy in
// usr/bin has a different command line and cannot export images.
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let platforms = ["iOS", "macOS"]
let renditions = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]
let cell = 256, padding = 16

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("render-app-icon-\(getpid())")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

func render(platform: String, rendition: String) -> NSImage {
    let file = scratch.appendingPathComponent("\(platform)-\(rendition).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ictool)
    process.arguments = [
        icon, "--export-image", "--output-file", file.path,
        "--platform", platform, "--rendition", rendition,
        "--width", "512", "--height", "512", "--scale", "1",
        "--tint-color", "0.6", "--tint-strength", "0.75",
    ]
    process.standardOutput = FileHandle.nullDevice
    try! process.run()
    process.waitUntilExit()
    // ictool exits 0 and prints "{}" even when it writes nothing, so check the file.
    guard process.terminationStatus == 0, let image = NSImage(contentsOf: file) else {
        FileHandle.standardError.write(Data("error: ictool rendered no \(platform) \(rendition) image\n".utf8))
        exit(1)
    }
    return image
}

let width = renditions.count * (cell + padding) + padding
let height = platforms.count * (cell + padding) + padding
let sheet = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
// Mid grey, so both the light and the dark tiles and the clear glass show their edges.
NSColor(white: 0.5, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
for (row, platform) in platforms.enumerated() {
    for (column, rendition) in renditions.enumerated() {
        let frame = NSRect(
            x: padding + column * (cell + padding),
            y: height - (row + 1) * (cell + padding),
            width: cell, height: cell)
        render(platform: platform, rendition: rendition).draw(in: frame)
    }
}
NSGraphicsContext.current = nil
try sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
