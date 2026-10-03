import Foundation
import MindMapDomain
import MindMapGraph

/// One connection as the inspector and VoiceOver list it for a topic.
struct ConnectionSummary: Identifiable, Hashable {
    let edge: MindEdge
    /// True when the topic is the connection's source.
    let isOutgoing: Bool
    let otherID: NodeID
    let otherTitle: String

    var id: EdgeID { edge.id }

    /// "Connection to Budget, label: depends on", as docs/node-organization.md
    /// *Accessibility* words it.
    var spokenDescription: String {
        Self.spokenDescription(isOutgoing: isOutgoing, otherTitle: otherTitle, label: edge.label)
    }

    nonisolated static func spokenDescription(isOutgoing: Bool, otherTitle: String, label: String?) -> String {
        let other = otherTitle.isEmpty ? String(localized: "Untitled Topic") : otherTitle
        let base = isOutgoing
            ? String(localized: "Connection to \(other)")
            : String(localized: "Connection from \(other)")
        guard let label else { return base }
        return String(localized: "\(base), label: \(label)")
    }
}

/// A topic a new connection can go to, with its path for the picker.
struct ConnectionCandidate: Identifiable, Hashable {
    let id: NodeID
    let title: String
    /// Ancestor titles from the central topic down, empty for the central topic.
    let path: [String]
}

// Connections between two topics (FR-EDT-12, MM-33). In code these stay
// edges and cross-links; on screen they are "Connection" / "kết nối", so
// "Link" means only a topic's URL.
extension EditorSession {
    var canAddConnection: Bool {
        guard let selection, engine.state.node(selection) != nil else { return false }
        return engine.state.nodes.count > 1
    }

    /// Topic ▸ Add Connection…: with two topics selected, connects the
    /// primary one to the other right away; otherwise asks for the target.
    func beginAddingConnection() {
        guard let source = selection, canAddConnection else { return }
        if selectedIDs.count == 2, let target = selectedIDs.first(where: { $0 != source }) {
            connect(source, to: target)
            return
        }
        connectionSource = source
    }

    /// Every other topic, in reading order, for the target picker.
    func connectionCandidates(from source: NodeID) -> [ConnectionCandidate] {
        let state = engine.state
        var path: [String] = []
        var candidates: [ConnectionCandidate] = []
        for item in state.readingOrder() {
            guard let node = state.node(item.id) else { continue }
            // A floating topic starts a path of its own: it has no parent.
            if node.parentID == nil { path.removeAll() } else { path.removeLast(max(path.count - item.depth, 0)) }
            if item.id != source {
                candidates.append(ConnectionCandidate(id: item.id, title: node.title, path: path))
            }
            path.append(node.title.isEmpty ? String(localized: "Untitled Topic") : node.title)
        }
        return candidates
    }

    /// Ends the picker by connecting the source to `target`.
    func finishAddingConnection(to target: NodeID) {
        guard let source = connectionSource else { return }
        connectionSource = nil
        connect(source, to: target)
    }

    /// The topic's connections, outgoing first, then by the other end's title.
    func connections(of id: NodeID) -> [ConnectionSummary] {
        let state = engine.state
        return state.edges(touching: id).compactMap { edge -> ConnectionSummary? in
            let isOutgoing = edge.sourceNodeID == id
            let otherID = isOutgoing ? edge.targetNodeID : edge.sourceNodeID
            guard let other = state.node(otherID) else { return nil }
            return ConnectionSummary(edge: edge, isOutgoing: isOutgoing, otherID: otherID, otherTitle: other.title)
        }
        .sorted { lhs, rhs in
            if lhs.isOutgoing != rhs.isOutgoing { return lhs.isOutgoing }
            if lhs.otherTitle != rhs.otherTitle { return lhs.otherTitle.localizedStandardCompare(rhs.otherTitle) == .orderedAscending }
            return lhs.edge.createdAt < rhs.edge.createdAt
        }
    }

    /// One step named "Edit Connection". An empty label removes it.
    func setConnectionLabel(_ text: String, for id: EdgeID) {
        guard let edge = engine.state.edges[id] else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? nil : trimmed
        guard edge.label != label else { return }
        perform(UpdateEdgeCommand(edgeID: id, label: .set(label)), named: String(localized: "Edit Connection"))
    }

    func setConnectionLineStyle(_ style: EdgeLineStyle, for id: EdgeID) {
        changeConnectionStyle(UpdateEdgeCommand(edgeID: id, lineStyle: .set(style)))
    }

    func setConnectionArrowHeads(_ arrows: EdgeArrowHeads, for id: EdgeID) {
        changeConnectionStyle(UpdateEdgeCommand(edgeID: id, arrowHeads: .set(arrows)))
    }

    /// Nil is the default connection colour.
    func setConnectionColor(_ color: TopicColor?, for id: EdgeID) {
        changeConnectionStyle(UpdateEdgeCommand(edgeID: id, color: .set(color)))
    }

    func reverseConnection(_ id: EdgeID) {
        perform(ReverseEdgeCommand(edgeID: id), named: String(localized: "Reverse Connection"))
    }

    private func changeConnectionStyle(_ command: UpdateEdgeCommand) {
        perform(command, named: String(localized: "Change Connection Style"))
    }
}

extension EdgeLineStyle {
    static let choices: [EdgeLineStyle] = [.solid, .dashed, .dotted]

    var title: String {
        switch self {
        case .solid: String(localized: "Solid")
        case .dotted: String(localized: "Dotted")
        default: String(localized: "Dashed")
        }
    }
}

extension EdgeArrowHeads {
    static let choices: [EdgeArrowHeads] = [.none, .end, .start, .both]

    var title: String {
        switch self {
        case .end: String(localized: "At End")
        case .start: String(localized: "At Start")
        case .both: String(localized: "Both Ends")
        default: String(localized: "None")
        }
    }
}

extension MindEdge {
    /// The look drawn when the style fields are unset (V1 links).
    var resolvedLineStyle: EdgeLineStyle { lineStyle ?? .dashed }
    var resolvedArrowHeads: EdgeArrowHeads { arrowHeads ?? (edgeType == .reference ? .end : .none) }
}
