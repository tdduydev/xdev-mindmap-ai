import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph

/// Turns a graph into screen geometry: sizes in, frames and edge paths out.
///
/// Engines are pure values with no UI, so the canvas can run them off the main
/// actor and tests can check them without a window. Topic sizes are an input
/// because only the view knows how a title wraps at the current Dynamic Type size.
public protocol MindMapLayoutEngine: Sendable {
    /// Lays out every visible topic from scratch.
    ///
    /// - Parameter sizes: The measured size of each topic. A topic missing from
    ///   the table gets `options.defaultNodeSize`.
    /// - Parameter callouts: The measured bubble of each topic with a callout
    ///   (FR-ORG-30). The bubble sits above the card and its room is reserved,
    ///   so it never covers another topic. A topic whose bubble changed for a
    ///   reason other than a command (a bubble opened for typing) must be in
    ///   `changed` on `update`, as for sizes.
    func layout(
        _ graph: GraphState,
        sizes: [NodeID: CGSize],
        callouts: [NodeID: CGSize],
        options: LayoutOptions
    ) -> MapLayout

    /// Lays out the graph again after an edit, reusing `previous` for the
    /// branches the edit did not touch.
    ///
    /// The result is the same as `layout(_:sizes:options:)` would give for the
    /// same input, as long as `changed` names every topic whose own content or
    /// size changed, plus the old and new parent of every topic that moved or
    /// was deleted. `GraphChangeSet.layoutInvalidation` builds that set.
    func update(
        _ previous: MapLayout,
        graph: GraphState,
        sizes: [NodeID: CGSize],
        callouts: [NodeID: CGSize],
        options: LayoutOptions,
        changed: Set<NodeID>
    ) -> MapLayout
}

extension MindMapLayoutEngine {
    /// Engines without incremental support lay out everything again.
    public func update(
        _ previous: MapLayout,
        graph: GraphState,
        sizes: [NodeID: CGSize],
        callouts: [NodeID: CGSize],
        options: LayoutOptions,
        changed: Set<NodeID>
    ) -> MapLayout {
        layout(graph, sizes: sizes, callouts: callouts, options: options)
    }

    /// A map without callouts.
    public func layout(_ graph: GraphState, sizes: [NodeID: CGSize], options: LayoutOptions) -> MapLayout {
        layout(graph, sizes: sizes, callouts: [:], options: options)
    }

    /// A map without callouts.
    public func update(
        _ previous: MapLayout,
        graph: GraphState,
        sizes: [NodeID: CGSize],
        options: LayoutOptions,
        changed: Set<NodeID>
    ) -> MapLayout {
        update(previous, graph: graph, sizes: sizes, callouts: [:], options: options, changed: changed)
    }
}

/// Geometry settings shared by the engines. The user's stored choice of style
/// lives in `LayoutConfiguration`; this is how that style is drawn.
public struct LayoutOptions: Equatable, Sendable {
    /// Which side of the central topic the main branches go to.
    public var sides: BranchSides
    /// Gap between a topic and its children.
    public var horizontalSpacing: CGFloat
    /// Gap between neighboring sibling branches.
    public var verticalSpacing: CGFloat
    /// Used for a topic the caller has not measured yet.
    public var defaultNodeSize: CGSize
    /// From a callout bubble's bottom edge to its card's top: the tail and the
    /// gap past it.
    public var calloutSpacing: CGFloat
    /// From a boundary's members to its frame, reserved above and below the run.
    public var boundaryPadding: CGFloat
    /// Room reserved above a titled boundary's members for its title capsule.
    public var boundaryTitleHeight: CGFloat
    /// From the outermost edge of a summary's run to its bracket.
    public var summaryBracketGap: CGFloat
    /// How far a summary bracket reaches from its back to its tip.
    public var summaryBracketWidth: CGFloat

    public init(
        sides: BranchSides = .balanced,
        horizontalSpacing: CGFloat = 48,
        verticalSpacing: CGFloat = 16,
        defaultNodeSize: CGSize = CGSize(width: 120, height: 36),
        calloutSpacing: CGFloat = 14,
        boundaryPadding: CGFloat = 8,
        boundaryTitleHeight: CGFloat = 20,
        summaryBracketGap: CGFloat = 8,
        summaryBracketWidth: CGFloat = 12
    ) {
        self.sides = sides
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.defaultNodeSize = defaultNodeSize
        self.calloutSpacing = calloutSpacing
        self.boundaryPadding = boundaryPadding
        self.boundaryTitleHeight = boundaryTitleHeight
        self.summaryBracketGap = summaryBracketGap
        self.summaryBracketWidth = summaryBracketWidth
    }
}

public enum BranchSides: String, Hashable, Sendable, CaseIterable {
    /// Main branches split between right and left so both sides hold about the
    /// same number of visible topics.
    case balanced
    case rightOnly
    case leftOnly
}

extension LayoutStyle {
    /// The engine that draws this style.
    public var engine: any MindMapLayoutEngine {
        switch self {
        case .horizontalTree: HorizontalTreeLayout()
        }
    }
}
