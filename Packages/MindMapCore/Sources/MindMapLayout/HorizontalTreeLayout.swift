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
///
/// Each floating topic (ADR 0010) is centred on its stored position, with its
/// branch growing to the right of it by the same rules. Floating branches are
/// laid out after the main tree in `GraphState.floatingTopicIDs` order and are
/// not pushed away from it or from each other: they may overlap.
///
/// A callout (FR-ORG-30) sits above its card, `calloutSpacing` away, and its
/// room is part of the topic's slot: the band grows upward by the bubble, and
/// children start past the wider of card and bubble. The bubble is centred on
/// the card but never passes the card's edge that faces the parent, so it
/// cannot reach into the parent's column. Connectors still attach to the card.
///
/// A boundary (MM-37) reserves `boundaryPadding` above and below its run of
/// siblings, plus `boundaryTitleHeight` above it when it has a title, so its
/// frame never covers a neighbouring branch. Its frame is the union of its
/// visible members' branches and the boundaries nested inside them.
///
/// A summary (FR-ORG-29) draws a bracket `summaryBracketGap` beyond the
/// outermost edge of its run's branches, and its summary topic one
/// `horizontalSpacing` past the bracket's tip, centred on the run. The summary
/// topic is out of its parent's column; when its branch is taller than the run,
/// the run gets the difference as room above and below, so the branch never
/// covers a neighbour. Summaries are placed after the tree, innermost first,
/// so a bracket clears every summary nested in or below its run.
public struct HorizontalTreeLayout: MindMapLayoutEngine {
    public init() {}

    public func layout(
        _ graph: GraphState,
        sizes: [NodeID: CGSize],
        callouts: [NodeID: CGSize],
        options: LayoutOptions
    ) -> MapLayout {
        var pass = LayoutPass(graph: graph, sizes: sizes, callouts: callouts, options: options, previous: nil, dirty: [])
        return pass.run()
    }

    public func update(
        _ previous: MapLayout,
        graph: GraphState,
        sizes: [NodeID: CGSize],
        callouts: [NodeID: CGSize],
        options: LayoutOptions,
        changed: Set<NodeID>
    ) -> MapLayout {
        guard previous.options == options, previous.rootID != nil, previous.rootID == graph.map.rootNodeID else {
            return layout(graph, sizes: sizes, callouts: callouts, options: options)
        }
        let dirty = Self.dirtyBranches(for: changed, in: graph)
        var pass = LayoutPass(
            graph: graph, sizes: sizes, callouts: callouts, options: options, previous: previous, dirty: dirty
        )
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
    let callouts: [NodeID: CGSize]
    let options: LayoutOptions
    let previous: MapLayout?
    let dirty: Set<NodeID>
    /// Valid boundaries by parent, so measuring a branch does not scan every group.
    let boundariesByParent: [NodeID: [MindGroup]]
    /// Valid summaries by parent, fewest members first, so inner brackets are
    /// placed before the ones around them.
    let summariesByParent: [NodeID: [MindGroup]]
    /// The topic each summary shows beyond its bracket. A topic named by two
    /// summaries belongs to the oldest; the other draws its bracket only.
    let summaryTopics: [GroupID: NodeID]
    /// Every topic in `summaryTopics`, left out of its parent's column.
    let summaryTopicSet: Set<NodeID>

    private var result: MapLayout
    /// Topics the placement walk reached in this pass; an update must not remove them.
    private var placed: Set<NodeID> = []
    /// Topics that were visible children of a re-measured topic and no longer
    /// are; their old entries go unless they turned up elsewhere.
    private var orphans: [NodeID] = []

    init(
        graph: GraphState,
        sizes: [NodeID: CGSize],
        callouts: [NodeID: CGSize],
        options: LayoutOptions,
        previous: MapLayout?,
        dirty: Set<NodeID>
    ) {
        self.graph = graph
        self.sizes = sizes
        self.callouts = callouts
        self.options = options
        self.previous = previous
        self.dirty = dirty
        boundariesByParent = Dictionary(
            grouping: graph.groups.values.filter { $0.kind == .boundary && $0.parentNodeID != nil && graph.members(of: $0) != nil },
            by: { $0.parentNodeID! }
        )
        var memberCounts: [GroupID: Int] = [:]
        for group in graph.groups.values where group.kind == .summary && group.parentNodeID != nil {
            if let members = graph.members(of: group) { memberCounts[group.id] = members.count }
        }
        let summaries = graph.groups.values
            .filter { memberCounts[$0.id] != nil }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        var topics: [GroupID: NodeID] = [:]
        var claimed: Set<NodeID> = []
        for group in summaries {
            guard let topicID = group.summaryNodeID, graph.node(topicID)?.parentID == group.parentNodeID,
                  topicID != graph.map.rootNodeID, claimed.insert(topicID).inserted else { continue }
            topics[group.id] = topicID
        }
        summaryTopics = topics
        summaryTopicSet = claimed
        summariesByParent = Dictionary(grouping: summaries, by: { $0.parentNodeID! }).mapValues { groups in
            groups.sorted { (memberCounts[$0.id]!, $0.createdAt, $0.id) < (memberCounts[$1.id]!, $1.createdAt, $1.id) }
        }
        result = previous ?? MapLayout(options: options)
    }

    mutating func run() -> MapLayout {
        guard let rootID = graph.map.rootNodeID, graph.node(rootID) != nil else {
            return MapLayout(options: options)
        }
        result.rootID = rootID
        let floating = graph.floatingTopicIDs
        if let old = previous?.floatingTopicIDs {
            // A floating topic that was deleted or attached is reached from no
            // re-measured parent; it goes unless it was placed in the tree.
            let current = Set(floating)
            orphans.append(contentsOf: old.filter { !current.contains($0) })
        }
        result.floatingTopicIDs = floating
        // Summary topics are reached from no column; each goes unless placed again.
        orphans.append(contentsOf: result.summaries.values.compactMap(\.summaryNodeID))
        measure(from: rootID, rootID: rootID)
        for id in floating {
            measure(from: id, rootID: rootID)
        }
        place(rootID: rootID)
        for id in floating {
            placeFloating(id)
        }
        result.summaries = [:]
        placeSummaries(from: rootID)
        for id in floating {
            placeSummaries(from: id)
        }
        removeOrphans()
        crossLinks()
        boundaryFrames()
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

    /// The caller decides which topics have a bubble: the canvas also gives
    /// one to a topic whose callout is still being typed.
    private func calloutSize(of id: NodeID) -> CGSize? {
        guard let size = callouts[id], size.width > 0, size.height > 0 else { return nil }
        return size
    }

    /// How far the bubble and its spacing stand above the card.
    private func calloutRise(of id: NodeID) -> CGFloat {
        calloutSize(of: id).map { $0.height + options.calloutSpacing } ?? 0
    }

    private func visibleChildren(of id: NodeID, rootID: NodeID) -> [NodeID] {
        guard let node = graph.node(id), !node.isCollapsed else { return [] }
        // The root can only be a child in corrupt data; skipping it keeps the walk finite.
        return graph.childIDs(of: id).filter { $0 != rootID && !summaryTopicSet.contains($0) }
    }

    /// The summary topics shown beside runs of `id`'s children; none when collapsed.
    private func visibleSummaryTopics(of id: NodeID) -> [NodeID] {
        guard let groups = summariesByParent[id], graph.node(id)?.isCollapsed == false else { return [] }
        return groups.compactMap { summaryTopics[$0.id] }
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
            for child in visibleChildren(of: id, rootID: rootID) + visibleSummaryTopics(of: id) where !isReusable(child) {
                stack.append((child, false))
            }
        }
    }

    /// Runs after every visible child has a measure.
    private mutating func measureBranch(_ id: NodeID, rootID: NodeID) {
        let children = visibleChildren(of: id, rootID: rootID)
        var weight = 1
        var block: CGFloat = 0
        let gaps = boundaryGaps(under: id, children: children)
        for summaryTopic in visibleSummaryTopics(of: id) {
            guard let summaryMeasure = result.measures[summaryTopic] else { preconditionFailure("Summary measured after its parent") }
            weight += summaryMeasure.weight
        }
        for (index, child) in children.enumerated() {
            guard let childMeasure = result.measures[child] else { preconditionFailure("Child measured after its parent") }
            weight += childMeasure.weight
            block += childMeasure.extent + gaps[index].above + gaps[index].below
            if index > 0 { block += options.verticalSpacing }
        }
        let isCollapsed = graph.node(id)?.isCollapsed ?? false
        let half = size(of: id).height / 2
        // The children's block is centred on the card; the callout adds room above it only.
        let ascent = max(half + calloutRise(of: id), block / 2)
        let descent = max(half, block / 2)
        let branch = BranchMeasure(
            extent: ascent + descent,
            ascent: ascent,
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
        let rootSlot = slot(of: rootID)
        var stack = placements(for: right, under: rootID, in: rootFrame, slot: rootSlot, side: .right, depth: 1)
        // With both sides in use, reading goes clockwise around the central topic:
        // down the right side, then up the left, so the first left branch sits at
        // the bottom. A left-only map has no right side to continue from, so it
        // reads top to bottom like a right-only one.
        let leftOrder = options.sides == .balanced ? Array(left.reversed()) : left
        stack += placements(for: leftOrder, under: rootID, in: rootFrame, slot: rootSlot, side: .left, depth: 1)
        place(stack)
    }

    /// A floating topic is drawn as a main topic (depth 1) on the right, with
    /// no connector: it has no parent to draw one from.
    private mutating func placeFloating(_ id: NodeID) {
        guard let position = graph.node(id)?.position else { return }
        let nodeSize = size(of: id)
        let frame = CGRect(
            x: position.x - nodeSize.width / 2,
            y: position.y - nodeSize.height / 2,
            width: nodeSize.width,
            height: nodeSize.height
        )
        // It may have had one in the previous layout, before it was detached.
        result.connectors[id] = nil
        guard write(id, frame: frame, side: .right, depth: 1) else { return }
        place(placements(for: measure(of: id).visibleChildren, under: id, in: frame, slot: slot(of: id), side: .right, depth: 2))
    }

    private mutating func place(_ start: [Placement]) {
        var stack = start
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
                under: next.id,
                in: frame,
                slot: slot(of: next.id),
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
            calloutFrame: calloutFrame(of: id, card: frame, side: side),
            side: side,
            depth: depth,
            hiddenDescendantCount: measure(of: id).hiddenDescendantCount
        )
        return true
    }

    /// Centred above the card, pulled back so it never passes the card's edge
    /// that faces the parent (the central topic and floating topics have none).
    private func calloutFrame(of id: NodeID, card: CGRect, side: LayoutSide) -> CGRect? {
        guard let bubble = calloutSize(of: id) else { return nil }
        var minX = card.midX - bubble.width / 2
        switch side {
        case .right: minX = max(minX, card.minX)
        case .left: minX = min(minX, card.maxX - bubble.width)
        case .center: break
        }
        return CGRect(
            x: minX,
            y: card.minY - options.calloutSpacing - bubble.height,
            width: bubble.width,
            height: bubble.height
        )
    }

    /// The card and its bubble: what children have to stay clear of.
    private func slot(of id: NodeID) -> CGRect {
        guard let node = result.nodes[id] else { preconditionFailure("Slot of a topic that was not placed") }
        return node.calloutFrame.map { node.frame.union($0) } ?? node.frame
    }

    private func measure(of id: NodeID) -> BranchMeasure {
        guard let measure = result.measures[id] else { preconditionFailure("Placing a topic that was not measured") }
        return measure
    }

    /// Stacks the children's bands top to bottom, centered on the parent.
    private func placements(
        for children: [NodeID],
        under parentID: NodeID,
        in parentFrame: CGRect,
        slot parentSlot: CGRect,
        side: LayoutSide,
        depth: Int
    ) -> [Placement] {
        guard !children.isEmpty else { return [] }
        let measures = children.map { measure(of: $0) }
        let gaps = boundaryGaps(under: parentID, children: children)
        let block = zip(measures, gaps).reduce(0) { $0 + $1.0.extent + $1.1.above + $1.1.below }
            + options.verticalSpacing * CGFloat(children.count - 1)
        let anchorX = side == .left
            ? parentSlot.minX - options.horizontalSpacing
            : parentSlot.maxX + options.horizontalSpacing
        var top = parentFrame.midY - block / 2
        var list: [Placement] = []
        list.reserveCapacity(children.count)
        for (index, (child, childMeasure)) in zip(children, measures).enumerated() {
            top += gaps[index].above
            list.append(Placement(
                id: child,
                side: side,
                depth: depth,
                anchorX: anchorX,
                centerY: top + childMeasure.ascent,
                parentFrame: parentFrame
            ))
            top += childMeasure.extent + gaps[index].below + options.verticalSpacing
        }
        return list
    }

    /// Room each child needs above and below its band for the boundaries it
    /// starts or ends. Uses the topmost and bottommost member in `children`'
    /// order, so the title room stays on top when the left side is reversed.
    /// A summary branch taller than its run adds half the difference on each
    /// side of the run.
    private func boundaryGaps(under parentID: NodeID, children: [NodeID]) -> [(above: CGFloat, below: CGFloat)] {
        var gaps = Array(repeating: (above: CGFloat(0), below: CGFloat(0)), count: children.count)
        guard !children.isEmpty else { return gaps }
        let boundaries = boundariesByParent[parentID] ?? []
        let summaries = graph.node(parentID)?.isCollapsed == false ? summariesByParent[parentID] ?? [] : []
        guard !boundaries.isEmpty || !summaries.isEmpty else { return gaps }
        let index = Dictionary(children.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        for boundary in boundaries {
            guard let first = boundary.firstNodeID.flatMap({ index[$0] }),
                  let last = boundary.lastNodeID.flatMap({ index[$0] }) else { continue }
            gaps[min(first, last)].above += options.boundaryPadding + titleRoom(of: boundary)
            gaps[max(first, last)].below += options.boundaryPadding
        }
        for summary in summaries {
            guard let topicID = summaryTopics[summary.id], let topic = result.measures[topicID],
                  let first = summary.firstNodeID.flatMap({ index[$0] }),
                  let last = summary.lastNodeID.flatMap({ index[$0] }) else { continue }
            let run = min(first, last)...max(first, last)
            let height = run.reduce(CGFloat(0)) { total, member in
                total + (result.measures[children[member]]?.extent ?? 0)
            } + options.verticalSpacing * CGFloat(run.count - 1)
            guard topic.extent > height else { continue }
            let extra = (topic.extent - height) / 2
            gaps[run.lowerBound].above += extra
            gaps[run.upperBound].below += extra
        }
        return gaps
    }

    private func titleRoom(of boundary: MindGroup) -> CGFloat {
        boundary.title == nil ? 0 : options.boundaryTitleHeight
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
    private mutating func crossLinks() {
        var paths: [EdgeID: EdgePath] = [:]
        var rerouted: Set<EdgeID> = []
        var counts: [NodeID: Int] = [:]
        for edge in graph.edges.values where edge.sourceNodeID != edge.targetNodeID {
            // Hiding a connection inside a collapsed branch would lose it from
            // view entirely; its visible ancestor stands in for it.
            guard let sourceID = visibleStandIn(for: edge.sourceNodeID),
                  let targetID = visibleStandIn(for: edge.targetNodeID) else { continue }
            var badged: Set<NodeID> = []
            if sourceID != edge.sourceNodeID { badged.insert(sourceID) }
            if targetID != edge.targetNodeID { badged.insert(targetID) }
            for id in badged { counts[id, default: 0] += 1 }
            guard sourceID != targetID,
                  let source = result.nodes[sourceID]?.frame,
                  let target = result.nodes[targetID]?.frame else { continue }
            if sourceID != edge.sourceNodeID || targetID != edge.targetNodeID { rerouted.insert(edge.id) }
            let forward = target.midX >= source.midX
            paths[edge.id] = .horizontal(
                from: CGPoint(x: forward ? source.maxX : source.minX, y: source.midY),
                to: CGPoint(x: forward ? target.minX : target.maxX, y: target.midY)
            )
        }
        result.crossLinks = paths
        result.reroutedCrossLinks = rerouted
        result.hiddenCrossLinkCounts = counts
    }

    /// The topic itself when laid out, else its nearest laid-out ancestor;
    /// nil for a topic outside the tree (an orphan still syncing).
    private func visibleStandIn(for id: NodeID) -> NodeID? {
        var current: NodeID? = id
        var steps = 0
        while let nodeID = current, steps <= graph.nodes.count {
            if result.nodes[nodeID] != nil { return nodeID }
            current = graph.node(nodeID)?.parentID
            steps += 1
        }
        return nil
    }

    /// Recomputed on every pass, like cross-links: a map has few boundaries and
    /// a frame depends on every topic below its members.
    private mutating func boundaryFrames() {
        struct Pending {
            let group: MindGroup
            let members: [NodeID]
            let depth: Int
        }
        var pending: [Pending] = []
        for (parentID, boundaries) in boundariesByParent {
            // Hidden with its parent: a collapsed or hidden parent shows no members.
            guard let parent = result.nodes[parentID], let parentMeasure = result.measures[parentID] else { continue }
            let visible = Set(parentMeasure.visibleChildren)
            for boundary in boundaries {
                guard var members = graph.members(of: boundary)?.filter({ visible.contains($0) && result.nodes[$0] != nil }),
                      let firstSide = members.first.flatMap({ result.nodes[$0]?.side }) else { continue }
                // A run split by the central topic frames only the first member's side.
                members = members.filter { result.nodes[$0]?.side == firstSide }
                pending.append(Pending(group: boundary, members: members, depth: parent.depth))
            }
        }
        // Inner boundaries first, so an outer frame can take them in.
        pending.sort { $0.depth != $1.depth ? $0.depth > $1.depth : $0.members.count < $1.members.count }
        var frames: [GroupID: CGRect] = [:]
        var done: [(group: MindGroup, members: Set<NodeID>)] = []
        for item in pending {
            var union: CGRect?
            for member in item.members {
                let frame = branchFrame(of: member)
                union = union?.union(frame) ?? frame
            }
            guard var frame = union else { continue }
            let members = Set(item.members)
            for inner in done where isInside(inner.group, members: inner.members, of: item.group, members: members) {
                if let innerFrame = frames[inner.group.id] { frame = frame.union(innerFrame) }
            }
            frame = frame.insetBy(dx: -options.boundaryPadding, dy: -options.boundaryPadding)
            let title = titleRoom(of: item.group)
            frame.origin.y -= title
            frame.size.height += title
            frames[item.group.id] = frame
            done.append((item.group, members))
        }
        result.boundaries = frames
    }

    /// Every visible card and callout in the branch, with the summaries
    /// placed inside it.
    private func branchFrame(of id: NodeID) -> CGRect {
        var union: CGRect?
        var stack = [id]
        while let next = stack.popLast() {
            guard let node = result.nodes[next] else { continue }
            let frame = node.calloutFrame.map { node.frame.union($0) } ?? node.frame
            union = union?.union(frame) ?? frame
            stack += result.measures[next]?.visibleChildren ?? []
            for summary in summariesByParent[next] ?? [] {
                guard let bracket = result.summaries[summary.id] else { continue }
                union = union?.union(bracket.frame) ?? bracket.frame
                if let topicID = bracket.summaryNodeID { stack.append(topicID) }
            }
        }
        return union ?? .zero
    }

    // MARK: Summaries

    private enum SummaryStep {
        case visit(NodeID)
        case place(MindGroup)
    }

    /// Bottom-up over the placed tree: a node's summaries are placed after
    /// every branch below it is final, inner ones first, and each summary
    /// topic's own branch is visited before the next summary beside it.
    private mutating func placeSummaries(from start: NodeID) {
        var stack: [SummaryStep] = [.visit(start)]
        var done: [NodeID: [(members: Set<NodeID>, frame: CGRect)]] = [:]
        while let step = stack.popLast() {
            switch step {
            case .visit(let id):
                guard result.nodes[id] != nil, let measure = result.measures[id] else { continue }
                var steps = measure.visibleChildren.map { SummaryStep.visit($0) }
                if graph.node(id)?.isCollapsed == false {
                    for summary in summariesByParent[id] ?? [] {
                        steps.append(.place(summary))
                        if let topicID = summaryTopics[summary.id] { steps.append(.visit(topicID)) }
                    }
                }
                stack += steps.reversed()
            case .place(let summary):
                guard let parentID = summary.parentNodeID,
                      let placed = placeSummary(summary, inner: done[parentID] ?? []) else { continue }
                done[parentID, default: []].append(placed)
            }
        }
    }

    /// Returns the members and everything the summary drew, for the summaries around it.
    private mutating func placeSummary(
        _ summary: MindGroup,
        inner: [(members: Set<NodeID>, frame: CGRect)]
    ) -> (members: Set<NodeID>, frame: CGRect)? {
        guard let parentID = summary.parentNodeID, let parent = result.nodes[parentID],
              let visible = result.measures[parentID].map({ Set($0.visibleChildren) }),
              var members = graph.members(of: summary)?.filter({ visible.contains($0) && result.nodes[$0] != nil }),
              let side = members.first.flatMap({ result.nodes[$0]?.side }) else { return nil }
        // A run split by the central topic brackets only the first member's side.
        members = members.filter { result.nodes[$0]?.side == side }
        let memberSet = Set(members)
        var union = members.map(branchFrame(of:)).reduce(CGRect.null) { $0.union($1) }
        for item in inner where item.members.isSubset(of: memberSet) {
            union = union.union(item.frame)
        }
        let width = options.summaryBracketWidth
        let backX = side == .left ? union.minX - options.summaryBracketGap - width : union.maxX + options.summaryBracketGap
        let bracket = SummaryBracket(
            frame: CGRect(x: backX, y: union.minY, width: width, height: union.height),
            side: side,
            summaryNodeID: summaryTopics[summary.id]
        )
        result.summaries[summary.id] = bracket
        var drawn = union.union(bracket.frame)
        if let topicID = bracket.summaryNodeID, let topicMeasure = result.measures[topicID] {
            let tip = bracket.tip
            place([Placement(
                id: topicID,
                side: side,
                depth: parent.depth + 1,
                anchorX: side == .left ? tip.x - options.horizontalSpacing : tip.x + options.horizontalSpacing,
                centerY: tip.y + topicMeasure.ascent - topicMeasure.extent / 2,
                parentFrame: parent.frame
            )])
            // The bracket stands for the line from the parent.
            result.connectors[topicID] = nil
            drawn = drawn.union(branchFrame(of: topicID))
        }
        return (memberSet, drawn)
    }

    /// Nested in a run under the same parent, or under one of the members.
    private func isInside(_ inner: MindGroup, members innerMembers: Set<NodeID>, of outer: MindGroup, members: Set<NodeID>) -> Bool {
        if inner.parentNodeID == outer.parentNodeID { return innerMembers.isSubset(of: members) }
        var current = inner.parentNodeID
        var steps = 0
        while let id = current, steps <= graph.nodes.count {
            if members.contains(id) { return true }
            current = graph.node(id)?.parentID
            steps += 1
        }
        return false
    }

    private func bounds() -> CGRect {
        var union: CGRect?
        for node in result.nodes.values {
            let frame = node.calloutFrame.map { node.frame.union($0) } ?? node.frame
            union = union?.union(frame) ?? frame
        }
        for frame in result.boundaries.values {
            union = union?.union(frame) ?? frame
        }
        for bracket in result.summaries.values {
            union = union?.union(bracket.frame) ?? bracket.frame
        }
        return union ?? .zero
    }
}
