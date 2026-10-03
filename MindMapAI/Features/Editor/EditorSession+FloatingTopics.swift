import Foundation
import MindMapDomain
import MindMapGraph

/// Floating topics (FR-ORG-27, ADR 0010): topics with no parent beside the
/// tree, at a stored position relative to the central topic. The commands are
/// MindMapGraph's; this names them for the Edit menu and keeps the selection.
extension EditorSession {
    func isFloating(_ id: NodeID) -> Bool {
        engine.state.node(id)?.isFloating(rootID: rootID) == true
    }

    /// A floating topic needs the central topic to float beside.
    var canAddFloatingTopic: Bool { rootID != nil }

    /// Detach Topic: a topic in the tree, never the central topic.
    var canDetachSelection: Bool {
        guard let selection, selection != rootID else { return false }
        return engine.state.node(selection)?.parentID != nil
    }

    var canAttachSelection: Bool { selection.map(isFloating) == true }

    func beginAttaching(_ id: NodeID) {
        guard isFloating(id) else { return }
        attachTarget = id
    }

    func attach(_ id: NodeID, to parentID: NodeID) {
        guard isFloating(id), canMove([id], to: .child(of: parentID)) else { return }
        move([id], to: .child(of: parentID))
        attachTarget = nil
        selection = id
    }

    /// Makes an empty floating topic at `position`, selects it and asks the
    /// view to open its title, as Add Topic does.
    @discardableResult
    func addFloatingTopic(at position: TopicPosition) -> NodeID? {
        guard canAddFloatingTopic else { return nil }
        let id = NodeID()
        guard perform(AddFloatingTopicCommand(nodeID: id, title: "", position: position), named: String(localized: "Add Floating Topic")) else {
            return nil
        }
        selection = id
        focusRequest = id
        return id
    }

    /// Topic ▸ Add Floating Topic: at the spot the canvas offers.
    func addFloatingTopic() {
        addFloatingTopic(at: floatingTopicSpot())
    }

    /// Moves a floating topic with its branch. The same place is no step.
    func moveFloatingTopic(_ id: NodeID, to position: TopicPosition) {
        guard isFloating(id), engine.state.node(id)?.position != position else { return }
        perform(MoveFloatingTopicCommand(nodeID: id, to: position), named: String(localized: "Move Topic"))
    }

    /// Takes a branch out of the tree and makes its top floating at `position`.
    func detach(_ id: NodeID, to position: TopicPosition) {
        guard id != rootID, engine.state.node(id)?.parentID != nil else { return }
        if perform(DetachBranchCommand(nodeID: id, position: position), named: String(localized: "Detach Topic")) {
            selection = id
        }
    }

    /// Topic ▸ Detach Topic, placed as Add Floating Topic places a new one.
    func detachSelection() {
        guard canDetachSelection, let selection else { return }
        detach(selection, to: floatingTopicSpot())
    }

    /// Where a floating topic goes without a pointer: the canvas's free spot
    /// near the middle of the view, or below the central topic when no canvas
    /// has laid the map out (the outline before the canvas showed).
    private func floatingTopicSpot() -> TopicPosition {
        floatingTopicPlacement?() ?? TopicPosition(x: 0, y: Double(CanvasMetrics.floatingTopicFallbackOffset))
    }
}
