import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapSearch

/// The reads the MCP server and the chat share (docs/mcp.md, Shared query
/// layer). Read-only: nothing here changes a map. Maps in Recently Deleted are
/// never returned, whatever the graph source says.
///
/// Logs nothing: every argument and result is map content (docs/privacy.md).
public struct MapQueries: Sendable {
    /// Longest note excerpt in a search hit, in characters.
    static let excerptLength = 160

    private let repository: any MapRepository
    private let graphs: any GraphSource

    public init(repository: any MapRepository, graphs: any GraphSource) {
        self.repository = repository
        self.graphs = graphs
    }

    // MARK: Maps

    /// Live maps, most recently edited first. `text` matches titles the way
    /// Find does (case, Vietnamese marks, đ); nil or blank lists every map.
    public func maps(matching text: String?, limit: Int) async throws -> [MapListing] {
        guard limit > 0 else { return [] }
        let query = SearchQuery(text ?? "")
        let stored = try await repository.fetchMaps()
        let liveIDs = Set(stored.map(\.id))
        let counts = try await repository.fetchTopicCounts()
        let open = await graphs.openMapIDs()
        var listings: [MapListing] = []
        for map in stored {
            // An open map's title and size can be ahead of the store.
            let live = open.contains(map.id) ? try await liveGraph(map.id, among: liveIDs) : nil
            if open.contains(map.id), live == nil { continue }
            let title = live?.map.title ?? map.title
            guard query.isEmpty || query.matches(title) else { continue }
            listings.append(MapListing(
                mapID: map.id,
                title: title,
                topicCount: live?.nodes.count ?? counts[map.id] ?? 0,
                updatedAt: live?.map.updatedAt ?? map.updatedAt
            ))
        }
        // Stable on ties, so equal edit times keep the store's order.
        let ordered = listings.enumerated().sorted { lhs, rhs in
            lhs.element.updatedAt != rhs.element.updatedAt
                ? lhs.element.updatedAt > rhs.element.updatedAt
                : lhs.offset < rhs.offset
        }
        return ordered.prefix(limit).map(\.element)
    }

    // MARK: Outline

    /// The map, or the branch under `branch`, top to bottom. `depth` 0 is the
    /// starting topic alone; nil is every level. The first topic is always
    /// returned, with its note cut if the note alone is over the limit; after
    /// that the outline stops at the first topic that does not fit, so it
    /// never skips a parent to show a child.
    public func outline(
        of mapID: MapID,
        branch: NodeID? = nil,
        depth: Int? = nil,
        includeNotes: Bool = true,
        limit: TextLimit
    ) async throws -> OutlineExcerpt {
        guard let state = try await liveGraph(mapID, among: liveMapIDs()) else { throw MapQueryError.mapNotFound }
        guard let startID = branch ?? state.map.rootNodeID, state.node(startID) != nil else {
            throw MapQueryError.topicNotFound
        }
        let maximumDepth = depth.map { max(0, $0) }
        var topics: [OutlineTopic] = []
        var remaining = limit.budget
        var omitted = 0
        var deeper = 0
        var isFull = false

        // The whole map is the main tree, then each floating branch at depth 0
        // (FR-ORG-27); `isFloating` tells a reader which tree a topic heads.
        let starts = branch == nil ? state.topLevelIDs : [startID]
        for (id, level) in Self.walk(state, from: starts) {
            if let maximumDepth, level > maximumDepth {
                deeper += 1
                continue
            }
            if isFull {
                omitted += 1
                continue
            }
            guard let node = state.node(id) else { continue }
            let title = Self.singleLine(node.title)
            let note = includeNotes ? node.note.flatMap(Self.nonBlank) : nil
            let titleCost = limit.cost(title) + limit.perTopic
            let noteCost = note.map(limit.cost) ?? 0

            if titleCost + noteCost <= remaining {
                topics.append(OutlineTopic(
                    nodeID: id, depth: level, title: title, note: note,
                    isNoteCut: false, childCount: state.childIDs(of: id).count,
                    isFloating: node.isFloating(rootID: state.map.rootNodeID)
                ))
                remaining -= titleCost + noteCost
            } else if topics.isEmpty {
                // Without this, a branch whose top topic has a long note would
                // come back empty and the reader could not go deeper.
                let cut = note.map { limit.prefix(of: $0, fitting: remaining - titleCost) }
                topics.append(OutlineTopic(
                    nodeID: id, depth: level, title: title, note: cut.flatMap(Self.nonBlank),
                    isNoteCut: note != nil, childCount: state.childIDs(of: id).count,
                    isFloating: node.isFloating(rootID: state.map.rootNodeID)
                ))
                remaining = 0
                isFull = true
            } else {
                isFull = true
                omitted += 1
            }
        }
        return OutlineExcerpt(
            mapID: mapID,
            mapTitle: state.map.title,
            topics: topics,
            omittedTopicCount: omitted,
            deeperTopicCount: deeper
        )
    }

    // MARK: Search

    /// Topics whose title or note holds every word of `text`, with the same
    /// folding as Find. Title matches come first, then note matches; within
    /// each, maps go most recently edited first and topics in reading order.
    /// `mapID` nil searches every live map.
    public func search(_ text: String, in mapID: MapID? = nil, limit: Int) async throws -> [TopicHit] {
        let query = SearchQuery(text)
        guard limit > 0, !query.isEmpty else { return [] }

        let maps = try await repository.fetchMaps()
        let live = Set(maps.map(\.id))
        let candidates = if let mapID { [mapID] } else { try await mapsThatMayMatch(query, among: maps) }

        var titleHits: [TopicHit] = []
        var noteHits: [TopicHit] = []
        for candidate in candidates {
            guard let state = try await liveGraph(candidate, among: live) else {
                if mapID != nil { throw MapQueryError.mapNotFound }
                continue
            }
            for id in MapFind.matches(query, in: state) {
                guard let node = state.node(id) else { continue }
                let ref = TopicRef(mapID: candidate, nodeID: id)
                let path = state.ancestors(of: id).reversed().compactMap { state.node($0).map { Self.singleLine($0.title) } }
                if query.matches(node.title) {
                    titleHits.append(TopicHit(
                        ref: ref, mapTitle: state.map.title, title: Self.singleLine(node.title),
                        path: path, match: .title, excerpt: nil
                    ))
                } else if noteHits.count < limit {
                    noteHits.append(TopicHit(
                        ref: ref, mapTitle: state.map.title, title: Self.singleLine(node.title),
                        path: path, match: .note, excerpt: node.note.map { Self.excerpt(of: $0, for: query) }
                    ))
                }
            }
            // Title hits rank first, so once there are enough nothing later can displace them.
            if titleHits.count >= limit { break }
        }
        return Array((titleHits + noteHits).prefix(limit))
    }

    // MARK: Topic

    /// Nil when the map is not live or has no such topic.
    public func topic(_ ref: TopicRef) async throws -> TopicDetail? {
        guard let state = try await liveGraph(ref.mapID, among: liveMapIDs()), let node = state.node(ref.nodeID) else { return nil }
        let summary = { (id: NodeID) in state.node(id).map { TopicSummary(nodeID: id, title: Self.singleLine($0.title)) } }
        let links = state.edges(touching: ref.nodeID)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            .compactMap { edge -> TopicDetail.CrossLink? in
                let isOutgoing = edge.sourceNodeID == ref.nodeID
                guard let other = summary(isOutgoing ? edge.targetNodeID : edge.sourceNodeID) else { return nil }
                return TopicDetail.CrossLink(topic: other, label: edge.label, direction: isOutgoing ? .outgoing : .incoming)
            }
        return TopicDetail(
            ref: ref,
            mapTitle: state.map.title,
            title: node.title,
            note: node.note.flatMap(Self.nonBlank),
            path: state.ancestors(of: ref.nodeID).reversed().compactMap(summary),
            children: state.childIDs(of: ref.nodeID).compactMap(summary),
            tags: state.tags(of: ref.nodeID).map(\.name),
            taskState: node.taskState,
            priority: node.priority,
            startDate: node.startDate,
            dueDate: node.dueDate,
            crossLinks: links
        )
    }

    // MARK: Helpers

    /// The graph to read, or nil when the map is gone or in Recently Deleted.
    /// The store's live list is checked too: an open editor's copy of the map
    /// may not know it was moved to Recently Deleted from the library.
    private func liveGraph(_ mapID: MapID, among live: Set<MapID>) async throws -> GraphState? {
        guard live.contains(mapID) else { return nil }
        guard let state = try await graphs.graph(for: mapID), state.map.deletedAt == nil else { return nil }
        return state
    }

    private func liveMapIDs() async throws -> Set<MapID> {
        Set(try await repository.fetchMaps().map(\.id))
    }

    /// Live maps that may hold a match, most recently edited first. The store's
    /// text index picks among saved maps; open maps are always searched, since
    /// their latest edits may not be in the store yet.
    private func mapsThatMayMatch(_ query: SearchQuery, among maps: [MindMap]) async throws -> [MapID] {
        let open = await graphs.openMapIDs()
        let texts = try await repository.fetchTopicTexts()
        let documents = maps.filter { !open.contains($0.id) }.map {
            MapSearchDocument(mapID: $0.id, title: $0.title, topicTexts: texts[$0.id] ?? [])
        }
        let index = await LibrarySearchIndex.build(documents: documents)
        let found = Set(index.search(query).hits.keys)
        return maps.map(\.id).filter { found.contains($0) || open.contains($0) }
    }

    /// Pre-order from each start with depth, every branch open, safe against a
    /// corrupt parent loop.
    private static func walk(_ state: GraphState, from starts: [NodeID]) -> [(NodeID, Int)] {
        var result: [(NodeID, Int)] = []
        var visited: Set<NodeID> = []
        var stack: [(NodeID, Int)] = starts.reversed().map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            guard state.node(id) != nil, visited.insert(id).inserted else { continue }
            result.append((id, depth))
            stack.append(contentsOf: state.childIDs(of: id).reversed().map { ($0, depth + 1) })
        }
        return result
    }

    /// The note line holding the most query words, shortened around the first
    /// of them so the match shows even in a long paragraph.
    static func excerpt(of note: String, for query: SearchQuery) -> String {
        let lines = note.split(whereSeparator: \.isNewline).map(String.init)
        let scores = lines.map { score($0, query) }
        let best = scores.max().flatMap { top in scores.firstIndex(of: top).map { lines[$0] } } ?? note
        let line = best.trimmingCharacters(in: .whitespaces)
        guard line.count > excerptLength else { return line }

        // Folding keeps one character per character for Vietnamese and Latin
        // text, so an offset in the folded line is the same offset here. When it
        // does not (rare ligatures), the excerpt starts a little off, no worse.
        let folded = SearchText.fold(line)
        let firstMatch = query.terms.compactMap { folded.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        let offset = firstMatch.map { folded.distance(from: folded.startIndex, to: $0.lowerBound) } ?? 0
        let start = min(max(0, offset - excerptLength / 4), line.count - excerptLength)
        let startIndex = line.index(line.startIndex, offsetBy: start)
        let endIndex = line.index(startIndex, offsetBy: excerptLength)
        return (start > 0 ? "…" : "") + line[startIndex..<endIndex] + (endIndex < line.endIndex ? "…" : "")
    }

    private static func score(_ line: String, _ query: SearchQuery) -> Int {
        let folded = SearchText.fold(line)
        return query.terms.filter { folded.contains($0) }.count
    }

    /// `text` on one line, as titles are in every result: for callers that
    /// write a title or note into a one-line format of their own.
    public static func oneLine(_ text: String) -> String {
        singleLine(text)
    }

    /// Titles are one line in every output, as in Markdown export.
    static func singleLine(_ title: String) -> String {
        title.split(omittingEmptySubsequences: true) { $0.isNewline }.joined(separator: " ")
    }

    private static func nonBlank(_ text: String) -> String? {
        text.allSatisfy(\.isWhitespace) ? nil : text
    }
}
