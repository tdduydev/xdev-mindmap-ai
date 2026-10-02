#if os(macOS)
import AppKit
import Foundation
@testable import MindMapAI
import StoreKit
import StoreKitTest
import SwiftUI
import Testing

/// Renders the real paywall for the App Store Connect review screenshot of
/// MindMap AI Pro. Off by default, so `scripts/ci.sh` skips it; run it with
/// `scripts/render-iap-screenshot.sh`, which turns it on and saves the PNG.
@Suite("IAP review screenshot", .serialized, .tags(.reviewScreenshot))
struct IAPReviewScreenshotTests {
    /// 2880×1800 pixels: one of the four macOS sizes App Store Connect accepts
    /// for screenshots, which the IAP review screenshot must meet (App Store
    /// Connect Help ▸ Screenshot specifications ▸ macOS; In-App Purchase information).
    static let canvasSize = CGSize(width: 1440, height: 900)
    static let scale: CGFloat = 2

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MINDMAP_RENDER_IAP_SCREENSHOT"] == "1"))
    func rendersThePaywall() async throws {
        let url = try #require(
            Bundle.allBundles.lazy.compactMap { $0.url(forResource: "MindMapAI", withExtension: "storekit") }.first
        )
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()

        // The product the paywall shows comes from MindMapAI.storekit, not from a stub.
        let store = ProEntitlement(syncWithAppStore: {})
        await store.loadProduct()
        let product = try #require(store.product)
        #expect(product.displayPrice == "$14.99")
        #expect(!store.isUnlocked)

        let window = try await Self.paywallWindow(store: store)
        defer { window.close() }
        let picture = try Self.screenshot(of: try Self.capture(window))

        let png = try #require(NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]))
        Attachment.record(png, named: "iap-pro.png")
    }

    /// ImageRenderer draws nothing for PaywallView on macOS: the grouped Form is
    /// an NSScrollView and NSTableView inside, and buttons are AppKit controls.
    /// So the paywall goes into a real window and AppKit draws the window itself.
    private static func paywallWindow(store: ProEntitlement) async throws -> NSWindow {
        let hosting = NSHostingView(rootView: PaywallView()
            .environment(store)
            // The test host is never the active app, so SwiftUI would draw the
            // prominent button gray, as in a window in the background. AppKit
            // still draws the title bar inactive (gray traffic lights).
            .environment(\.controlActiveState, .key))
        let window = NSWindow(
            // Off every screen; the window only needs to exist to be drawn.
            contentRect: CGRect(x: -10_000, y: -10_000, width: Metrics.paywallWidth, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()

        // Let SwiftUI lay out the Form, then fit the window to it so there is
        // no empty space under the footer.
        try await Task.sleep(for: .milliseconds(500))
        window.setContentSize(CGSize(width: Metrics.paywallWidth, height: ceil(hosting.fittingSize.height)))
        try await Task.sleep(for: .milliseconds(500))
        return window
    }

    private static func capture(_ window: NSWindow) throws -> CGImage {
        // The frame view is the content view's superview: it draws the title bar too.
        let frameView = try #require(window.contentView?.superview)
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return try #require(rep.cgImage)
    }

    /// The window centered on a plain light gray backdrop with a soft shadow,
    /// opaque, because App Store Connect refuses screenshots with alpha.
    private static func screenshot(of window: CGImage) throws -> CGImage {
        let width = Int(canvasSize.width * scale)
        let height = Int(canvasSize.height * scale)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let frame = CGRect(
            x: (CGFloat(width) - CGFloat(window.width)) / 2,
            y: (CGFloat(height) - CGFloat(window.height)) / 2,
            width: CGFloat(window.width), height: CGFloat(window.height)
        ).integral
        let outline = CGPath(roundedRect: frame, cornerWidth: 16 * scale, cornerHeight: 16 * scale, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 40 * scale, color: CGColor(gray: 0, alpha: 0.25))
        context.addPath(outline)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.draw(window, in: frame)
        context.restoreGState()

        context.addPath(outline)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.15))
        context.setLineWidth(scale)
        context.strokePath()

        return try #require(context.makeImage())
    }
}

extension Tag {
    @Tag static var reviewScreenshot: Self
}
#endif
