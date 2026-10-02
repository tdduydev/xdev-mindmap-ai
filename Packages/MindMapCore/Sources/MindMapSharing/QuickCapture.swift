import Foundation
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence

/// Adds content to maps from outside the editor: the Share Extension and the
/// App Intents. Every change still goes through a `GraphCommand` run by a
/// `GraphEngine`, so it is validated like an edit; there is no undo here,
/// because no editor window owns the change.
public struct QuickCapture: Sendable {
    public enum Failure: Error, Hashable, Sendable {
        /// Deleted, maybe on another device, after it was offered; a map in
        /// Recently Deleted counts as gone.
        case mapNotFound
        case nothingToAdd
    }

    private let repository: any MapRepository
    private let clock: @Sendable () -> Date

    public init(repository: any MapRepository, clock: @escaping @Sendable () -> Date = { .now }) {
        self.repository = repository
        self.clock = clock
    }

    /// Most recently edited first.
    public func recentMaps(limit: Int = 20) async throws -> [MindMap] {
        Array(try await repository.fetchMaps().prefix(limit))
    }

    public func map(_ id: MapID) async throws -> MindMap? {
        try await repository.fetchMaps().first { $0.id == id }
    }

    /// A new map from `draft`. An empty draft makes an empty map named `title`.
    @discardableResult
    public func createMap(from draft: OutlineDraft, title: String) async throws -> MindMap {
        let graph = draft.isEmpty
            ? GraphState.newMap(title: title, now: clock())
            : try GraphState.imported(from: draft, title: title, now: clock())
        try await repository.create(graph)
        return graph.map
    }

    /// Adds `draft` as the last children of the map's central topic.
    @discardableResult
    public func add(_ draft: OutlineDraft, to mapID: MapID, origin: NodeOrigin = .imported) async throws -> MindMap {
        guard !draft.isEmpty else { throw Failure.nothingToAdd }
        guard let state = try await repository.loadGraph(for: mapID), state.map.deletedAt == nil else {
            throw Failure.mapNotFound
        }
        // Records from sync can arrive out of order; repair before running a
        // command and save the repair, as the editor does when it opens a map.
        let repair = try GraphRepair.repair(state, now: clock())
        if !repair.changes.isEmpty {
            try await repository.save(repair.changes, map: repair.state.map)
        }
        var engine = try GraphEngine(state: repair.state, clock: clock)
        guard let rootID = engine.state.map.rootNodeID else { throw Failure.mapNotFound }
        let changes = try engine.execute(InsertOutlineCommand(draft, under: rootID, origin: origin))
        try await repository.save(changes, map: engine.state.map)
        return engine.state.map
    }

    /// One idea as a topic under the central topic of `mapID`, or of the most
    /// recently edited map. With no map at all, the idea starts a new one.
    @discardableResult
    public func addIdea(_ idea: String, to mapID: MapID? = nil) async throws -> MindMap {
        let title = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Failure.nothingToAdd }
        let draft = OutlineDraft(items: [OutlineDraft.Item(depth: 0, title: title)])
        if let mapID {
            return try await add(draft, to: mapID, origin: .user)
        }
        guard let recent = try await repository.fetchMaps().first else {
            return try await createMap(from: OutlineDraft(), title: title)
        }
        return try await add(draft, to: recent.id, origin: .user)
    }
}
