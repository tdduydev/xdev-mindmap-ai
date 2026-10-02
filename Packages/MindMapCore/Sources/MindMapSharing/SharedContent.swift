import Foundation
import MindMapInterchange

/// What a share sheet or a shortcut hands over, before it becomes topics.
public enum SharedContent: Hashable, Sendable {
    /// Read as Markdown, which falls back to one topic per line for plain text.
    case text(String)
    /// `title` is the page name when the sender gives one, as Safari does.
    case link(URL, title: String?)

    /// Topics in the order they were shared. A link becomes one topic named
    /// after its page, with the address as its note, so nothing is lost.
    public static func outline(of contents: [SharedContent]) -> OutlineDraft {
        var items: [OutlineDraft.Item] = []
        for content in contents {
            switch content {
            case .text(let text):
                items += InterchangeFormat.markdown.parse(text).items
            case .link(let url, let title):
                let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                items.append(name.isEmpty
                    ? OutlineDraft.Item(depth: 0, title: url.absoluteString)
                    : OutlineDraft.Item(depth: 0, title: name, note: url.absoluteString))
            }
        }
        return OutlineDraft(items: items)
    }
}
