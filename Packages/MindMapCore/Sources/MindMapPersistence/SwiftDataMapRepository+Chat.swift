import Foundation
import MindMapAICore
import MindMapDomain
import SwiftData

extension SwiftDataMapRepository: ChatHistoryStore {
    public func chatTurns(for mapID: MapID) async throws -> [ChatTurn] {
        var seen = Set<UUID>()
        // A turn synced twice shows once; the copy is folded on the next append.
        let turns = try modelContext.fetch(ChatTurnRecord.inMap(mapID.rawValue))
            .filter { seen.insert($0.turnID).inserted }
            .map(\.domainValue)
        return Array(turns.suffix(ChatHistory.maximumTurns))
    }

    public func appendChatTurn(_ turn: ChatTurn, to mapID: MapID, at date: Date) async throws {
        var records = try modelContext.fetch(ChatTurnRecord.withID(turn.id))
        let record: ChatTurnRecord
        if records.isEmpty {
            record = ChatTurnRecord(turnID: turn.id, mapID: mapID.rawValue)
            record.createdAt = date
            modelContext.insert(record)
        } else {
            record = records.removeFirst()
            records.forEach(modelContext.delete)
        }
        try record.update(from: turn)
        try trimChat(of: mapID)
        try commit()
    }

    public func deleteChatTurn(_ turnID: UUID, from mapID: MapID) async throws {
        let records = try modelContext.fetch(ChatTurnRecord.withID(turnID)).filter { $0.mapID == mapID.rawValue }
        guard !records.isEmpty else { return }
        records.forEach(modelContext.delete)
        try commit()
    }

    public func clearChat(for mapID: MapID) async throws {
        let records = try modelContext.fetch(ChatTurnRecord.inMap(mapID.rawValue))
        guard !records.isEmpty else { return }
        records.forEach(modelContext.delete)
        try commit()
    }

    /// Drops the oldest turns beyond the limit, counting the unsaved insert.
    private func trimChat(of mapID: MapID) throws {
        let records = try modelContext.fetch(ChatTurnRecord.inMap(mapID.rawValue))
        let excess = records.count - ChatHistory.maximumTurns
        guard excess > 0 else { return }
        records.prefix(excess).forEach(modelContext.delete)
    }
}
