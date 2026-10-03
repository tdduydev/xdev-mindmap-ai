import Foundation
import MindMapDomain

/// The short handles a conversation's tools give topics (T1, T2…), and the
/// check that turns the handles an answer cites into citations.
///
/// A UUID costs the model many tokens and is easy to garble; a handle costs one
/// or two. Only handles a tool returned in this conversation resolve, so a
/// handle the model makes up never becomes a link (ADR 0009).
public struct CitationTable: Hashable, Sendable {
    private struct Entry: Hashable, Sendable {
        let mapID: MapID
        let nodeID: NodeID
        var title: String
    }

    /// By map and topic: across the library two maps may share a node ID
    /// (a duplicated or imported map), and each topic needs its own handle.
    private struct Key: Hashable, Sendable {
        let mapID: MapID
        let nodeID: NodeID
    }

    private var entries: [String: Entry] = [:]
    private var handles: [Key: String] = [:]
    private var lastNumber = 0

    public init() {}

    /// Keeps the handles of an earlier conversation, so its answers still
    /// resolve and new topics get new numbers.
    public init(history: [ChatTurn]) {
        for citation in history.flatMap(\.citations) {
            guard let number = Self.number(of: citation.handle), entries[citation.handle] == nil else { continue }
            entries[citation.handle] = Entry(mapID: citation.mapID, nodeID: citation.nodeID, title: citation.title)
            handles[Key(mapID: citation.mapID, nodeID: citation.nodeID)] = citation.handle
            lastNumber = max(lastNumber, number)
        }
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// The topic's handle, the same one each time it comes up.
    public mutating func handle(for nodeID: NodeID, in mapID: MapID, title: String) -> String {
        let key = Key(mapID: mapID, nodeID: nodeID)
        if let handle = handles[key] {
            entries[handle]?.title = title
            return handle
        }
        lastNumber += 1
        let handle = "T\(lastNumber)"
        entries[handle] = Entry(mapID: mapID, nodeID: nodeID, title: title)
        handles[key] = handle
        return handle
    }

    /// Nil for a handle no tool returned. Case and spaces do not matter: the
    /// model sometimes writes "t3" or "T 3".
    public func citation(for handle: String) -> ChatCitation? {
        guard let key = Self.normalized(handle), let entry = entries[key] else { return nil }
        return ChatCitation(handle: key, mapID: entry.mapID, nodeID: entry.nodeID, title: entry.title)
    }

    /// The known topics `text` cites, once each, in the order they appear.
    public func citations(in text: String) -> [ChatCitation] {
        var seen: Set<String> = []
        return Self.citedHandles(in: text).compactMap { handle in
            guard let citation = citation(for: handle), seen.insert(citation.handle).inserted else { return nil }
            return citation
        }
    }

    // MARK: Text

    /// Every handle inside brackets, such as "[T3]" or "[T1, T4]", in order.
    public static func citedHandles(in text: String) -> [String] {
        text.matches(of: citationGroup).flatMap { match in
            match.output.matches(of: handlePattern).map { String($0.output) }
        }
    }

    /// `text` with its bracketed handles removed, known or not, for display;
    /// the citations show as chips instead. A handle still being written at
    /// the end of a streaming answer goes too, so "[T" never flashes.
    public static func displayText(_ text: String) -> String {
        var result = text.replacing(spacedCitationGroup, with: "")
        if let partial = result.firstMatch(of: trailingPartialGroup) {
            result.removeSubrange(partial.range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Helpers

    private static func normalized(_ handle: String) -> String? {
        let compact = handle.filter { !$0.isWhitespace }
        return number(of: compact).map { "T\($0)" }
    }

    private static func number(of handle: String) -> Int? {
        guard handle.first == "T" || handle.first == "t" else { return nil }
        return Int(handle.dropFirst())
    }

    nonisolated(unsafe) private static let handlePattern = /[Tt]\s?\d+/
    nonisolated(unsafe) private static let citationGroup = /\[\s*[TtMm]\s?\d+(?:\s*[,;]\s*[TtMm]\s?\d+)*\s*\]/
    // Display also strips map handles (M1…), which the library's listMaps
    // returns: they are never citations, but the model may still cite one.
    nonisolated(unsafe) private static let spacedCitationGroup = /[ \t]*\[\s*[TtMm]\s?\d+(?:\s*[,;]\s*[TtMm]\s?\d+)*\s*\]/
    nonisolated(unsafe) private static let trailingPartialGroup = /[ \t]*\[\s*(?:[TtMm]\s?\d*(?:\s*[,;]\s*(?:[TtMm]\s?\d*)?)*)?$/
}
