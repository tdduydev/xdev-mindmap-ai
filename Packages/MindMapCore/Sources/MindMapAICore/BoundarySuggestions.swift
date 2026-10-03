import Foundation
import MindMapDomain
import MindMapGraph

// Summarize Boundary and Suggest Groups (MM-37, docs/node-organization.md
// *AI*). Both answers are previews held apart from the graph, like topic and
// tag suggestions; Accept is one command and one undo step.

/// One child as the model sees it, by a short reference such as "t1".
public struct GroupSuggestionTopic: Hashable, Sendable {
    public let reference: String
    public let nodeID: NodeID
    public let title: String

    public init(reference: String, nodeID: NodeID, title: String) {
        self.reference = reference
        self.nodeID = nodeID
        self.title = title
    }
}

/// The children of one topic, for the model to sort into groups.
public struct SuggestGroupsRequest: Hashable, Sendable {
    public var mapTitle: String
    public var parentID: NodeID
    public var parentTitle: String
    /// Ancestors of the parent, the central topic first, for meaning.
    public var path: [String]
    public var children: [GroupSuggestionTopic]
    public var language: AILanguage
    public var userLocaleIdentifier: String

    public init(
        mapTitle: String,
        parentID: NodeID,
        parentTitle: String,
        path: [String] = [],
        children: [GroupSuggestionTopic],
        language: AILanguage,
        userLocaleIdentifier: String
    ) {
        self.mapTitle = mapTitle
        self.parentID = parentID
        self.parentTitle = parentTitle
        self.path = path
        self.children = Array(children.prefix(AIProposalLimits.maximumGroupedChildren))
        self.language = language
        self.userLocaleIdentifier = userLocaleIdentifier
    }

    /// Fewer children than this leave nothing worth grouping.
    public static let minimumChildren = 4

    /// Nil when the topic is gone or has fewer than `minimumChildren` children
    /// that a boundary may span (summary topics are left out).
    public static func make(
        for parentID: NodeID,
        in state: GraphState,
        language: AILanguage,
        userLocaleIdentifier: String
    ) -> SuggestGroupsRequest? {
        guard let parent = state.node(parentID) else { return nil }
        let ids = state.runSiblingIDs(of: parentID)
        guard ids.count >= minimumChildren else { return nil }
        let children = ids.prefix(AIProposalLimits.maximumGroupedChildren).enumerated().compactMap { index, id in
            state.node(id).map { GroupSuggestionTopic(reference: "t\(index + 1)", nodeID: id, title: AITextLimit.shorten($0.title)) }
        }
        return SuggestGroupsRequest(
            mapTitle: AITextLimit.shorten(state.map.title),
            parentID: parentID,
            parentTitle: AITextLimit.shorten(parent.title),
            path: state.ancestors(of: parentID).reversed().prefix(3).compactMap { state.node($0).map { AITextLimit.shorten($0.title) } },
            children: children,
            language: language,
            userLocaleIdentifier: userLocaleIdentifier
        )
    }

    public func child(reference: String) -> GroupSuggestionTopic? {
        children.first { $0.reference == reference }
    }
}

/// Groups of children with a title each, checked: known children only, a
/// child in one group at most, two or more children per group.
public struct AIGroupSuggestions: Hashable, Sendable {
    public struct Group: Hashable, Sendable {
        public let title: String
        /// In the order the children are in the map.
        public let nodeIDs: [NodeID]

        public init(title: String, nodeIDs: [NodeID]) {
            self.title = title
            self.nodeIDs = nodeIDs
        }
    }

    public var parentID: NodeID
    public var groups: [Group]

    public init(parentID: NodeID, groups: [Group]) {
        self.parentID = parentID
        self.groups = groups
    }

    /// What the model wrote, made safe to show. A bad reference, a repeated
    /// child, a group of one or a group with no title is dropped rather than
    /// failing the whole answer; nothing usable left is `ProposalError.empty`.
    public static func checked(_ answer: [(title: String, references: [String])], for request: SuggestGroupsRequest) throws -> AIGroupSuggestions {
        let order = Dictionary(request.children.enumerated().map { ($1.nodeID, $0) }, uniquingKeysWith: { first, _ in first })
        var used: Set<NodeID> = []
        var groups: [Group] = []
        for item in answer where groups.count < AIProposalLimits.maximumSuggestedGroups {
            guard let title = AITextLimit.boundaryTitle(item.title) else { continue }
            var ids: [NodeID] = []
            for reference in item.references {
                guard let child = request.child(reference: reference.trimmingCharacters(in: .whitespaces)),
                      !used.contains(child.nodeID), !ids.contains(child.nodeID) else { continue }
                ids.append(child.nodeID)
            }
            guard ids.count >= 2 else { continue }
            used.formUnion(ids)
            groups.append(Group(title: title, nodeIDs: ids.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }))
        }
        guard !groups.isEmpty else { throw ProposalError.empty }
        return AIGroupSuggestions(parentID: request.parentID, groups: groups)
    }
}

/// A boundary's members and their branches, for a short title.
public struct SummarizeBoundaryRequest: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        /// 0 for a member, 1 for its child, and so on.
        public let depth: Int
        public let title: String

        public init(depth: Int, title: String) {
            self.depth = depth
            self.title = title
        }
    }

    public var mapTitle: String
    public var groupID: GroupID
    public var parentTitle: String
    public var currentTitle: String?
    public var outline: [Line]
    public var omittedCount: Int
    public var language: AILanguage
    public var userLocaleIdentifier: String

    public init(
        mapTitle: String,
        groupID: GroupID,
        parentTitle: String,
        currentTitle: String? = nil,
        outline: [Line],
        omittedCount: Int = 0,
        language: AILanguage,
        userLocaleIdentifier: String
    ) {
        self.mapTitle = mapTitle
        self.groupID = groupID
        self.parentTitle = parentTitle
        self.currentTitle = currentTitle
        self.outline = outline
        self.omittedCount = omittedCount
        self.language = language
        self.userLocaleIdentifier = userLocaleIdentifier
    }

    /// Lines past this many are counted, not sent: a title needs the gist,
    /// and the on-device context is small.
    public static let maximumLines = 60

    /// Nil when the boundary is gone or has no member.
    public static func make(
        for groupID: GroupID,
        in state: GraphState,
        language: AILanguage,
        userLocaleIdentifier: String
    ) -> SummarizeBoundaryRequest? {
        guard let group = state.group(groupID), group.kind == .boundary, let members = state.members(of: group),
              !members.isEmpty, let parentID = group.parentNodeID, let parent = state.node(parentID) else { return nil }
        var lines: [Line] = []
        var omitted = 0
        // Pre-order with an explicit stack, members in display order.
        var stack: [(NodeID, Int)] = members.reversed().map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            guard let node = state.node(id) else { continue }
            if lines.count < maximumLines {
                lines.append(Line(depth: depth, title: AITextLimit.shorten(node.title)))
            } else {
                omitted += 1
            }
            stack += state.childIDs(of: id).reversed().map { ($0, depth + 1) }
        }
        return SummarizeBoundaryRequest(
            mapTitle: AITextLimit.shorten(state.map.title),
            groupID: groupID,
            parentTitle: AITextLimit.shorten(parent.title),
            currentTitle: group.title,
            outline: lines,
            omittedCount: omitted,
            language: language,
            userLocaleIdentifier: userLocaleIdentifier
        )
    }
}

/// A suggested title for one boundary.
public struct AIBoundaryTitle: Hashable, Sendable {
    public var groupID: GroupID
    public var title: String

    public init(groupID: GroupID, title: String) {
        self.groupID = groupID
        self.title = title
    }

    /// The model's text as a title: one line, no quotes, capped.
    public static func checked(_ text: String, for request: SummarizeBoundaryRequest) throws -> AIBoundaryTitle {
        guard let title = AITextLimit.boundaryTitle(text) else { throw ProposalError.empty }
        return AIBoundaryTitle(groupID: request.groupID, title: title)
    }
}

/// Suggested boundaries or a suggested boundary title while the person
/// decides. Nothing reaches the map before Accept; the canvas draws
/// `preview(in:)` with the AI style.
public struct BoundarySuggestionState: Hashable, Sendable {
    public struct Group: Identifiable, Hashable, Sendable {
        /// The boundary's ID if accepted, so the preview and the map agree.
        public let id: GroupID
        public var title: String
        public let nodeIDs: [NodeID]
    }

    public enum Kind: Hashable, Sendable {
        /// Suggest Groups under `parentID`.
        case groups(parentID: NodeID)
        /// Summarize Boundary: `groups` holds the one boundary, by its own ID.
        case title
    }

    public let kind: Kind
    public private(set) var groups: [Group]

    public init(_ result: AIGroupSuggestions) {
        kind = .groups(parentID: result.parentID)
        groups = result.groups.map { Group(id: GroupID(), title: $0.title, nodeIDs: $0.nodeIDs) }
    }

    public init(_ result: AIBoundaryTitle) {
        kind = .title
        groups = [Group(id: result.groupID, title: result.title, nodeIDs: [])]
    }

    public var isEmpty: Bool { groups.isEmpty }

    /// An edit before Accept. A title that cleans to nothing leaves it as it was.
    public mutating func rename(_ id: GroupID, to title: String) {
        guard let title = AITextLimit.boundaryTitle(title), let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].title = title
    }

    public mutating func remove(_ id: GroupID) {
        groups.removeAll { $0.id == id }
    }

    /// Drops what the map no longer allows: a boundary deleted meanwhile, or
    /// children that left the parent (a group left with one is dropped).
    public mutating func prune(in state: GraphState) {
        switch kind {
        case .title:
            groups.removeAll { state.group($0.id)?.kind != .boundary }
        case .groups(let parentID):
            let children = Set(state.runSiblingIDs(of: parentID))
            groups = groups.compactMap { group in
                let kept = group.nodeIDs.filter(children.contains)
                return kept.count >= 2 ? Group(id: group.id, title: group.title, nodeIDs: kept) : nil
            }
        }
    }

    /// How many children Accept would move, for the suggestion bar.
    public func movedCount(in state: GraphState) -> Int {
        guard case .groups(let parentID) = kind else { return 0 }
        let current = state.runSiblingIDs(of: parentID)
        let target = order(of: current)
        return zip(current, target).filter { $0 != $1 }.count
    }

    /// Accept as one command: for groups, the children reordered so each
    /// group's members sit together (relative order kept), then one boundary
    /// per group with `origin = ai`; a group that would cross an existing
    /// boundary is left out. For a title, the rename. Dry-run on a copy.
    public func command(in engine: GraphEngine) throws -> BatchCommand {
        var probe = engine
        var commands: [any GraphCommand] = []
        switch kind {
        case .title:
            guard let group = groups.first, engine.state.group(group.id) != nil else { throw ProposalError.anchorNotFound }
            commands.append(UpdateGroupCommand(groupID: group.id, title: .set(group.title)))
            do { try probe.execute(BatchCommand(commands)) } catch { throw ProposalError.rejectedByGraph }
        case .groups(let parentID):
            guard engine.state.node(parentID) != nil, !groups.isEmpty else { throw ProposalError.anchorNotFound }
            let current = engine.state.runSiblingIDs(of: parentID)
            let target = order(of: current)
            if let start = target.indices.first(where: { current[$0] != target[$0] }) {
                for id in target[start...] {
                    commands.append(ReparentNodeCommand(nodeID: id, newParentID: parentID, placement: .last))
                }
                do { try probe.execute(BatchCommand(commands)) } catch { throw ProposalError.rejectedByGraph }
            }
            var added = 0
            for group in groups {
                guard let first = group.nodeIDs.first, let last = group.nodeIDs.last else { continue }
                let add = AddGroupCommand(groupID: group.id, from: first, to: last, title: group.title, origin: .ai)
                guard (try? probe.execute(add)) != nil else { continue }
                commands.append(add)
                added += 1
            }
            guard added > 0 else { throw ProposalError.rejectedByGraph }
        }
        return BatchCommand(commands)
    }

    /// The map as it would be after Accept, and the boundaries to draw in the
    /// AI style; nil when Accept would fail.
    public func preview(in engine: GraphEngine) -> (state: GraphState, boundaries: Set<GroupID>)? {
        guard let command = try? command(in: engine) else { return nil }
        var probe = engine
        guard (try? probe.execute(command)) != nil else { return nil }
        let drawn = Set(groups.map(\.id)).filter { probe.state.group($0) != nil }
        return (probe.state, drawn)
    }

    /// The children with each group's members moved up to its first member.
    private func order(of children: [NodeID]) -> [NodeID] {
        var groupOf: [NodeID: Int] = [:]
        for (index, group) in groups.enumerated() {
            for id in group.nodeIDs { groupOf[id] = index }
        }
        let members = groups.map { group in children.filter { groupOf[$0] != nil && group.nodeIDs.contains($0) } }
        var emitted: Set<Int> = []
        var result: [NodeID] = []
        for id in children {
            guard let index = groupOf[id] else {
                result.append(id)
                continue
            }
            if emitted.insert(index).inserted { result += members[index] }
        }
        return result
    }
}

/// Shortening shared by the boundary requests.
enum AITextLimit {
    /// As `AIContextBuilder` does for titles.
    static let maximumTitleLength = 80
    /// A boundary title is a short label for its capsule.
    static let maximumBoundaryTitleLength = 60

    static func shorten(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count <= maximumTitleLength ? line : String(line.prefix(maximumTitleLength - 1)) + "…"
    }

    /// One line without wrapping quotes or a trailing full stop; nil if blank.
    static func boundaryTitle(_ text: String) -> String? {
        var line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"“”'")))
        if line.hasSuffix(".") { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return line.count <= maximumBoundaryTitleLength ? line : String(line.prefix(maximumBoundaryTitleLength - 1)) + "…"
    }
}
