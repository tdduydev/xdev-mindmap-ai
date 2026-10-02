import Foundation
import MindMapDomain
import SwiftData

/// A record type the repository writes one domain value into, so saving and
/// deleting work the same way for every record of a map.
protocol StoredRecord: PersistentModel {
    associatedtype Value
    var recordID: UUID { get }
    static func id(of value: Value) -> UUID
    static func make(for value: Value) -> Self
    func update(from value: Value)
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<Self>
    static func inMap(_ mapID: UUID) -> FetchDescriptor<Self>
}

extension NodeRecord: StoredRecord {
    var recordID: UUID { nodeID }
    static func id(of node: MindNode) -> UUID { node.id.rawValue }
    static func make(for node: MindNode) -> NodeRecord { NodeRecord(nodeID: node.id.rawValue, mapID: node.mapID.rawValue) }
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<NodeRecord> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.nodeID) })
    }
    static func inMap(_ mapID: UUID) -> FetchDescriptor<NodeRecord> {
        FetchDescriptor(predicate: #Predicate { $0.mapID == mapID })
    }
}

extension EdgeRecord: StoredRecord {
    var recordID: UUID { edgeID }
    static func id(of edge: MindEdge) -> UUID { edge.id.rawValue }
    static func make(for edge: MindEdge) -> EdgeRecord { EdgeRecord(edgeID: edge.id.rawValue, mapID: edge.mapID.rawValue) }
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<EdgeRecord> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.edgeID) })
    }
    static func inMap(_ mapID: UUID) -> FetchDescriptor<EdgeRecord> {
        FetchDescriptor(predicate: #Predicate { $0.mapID == mapID })
    }
}

extension TagRecord: StoredRecord {
    var recordID: UUID { tagID }
    static func id(of tag: MindTag) -> UUID { tag.id.rawValue }
    static func make(for tag: MindTag) -> TagRecord { TagRecord(tagID: tag.id.rawValue, mapID: tag.mapID?.rawValue) }
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<TagRecord> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.tagID) })
    }
    /// The map's own tags only; shared tags belong to the library.
    static func inMap(_ mapID: UUID) -> FetchDescriptor<TagRecord> {
        let id: UUID? = mapID
        return FetchDescriptor(predicate: #Predicate { $0.mapID == id })
    }
    /// The map's own tags and every shared tag, which any map may use.
    static func available(in mapID: UUID) -> FetchDescriptor<TagRecord> {
        let id: UUID? = mapID
        return FetchDescriptor(predicate: #Predicate { $0.mapID == id || $0.mapID == nil })
    }
}

extension NodeTagRecord: StoredRecord {
    var recordID: UUID { linkID }
    static func id(of link: MindNodeTag) -> UUID { link.id.rawValue }
    static func make(for link: MindNodeTag) -> NodeTagRecord { NodeTagRecord(linkID: link.id.rawValue, mapID: link.mapID.rawValue) }
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<NodeTagRecord> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.linkID) })
    }
    static func inMap(_ mapID: UUID) -> FetchDescriptor<NodeTagRecord> {
        FetchDescriptor(predicate: #Predicate { $0.mapID == mapID })
    }
}

extension GroupRecord: StoredRecord {
    var recordID: UUID { groupID }
    static func id(of group: MindGroup) -> UUID { group.id.rawValue }
    static func make(for group: MindGroup) -> GroupRecord { GroupRecord(groupID: group.id.rawValue, mapID: group.mapID.rawValue) }
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<GroupRecord> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.groupID) })
    }
    static func inMap(_ mapID: UUID) -> FetchDescriptor<GroupRecord> {
        FetchDescriptor(predicate: #Predicate { $0.mapID == mapID })
    }
}

extension ImageRecord: StoredRecord {
    var recordID: UUID { imageID }
    static func id(of image: MindImage) -> UUID { image.id.rawValue }
    static func make(for image: MindImage) -> ImageRecord { ImageRecord(imageID: image.id.rawValue, mapID: image.mapID.rawValue) }
    static func withIDs(_ ids: [UUID]) -> FetchDescriptor<ImageRecord> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.imageID) })
    }
    static func inMap(_ mapID: UUID) -> FetchDescriptor<ImageRecord> {
        FetchDescriptor(predicate: #Predicate { $0.mapID == mapID })
    }
}
