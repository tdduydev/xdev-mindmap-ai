import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Stored node types (link, floating, image, summary, callout)")
struct NodeTypePersistenceTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository
    static let bytes = Data(repeating: 42, count: 4_096)

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    func imageRecords() throws -> [ImageRecord] {
        try ModelContext(container).fetch(FetchDescriptor<ImageRecord>())
    }

    /// A map with an image on the central topic, saved as an editor would.
    func mapWithImage() async throws -> (GraphEngine, MindImage) {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Pictures"))
        try await repository.create(engine.state)
        let rootID = try #require(engine.state.map.rootNodeID)
        let image = MindImage(mapID: engine.state.map.id, nodeID: rootID, data: Self.bytes, byteCount: Self.bytes.count)
        let changes = try engine.execute(EditGraphForTest { try $0.insertImage(image) })
        try await repository.save(changes, map: engine.state.map)
        return (engine, image)
    }

    @Test func imageEditsKeepTheStoredBytes() async throws {
        let (start, image) = try await mapWithImage()
        var engine = start
        let imageID = image.id

        let changes = try engine.execute(EditGraphForTest { try $0.updateImage(imageID) { $0.displayWidth = 96 } })
        try await repository.save(changes, map: engine.state.map)

        #expect(try await repository.imageData(for: image.id) == Self.bytes)
        let loaded = try #require(try await repository.loadGraph(for: engine.state.map.id))
        #expect(loaded.images[image.id]?.displayWidth == 96)
        #expect(loaded.images[image.id]?.data == nil)
    }

    /// Delete Topic, then undo: the image comes back with its bytes when the
    /// editor had loaded them.
    @Test func undoingARemovedImageStoresItsBytesAgain() async throws {
        let (start, image) = try await mapWithImage()
        var engine = start
        let imageID = image.id
        let mapID = engine.state.map.id
        engine.imageData[image.id] = try await repository.imageData(for: image.id)

        let removed = try engine.execute(EditGraphForTest { try $0.removeImage(imageID) })
        try await repository.save(removed, map: engine.state.map)
        #expect(try imageRecords().isEmpty)

        let undoResult = engine.undo()
        let undone = try #require(undoResult)
        try await repository.save(undone, map: engine.state.map)
        #expect(try await repository.imageData(for: image.id) == Self.bytes)
        #expect(try await repository.loadGraph(for: mapID) == engine.state)
    }

    @Test func deletingAMapDeletesItsImages() async throws {
        let (engine, _) = try await mapWithImage()
        #expect(try imageRecords().count == 1)

        try await repository.deleteMap(engine.state.map.id)

        #expect(try imageRecords().isEmpty)
    }

    /// One coordinate alone reads as no position, and is left as stored.
    @Test func halfAPositionIsNoPosition() async throws {
        let graph = GraphState.newMap(title: "Half")
        try await repository.create(graph)
        let context = ModelContext(container)
        let record = NodeRecord(nodeID: UUID(), mapID: graph.map.id.rawValue)
        record.title = "Half"
        record.positionX = 10
        context.insert(record)
        try context.save()

        let loaded = try #require(try await repository.loadGraph(for: graph.map.id))

        #expect(loaded.node(NodeID(record.nodeID))?.position == nil)
    }

    @Test func createdGraphKeepsLinkCalloutAndFloatingTopic() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Fields"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let mapID = engine.state.map.id
        let floating = MindNode(mapID: mapID, parentID: nil, title: "Aside", position: TopicPosition(x: 10, y: 20))
        try engine.execute(EditGraphForTest { transaction in
            try transaction.insertNode(floating)
            try transaction.updateNode(rootID) { node in
                node.link = TopicLink(string: "mailto:team@example.com")
                node.callout = "Due Friday"
            }
        })

        try await repository.create(engine.state)

        #expect(try await repository.loadGraph(for: mapID) == engine.state)
    }
}
