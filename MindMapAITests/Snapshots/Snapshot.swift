#if os(macOS)
import AppKit
import Foundation
@testable import MindMapAI
import SwiftUI
import Testing

/// Snapshot testing without a dependency (ADR 0001): a view is drawn in an
/// off-screen window, compared pixel by pixel with a reference PNG in
/// `MindMapAITests/Snapshots/References`, and passes when few enough pixels
/// differ. Run with `scripts/snapshot-tests.sh` (docs/testing.md, Snapshot tests).
enum Snapshot {
    /// How the run was asked for: `MINDMAP_SNAPSHOTS=compare` or `record`.
    /// Unset (as in `scripts/ci.sh`) the suites are skipped.
    nonisolated enum Mode: String {
        case compare, record
    }

    nonisolated static let mode = ProcessInfo.processInfo.environment["MINDMAP_SNAPSHOTS"].flatMap(Mode.init(rawValue:))

    /// A channel may move this much before its pixel counts as different:
    /// enough for antialiasing that shifts between runs, far below a colour
    /// change of the design system.
    static let channelTolerance = 24
    /// The share of pixels that may differ: a few glyph edges, not a moved view.
    static let pixelTolerance = 0.002
    /// A pixel only counts when no pixel this close in the other image matches
    /// it, both ways round: text antialiasing on the shared Mac mini moves
    /// glyph edges by a pixel between OS updates (MM-81), which failed every
    /// scene with text, while a missing line or a changed colour still has no
    /// match nearby.
    static let neighbourRadius = 1

    /// The language of this run (`-testLanguage`), in each reference's name.
    static var language: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Compares `image` with the reference named `name`, or records it as the new reference.
    static func verify(
        _ image: CGImage, named name: String,
        pixelTolerance: Double = Snapshot.pixelTolerance,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let fileName = "\(name).\(language)"
        let actual = try Bitmap(image)
        let png = try actual.png()
        switch mode {
        case .record, nil:
            // The script copies `reference.` attachments into the repo.
            Attachment.record(png, named: "reference.\(fileName).png", sourceLocation: sourceLocation)
        case .compare:
            guard let url = referenceBundle.url(forResource: fileName, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let reference = NSBitmapImageRep(data: data)?.cgImage else {
                Attachment.record(png, named: "actual.\(fileName).png", sourceLocation: sourceLocation)
                Issue.record("No reference \(fileName).png; record one with scripts/snapshot-tests.sh --record", sourceLocation: sourceLocation)
                return
            }
            let expected = try Bitmap(reference)
            let comparison = actual.compared(with: expected, pixelTolerance: pixelTolerance)
            if comparison.differs {
                Attachment.record(png, named: "actual.\(fileName).png", sourceLocation: sourceLocation)
                if let diff = comparison.diff {
                    Attachment.record(try diff.png(), named: "diff.\(fileName).png", sourceLocation: sourceLocation)
                }
                Issue.record("\(fileName): \(comparison.summary)", sourceLocation: sourceLocation)
            }
        }
    }

    /// References are resources of the test bundle: the hosted tests run in
    /// the app sandbox, which cannot read the repo.
    private static let referenceBundle = Bundle(for: BundleToken.self)
    private final class BundleToken {}
}

/// The appearances each scene is drawn in (NFR-A11Y: Increase Contrast).
enum SnapshotAppearance: String, CaseIterable {
    case light, dark, increasedContrast

    var appKit: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .increasedContrast: NSAppearance(named: .accessibilityHighContrastAqua)
        }
    }

    /// SwiftUI reads contrast from its own environment; AppKit's high-contrast
    /// appearance alone leaves asset colours on their normal variant
    /// (DesignSystemAssetTests).
    var contrast: ColorSchemeContrast {
        self == .increasedContrast ? .increased : .standard
    }
}

/// Draws SwiftUI views the way a Mac window shows them, with no screen: the
/// window sits off every display and AppKit draws its frame view into a bitmap,
/// which works while the Mac is locked (XCUITest does not). ImageRenderer
/// cannot stand in: it draws grouped Forms and AppKit controls blank.
@MainActor
enum SnapshotWindow {
    /// Opens `view` in a window of `size` (content, without the title bar).
    static func open<Content: View>(
        _ view: Content,
        size: CGSize,
        title: String = "",
        appearance: SnapshotAppearance,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    ) -> NSWindow {
        let hosting = NSHostingView(rootView: view
            .environment(\._colorSchemeContrast, appearance.contrast)
            // The test host is never the active app; without this SwiftUI
            // draws every control as in a background window.
            .environment(\.controlActiveState, .key))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
            styleMask: styleMask, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        window.appearance = appearance.appKit
        window.contentView = hosting
        window.orderFrontRegardless()
        return window
    }

    /// Waits for `condition`, then a moment more for SwiftUI's layout and AppKit's drawing.
    static func settle(until condition: () -> Bool = { true }) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), "the scene never got ready")
        try await Task.sleep(for: .milliseconds(600))
    }

    /// The window once three captures a moment apart are the same: AppKit
    /// updates the toolbar and SwiftUI the environment a few frames after
    /// the content, so a single capture now and then catches the window
    /// halfway. Two were not enough: the first map window of a run sometimes
    /// held a toolbar item blank for two captures (MM-81).
    static func stableCapture(_ window: NSWindow) async throws -> CGImage {
        var previous = try capture(window)
        var unchanged = 0
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            let next = try capture(window)
            if try Bitmap(next).pixels == Bitmap(previous).pixels {
                unchanged += 1
                if unchanged == 2 { return next }
            } else {
                unchanged = 0
            }
            previous = next
        }
        Issue.record("the window never stopped changing")
        return previous
    }

    /// The whole window at 1× (the frame view draws the title bar and toolbar
    /// too). 1× whatever the screen, so a run on a Retina display, a plain
    /// one or none draws the same pixels, and references stay small.
    static func capture(_ window: NSWindow) throws -> CGImage {
        let view = try #require(window.contentView?.superview)
        let bounds = view.bounds
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return try #require(rep.cgImage)
    }
}

/// RGBA pixels in sRGB, so two images compare byte for byte whatever the
/// colour space they were drawn in.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    struct Comparison {
        let differs: Bool
        let summary: String
        /// The reference faded, with differing pixels in red; nil when the sizes differ.
        let diff: Bitmap?
    }

    func compared(with reference: Bitmap, pixelTolerance: Double = Snapshot.pixelTolerance) -> Comparison {
        guard width == reference.width, height == reference.height else {
            return Comparison(differs: true, summary: "size \(width)×\(height), reference \(reference.width)×\(reference.height)", diff: nil)
        }
        var diff = reference.pixels
        var changed = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            var delta = 0
            for channel in 0..<4 {
                delta = max(delta, abs(Int(pixels[offset + channel]) - Int(reference.pixels[offset + channel])))
            }
            if delta > Snapshot.channelTolerance, !matchesNearby(offset / 4, in: reference) {
                changed += 1
                diff.replaceSubrange(offset..<offset + 4, with: [255, 0, 0, 255])
            } else {
                for channel in 0..<3 { diff[offset + channel] = 255 - (255 - diff[offset + channel]) / 4 }
                diff[offset + 3] = 255
            }
        }
        let share = Double(changed) / Double(width * height)
        let percent = (share * 100).formatted(.number.precision(.fractionLength(3)))
        return Comparison(
            differs: share > pixelTolerance,
            summary: "\(changed) pixels differ (\(percent)%)",
            diff: Bitmap(width: width, height: height, pixels: diff)
        )
    }

    /// Whether the pixel at `index` has a match within `Snapshot.neighbourRadius`
    /// in `reference`, and its counterpart in `reference` one in this image.
    private func matchesNearby(_ index: Int, in reference: Bitmap) -> Bool {
        reference.hasPixel(near: index, matching: self) && hasPixel(near: index, matching: reference)
    }

    /// Whether a pixel around `index` is within `Snapshot.channelTolerance` of
    /// `other`'s pixel at `index`.
    private func hasPixel(near index: Int, matching other: Bitmap) -> Bool {
        let x = index % width, y = index / width
        let radius = Snapshot.neighbourRadius
        for nearY in max(0, y - radius)...min(height - 1, y + radius) {
            for nearX in max(0, x - radius)...min(width - 1, x + radius) {
                let near = (nearY * width + nearX) * 4
                if (0..<4).allSatisfy({ abs(Int(pixels[near + $0]) - Int(other.pixels[index * 4 + $0])) <= Snapshot.channelTolerance }) {
                    return true
                }
            }
        }
        return false
    }

    func png() throws -> Data {
        var pixels = pixels
        let image = try pixels.withUnsafeMutableBytes { buffer -> CGImage in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(context.makeImage())
        }
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
#endif
