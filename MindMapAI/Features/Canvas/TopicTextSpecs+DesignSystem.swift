import CoreGraphics
import Foundation

extension TopicTextSpecs {
    /// Reads the content fonts and canvas boxes from the design system.
    ///
    /// - Parameter scaledSize: The point size of a content style at the current
    ///   Dynamic Type setting. The view supplies it, because only iOS and
    ///   iPadOS scale; macOS draws the design size.
    static func make(scaledSize: (ContentStyle) -> CGFloat) -> TopicTextSpecs {
        let levels = (0...3).map { level in
            let style = Typography.Content.topic(level: level)
            let box = CanvasMetrics.box(level: level)
            let size = scaledSize(style)
            // The design's line height grows with the font, as Dynamic Type does for system styles.
            let lineHeight = style.lineHeight * size / style.size
            let natural = TopicMeasurer.naturalLineHeight(postScriptName: style.face.postScriptName, size: size)
            return TopicTextSpec(
                postScriptName: style.face.postScriptName,
                pointSize: size,
                lineSpacing: max(0, lineHeight - natural),
                horizontalPadding: box.horizontalPadding,
                verticalPadding: box.verticalPadding,
                minimumWidth: box.minimumWidth,
                maximumWidth: box.maximumWidth,
                minimumHeight: CanvasMetrics.minimumPointerHeight
            )
        }
        return TopicTextSpecs(levels: levels, placeholder: String(localized: "Untitled Topic"))
    }

    /// Design sizes, without Dynamic Type: the Mac, and tests.
    static func designSizes() -> TopicTextSpecs {
        make { $0.size }
    }
}
