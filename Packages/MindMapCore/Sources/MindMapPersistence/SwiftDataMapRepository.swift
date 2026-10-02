import CoreData
import Foundation
import MindMapDomain
import MindMapGraph
import OSLog
import SwiftData

/// `MapRepository` on SwiftData. Runs on its own actor with its own context, so
/// saving never blocks the UI.
@ModelActor
public actor SwiftDataMapRepository: MapRepository {
    /// Signs this repository's transactions in the store's persistent history,
    /// so it can tell its own commits from anyone else's. Unique per instance:
    /// a second repository on the same file (another process) counts as foreign.
    private let author = "MindMapAI.repository.\(UUID().uuidString)"
    private var subscribers: [UUID: AsyncStream<MapRepositoryChange>.Continuation] = [:]
    private var remoteChangeObserver: (any NSObjectProtocol)?
    /// The newest foreign transaction subscribers have already been told about.
    private var lastForeignTransaction: Int64 = .min

    private static let logger = Logger(subsystem: "asia.xdev.mindmapai", category: "Persistence")

    /// A repository can go away before its last subscriber does.
    isolated deinit {
        if let remoteChangeObserver { NotificationCenter.default.removeObserver(remoteChangeObserver) }
    }

    // MARK: Change stream

    public func changes() async -> AsyncStream<MapRepositoryChange> {
        if remoteChangeObserver == nil { startObservingStore() }
        let id = UUID()
        // Unbounded: a dropped `.saved` would leave a library showing an old title.
        let (stream, continuation) = AsyncStream<MapRepositoryChange>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Core Data posts a remote-change notice for every commit to the store
    /// through any container, this repository's own included. The notice
    /// does not say who wrote, so `storeDidChange` asks the history.
    private func startObservingStore() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.storeDidChange() }
        }
        // Foreign writes already stored are in each subscriber's first fetch.
        do {
            lastForeignTransaction = try newestForeignTransaction()?.transactionIdentifier ?? .min
        } catch {
            Self.logger.error("Reading store history failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func storeDidChange() {
        guard !subscribers.isEmpty else { return }
        do {
            guard let newest = try newestForeignTransaction() else { return }
            lastForeignTransaction = newest.transactionIdentifier
        } catch {
            // Fetching again is always correct, only slower.
            Self.logger.error("Reading store history failed: \(error.localizedDescription, privacy: .public)")
        }
        publish(.storeChanged)
    }

    /// Only the newest one, and never this repository's own: fetching a
    /// transaction loads all its changes, and reading back a 10,000-topic
    /// create took 0.14 s on an M1 in a debug build, to learn nothing.
    private func newestForeignTransaction() throws -> DefaultHistoryTransaction? {
        let ownAuthor = author
        let last = lastForeignTransaction
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            // `author != x` alone would skip unsigned transactions, as SQL does with NULL.
            predicate: #Predicate { $0.transactionIdentifier > last && ($0.author == nil || $0.author != ownAuthor) },
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetchHistory(descriptor).first
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
        guard subscribers.isEmpty, let remoteChangeObserver else { return }
        NotificationCenter.default.removeObserver(remoteChangeObserver)
        self.remoteChangeObserver = nil
        lastForeignTransaction = .min
    }

    private func publish(_ change: MapRepositoryChange) {
        for subscriber in subscribers.values { subscriber.yield(change) }
    }

    // MARK: Reading and writing

    public func fetchMaps() async throws -> [MindMap] {
        let descriptor = FetchDescriptor<MapRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.domainValue)
    }

    public func loadGraph(for mapID: MapID) async throws -> GraphState? {
        guard let mapRecord = try mapRecords(for: mapID).first else { return nil }
        let id = mapID.rawValue
        let nodes = try modelContext.fetch(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.mapID == id }))
        let edges = try modelContext.fetch(FetchDescriptor<EdgeRecord>(predicate: #Predicate { $0.mapID == id }))
        return GraphState(
            map: mapRecord.domainValue,
            nodes: nodes.map(\.domainValue),
            edges: edges.compactMap(\.domainValue)
        )
    }

    public func create(_ graph: GraphState) async throws {
        let mapRecord = MapRecord(mapID: graph.map.id.rawValue)
        mapRecord.update(from: graph.map)
        modelContext.insert(mapRecord)
        for node in graph.nodes.values {
            let record = NodeRecord(nodeID: node.id.rawValue, mapID: node.mapID.rawValue)
            record.update(from: node)
            modelContext.insert(record)
        }
        for edge in graph.edges.values {
            let record = EdgeRecord(edgeID: edge.id.rawValue, mapID: edge.mapID.rawValue)
            record.update(from: edge)
            modelContext.insert(record)
        }
        try commit()
        publish(.saved(mapRecord.domainValue))
    }

    public func save(_ changes: GraphChangeSet, map: MindMap) async throws {
        let record = try mapRecord(for: map)
        record.updateGraphFields(from: map)
        try upsertNodes(changes.savedNodes)
        try deleteNodes(changes.deletedNodeIDs)
        try upsertEdges(changes.savedEdges)
        try deleteEdges(changes.deletedEdgeIDs)
        try commit()
        publish(.saved(record.domainValue))
    }

    public func setFavorite(_ isFavorite: Bool, for mapID: MapID) async throws {
        guard let record = try mapRecords(for: mapID).first else { return }
        record.isFavorite = isFavorite
        try commit()
        publish(.saved(record.domainValue))
    }

    public func deleteMap(_ mapID: MapID) async throws {
        let id = mapID.rawValue
        // Records are deleted one by one rather than with a batch delete, which
        // goes around the change tracking that CloudKit mirroring relies on.
        for record in try mapRecords(for: mapID) {
            modelContext.delete(record)
        }
        for record in try modelContext.fetch(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.mapID == id })) {
            modelContext.delete(record)
        }
        for record in try modelContext.fetch(FetchDescriptor<EdgeRecord>(predicate: #Predicate { $0.mapID == id })) {
            modelContext.delete(record)
        }
        try commit()
        publish(.deleted(mapID))
    }

    public func fetchTopicTexts() async throws -> [MapID: [String]] {
        var descriptor = FetchDescriptor<NodeRecord>()
        // Search reads only text; skipping the other columns keeps a large library cheap to scan.
        descriptor.propertiesToFetch = [\.mapID, \.title, \.note]
        var texts: [MapID: [String]] = [:]
        for record in try modelContext.fetch(descriptor) {
            let found = [record.title, record.note ?? ""].filter { !$0.isEmpty }
            guard !found.isEmpty else { continue }
            texts[MapID(record.mapID), default: []].append(contentsOf: found)
        }
        return texts
    }

    // MARK: Writing

    /// Every write ends here, so every transaction carries this repository's author.
    private func commit() throws {
        modelContext.author = author
        try modelContext.save()
    }

    /// The map's record, created with every field if it is not stored yet.
    private func mapRecord(for map: MindMap) throws -> MapRecord {
        var records = try mapRecords(for: map.id)
        guard !records.isEmpty else {
            let record = MapRecord(mapID: map.id.rawValue)
            record.update(from: map)
            modelContext.insert(record)
            return record
        }
        let record = records.removeFirst()
        // Duplicates of one map can only come from sync; fold them into one record.
        records.forEach(modelContext.delete)
        return record
    }

    private func upsertNodes(_ nodes: [MindNode]) throws {
        guard !nodes.isEmpty else { return }
        let ids = nodes.map(\.id.rawValue)
        let existing = try modelContext.fetch(FetchDescriptor<NodeRecord>(predicate: #Predicate { ids.contains($0.nodeID) }))
        var recordsByID = Dictionary(grouping: existing, by: \.nodeID)
        for node in nodes {
            var records = recordsByID.removeValue(forKey: node.id.rawValue) ?? []
            let record: NodeRecord
            if records.isEmpty {
                record = NodeRecord(nodeID: node.id.rawValue, mapID: node.mapID.rawValue)
                modelContext.insert(record)
            } else {
                record = records.removeFirst()
            }
            record.update(from: node)
            records.forEach(modelContext.delete)
        }
    }

    private func deleteNodes(_ ids: [NodeID]) throws {
        guard !ids.isEmpty else { return }
        let rawIDs = ids.map(\.rawValue)
        for record in try modelContext.fetch(FetchDescriptor<NodeRecord>(predicate: #Predicate { rawIDs.contains($0.nodeID) })) {
            modelContext.delete(record)
        }
    }

    private func upsertEdges(_ edges: [MindEdge]) throws {
        guard !edges.isEmpty else { return }
        let ids = edges.map(\.id.rawValue)
        let existing = try modelContext.fetch(FetchDescriptor<EdgeRecord>(predicate: #Predicate { ids.contains($0.edgeID) }))
        var recordsByID = Dictionary(grouping: existing, by: \.edgeID)
        for edge in edges {
            var records = recordsByID.removeValue(forKey: edge.id.rawValue) ?? []
            let record: EdgeRecord
            if records.isEmpty {
                record = EdgeRecord(edgeID: edge.id.rawValue, mapID: edge.mapID.rawValue)
                modelContext.insert(record)
            } else {
                record = records.removeFirst()
            }
            record.update(from: edge)
            records.forEach(modelContext.delete)
        }
    }

    private func deleteEdges(_ ids: [EdgeID]) throws {
        guard !ids.isEmpty else { return }
        let rawIDs = ids.map(\.rawValue)
        for record in try modelContext.fetch(FetchDescriptor<EdgeRecord>(predicate: #Predicate { rawIDs.contains($0.edgeID) })) {
            modelContext.delete(record)
        }
    }

    // MARK: Reading

    private func mapRecords(for mapID: MapID) throws -> [MapRecord] {
        let id = mapID.rawValue
        return try modelContext.fetch(FetchDescriptor<MapRecord>(predicate: #Predicate { $0.mapID == id }))
    }
}
