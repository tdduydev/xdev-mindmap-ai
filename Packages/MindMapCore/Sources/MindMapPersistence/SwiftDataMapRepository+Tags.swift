import Foundation
import MindMapDomain
import MindMapGraph
import SwiftData

// Shared tags as library data. Every write here deletes and updates records
// one by one, as the rest of the repository does, for CloudKit's change tracking.
extension SwiftDataMapRepository {
    public func sharedTagMapCounts() async throws -> [TagID: Int] {
        let shared = Set(try sharedTagRecords().map(\.tagID))
        guard !shared.isEmpty else { return [:] }
        var descriptor = FetchDescriptor<NodeTagRecord>()
        descriptor.propertiesToFetch = [\.mapID, \.tagID]
        var maps: [UUID: Set<UUID>] = [:]
        for link in try modelContext.fetch(descriptor) where shared.contains(link.tagID) {
            maps[link.tagID, default: []].insert(link.mapID)
        }
        return Dictionary(uniqueKeysWithValues: maps.map { (TagID($0.key), $0.value.count) })
    }

    public func renameSharedTag(_ id: TagID, to name: String) async throws -> LibraryTagChange {
        let record = try tagRecord(id, shared: true)
        guard let name = MindTag.normalizedName(name) else { throw LibraryTagError.invalidName }
        let key = MindTag.key(for: name)
        if let other = try sharedTagRecords().first(where: { $0.tagID != record.tagID && MindTag.key(for: $0.name) == key }) {
            throw LibraryTagError.nameTaken(TagID(other.tagID))
        }
        guard record.name != name else { return LibraryTagChange() }
        record.name = name
        record.updatedAt = .now
        return try finish(LibraryTagChange(savedTags: [record.domainValue]))
    }

    public func setSharedTagColor(_ id: TagID, to color: TopicColor?) async throws -> LibraryTagChange {
        let record = try tagRecord(id, shared: true)
        guard record.colorToken != color?.rawValue else { return LibraryTagChange() }
        record.colorToken = color?.rawValue
        record.updatedAt = .now
        return try finish(LibraryTagChange(savedTags: [record.domainValue]))
    }

    public func deleteSharedTag(_ id: TagID) async throws -> LibraryTagChange {
        let record = try tagRecord(id, shared: true)
        var change = LibraryTagChange(deletedTagIDs: [id])
        for link in try links(to: record.tagID) {
            change.deletedNodeTagIDs.append(NodeTagID(link.linkID))
            modelContext.delete(link)
        }
        modelContext.delete(record)
        return try finish(change)
    }

    public func mergeSharedTags(into survivorID: TagID, merging mergedIDs: [TagID]) async throws -> LibraryTagChange {
        let survivor = try tagRecord(survivorID, shared: true)
        let merged = try mergedIDs.filter { $0 != survivorID }.map { try tagRecord($0, shared: true) }
        var change = LibraryTagChange()
        try merge(merged, into: survivor, recording: &change)
        return try finish(change)
    }

    public func makeTagShared(_ id: TagID) async throws -> LibraryTagChange {
        let record = try tagRecord(id, shared: false)
        let key = MindTag.key(for: record.name)
        if let other = try sharedTagRecords().first(where: { MindTag.key(for: $0.name) == key }) {
            throw LibraryTagError.nameTaken(TagID(other.tagID))
        }
        record.mapID = nil
        record.updatedAt = .now
        return try finish(LibraryTagChange(savedTags: [record.domainValue]))
    }

    public func makeMapTag(_ id: TagID, in mapID: MapID) async throws -> LibraryTagChange {
        let record = try tagRecord(id, shared: true)
        let target = mapID.rawValue
        let otherMaps = Set(try links(to: record.tagID).map(\.mapID)).subtracting([target])
        guard otherMaps.isEmpty else { throw LibraryTagError.usedInOtherMaps(count: otherMaps.count) }
        let mapTags = try modelContext.fetch(TagRecord.inMap(target))
        let key = MindTag.key(for: record.name)
        if let other = mapTags.first(where: { MindTag.key(for: $0.name) == key }) {
            throw LibraryTagError.nameTaken(TagID(other.tagID))
        }
        record.mapID = target
        record.sortOrder = (mapTags.map(\.sortOrder).max() ?? -1) + 1
        record.updatedAt = .now
        return try finish(LibraryTagChange(savedTags: [record.domainValue]))
    }

    public func repairSharedTags() async throws -> LibraryTagChange {
        let groups = Dictionary(grouping: try sharedTagRecords()) { MindTag.key(for: $0.name) }
        var change = LibraryTagChange()
        for records in groups.values where records.count > 1 {
            // The oldest survives, by the same order on every device.
            let sorted = records.sorted { ($0.createdAt, $0.tagID.uuidString) < ($1.createdAt, $1.tagID.uuidString) }
            try merge(Array(sorted.dropFirst()), into: sorted[0], recording: &change)
        }
        guard !change.isEmpty else { return change }
        return try finish(change)
    }

    // MARK: Helpers

    /// The names of the tags each map's topics carry, shared tags included.
    func tagNamesByMap() throws -> [MapID: [String]] {
        var tagDescriptor = FetchDescriptor<TagRecord>()
        tagDescriptor.propertiesToFetch = [\.tagID, \.name]
        let names = Dictionary(try modelContext.fetch(tagDescriptor).map { ($0.tagID, $0.name) }) { first, _ in first }
        guard !names.isEmpty else { return [:] }
        var linkDescriptor = FetchDescriptor<NodeTagRecord>()
        linkDescriptor.propertiesToFetch = [\.mapID, \.tagID]
        var used: [UUID: Set<UUID>] = [:]
        for link in try modelContext.fetch(linkDescriptor) where names[link.tagID] != nil {
            used[link.mapID, default: []].insert(link.tagID)
        }
        return Dictionary(uniqueKeysWithValues: used.map { mapID, tagIDs in
            (MapID(mapID), tagIDs.compactMap { names[$0] })
        })
    }

    private func sharedTagRecords() throws -> [TagRecord] {
        try modelContext.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { $0.mapID == nil }))
    }

    /// The first record of a tag, which must be in the expected scope.
    private func tagRecord(_ id: TagID, shared: Bool) throws -> TagRecord {
        guard let record = try modelContext.fetch(TagRecord.withIDs([id.rawValue])).first else {
            throw LibraryTagError.tagNotFound(id)
        }
        guard (record.mapID == nil) == shared else { throw LibraryTagError.wrongScope(id) }
        return record
    }

    private func links(to tagID: UUID) throws -> [NodeTagRecord] {
        try modelContext.fetch(FetchDescriptor<NodeTagRecord>(predicate: #Predicate { $0.tagID == tagID }))
    }

    /// Points the merged tags' links at the survivor and deletes the merged
    /// tags. A topic that ends up with two links keeps the older one, the
    /// choice `GraphTransaction.moveTagLinks` and repair make too.
    private func merge(_ merged: [TagRecord], into survivor: TagRecord, recording change: inout LibraryTagChange) throws {
        var kept: [String: NodeTagRecord] = [:]
        for link in try links(to: survivor.tagID) {
            kept[Self.linkKey(link)] = link
        }
        let now = Date.now
        for tag in merged {
            for link in try links(to: tag.tagID) {
                let key = Self.linkKey(link)
                if let existing = kept[key] {
                    let existingIsOlder = (existing.createdAt, existing.linkID.uuidString) <= (link.createdAt, link.linkID.uuidString)
                    let doomed = existingIsOlder ? link : existing
                    change.deletedNodeTagIDs.append(NodeTagID(doomed.linkID))
                    change.savedNodeTags.removeAll { $0.id.rawValue == doomed.linkID }
                    modelContext.delete(doomed)
                    if existingIsOlder { continue }
                }
                link.tagID = survivor.tagID
                link.updatedAt = now
                kept[key] = link
                change.savedNodeTags.append(link.domainValue)
            }
            change.deletedTagIDs.append(TagID(tag.tagID))
            modelContext.delete(tag)
        }
    }

    private static func linkKey(_ link: NodeTagRecord) -> String {
        "\(link.mapID)/\(link.nodeID)"
    }

    private func finish(_ change: LibraryTagChange) throws -> LibraryTagChange {
        guard !change.isEmpty else { return change }
        try commit()
        publish(.tagsChanged(change))
        return change
    }
}
