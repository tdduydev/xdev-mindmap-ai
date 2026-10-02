import CoreGraphics
import Foundation
import ImageIO
import MindMapDomain
import SwiftUI

/// The metadata fixes the frame before bytes arrive, keeping the layout still.
struct TopicImageView: View {
    let image: MindImage
    let level: Int
    let spec: TopicTextSpec
    let data: Data?

    private var size: CGSize {
        let dimensions = image.displaySize(
            maximumWidth: Double(spec.maximumWidth - 2 * spec.horizontalPadding),
            maximumAspect: CanvasMetrics.imageMaxAspect
        )
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    var body: some View {
        Group {
            if let data, let preview = TopicThumbnailCache.preview(for: image.id, data: data, size: size) {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Palette.canvasBackground)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: CanvasMetrics.imageCornerRadius))
        .accessibilityHidden(true)
    }
}

@MainActor
private enum TopicThumbnailCache {
    private final class Box: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func preview(for id: ImageID, data: Data, size: CGSize) -> CGImage? {
        let pixels = Int(max(size.width, size.height) * 2)
        let key = "\(id)-\(pixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached.image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { return nil }
        cache.setObject(Box(preview), forKey: key, cost: preview.bytesPerRow * preview.height)
        return preview
    }
}

struct LoadedTopicImage: View {
    let image: MindImage
    let level: Int
    let spec: TopicTextSpec
    let session: EditorSession
    @State private var data: Data?

    var body: some View {
        TopicImageView(image: image, level: level, spec: spec, data: data)
            .task(id: image.id) {
                data = nil
                data = await session.imageBytes(for: image)
            }
    }
}

struct TopicImageAccessibility: ViewModifier {
    let image: MindImage?

    func body(content: Content) -> some View {
        if let image {
            content.accessibilityCustomContent(LocalizedStringKey("Image"), image.altText ?? String(localized: "No description"))
        } else {
            content
        }
    }
}
