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

    func publish(_ change: MapRepositoryChange) {
        for subscriber in subscribers.values { subscriber.yield(change) }
    }

    // MARK: Reading and writing

    public func fetchMaps() async throws -> [MindMap] {
        let descriptor = FetchDescriptor<MapRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.domainValue)
    }

    public func fetchDeletedMaps() async throws -> [MindMap] {
        try deletedMapRecords()
            .map(\.domainValue)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    public func loadGraph(for mapID: MapID) async throws -> GraphState? {
        guard let mapRecord = try mapRecords(for: mapID).first else { return nil }
        let id = mapID.rawValue
        return GraphState(
            map: mapRecord.domainValue,
            nodes: try modelContext.fetch(NodeRecord.inMap(id)).map(\.domainValue),
            edges: try modelContext.fetch(EdgeRecord.inMap(id)).compactMap(\.domainValue),
            tags: try modelContext.fetch(TagRecord.available(in: id)).map(\.domainValue),
            nodeTags: try modelContext.fetch(NodeTagRecord.inMap(id)).map(\.domainValue),
            groups: try modelContext.fetch(GroupRecord.inMap(id)).map(\.domainValue),
            images: try modelContext.fetch(ImageRecord.inMap(id)).map(\.domainValue)
        )
    }

    public func imageData(for imageID: ImageID) async throws -> Data? {
        let records = try modelContext.fetch(ImageRecord.withIDs([imageID.rawValue]))
        // Sync duplicates are folded on the next save; any copy with bytes will do.
        return records.lazy.compactMap(\.data).first
    }

    public func create(_ graph: GraphState, imageData: [ImageID: Data]) async throws {
        let mapRecord = MapRecord(mapID: graph.map.id.rawValue)
        mapRecord.update(from: graph.map)
        modelContext.insert(mapRecord)
        insert(Array(graph.nodes.values), as: NodeRecord.self)
        insert(Array(graph.edges.values), as: EdgeRecord.self)
        // Shared tags are already stored: they belong to the library, not to this map.
        insert(graph.tags.values.filter { $0.mapID == graph.map.id }, as: TagRecord.self)
        insert(Array(graph.nodeTags.values), as: NodeTagRecord.self)
        insert(Array(graph.groups.values), as: GroupRecord.self)
        insert(graph.images.values.map { image in
            var image = image
            image.data = imageData[image.id]
            return image
        }, as: ImageRecord.self)
        try commit()
        publish(.saved(mapRecord.domainValue))
    }

    public func save(_ changes: GraphChangeSet, map: MindMap) async throws {
        let record = try mapRecord(for: map)
        record.updateGraphFields(from: map)
        try upsert(changes.savedNodes, as: NodeRecord.self)
        try delete(changes.deletedNodeIDs.map(\.rawValue), as: NodeRecord.self)
        try upsert(changes.savedEdges, as: EdgeRecord.self)
        try delete(changes.deletedEdgeIDs.map(\.rawValue), as: EdgeRecord.self)
        try upsert(changes.savedTags, as: TagRecord.self)
        try delete(changes.deletedTagIDs.map(\.rawValue), as: TagRecord.self)
        try upsert(changes.savedNodeTags, as: NodeTagRecord.self)
        try delete(changes.deletedNodeTagIDs.map(\.rawValue), as: NodeTagRecord.self)
        try upsert(changes.savedGroups, as: GroupRecord.self)
        try delete(changes.deletedGroupIDs.map(\.rawValue), as: GroupRecord.self)
        try upsert(changes.savedImages, as: ImageRecord.self)
        try delete(changes.deletedImageIDs.map(\.rawValue), as: ImageRecord.self)
        try commit()
        publish(.saved(record.domainValue))
    }

    public func setFavorite(_ isFavorite: Bool, for mapID: MapID) async throws {
        guard let record = try mapRecords(for: mapID).first else { return }
        record.isFavorite = isFavorite
        try commit()
        publish(.saved(record.domainValue))
    }

    public func moveToRecentlyDeleted(_ mapID: MapID, at date: Date) async throws {
        try setDeletedAt(date, for: mapID)
    }

    public func restoreMap(_ mapID: MapID) async throws {
        try setDeletedAt(nil, for: mapID)
    }

    /// Every record of one map, duplicates from sync included, gets the same
    /// value, so a duplicate cannot keep a restored map in Recently Deleted.
    private func setDeletedAt(_ date: Date?, for mapID: MapID) throws {
        let records = try mapRecords(for: mapID)
        guard let first = records.first else { return }
        for record in records { record.deletedAt = date }
        try commit()
        publish(.saved(first.domainValue))
    }

    public func deleteMap(_ mapID: MapID) async throws {
        try deleteRecords(of: mapID)
        try commit()
        publish(.deleted(mapID))
    }

    @discardableResult
    public func purgeDeletedMaps(deletedBefore cutoff: Date) async throws -> [MapID] {
        let due = try deletedMapRecords().filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        // Nothing due is the usual case on launch: no commit, so no change
        // notice goes out to every window for nothing.
        guard !due.isEmpty else { return [] }
        let ids = Array(Set(due.map { MapID($0.mapID) }))
        for id in ids { try deleteRecords(of: id) }
        try commit()
        for id in ids { publish(.deleted(id)) }
        return ids
    }

    /// Records are deleted one by one rather than with a batch delete, which
    /// goes around the change tracking that CloudKit mirroring relies on.
    private func deleteRecords(of mapID: MapID) throws {
        let id = mapID.rawValue
        for record in try mapRecords(for: mapID) {
            modelContext.delete(record)
        }
        try deleteAll(NodeRecord.inMap(id))
        try deleteAll(EdgeRecord.inMap(id))
        try deleteAll(TagRecord.inMap(id))
        try deleteAll(NodeTagRecord.inMap(id))
        try deleteAll(GroupRecord.inMap(id))
        // One by one also removes each image's external file.
        try deleteAll(ImageRecord.inMap(id))
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
        for (mapID, names) in try tagNamesByMap() {
            texts[mapID, default: []].append(contentsOf: names)
        }
        return texts
    }

    public func fetchTopicCounts() async throws -> [MapID: Int] {
        var descriptor = FetchDescriptor<NodeRecord>()
        descriptor.propertiesToFetch = [\.mapID]
        var counts: [MapID: Int] = [:]
        for record in try modelContext.fetch(descriptor) {
            counts[MapID(record.mapID), default: 0] += 1
        }
        return counts
    }

    // MARK: Writing

    /// Every write ends here, so every transaction carries this repository's author.
    func commit() throws {
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

    private func insert<Record: StoredRecord>(_ values: [Record.Value], as _: Record.Type) {
        for value in values {
            let record = Record.make(for: value)
            record.update(from: value)
            modelContext.insert(record)
        }
    }

    private func upsert<Record: StoredRecord>(_ values: [Record.Value], as _: Record.Type) throws {
        guard !values.isEmpty else { return }
        let existing = try modelContext.fetch(Record.withIDs(values.map(Record.id(of:))))
        var recordsByID = Dictionary(grouping: existing, by: \.recordID)
        for value in values {
            var records = recordsByID.removeValue(forKey: Record.id(of: value)) ?? []
            let record: Record
            if records.isEmpty {
                record = Record.make(for: value)
                modelContext.insert(record)
            } else {
                record = records.removeFirst()
            }
            record.update(from: value)
            // Duplicates of one record can only come from sync; fold them into one.
            records.forEach(modelContext.delete)
        }
    }

    private func delete<Record: StoredRecord>(_ ids: [UUID], as _: Record.Type) throws {
        guard !ids.isEmpty else { return }
        try deleteAll(Record.withIDs(ids))
    }

    /// One record at a time: a batch delete goes around the change tracking
    /// that CloudKit mirroring relies on.
    private func deleteAll<Record: PersistentModel>(_ descriptor: FetchDescriptor<Record>) throws {
        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
    }

    // MARK: Reading

    private func deletedMapRecords() throws -> [MapRecord] {
        try modelContext.fetch(FetchDescriptor<MapRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    private func mapRecords(for mapID: MapID) throws -> [MapRecord] {
        let id = mapID.rawValue
        return try modelContext.fetch(FetchDescriptor<MapRecord>(predicate: #Predicate { $0.mapID == id }))
    }
}
