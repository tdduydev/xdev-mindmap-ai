import Foundation
import MindMapDomain
import MindMapGraph

extension TopicLinkError {
    /// Shown under the URL field (docs/node-organization.md "Links").
    var message: String {
        switch self {
        case .unsupportedScheme: String(localized: "Only web and email links can be added.")
        case .missingHost: String(localized: "Add a web address after “https://”.")
        case .missingAddress: String(localized: "Add an email address after “mailto:”.")
        case .tooLong: String(localized: "This link is too long.")
        case .unreadable: String(localized: "This isn’t a web or email address.")
        }
    }
}

// A topic's URL link (FR-ORG-26). Single-topic, like the note: Add Link… acts
// on the primary selection. Nothing is fetched for a link; opening it is the
// view's `openURL`.
extension EditorSession {
    var canEditSelectionLink: Bool { selectedNode != nil }

    /// The selection's link when this build can open it, for Open Link.
    var selectionLinkURL: URL? { selectedNode?.link?.url }

    /// Topic ▸ Add Link… or Edit Link…, by whether the selection has a link.
    var selectionHasLink: Bool { selectedNode?.link != nil }

    /// Opens the link sheet for the selected topic.
    func beginEditingSelectionLink() {
        guard let selection, canEditSelectionLink else { return }
        linkEditorTarget = selection
    }

    /// Checks typed text and sets it as the topic's link: one step named
    /// "Add Link", "Edit Link" or, for an empty field, "Remove Link".
    /// Returns why the text was refused, changing nothing.
    @discardableResult
    func setLink(_ text: String, for id: NodeID) -> TopicLinkError? {
        let link: TopicLink?
        do {
            link = try TopicLink.validated(text)
        } catch {
            return error
        }
        setLink(link, for: id)
        return nil
    }

    func removeLink(from id: NodeID) {
        setLink(nil as TopicLink?, for: id)
    }

    private func setLink(_ link: TopicLink?, for id: NodeID) {
        guard let node = engine.state.node(id), node.link != link else { return }
        let name = switch (node.link, link) {
        case (nil, _): String(localized: "Add Link")
        case (_, nil): String(localized: "Remove Link")
        default: String(localized: "Edit Link")
        }
        perform(SetNodeLinkCommand(nodeIDs: [id], link: link), named: name)
    }
}
