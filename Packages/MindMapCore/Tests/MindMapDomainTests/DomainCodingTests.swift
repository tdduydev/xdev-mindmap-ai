import Foundation
import MindMapDomain
import Testing

@Suite("Domain values")
struct DomainCodingTests {
    @Test func identifierEncodesAsABareUUID() throws {
        let uuid = UUID()
        let data = try JSONEncoder().encode(NodeID(uuid))

        #expect(String(decoding: data, as: UTF8.self) == "\"\(uuid.uuidString)\"")
        #expect(try JSONDecoder().decode(NodeID.self, from: data) == NodeID(uuid))
    }

    @Test func nodeRoundTripsThroughJSON() throws {
        let mapID = MapID()
        let node = MindNode(
            mapID: mapID,
            parentID: NodeID(),
            title: "Thiết kế backend architecture cho HIS",
            note: "Mixed-language content must survive",
            sortOrder: 2.5,
            isCollapsed: true,
            metadata: NodeMetadata(origin: .ai),
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )

        let decoded = try JSONDecoder().decode(MindNode.self, from: JSONEncoder().encode(node))

        #expect(decoded == node)
    }

    @Test func updatedAtDefaultsToCreatedAt() {
        let created = Date(timeIntervalSinceReferenceDate: 42)
        let map = MindMap(title: "Plan", createdAt: created)

        #expect(map.updatedAt == created)
    }
}
