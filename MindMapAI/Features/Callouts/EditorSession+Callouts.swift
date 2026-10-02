import Foundation
import MindMapDomain
import MindMapGraph

// A topic's callout (FR-ORG-30): a short remark in a bubble above it. Single
// topic, like the link: Add Callout acts on the primary selection. The text is
// typed in the bubble on the canvas; nothing is stored until it is committed,
// so an empty bubble closed with Return or Esc leaves no undo step.
extension EditorSession {
    var canEditSelectionCallout: Bool { selectedNode != nil }

    /// Topic ▸ Add Callout or Edit Callout, by whether the selection has one.
    var selectionHasCallout: Bool { selectedNode?.callout != nil }

    /// Opens the selected topic's bubble for typing.
    func beginEditingSelectionCallout() {
        guard let selection, canEditSelectionCallout else { return }
        calloutEditorTarget = selection
        // The bubble lives on the canvas; the outline has no room for it.
        presentation = .canvas
    }

    /// Commits typed text: "Add Callout", "Edit Callout" or, for blank text,
    /// "Remove Callout". The same text changes nothing.
    func setCallout(_ text: String, for id: NodeID) {
        if calloutEditorTarget == id { calloutEditorTarget = nil }
        guard let node = engine.state.node(id) else { return }
        let callout = MindNode.normalizedCallout(text)
        guard node.callout != callout else { return }
        let name = switch (node.callout, callout) {
        case (nil, _): String(localized: "Add Callout")
        case (_, nil): String(localized: "Remove Callout")
        default: String(localized: "Edit Callout")
        }
        perform(SetCalloutCommand(nodeIDs: [id], text: callout), named: name)
    }

    func removeCallout(from id: NodeID) {
        setCallout("", for: id)
    }
}
