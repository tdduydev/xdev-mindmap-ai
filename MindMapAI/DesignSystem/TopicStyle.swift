import MindMapDomain
import SwiftUI

/// Everything the canvas needs to draw one topic at rest, resolved once from
/// its level, branch, theme and the appearance. States (selection, hover,
/// search match, suggestion) are drawn on top from the fields here and the
/// semantic `Palette`.
struct TopicStyle: Hashable {
    enum Kind: Hashable, Sendable {
        /// Filled navy card.
        case central
        /// Tinted card with a branch-coloured stroke.
        case main
        /// Lightly tinted card, no stroke.
        case sub
    }

    let kind: Kind
    let text: ContentStyle
    let textColor: SRGBColor
    let secondaryTextColor: SRGBColor
    let fill: SRGBColor
    /// Fill under the pointer: 4% darker in light, 6% lighter in dark.
    let hoverFill: SRGBColor
    /// Nil when the topic has no outline.
    let stroke: SRGBColor?
    let strokeWidth: CGFloat
    let box: CanvasMetrics.Box
    /// Colour and width of the hierarchy edge from the parent; width zero for the central topic.
    let edgeColor: SRGBColor
    let edgeWidth: CGFloat
    let badgeFill: SRGBColor
    let badgeText: SRGBColor
    let selectionRingWidth: CGFloat

    /// - Parameters:
    ///   - level: Depth from the central topic, which is 0.
    ///   - branch: Index of the topic's level-1 ancestor among the central
    ///     topic's children, in `sortOrder`; ignored for the central topic.
    ///   - color: A colour the person set on the topic or an ancestor
    ///     (FR-ORG-01). It wins over the theme's branch colour; fills and
    ///     badges derive from it as they do from a branch colour.
    static func resolve(
        level: Int,
        branch: Int,
        color: TopicColor? = nil,
        theme: MapTheme,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> TopicStyle {
        let variant = ColorVariant(colorScheme: colorScheme, contrast: contrast)
        let colors = color.map { BranchColors(line: $0.token, variant: variant) } ?? theme.branch(branch, in: variant)
        let tokens = Palette.Tokens.self
        let kind: Kind = level <= 0 ? .central : level == 1 ? .main : .sub

        let fill: SRGBColor
        let textColor: SRGBColor
        let stroke: SRGBColor?
        switch kind {
        case .central:
            fill = tokens.centralFill[variant]
            textColor = tokens.centralText[variant]
            stroke = nil
        case .main:
            fill = colors.mainFill
            textColor = tokens.topicText[variant]
            stroke = colors.line
        case .sub:
            fill = colors.subFill
            textColor = tokens.topicText[variant]
            stroke = nil
        }

        return TopicStyle(
            kind: kind,
            text: Typography.Content.topic(level: level),
            textColor: textColor,
            secondaryTextColor: kind == .central ? textColor : tokens.topicTextSecondary[variant],
            fill: fill,
            hoverFill: variant.isDark
                ? SRGBColor(hex: 0xFFFFFF).composited(over: fill, opacity: 0.06)
                : SRGBColor(hex: 0x000000).composited(over: fill, opacity: 0.04),
            stroke: stroke,
            strokeWidth: stroke == nil ? 0
                : variant.isHighContrast ? CanvasMetrics.mainStrokeWidthHighContrast : CanvasMetrics.mainStrokeWidth,
            box: CanvasMetrics.box(level: level),
            edgeColor: colors.line,
            edgeWidth: CanvasMetrics.edgeWidth(level: level),
            badgeFill: colors.badgeFill,
            badgeText: colors.badgeText,
            selectionRingWidth: variant.isHighContrast
                ? CanvasMetrics.selectionRingWidthHighContrast : CanvasMetrics.selectionRingWidth
        )
    }
}
