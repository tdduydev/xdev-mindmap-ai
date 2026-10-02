import Foundation
import MindMapDomain
import MindMapGraph

/// Find in one open map.
public enum MapFind {
    /// Topics whose title, note or one tag name holds every word of the query,
    /// top to bottom as the outline reads with every branch open, so Find Next
    /// walks the map in reading order, collapsed branches included. Floating
    /// branches come after the main tree, as the outline lists them.
    ///
    /// A word written `#name` matches only tags, by the start of their name:
    /// "#viec" finds topics tagged "việc" or "Việc cần làm". With only such
    /// words, a topic needs those tags and nothing else.
    public static func matches(_ query: SearchQuery, in state: GraphState) -> [NodeID] {
        guard !query.isEmpty else { return [] }
        let tagTerms = query.terms.compactMap(tagTerm)
        let textQuery = SearchQuery(terms: query.terms.filter { tagTerm($0) == nil && $0 != "#" })
        guard !tagTerms.isEmpty || !textQuery.isEmpty else { return [] }
        // Folded once per tag rather than once per topic that carries it.
        let foldedTagNames = state.tags.mapValues { SearchText.fold($0.name) }
        return state.readingOrder().map(\.id).filter { id in
            guard let node = state.node(id) else { return false }
            let tagNames = state.nodeTags(of: id).compactMap { foldedTagNames[$0.tagID] }
            guard tagTerms.allSatisfy({ term in tagNames.contains { $0.hasPrefix(term) } }) else { return false }
            guard !textQuery.isEmpty else { return true }
            return textQuery.matches(node.title)
                || node.note.map { textQuery.matches($0) } == true
                || tagNames.contains { textQuery.matches(folded: $0) }
        }
    }

    /// The folded tag name a `#name` word asks for; nil for any other word.
    private static func tagTerm(_ term: String) -> String? {
        guard term.hasPrefix("#"), term.count > 1 else { return nil }
        return String(term.dropFirst())
    }
}
