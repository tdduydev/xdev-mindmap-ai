import Foundation
import MindMapDomain
import MindMapGraph

/// What the filter bar asks for (MM-36). View state of one window: never a
/// command, never stored in the map, never synced, so a filter on the Mac
/// cannot hide topics on the iPad.
///
/// Criteria of different kinds must all hold; within one kind any choice
/// holds (a topic due today or overdue), except tags, where `tagMatch` decides.
public struct MapFilter: Hashable, Sendable, Codable {
    public enum TagMatch: String, Hashable, Sendable, Codable, CaseIterable {
        case any
        case all
    }

    public enum TaskChoice: String, Hashable, Sendable, Codable, CaseIterable {
        case open
        case done
        case notATask
    }

    public enum DueChoice: String, Hashable, Sendable, Codable, CaseIterable {
        case overdue
        case today
        case nextSevenDays
        case noDate
    }

    public var tagIDs: Set<TagID> = []
    public var tagMatch: TagMatch = .any
    /// Levels as shown (`TaskPriority.level`), so a stored 5 counts as low.
    public var priorities: Set<TaskPriority> = []
    public var tasks: Set<TaskChoice> = []
    public var due: Set<DueChoice> = []
    public var origins: Set<NodeOrigin> = []
    /// Folded like Find; a `#name` word asks for a tag, as in Find.
    public var text = ""

    public init() {}

    public var isActive: Bool {
        !tagIDs.isEmpty || !priorities.isEmpty || !tasks.isEmpty || !due.isEmpty || !origins.isEmpty
            || !SearchQuery(text).isEmpty
    }

    /// Topics that meet every criterion, any branch, collapsed or not.
    public func matches(in state: GraphState, today: CalendarDay) -> Set<NodeID> {
        let textMatches = SearchQuery(text).isEmpty ? nil : Set(MapFind.matches(SearchQuery(text), in: state))
        var tagsByNode: [NodeID: Set<TagID>] = [:]
        if !tagIDs.isEmpty {
            // Links whose tag is missing (sync order) match nothing.
            for link in state.nodeTags.values where state.tags[link.tagID] != nil {
                tagsByNode[link.nodeID, default: []].insert(link.tagID)
            }
        }
        let weekEnd = today.adding(days: 7)
        var result: Set<NodeID> = []
        for node in state.nodes.values {
            if let textMatches, !textMatches.contains(node.id) { continue }
            if !tagIDs.isEmpty {
                let own = tagsByNode[node.id] ?? []
                switch tagMatch {
                case .any: if own.isDisjoint(with: tagIDs) { continue }
                case .all: if !tagIDs.isSubset(of: own) { continue }
                }
            }
            if !priorities.isEmpty {
                guard let priority = node.priority, priorities.contains(priority.level) else { continue }
            }
            if !tasks.isEmpty {
                let choice: TaskChoice = switch node.taskState {
                case nil: .notATask
                case let state? where state.isDone: .done
                default: .open
                }
                if !tasks.contains(choice) { continue }
            }
            if !due.isEmpty, !due.contains(where: { matchesDue($0, node: node, today: today, weekEnd: weekEnd) }) {
                continue
            }
            if !origins.isEmpty, !origins.contains(node.metadata.origin) { continue }
            result.insert(node.id)
        }
        return result
    }

    private func matchesDue(_ choice: DueChoice, node: MindNode, today: CalendarDay, weekEnd: CalendarDay) -> Bool {
        switch choice {
        case .noDate:
            return node.dueDate == nil
        case .overdue:
            // Done tasks are never late, as the canvas draws them.
            guard let due = node.dueDate, node.taskState?.isDone != true, node.taskState != nil else { return false }
            return due < today
        case .today:
            return node.dueDate == today
        case .nextSevenDays:
            guard let due = node.dueDate else { return false }
            return today <= due && due <= weekEnd
        }
    }
}

/// Whether topics that do not match stay in place, faded, or leave the layout.
public enum FilterMode: String, Hashable, Sendable, Codable, CaseIterable {
    case dim
    case hide
}

/// What a window shows of a map under a filter and Focus on Branch.
public struct MapFilterView: Hashable, Sendable {
    /// Topics the filter selects inside the focused branch; every topic
    /// there when no filter is on.
    public let matches: Set<NodeID>
    /// Topics laid out: in dim mode every topic of the focused branch (or
    /// map); in hide mode the matches and their ancestors, so the tree stays
    /// connected. Collapse still hides what is under a collapsed topic.
    public let shown: Set<NodeID>
    /// The topic drawn in the centre; nil when nothing is focused.
    public let focusID: NodeID?
    public let isFiltering: Bool

    /// A shown topic that is drawn faded: it did not match.
    public func isDimmed(_ id: NodeID) -> Bool {
        isFiltering && !matches.contains(id)
    }

    /// Topics Select All and the rectangle may pick: shown and matching.
    public func isSelectable(_ id: NodeID) -> Bool {
        shown.contains(id) && matches.contains(id)
    }

    public init(state: GraphState, filter: MapFilter, mode: FilterMode, focusID: NodeID?, today: CalendarDay) {
        let focus = focusID.flatMap { state.node($0) == nil ? nil : $0 }
        let scope: Set<NodeID> = if let focus {
            Set([focus] + state.descendants(of: focus))
        } else {
            Set(state.nodes.keys)
        }
        self.focusID = focus
        isFiltering = filter.isActive
        guard filter.isActive else {
            matches = scope
            shown = scope
            return
        }
        let matches = filter.matches(in: state, today: today).intersection(scope)
        self.matches = matches
        switch mode {
        case .dim:
            shown = scope
        case .hide:
            var shown: Set<NodeID> = []
            let top = focus ?? state.map.rootNodeID
            if let top { shown.insert(top) }
            for id in matches where !shown.contains(id) {
                shown.insert(id)
                for ancestor in state.ancestors(of: id) {
                    guard scope.contains(ancestor), shown.insert(ancestor).inserted else { break }
                }
            }
            self.shown = shown
        }
    }

    /// The map as this view draws it: only shown topics, the focused one as
    /// the central topic. A view value for layout and drawing only; commands
    /// still run on the real state, so a branch action reaches hidden topics.
    public func project(_ state: GraphState) -> GraphState {
        guard focusID != nil || shown.count != state.nodes.count else { return state }
        var map = state.map
        if let focusID { map.rootNodeID = focusID }
        let nodes = state.nodes.values.compactMap { node -> MindNode? in
            guard shown.contains(node.id) else { return nil }
            var node = node
            if node.id == focusID { node.parentID = nil }
            return node
        }
        let edges = state.edges.values.filter { shown.contains($0.sourceNodeID) && shown.contains($0.targetNodeID) }
        let nodeTags = state.nodeTags.values.filter { shown.contains($0.nodeID) }
        let images = state.images.values.filter { shown.contains($0.nodeID) }
        // A group whose run lost a member to the filter is left out rather than
        // drawn around topics it does not hold.
        let groups = state.groups.values.filter { group in
            guard let members = state.members(of: group) else { return false }
            return members.allSatisfy(shown.contains)
                && group.parentNodeID.map(shown.contains) != false
                && group.summaryNodeID.map(shown.contains) != false
        }
        return GraphState(
            map: map, nodes: nodes, edges: edges, tags: Array(state.tags.values),
            nodeTags: Array(nodeTags), groups: Array(groups), images: Array(images)
        )
    }
}

extension CalendarDay {
    /// The day `days` after this one.
    public func adding(days: Int) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              let later = calendar.date(byAdding: .day, value: days, to: date) else { return self }
        return CalendarDay(later, in: calendar)
    }
}
