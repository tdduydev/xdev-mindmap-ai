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
    /// The line from each visible topic's parent to it, keyed by the child.
    public internal(set) var connectors: [NodeID: EdgePath]
    /// Cross-links whose two ends are both visible.
    public internal(set) var crossLinks: [EdgeID: EdgePath]
    /// The smallest rectangle holding every topic frame; `.zero` for an empty map.
    public internal(set) var bounds: CGRect

    /// Per-topic results kept so `update` can skip untouched branches.
    var measures: [NodeID: BranchMeasure]

    init(options: LayoutOptions) {
        rootID = nil
        self.options = options
        nodes = [:]
        connectors = [:]
        crossLinks = [:]
        bounds = .zero
        measures = [:]
    }
}

public struct LayoutNode: Equatable, Sendable {
    public var frame: CGRect
    public var side: LayoutSide
    /// 0 for the central topic.
    public var depth: Int
    /// How many topics a collapsed branch hides; 0 when expanded.
    public var hiddenDescendantCount: Int
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
    /// Visible topics in the branch, itself included; balances the two sides.
    var weight: Int
    var visibleChildren: [NodeID]
    var hiddenDescendantCount: Int
}
