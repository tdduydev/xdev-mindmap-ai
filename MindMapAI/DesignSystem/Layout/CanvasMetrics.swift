import SwiftUI

/// Topic and edge sizes on the canvas, in points at 100% zoom. Separate from
/// `Spacing` because the layout engine and the canvas read them by level.
enum CanvasMetrics {
    /// Sizes for one kind of topic.
    struct Box: Hashable, Sendable {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let minimumWidth: CGFloat
        /// Titles wrap at this width; they are never truncated on the canvas.
        let maximumWidth: CGFloat
        let cornerRadius: CGFloat
        /// Horizontal gap to the parent; zero for the central topic.
        let parentGap: CGFloat
        /// Vertical gap between siblings; zero for the central topic.
        let siblingGap: CGFloat
    }

    static let central = Box(horizontalPadding: 16, verticalPadding: 12, minimumWidth: 96, maximumWidth: 280, cornerRadius: 12, parentGap: 0, siblingGap: 0)
    static let main = Box(horizontalPadding: 12, verticalPadding: 8, minimumWidth: 56, maximumWidth: 240, cornerRadius: 10, parentGap: 64, siblingGap: 20)
    static let sub = Box(horizontalPadding: 10, verticalPadding: 6, minimumWidth: 40, maximumWidth: 220, cornerRadius: 8, parentGap: 40, siblingGap: 10)

    /// The box for a level: 0 is the central topic.
    static func box(level: Int) -> Box {
        switch level {
        case ...0: central
        case 1: main
        default: sub
        }
    }

    /// Width of the hierarchy edge into a topic at `level`; nothing enters the central topic.
    static func edgeWidth(level: Int) -> CGFloat {
        switch level {
        case ...0: 0
        case 1: 3
        case 2: 2
        default: 1.5
        }
    }

    static let mainStrokeWidth: CGFloat = 1.5
    static let mainStrokeWidthHighContrast: CGFloat = 2

    static let selectionRingWidth: CGFloat = 2
    static let selectionRingWidthHighContrast: CGFloat = 3
    /// Space between a topic and its selection ring.
    static let selectionRingGap: CGFloat = 2

    static let crossLinkWidth: CGFloat = 1.5
    static let crossLinkDash: [CGFloat] = [4, 3]
    /// Arrowhead of a `reference` cross-link: side length and half-angle (radians).
    static let crossLinkArrowLength: CGFloat = 8
    static let crossLinkArrowAngle: CGFloat = .pi / 7
    static let suggestionEdgeWidth: CGFloat = 1.5
    static let suggestionDash: [CGFloat] = [3, 3]

    static let dropTargetOutlineWidth: CGFloat = 2
    static let dropInsertionBarWidth: CGFloat = 3
    static let dropTargetDash: [CGFloat] = [5, 3]
    static let dragSourceOpacity: Double = 0.6
    /// How far a pointer or finger moves on a topic before it drags (MM-5).
    static let dragStartDistance: CGFloat = 4
    /// The top and bottom quarter of a topic drop beside it, the middle inside.
    static let dropEdgeFraction: CGFloat = 0.25
    /// The selection rectangle dragged on empty canvas.
    static let marqueeStrokeWidth: CGFloat = 1
    static let marqueeFillOpacity: Double = 0.12
    /// On touch, a hold on empty canvas before a drag draws a selection rectangle.
    static let marqueeHoldDuration: Double = 0.4

    /// Floating topics (FR-ORG-27): the step Add Floating Topic moves down
    /// from the middle of the view until the new topic overlaps none.
    static let floatingTopicNudge: CGFloat = 24
    /// Steps tried before it gives up and overlaps.
    static let floatingTopicNudgeLimit = 40
    /// Below the central topic, when no canvas has laid the map out.
    static let floatingTopicFallbackOffset: CGFloat = 160

    /// Size of the note symbol after a title.
    static let noteSymbolSize: CGFloat = 11

    /// The link symbol on a topic (FR-ORG-26), the size of the note mark.
    static let linkSymbolSize: CGFloat = noteSymbolSize

    /// Tag chips in a row under the title (MM-34), measured with it.
    static let tagChipHeight: CGFloat = 16
    static let tagChipHorizontalPadding: CGFloat = 6
    /// Between chips, and between rows of chips.
    static let tagChipSpacing: CGFloat = 4
    /// Between the title and the first row of chips.
    static let tagChipTopGap: CGFloat = 4
    /// The `sparkles` mark and its gap before a suggested tag's name.
    static let tagChipSymbolWidth: CGFloat = 13
    /// Tags shown on a topic before "+n". Read off the main actor by the
    /// layout pass, hence `nonisolated`.
    nonisolated static let maximumTopicTagChips = 3

    /// A picture on a topic (MM-63), above the title: its widths for Image
    /// Size ▸ Small, Medium (the default, `MindImage.defaultDisplayWidth`)
    /// and Large, never wider than the box's content.
    static let imageWidthSmall: Double = 96
    static let imageWidthMedium: Double = 160
    static let imageWidthLarge: Double = 240
    /// Height ÷ width; a taller picture is cropped to fill.
    static let imageMaxAspect: Double = 1.5
    /// Between the picture and the title.
    static let imageGap: CGFloat = 8
    static let imageCornerRadius: CGFloat = Radius.sm
    static let imagePlaceholderOpacity: Double = 0.3

    /// A callout bubble above its topic (FR-ORG-30). The layout reserves
    /// the bubble, its tail and `calloutGap`, so it covers no other topic.
    static let calloutGap: CGFloat = Spacing.sm
    static let calloutHorizontalPadding: CGFloat = 8
    static let calloutVerticalPadding: CGFloat = 6
    // Read by `CalloutBubbleShape`, which draws off the main actor.
    nonisolated static let calloutCornerRadius: CGFloat = 8 // Radius.md
    nonisolated static let calloutTailWidth: CGFloat = 8
    nonisolated static let calloutTailHeight: CGFloat = 6
    static let calloutStrokeWidth: CGFloat = 1
    static let calloutStrokeWidthHighContrast: CGFloat = 2
    /// From the bubble's bottom edge to the card: what `LayoutOptions.calloutSpacing` gets.
    static let calloutSpacing: CGFloat = calloutTailHeight + calloutGap

    /// The pointer hit area is the visual box, at least this tall.
    static let minimumPointerHeight: CGFloat = 28

    /// Height of the collapse-count capsule.
    #if os(iOS)
    static let collapseBadgeHeight: CGFloat = 22
    #else
    static let collapseBadgeHeight: CGFloat = 18
    #endif
    /// Space between a topic and its collapse badge.
    static let collapseBadgeGap: CGFloat = 4

    /// The round + buttons on a hovered or selected topic (MM-57), as tall as
    /// the collapse badge; the tap area is `Metrics.minimumHitTarget`.
    static let addButtonDiameter: CGFloat = collapseBadgeHeight
    static let addButtonRingWidth: CGFloat = 1.5
    #if os(iOS)
    static let addButtonSymbolSize: CGFloat = 12
    #else
    static let addButtonSymbolSize: CGFloat = 10
    #endif

    // MARK: Camera (MM-3)

    /// 10% to 400% (FR-CNV-02, a proposal in the SRS).
    static let zoomLimits: ClosedRange<CGFloat> = 0.1...4
    /// Where ⌘+ and ⌘− stop.
    static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]
    /// Zoom to Fit never enlarges a small map past actual size.
    static let fitZoomLimits: ClosedRange<CGFloat> = zoomLimits.lowerBound...1
    /// Room left around the map by Zoom to Fit, in view points.
    static let fitPadding: CGFloat = 48
    /// Room around the map in an exported PNG or PDF, in canvas points; wide
    /// enough for a collapse badge beside an outermost topic.
    static let exportPadding: CGFloat = 48
    /// Paper margin of an exported PDF page, in PDF points (1/72 inch).
    static let exportPageMargin: CGFloat = 36
    /// The longest side of an exported PNG, in pixels. A larger map is drawn at
    /// a lower scale rather than making an image other apps cannot open.
    static let exportMaximumPixels: CGFloat = 16_384
    /// Room kept between a topic scrolled into view and the view's edge.
    static let revealMargin: CGFloat = 32
    /// Fraction of the visible size drawn beyond each edge, so panning does not
    /// show topics popping in.
    static let cullingMargin: CGFloat = 0.25
    /// Below this zoom, titles are too small to read (under 4 pt); topics are
    /// drawn as plain shapes in the edge layer instead of as views, so a
    /// zoomed-out large map is one `Canvas` rather than hundreds of views.
    static let detailZoomThreshold: CGFloat = 0.3
    /// Points one notch of a non-precise mouse wheel pans.
    static let wheelLineStep: CGFloat = 16
    /// How fast ⌘-scroll zooms: the zoom is multiplied by e^(delta × this).
    static let wheelZoomRate: CGFloat = 0.01

    /// Layout gaps. The layout engine takes one gap for every level, so the
    /// canvas uses the sub-topic gaps, which most topics in a large map are.
    static let layoutParentGap: CGFloat = sub.parentGap
    static let layoutSiblingGap: CGFloat = sub.siblingGap
}
