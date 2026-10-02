import Foundation
import MindMapDomain
import MindMapGraph
import SwiftData

/// `MapRepository` on SwiftData. Runs on its own actor with its own context, so
/// saving never blocks the UI.
@ModelActor
public actor SwiftDataMapRepository: MapRepository {
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
        try modelContext.save()
    }

    public func save(_ changes: GraphChangeSet, map: MindMap) async throws {
        try mapRecord(for: map).updateGraphFields(from: map)
        try upsertNodes(changes.savedNodes)
        try deleteNodes(changes.deletedNodeIDs)
        try upsertEdges(changes.savedEdges)
        try deleteEdges(changes.deletedEdgeIDs)
        try modelContext.save()
    }

    public func setFavorite(_ isFavorite: Bool, for mapID: MapID) async throws {
        guard let record = try mapRecords(for: mapID).first else { return }
        record.isFavorite = isFavorite
        try modelContext.save()
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
        try modelContext.save()
    }

    // MARK: Writing

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
