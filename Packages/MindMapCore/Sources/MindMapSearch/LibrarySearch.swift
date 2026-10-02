import Foundation
import MindMapDomain

/// The text of one map that library search looks through.
public struct MapSearchDocument: Hashable, Sendable {
    public let mapID: MapID
    public let title: String
    /// Topic titles and notes, in any order.
    public let topicTexts: [String]

    public init(mapID: MapID, title: String, topicTexts: [String]) {
        self.mapID = mapID
        self.title = title
        self.topicTexts = topicTexts
    }
}

/// Why a map matched a query.
public enum LibrarySearchMatch: Hashable, Sendable {
    case title
    /// The words are in the map's topics. `excerpt` is a topic text that holds
    /// them, as typed, to show under the map's title.
    case content(excerpt: String?)
}

public struct LibrarySearchHit: Hashable, Sendable {
    public let mapID: MapID
    public let match: LibrarySearchMatch
}

/// Every map's text, folded once, so each keystroke only compares strings.
public struct LibrarySearchIndex: Sendable {
    private struct Entry: Sendable {
        let mapID: MapID
        let title: String
        let topics: [(text: String, folded: String)]
        /// Title and topics in one string, so the words of a query may come
        /// from different topics of the same map.
        let all: String
    }

    private let entries: [Entry]

    public init(documents: [MapSearchDocument]) {
        entries = documents.map { document in
            let title = SearchText.fold(document.title)
            let topics = document.topicTexts.map { ($0, SearchText.fold($0)) }
            let all = ([title] + topics.map(\.1)).joined(separator: "\n")
            return Entry(mapID: document.mapID, title: title, topics: topics, all: all)
        }
    }

    /// Builds the index away from the main actor; a library of large maps has
    /// tens of thousands of topics to fold.
    @concurrent
    public static func build(documents: [MapSearchDocument]) async -> LibrarySearchIndex {
        LibrarySearchIndex(documents: documents)
    }

    public func search(_ query: SearchQuery) -> LibrarySearchResults {
        guard !query.isEmpty else { return LibrarySearchResults(hits: [:]) }
        var hits: [MapID: LibrarySearchMatch] = [:]
        for entry in entries {
            if query.matches(folded: entry.title) {
                hits[entry.mapID] = .title
            } else if query.matches(folded: entry.all) {
                let excerpt = entry.topics.first { query.matches(folded: $0.folded) }
                    ?? entry.topics.first { topic in query.terms.contains { topic.folded.contains($0) } }
                hits[entry.mapID] = .content(excerpt: excerpt?.text)
            }
        }
        return LibrarySearchResults(hits: hits)
    }

    @concurrent
    public func searchInBackground(_ query: SearchQuery) async -> LibrarySearchResults {
        search(query)
    }
}

/// The maps that match a query, ranked against whatever order a list shows.
public struct LibrarySearchResults: Hashable, Sendable {
    public let hits: [MapID: LibrarySearchMatch]

    public init(hits: [MapID: LibrarySearchMatch]) {
        self.hits = hits
    }

    public static let empty = LibrarySearchResults(hits: [:])

    /// The matching maps among `order`: title matches first, then content
    /// matches, each group keeping the order it had in `order`.
    public func ranked(_ order: [MapID]) -> [LibrarySearchHit] {
        let found = order.compactMap { id in hits[id].map { LibrarySearchHit(mapID: id, match: $0) } }
        return found.filter { $0.match == .title } + found.filter { $0.match != .title }
    }
}
