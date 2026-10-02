import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph

/// The central topic in the middle, main branches to its right and left, each
/// branch growing outward with its children stacked top to bottom.
///
/// Every branch gets a horizontal band as tall as the branch, and sibling bands
/// are stacked without overlap, so topics of any size never collide. A topic is
/// centered on its children's block, and children start one gap past the edge
/// of their own parent, so a wide topic pushes only its own branch outward.
public struct HorizontalTreeLayout: MindMapLayoutEngine {
    public init() {}

    public func layout(_ graph: GraphState, sizes: [NodeID: CGSize], options: LayoutOptions) -> MapLayout {
        var pass = LayoutPass(graph: graph, sizes: sizes, options: options, previous: nil, dirty: [])
        return pass.run()
    }

    public func update(
        _ previous: MapLayout,
        graph: GraphState,
        sizes: [NodeID: CGSize],
        options: LayoutOptions,
        changed: Set<NodeID>
    ) -> MapLayout {
        guard previous.options == options, previous.rootID != nil, previous.rootID == graph.map.rootNodeID else {
            return layout(graph, sizes: sizes, options: options)
        }
        let dirty = Self.dirtyBranches(for: changed, in: graph)
        var pass = LayoutPass(graph: graph, sizes: sizes, options: options, previous: previous, dirty: dirty)
        return pass.run()
    }

    /// A changed topic can change the size of every branch that contains it, so
    /// its ancestors are measured again too; everything else keeps its old result.
    static func dirtyBranches(for changed: Set<NodeID>, in graph: GraphState) -> Set<NodeID> {
        var dirty: Set<NodeID> = []
        for id in changed {
            var current: NodeID? = id
            // Stops at a node already marked, so shared ancestors are walked once
            // and a corrupt parent loop cannot spin.
            while let nodeID = current, let node = graph.node(nodeID), dirty.insert(nodeID).inserted {
                current = node.parentID
            }
        }
        return dirty
    }
}

/// One run of the layout. With a `previous` layout, branches outside `dirty`
/// reuse their measure, and are left where they were when their frame comes
/// out the same; otherwise every visible topic is computed.
///
/// A reused branch is placed with the same arithmetic as a fresh one, never
/// shifted by a delta, so an update is bit-for-bit equal to a full layout.
private struct LayoutPass {
    let graph: GraphState
    let sizes: [NodeID: CGSize]
    let options: LayoutOptions
    let previous: MapLayout?
    let dirty: Set<NodeID>

    private var result: MapLayout
    /// Topics the placement walk reached in this pass; an update must not remove them.
    private var placed: Set<NodeID> = []
    /// Topics that were visible children of a re-measured topic and no longer
    /// are; their old entries go unless they turned up elsewhere.
    private var orphans: [NodeID] = []

    init(graph: GraphState, sizes: [NodeID: CGSize], options: LayoutOptions, previous: MapLayout?, dirty: Set<NodeID>) {
        self.graph = graph
        self.sizes = sizes
        self.options = options
        self.previous = previous
        self.dirty = dirty
        result = previous ?? MapLayout(options: options)
    }

    mutating func run() -> MapLayout {
        guard let rootID = graph.map.rootNodeID, graph.node(rootID) != nil else {
            return MapLayout(options: options)
        }
        result.rootID = rootID
        measure(from: rootID, rootID: rootID)
        place(rootID: rootID)
        removeOrphans()
        result.crossLinks = crossLinks()
        result.bounds = bounds()
        return result
    }

    // MARK: Measuring

    private func isReusable(_ id: NodeID) -> Bool {
        previous != nil && !dirty.contains(id) && result.measures[id] != nil
    }

    private func size(of id: NodeID) -> CGSize {
        sizes[id] ?? options.defaultNodeSize
    }

    private func visibleChildren(of id: NodeID, rootID: NodeID) -> [NodeID] {
        guard let node = graph.node(id), !node.isCollapsed else { return [] }
        // The root can only be a child in corrupt data; skipping it keeps the walk finite.
        return graph.childIDs(of: id).filter { $0 != rootID }
    }

    /// Bottom-up, with an explicit stack so a very deep map cannot overflow it.
    private mutating func measure(from start: NodeID, rootID: NodeID) {
        var stack: [(id: NodeID, childrenDone: Bool)] = [(start, false)]
        while let (id, childrenDone) = stack.popLast() {
            if childrenDone {
                measureBranch(id, rootID: rootID)
                continue
            }
            if isReusable(id) { continue }
            stack.append((id, true))
            for child in visibleChildren(of: id, rootID: rootID) where !isReusable(child) {
                stack.append((child, false))
            }
        }
    }

    /// Runs after every visible child has a measure.
    private mutating func measureBranch(_ id: NodeID, rootID: NodeID) {
        let children = visibleChildren(of: id, rootID: rootID)
        var weight = 1
        var block: CGFloat = 0
        for (index, child) in children.enumerated() {
            guard let childMeasure = result.measures[child] else { preconditionFailure("Child measured after its parent") }
            weight += childMeasure.weight
            block += childMeasure.extent
            if index > 0 { block += options.verticalSpacing }
        }
        let isCollapsed = graph.node(id)?.isCollapsed ?? false
        let branch = BranchMeasure(
            extent: max(size(of: id).height, block),
            weight: weight,
            visibleChildren: children,
            hiddenDescendantCount: isCollapsed ? graph.descendants(of: id).count : 0
        )
        if previous != nil, let old = result.measures[id], !old.visibleChildren.isEmpty {
            let current = Set(children)
            orphans.append(contentsOf: old.visibleChildren.filter { !current.contains($0) })
        }
        result.measures[id] = branch
    }

    // MARK: Placing

    private struct Placement {
        let id: NodeID
        let side: LayoutSide
        let depth: Int
        /// The x of the edge that faces the parent.
        let anchorX: CGFloat
        let centerY: CGFloat
        let parentFrame: CGRect
    }

    /// Top-down, with an explicit stack for the same reason as `measure`.
    private mutating func place(rootID: NodeID) {
        let rootSize = size(of: rootID)
        let rootFrame = CGRect(
            x: -rootSize.width / 2,
            y: -rootSize.height / 2,
            width: rootSize.width,
            height: rootSize.height
        )
        guard write(rootID, frame: rootFrame, side: .center, depth: 0) else { return }

        let (right, left) = split(measure(of: rootID).visibleChildren)
        var stack = placements(for: right, in: rootFrame, side: .right, depth: 1)
        // With both sides in use, reading goes clockwise around the central topic:
        // down the right side, then up the left, so the first left branch sits at
        // the bottom. A left-only map has no right side to continue from, so it
        // reads top to bottom like a right-only one.
        let leftOrder = options.sides == .balanced ? Array(left.reversed()) : left
        stack += placements(for: leftOrder, in: rootFrame, side: .left, depth: 1)

        while let next = stack.popLast() {
            let nodeSize = size(of: next.id)
            let minX = next.side == .left ? next.anchorX - nodeSize.width : next.anchorX
            let frame = CGRect(
                x: minX,
                y: next.centerY - nodeSize.height / 2,
                width: nodeSize.width,
                height: nodeSize.height
            )
            // Written before the early stop below: a topic can keep its frame while
            // its parent moves (a parent re-centered on a block that grew below and
            // shrank above), and the connector starts on the parent's edge.
            result.connectors[next.id] = connector(from: next.parentFrame, to: frame, side: next.side)
            guard write(next.id, frame: frame, side: next.side, depth: next.depth) else { continue }
            stack += placements(
                for: measure(of: next.id).visibleChildren,
                in: frame,
                side: next.side,
                depth: next.depth + 1
            )
        }
    }

    /// Records a topic's place. Returns false when an untouched branch landed
    /// exactly where it was, so nothing inside it can have moved.
    private mutating func write(_ id: NodeID, frame: CGRect, side: LayoutSide, depth: Int) -> Bool {
        // Reached by the walk means visible, so `removeOrphans` must keep it even
        // when the early stop below leaves its entry untouched.
        if previous != nil { placed.insert(id) }
        if previous != nil, !dirty.contains(id), let old = result.nodes[id],
           old.frame == frame, old.side == side, old.depth == depth {
            return false
        }
        result.nodes[id] = LayoutNode(
            frame: frame,
            side: side,
            depth: depth,
            hiddenDescendantCount: measure(of: id).hiddenDescendantCount
        )
        return true
    }

    private func measure(of id: NodeID) -> BranchMeasure {
        guard let measure = result.measures[id] else { preconditionFailure("Placing a topic that was not measured") }
        return measure
    }

    /// Stacks the children's bands top to bottom, centered on the parent.
    private func placements(for children: [NodeID], in parentFrame: CGRect, side: LayoutSide, depth: Int) -> [Placement] {
        guard !children.isEmpty else { return [] }
        let extents = children.map { measure(of: $0).extent }
        let block = extents.reduce(0, +) + options.verticalSpacing * CGFloat(children.count - 1)
        let anchorX = side == .left
            ? parentFrame.minX - options.horizontalSpacing
            : parentFrame.maxX + options.horizontalSpacing
        var top = parentFrame.midY - block / 2
        var list: [Placement] = []
        list.reserveCapacity(children.count)
        for (child, extent) in zip(children, extents) {
            list.append(Placement(
                id: child,
                side: side,
                depth: depth,
                anchorX: anchorX,
                centerY: top + extent / 2,
                parentFrame: parentFrame
            ))
            top += extent + options.verticalSpacing
        }
        return list
    }

    /// Main branches in display order: a prefix goes right, the rest left.
    /// Keeping order means a branch only changes side when the balance demands it.
    private func split(_ branches: [NodeID]) -> (right: [NodeID], left: [NodeID]) {
        switch options.sides {
        case .rightOnly:
            return (branches, [])
        case .leftOnly:
            return ([], branches)
        case .balanced:
            let weights = branches.map { measure(of: $0).weight }
            let total = weights.reduce(0, +)
            var bestCount = 0
            var bestDifference = total
            var prefix = 0
            for (index, weight) in weights.enumerated() {
                prefix += weight
                let difference = abs(2 * prefix - total)
                // On a tie the right side takes the extra branch, as people expect
                // the first ideas on the right.
                if difference <= bestDifference {
                    bestCount = index + 1
                    bestDifference = difference
                }
            }
            return (Array(branches.prefix(bestCount)), Array(branches.dropFirst(bestCount)))
        }
    }

    private func connector(from parent: CGRect, to child: CGRect, side: LayoutSide) -> EdgePath {
        if side == .left {
            return .horizontal(from: CGPoint(x: parent.minX, y: parent.midY), to: CGPoint(x: child.maxX, y: child.midY))
        }
        return .horizontal(from: CGPoint(x: parent.maxX, y: parent.midY), to: CGPoint(x: child.minX, y: child.midY))
    }

    // MARK: Finishing

    private mutating func removeOrphans() {
        var stack = orphans
        while let id = stack.popLast() {
            // Placed in this pass means it moved rather than disappeared, and so
            // did anything below it that is still visible.
            guard !placed.contains(id) else { continue }
            if let removed = result.measures.removeValue(forKey: id) {
                stack.append(contentsOf: removed.visibleChildren)
            }
            result.nodes[id] = nil
            result.connectors[id] = nil
        }
    }

    /// Recomputed on every pass: a map has few cross-links, and an edge edit
    /// changes no topic, so it would not show up in `changed`.
    private func crossLinks() -> [EdgeID: EdgePath] {
        var paths: [EdgeID: EdgePath] = [:]
        for edge in graph.edges.values where edge.sourceNodeID != edge.targetNodeID {
            guard let source = result.nodes[edge.sourceNodeID]?.frame,
                  let target = result.nodes[edge.targetNodeID]?.frame else { continue }
            let forward = target.midX >= source.midX
            paths[edge.id] = .horizontal(
                from: CGPoint(x: forward ? source.maxX : source.minX, y: source.midY),
                to: CGPoint(x: forward ? target.minX : target.maxX, y: target.midY)
            )
        }
        return paths
    }

    private func bounds() -> CGRect {
        var union: CGRect?
        for node in result.nodes.values {
            union = union?.union(node.frame) ?? node.frame
        }
        return union ?? .zero
    }
}
