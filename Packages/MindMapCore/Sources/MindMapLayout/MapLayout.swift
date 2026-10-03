import CoreGraphics
import Foundation
import MindMapDomain

/// The geometry of one map, in canvas points with the central topic centered
/// on the origin. Only visible topics appear: the inside of a collapsed branch
/// takes no space.
public struct MapLayout: Equatable, Sendable {
    public internal(set) var rootID: NodeID?
    public internal(set) var options: LayoutOptions
    public internal(set) var nodes: [NodeID: LayoutNode]
    /// Floating topics laid out around their stored positions, in layout order.
    public internal(set) var floatingTopicIDs: [NodeID]
    /// The line from each visible topic's parent to it, keyed by the child.
    public internal(set) var connectors: [NodeID: EdgePath]
    /// Every cross-link with at least one visible end. An end hidden in a
    /// collapsed branch is drawn to its nearest visible ancestor.
    public internal(set) var crossLinks: [EdgeID: EdgePath]
    /// Cross-links drawn to an ancestor instead of an end, which the canvas dims.
    public internal(set) var reroutedCrossLinks: Set<EdgeID>
    /// Per visible topic, how many cross-links reach topics hidden below it;
    /// the canvas shows it as a badge. A link with both ends below one topic
    /// is counted but not drawn.
    public internal(set) var hiddenCrossLinkCounts: [NodeID: Int]
    /// The frame of each boundary with a visible member: its visible members'
    /// branches plus `boundaryPadding`, and the title's room on top when it has
    /// one. Hidden with its parent; members on the far side of the central
    /// topic from the first member are left out.
    public internal(set) var boundaries: [GroupID: CGRect]
    /// The bracket of each summary with a visible member. Hidden with its
    /// parent; members on the far side of the central topic from the first
    /// member are left out, as for boundaries.
    public internal(set) var summaries: [GroupID: SummaryBracket]
    /// The smallest rectangle holding every topic frame, callout, boundary and bracket; `.zero` for an empty map.
    public internal(set) var bounds: CGRect

    /// Per-topic results kept so `update` can skip untouched branches.
    var measures: [NodeID: BranchMeasure]

    init(options: LayoutOptions) {
        rootID = nil
        self.options = options
        nodes = [:]
        floatingTopicIDs = []
        connectors = [:]
        crossLinks = [:]
        reroutedCrossLinks = []
        hiddenCrossLinkCounts = [:]
        boundaries = [:]
        summaries = [:]
        bounds = .zero
        measures = [:]
    }
}

public struct LayoutNode: Equatable, Sendable {
    /// The topic's card; connectors attach to it.
    public var frame: CGRect
    /// The callout bubble above the card, nil without one (FR-ORG-30). Its
    /// room is reserved, so it overlaps no other topic or bubble.
    public var calloutFrame: CGRect?
    public var side: LayoutSide
    /// 0 for the central topic.
    public var depth: Int
    /// How many topics a collapsed branch hides; 0 when expanded.
    public var hiddenDescendantCount: Int
}

/// A `}` beyond a run of siblings, its back facing the run.
public struct SummaryBracket: Equatable, Sendable {
    /// From the back (facing the run) to the tip, spanning the run's branches.
    public var frame: CGRect
    /// `.left` when the run grows leftward, so the tip points left.
    public var side: LayoutSide
    /// The summary topic beside the tip, nil while it is missing (still syncing).
    public var summaryNodeID: NodeID?

    /// Where the summary topic meets the bracket.
    public var tip: CGPoint {
        CGPoint(x: side == .left ? frame.minX : frame.maxX, y: frame.midY)
    }
}

public enum LayoutSide: Hashable, Sendable {
    /// The central topic.
    case center
    case right
    case left
}

/// A cubic Bézier curve, the shape the canvas strokes for an edge.
public struct EdgePath: Equatable, Sendable {
    public var start: CGPoint
    public var control1: CGPoint
    public var control2: CGPoint
    public var end: CGPoint

    /// Leaves and enters horizontally, so the curve reads as a tree branch.
    static func horizontal(from start: CGPoint, to end: CGPoint) -> EdgePath {
        let midX = (start.x + end.x) / 2
        return EdgePath(
            start: start,
            control1: CGPoint(x: midX, y: start.y),
            control2: CGPoint(x: midX, y: end.y),
            end: end
        )
    }
}

/// What a branch needs from its parent to be placed.
struct BranchMeasure: Equatable, Sendable {
    /// Height of the band the branch occupies, the topic and all visible descendants.
    var extent: CGFloat
    /// The part of `extent` above the card's centre. More than half of it when
    /// a callout above the card needs the room.
    var ascent: CGFloat
    /// Visible topics in the branch, itself included; balances the two sides.
    var weight: Int
    var visibleChildren: [NodeID]
    var hiddenDescendantCount: Int
}
