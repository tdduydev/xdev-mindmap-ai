import CoreGraphics
import Foundation

extension TopicTextSpecs {
    /// Reads the content fonts and canvas boxes from the design system.
    ///
    /// - Parameter scaledSize: The point size of a content style at the current
    ///   Dynamic Type setting. The view supplies it, because only iOS and
    ///   iPadOS scale; macOS draws the design size.
    ///   - showsColorShapes: Differentiate Without Color, which adds the
    ///     colour's shape before a coloured topic's title (FR-ORG-02).
    static func make(showsColorShapes: Bool = false, scaledSize: (ContentStyle) -> CGFloat) -> TopicTextSpecs {
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
        let badge = Typography.Content.badge
        let chipSize = scaledSize(badge)
        let chip = TopicChipSpec(
            postScriptName: badge.face.postScriptName,
            pointSize: chipSize,
            horizontalPadding: CanvasMetrics.tagChipHorizontalPadding,
            // Chips grow with their text, as the title does.
            height: (CanvasMetrics.tagChipHeight * chipSize / badge.size).rounded(.up),
            spacing: CanvasMetrics.tagChipSpacing,
            topGap: CanvasMetrics.tagChipTopGap,
            symbolWidth: (CanvasMetrics.tagChipSymbolWidth * chipSize / badge.size).rounded(.up)
        )
        let image = TopicImageSpec(maximumAspect: CanvasMetrics.imageMaxAspect, gap: CanvasMetrics.imageGap)
        let mark = TopicMarkSpec(
            shapeSize: CanvasMetrics.topicColorShapeSize,
            gap: CanvasMetrics.topicMarkGap,
            symbolWidthFactor: CanvasMetrics.topicSymbolWidthFactor,
            showsColorShapes: showsColorShapes
        )
        return TopicTextSpecs(levels: levels, placeholder: String(localized: "Untitled Topic"), chip: chip, image: image, mark: mark)
    }

    /// Design sizes, without Dynamic Type: the Mac, and tests.
    static func designSizes(showsColorShapes: Bool = false) -> TopicTextSpecs {
        make(showsColorShapes: showsColorShapes) { $0.size }
    }
}
