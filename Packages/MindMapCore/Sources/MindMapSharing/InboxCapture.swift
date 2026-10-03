import Foundation
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence

/// Where the Inbox map's ID is kept. The app and the watch use iCloud
/// key-value storage (`inbox.mapID`, ADR 0012), so the Inbox needs no schema
/// change; tests use a plain value.
public protocol InboxMapIDStore: Sendable {
    func inboxMapID() -> MapID?
    func setInboxMapID(_ id: MapID)
}

extension InboxMapIDStore {
    /// The key both the app and the watch read and write.
    public static var key: String { "inbox.mapID" }
}

/// Ideas captured away from the editor (the watch, FR-WCH-01) go to one map,
/// the Inbox, as topics under its central topic. Writes go through
/// `QuickCapture`, so each idea is a graph command and a saved change set.
public struct InboxCapture: Sendable {
    private let capture: QuickCapture
    private let repository: any MapRepository
    private let store: any InboxMapIDStore

    public init(repository: any MapRepository, store: any InboxMapIDStore, clock: @escaping @Sendable () -> Date = { .now }) {
        self.repository = repository
        self.store = store
        capture = QuickCapture(repository: repository, clock: clock)
    }

    /// Adds `idea` to the Inbox. A missing Inbox, or one in Recently Deleted,
    /// is replaced by a new map titled `inboxTitle` whose ID becomes the Inbox.
    @discardableResult
    public func addIdea(_ idea: String, inboxTitle: String) async throws -> MindMap {
        guard !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickCapture.Failure.nothingToAdd
        }
        if let id = store.inboxMapID() {
            do {
                return try await capture.addIdea(idea, to: id)
            } catch QuickCapture.Failure.mapNotFound {
                // Deleted on some device: the next idea starts a new Inbox.
            }
        }
        let inbox = try await capture.createMap(from: OutlineDraft(), title: inboxTitle)
        store.setInboxMapID(inbox.id)
        return try await capture.addIdea(idea, to: inbox.id)
    }

    /// The live maps the watch lists, most recently edited first (FR-WCH-02).
    public func recentMaps(limit: Int = 20) async throws -> [MindMap] {
        try await capture.recentMaps(limit: limit)
    }

    /// A map read top to bottom for a read-only outline, or nil when it is
    /// gone or in Recently Deleted.
    public func outline(of mapID: MapID) async throws -> [ReadOnlyTopic]? {
        guard let graph = try await repository.loadGraph(for: mapID), graph.map.deletedAt == nil else { return nil }
        return ReadOnlyTopic.tree(of: graph)
    }
}

/// One topic of a read-only outline, with its children, for views that show
/// a tree with their own expand and collapse (SwiftUI `OutlineGroup`).
public struct ReadOnlyTopic: Identifiable, Hashable, Sendable {
    public let id: NodeID
    public let title: String
    /// Nil for a leaf, so `OutlineGroup` draws no disclosure arrow.
    public let children: [ReadOnlyTopic]?

    public init(id: NodeID, title: String, children: [ReadOnlyTopic]?) {
        self.id = id
        self.title = title
        self.children = children
    }

    /// The central topic's tree, then each floating branch, every branch
    /// open, in reading order. A parent loop in synced records is cut where
    /// it repeats instead of recursing forever.
    public static func tree(of graph: GraphState) -> [ReadOnlyTopic] {
        var visited: Set<NodeID> = []
        return graph.topLevelIDs.compactMap { build($0, in: graph, visited: &visited) }
    }

    private static func build(_ id: NodeID, in graph: GraphState, visited: inout Set<NodeID>) -> ReadOnlyTopic? {
        guard let node = graph.nodes[id], visited.insert(id).inserted else { return nil }
        let children = graph.childIDs(of: id).compactMap { build($0, in: graph, visited: &visited) }
        return ReadOnlyTopic(id: id, title: node.title, children: children.isEmpty ? nil : children)
    }
}

/// The Inbox ID in iCloud key-value storage, shared by the app and the watch
/// through one `ubiquity-kvstore-identifier` (ADR 0012). Without iCloud it
/// still keeps the value on this device, so capture never fails for it.
public struct UbiquitousInboxStore: InboxMapIDStore {
    public init() {}

    public func inboxMapID() -> MapID? {
        NSUbiquitousKeyValueStore.default.string(forKey: Self.key)
            .flatMap(UUID.init(uuidString:))
            .map { MapID($0) }
    }

    public func setInboxMapID(_ id: MapID) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(id.rawValue.uuidString, forKey: Self.key)
        store.synchronize()
    }
}
