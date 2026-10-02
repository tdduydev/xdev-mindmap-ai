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
    static let suggestionEdgeWidth: CGFloat = 1.5
    static let suggestionDash: [CGFloat] = [3, 3]

    static let dropTargetOutlineWidth: CGFloat = 2
    static let dropInsertionBarWidth: CGFloat = 3
    static let dragSourceOpacity: Double = 0.6

    /// Size of the note symbol after a title.
    static let noteSymbolSize: CGFloat = 11

    /// The pointer hit area is the visual box, at least this tall.
    static let minimumPointerHeight: CGFloat = 28

    /// Height of the collapse-count capsule.
    #if os(iOS)
    static let collapseBadgeHeight: CGFloat = 22
    #else
    static let collapseBadgeHeight: CGFloat = 18
    #endif
}
