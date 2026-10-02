import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// Topic images on disk (MM-63): bytes beside the store, written only when
/// an image is added or replaced, kept across a reopen and a whole-graph create.
@Suite("Stored images")
struct ImagePersistenceTests {
    /// Above SwiftData's inline limit, so the bytes go to an external file.
    static let photo = Data((0..<1_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Every file under `folder` except the SQLite store and its journals.
    static func externalFiles(in folder: URL) -> [URL] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? []
        return files.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && !url.lastPathComponent.hasPrefix("Maps.store")
        }
    }

    @Test func savedImageSurvivesReopeningAndLivesOutsideTheDatabase() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Maps.store")

        var engine = try GraphEngine(state: GraphState.newMap(title: "Pictures"))
        let repository = try PersistenceController.makeRepository(at: .file(url))
        try await repository.create(engine.state)
        let rootID = try #require(engine.state.map.rootNodeID)
        let image = MindImage(mapID: engine.state.map.id, nodeID: rootID, data: Self.photo, pixelWidth: 2_048, pixelHeight: 1_536)
        let added = try engine.execute(SetNodeImageCommand(nodeID: rootID, image: image))
        try await repository.save(added, map: engine.state.map)

        #expect(Self.externalFiles(in: folder).contains { (try? Data(contentsOf: $0)) == Self.photo })

        let reopened = try PersistenceController.makeRepository(at: .file(url))
        let loaded = try #require(try await reopened.loadGraph(for: engine.state.map.id))
        #expect(loaded == engine.state)
        #expect(loaded.image(of: rootID)?.pixelWidth == 2_048)
        #expect(loaded.image(of: rootID)?.byteCount == Self.photo.count)
        #expect(loaded.image(of: rootID)?.data == nil)
        #expect(try await reopened.imageData(for: image.id) == Self.photo)
    }

    /// A size or description edit carries no bytes: the stored file is not rewritten.
    @Test func editingAnImageDoesNotRewriteItsFile() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Maps.store")

        var engine = try GraphEngine(state: GraphState.newMap(title: "Pictures"))
        let repository = try PersistenceController.makeRepository(at: .file(url))
        try await repository.create(engine.state)
        let rootID = try #require(engine.state.map.rootNodeID)
        let image = MindImage(mapID: engine.state.map.id, nodeID: rootID, data: Self.photo)
        try await repository.save(try engine.execute(SetNodeImageCommand(nodeID: rootID, image: image)), map: engine.state.map)
        let before = Self.externalFiles(in: folder).filter { (try? Data(contentsOf: $0)) == Self.photo }
        let dates = try before.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        #expect(before.count == 1)

        let edited = try engine.execute(UpdateImageCommand(imageID: image.id, displayWidth: .set(240), altText: .set("Whiteboard")))
        try await repository.save(edited, map: engine.state.map)

        let after = Self.externalFiles(in: folder).filter { (try? Data(contentsOf: $0)) == Self.photo }
        #expect(after == before)
        #expect(try after.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } == dates)
        let reopened = try PersistenceController.makeRepository(at: .file(url))
        let loaded = try #require(try await reopened.loadGraph(for: engine.state.map.id))
        #expect(loaded.images[image.id]?.altText == "Whiteboard")
        #expect(loaded.images[image.id]?.displayWidth == 240)
        #expect(try await reopened.imageData(for: image.id) == Self.photo)
    }

    /// A whole new graph (a backup, a duplicated map) stores the bytes it is given.
    @Test func createStoresTheBytesGivenBesideTheGraph() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Restored")
        let rootID = try #require(graph.map.rootNodeID)
        let withImage = MindImage(mapID: graph.map.id, nodeID: rootID, data: Data([1, 2, 3]), byteCount: 3)
        let state = GraphState(map: graph.map, nodes: graph.nodes.values, edges: [], images: [withImage])

        try await repository.create(state, imageData: [withImage.id: Data([1, 2, 3])])

        #expect(try await repository.imageData(for: withImage.id) == Data([1, 2, 3]))
        #expect(try await repository.loadGraph(for: graph.map.id) == state)
    }

    @Test func createWithoutBytesStoresTheRecordOnly() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Template")
        let rootID = try #require(graph.map.rootNodeID)
        let image = MindImage(mapID: graph.map.id, nodeID: rootID)
        let state = GraphState(map: graph.map, nodes: graph.nodes.values, edges: [], images: [image])

        try await repository.create(state)

        #expect(try await repository.imageData(for: image.id) == nil)
        #expect(try await repository.loadGraph(for: graph.map.id)?.images.keys.sorted() == [image.id])
    }
}
