import Foundation
import MindMapDomain
import MindMapGraph

/// Picks the part of a map an AI request needs: the focus topic, its
/// ancestors, a bounded set of descendants, its siblings and cross-links, the
/// map title and the output language.
///
/// The on-device model has a small context window and Vietnamese is costly in
/// tokens, so nearer topics win: children before siblings, siblings before
/// grandchildren, and the descendant walk stops at the first level that does
/// not fit instead of skipping around, which keeps the outline a true prefix
/// of the branch.
public struct AIContextBuilder: Sendable {
    public var limits: AIContextLimits

    public init(limits: AIContextLimits = AIContextLimits()) {
        self.limits = limits
    }

    /// Throws `GraphError.nodeNotFound` when the focus is not in the map.
    public func context(
        for focusID: NodeID,
        in state: GraphState,
        language: AILanguage,
        userLocaleIdentifier: String
    ) throws -> AIContext {
        guard let focusNode = state.node(focusID) else { throw GraphError.nodeNotFound(focusID) }
        var budget = TokenBudget(limit: limits.tokenBudget)

        // The map title and the focus always go in: without them the request
        // has no subject.
        let mapTitle = shorten(state.map.title, to: limits.maximumTitleLength)
        budget.spend(TokenEstimator.estimateLine(mapTitle))
        let focus = topic(focusNode, depth: 0, includeNote: true)
        budget.spend(cost(of: focus))

        let ancestors = chooseAncestors(of: focusID, in: state, budget: &budget)

        var included: Set<NodeID> = []
        var levels = descendantLevels(of: focusID, in: state)
        var descendantWalkStopped = false

        func includeLevel(_ ids: [NodeID]) {
            for id in ids {
                guard !descendantWalkStopped else { return }
                guard included.count < limits.maximumDescendants,
                      let node = state.node(id),
                      let parentID = node.parentID, parentID == focusID || included.contains(parentID),
                      budget.canAfford(cost(of: topic(node, depth: 1, includeNote: false)))
                else {
                    descendantWalkStopped = true
                    return
                }
                budget.spend(cost(of: topic(node, depth: 1, includeNote: false)))
                included.insert(id)
            }
        }

        if !levels.isEmpty { includeLevel(levels.removeFirst()) }

        var siblings: [ContextTopic] = []
        for id in state.siblings(of: focusID).prefix(limits.maximumSiblings) {
            guard let node = state.node(id) else { continue }
            let sibling = topic(node, depth: 0, includeNote: false)
            guard budget.canAfford(cost(of: sibling)) else { break }
            budget.spend(cost(of: sibling))
            siblings.append(sibling)
        }

        while !levels.isEmpty, !descendantWalkStopped {
            includeLevel(levels.removeFirst())
        }

        let linkedTopics = chooseLinkedTopics(of: focusID, in: state, budget: &budget)

        let allDescendants = state.descendants(of: focusID)
        let depths = relativeDepths(of: allDescendants, under: focusID, in: state)
        let descendants = allDescendants.compactMap { id -> ContextTopic? in
            guard included.contains(id), let node = state.node(id) else { return nil }
            return topic(node, depth: depths[id] ?? 1, includeNote: false)
        }

        return AIContext(
            mapID: state.map.id,
            mapTitle: mapTitle,
            focus: focus,
            ancestors: ancestors,
            siblings: siblings,
            descendants: descendants,
            linkedTopics: linkedTopics,
            omittedDescendantCount: allDescendants.count - descendants.count,
            language: language,
            userLocaleIdentifier: userLocaleIdentifier,
            estimatedTokens: budget.spent
        )
    }

    /// The whole branch under the focus split into contexts that each fit the
    /// budget, for summarizing a branch too large for one request: summarize
    /// each chunk, then combine the partial summaries in one more request.
    ///
    /// Each chunk keeps the map title, the focus and its ancestors, and carries
    /// no siblings or cross-links. A branch that fits returns one context.
    public func chunkContexts(
        for focusID: NodeID,
        in state: GraphState,
        language: AILanguage,
        userLocaleIdentifier: String
    ) throws -> [AIContext] {
        let base = try context(for: focusID, in: state, language: language, userLocaleIdentifier: userLocaleIdentifier)

        var headerCost = TokenEstimator.estimateLine(base.mapTitle) + cost(of: base.focus)
        headerCost += base.ancestors.reduce(0) { $0 + cost(of: $1) }
        // A deep ancestor chain must not leave chunks with no room at all.
        let chunkBudget = max(64, limits.tokenBudget - headerCost)

        let allDescendants = state.descendants(of: focusID)
        guard !allDescendants.isEmpty else { return [base] }
        let depths = relativeDepths(of: allDescendants, under: focusID, in: state)

        var chunks: [[ContextTopic]] = []
        var current: [ContextTopic] = []
        var currentCost = 0
        for id in allDescendants {
            guard let node = state.node(id) else { continue }
            let item = topic(node, depth: depths[id] ?? 1, includeNote: false)
            let itemCost = cost(of: item)
            if !current.isEmpty, currentCost + itemCost > chunkBudget {
                chunks.append(current)
                current = []
                currentCost = 0
            }
            current.append(item)
            currentCost += itemCost
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks.map { chunk in
            AIContext(
                mapID: base.mapID,
                mapTitle: base.mapTitle,
                focus: base.focus,
                ancestors: base.ancestors,
                descendants: chunk,
                language: language,
                userLocaleIdentifier: userLocaleIdentifier,
                estimatedTokens: headerCost + chunk.reduce(0) { $0 + cost(of: $1) }
            )
        }
    }

    // MARK: Parts

    private func chooseAncestors(of id: NodeID, in state: GraphState, budget: inout TokenBudget) -> [ContextTopic] {
        let chain = state.ancestors(of: id)
        var picked: [(id: NodeID, depth: Int)] = chain.enumerated().map { (id: $0.element, depth: -($0.offset + 1)) }
        if picked.count > limits.maximumAncestors, let root = picked.last {
            // The root names the whole map, so it outranks the middle of a long path.
            picked = Array(picked.prefix(limits.maximumAncestors - 1)) + [root]
        }

        var result: [ContextTopic] = []
        for entry in picked {
            guard let node = state.node(entry.id) else { continue }
            let ancestor = topic(node, depth: entry.depth, includeNote: false)
            guard budget.canAfford(cost(of: ancestor)) else { break }
            budget.spend(cost(of: ancestor))
            result.append(ancestor)
        }
        return result.reversed()
    }

    private func chooseLinkedTopics(of id: NodeID, in state: GraphState, budget: inout TokenBudget) -> [ContextTopic] {
        // Edges come from a dictionary; sorting keeps the prompt identical for
        // identical maps.
        let edges = state.edges(touching: id).sorted { $0.id < $1.id }
        var seen: Set<NodeID> = [id]
        var result: [ContextTopic] = []
        for edge in edges {
            guard result.count < limits.maximumLinkedTopics else { break }
            let otherID = edge.sourceNodeID == id ? edge.targetNodeID : edge.sourceNodeID
            guard seen.insert(otherID).inserted, let node = state.node(otherID) else { continue }
            let linked = topic(node, depth: 0, includeNote: false)
            guard budget.canAfford(cost(of: linked)) else { break }
            budget.spend(cost(of: linked))
            result.append(linked)
        }
        return result
    }

    /// Descendants grouped by level, 1 to `maximumDepth`, in display order.
    private func descendantLevels(of id: NodeID, in state: GraphState) -> [[NodeID]] {
        var levels: [[NodeID]] = []
        var frontier = state.childIDs(of: id)
        while !frontier.isEmpty, levels.count < limits.maximumDepth {
            levels.append(frontier)
            frontier = frontier.flatMap { state.childIDs(of: $0) }
        }
        return levels
    }

    /// Depth below `rootID` for a pre-order list, where parents come first.
    private func relativeDepths(of preorder: [NodeID], under rootID: NodeID, in state: GraphState) -> [NodeID: Int] {
        var depths: [NodeID: Int] = [rootID: 0]
        for id in preorder {
            let parentDepth = state.node(id)?.parentID.flatMap { depths[$0] } ?? 0
            depths[id] = parentDepth + 1
        }
        return depths
    }

    private func topic(_ node: MindNode, depth: Int, includeNote: Bool) -> ContextTopic {
        var note: String?
        if includeNote, let text = node.note {
            let shortened = shorten(text, to: limits.maximumNoteLength)
            note = shortened.isEmpty ? nil : shortened
        }
        return ContextTopic(
            nodeID: node.id,
            parentID: node.parentID,
            title: shorten(node.title, to: limits.maximumTitleLength),
            note: note,
            depth: depth
        )
    }

    private func cost(of topic: ContextTopic) -> Int {
        TokenEstimator.estimateLine(topic.title) + (topic.note.map(TokenEstimator.estimateLine) ?? 0)
    }

    /// One line of trimmed text, cut with an ellipsis when too long.
    private func shorten(_ text: String, to limit: Int) -> String {
        let oneLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard oneLine.count > limit, limit > 1 else { return oneLine }
        return String(oneLine.prefix(limit - 1)) + "…"
    }
}

private struct TokenBudget {
    let limit: Int
    private(set) var spent = 0

    init(limit: Int) {
        self.limit = limit
    }

    func canAfford(_ cost: Int) -> Bool {
        spent + cost <= limit
    }

    mutating func spend(_ cost: Int) {
        spent += cost
    }
}
