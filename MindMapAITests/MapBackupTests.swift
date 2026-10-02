import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import SwiftUI
import Testing

/// File ▸ Export… ▸ MindMap AI Backup and File ▸ Import… of the file it
/// writes (MM-54). The format itself is tested in `MapArchiveTests`.
@Suite("Map backup")
struct MapBackupTests {
    let repository: SwiftDataMapRepository
    let folder: URL

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        folder = FileManager.default.temporaryDirectory.appending(path: "MapBackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    /// A stored map with a tag, a colour and a boundary, which Markdown drops.
    private func storedMap() async throws -> GraphState {
        let base = GraphState.newMap(title: "Trip", theme: .graphite)
        let rootID = try #require(base.map.rootNodeID)
        let mapID = base.map.id
        let flights = MindNode(mapID: mapID, parentID: rootID, title: "Flights", sortOrder: 1, color: .violet, symbol: "airplane")
        let hotels = MindNode(mapID: mapID, parentID: rootID, title: "Hotels", sortOrder: 2, taskState: .open, priority: .high)
        let tag = MindTag(mapID: mapID, name: "Book")
        let graph = GraphState(
            map: base.map, nodes: Array(base.nodes.values) + [flights, hotels],
            edges: [MindEdge(mapID: mapID, sourceNodeID: flights.id, targetNodeID: hotels.id, label: "then")],
            tags: [tag], nodeTags: [MindNodeTag(mapID: mapID, nodeID: hotels.id, tagID: tag.id)],
            groups: [MindGroup(mapID: mapID, parentNodeID: rootID, firstNodeID: flights.id, lastNodeID: hotels.id, title: "Bookings")]
        )
        try await repository.create(graph)
        return try #require(try await repository.loadGraph(for: mapID))
    }

    @Test func aBackupComesBackAsANewMapWithEverything() async throws {
        let original = try await storedMap()
        var options = ExportOptions()
        options.format = .backup
        // A branch picked for a text export earlier does not shrink a backup.
        options.branch = original.firstNodeTitled("Flights")?.id
        let data = try await MapExporter.data(for: original, options: options, colorScheme: .light)
        let url = try write(data, as: "Trip.\(ExportFormat.backup.fileExtension)")
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = FileTransfer(createMap: { await library.createMap($0) }, openMap: { opened = $0 })

        await transfer.importFile(at: url, into: .newMap)

        #expect(transfer.failure == nil)
        let id = try #require(opened)
        #expect(id != original.map.id)
        let copy = try #require(try await repository.loadGraph(for: id))
        #expect(copy.map.title == "Trip")
        #expect(copy.map.theme == .graphite)
        #expect(copy.nodes.count == 3)
        let flights = try #require(copy.firstNodeTitled("Flights"))
        let hotels = try #require(copy.firstNodeTitled("Hotels"))
        #expect(flights.color == .violet)
        #expect(flights.symbol == "airplane")
        #expect(hotels.priority == .high)
        #expect(copy.tags(of: hotels.id).map(\.name) == ["Book"])
        #expect(copy.edges.values.map(\.label) == ["then"])
        #expect(copy.groups.values.first.flatMap { copy.members(of: $0) } == [flights.id, hotels.id])
        // The original is untouched: importing never overwrites.
        #expect(try await repository.loadGraph(for: original.map.id)?.nodes.count == 3)
        #expect(try await repository.fetchMaps().count == 2)
    }

    @Test func aBackupDoesNotGoIntoAnOpenMap() async throws {
        let original = try await storedMap()
        guard case .ready(let session) = await EditorSession.open(mapID: original.map.id, repository: repository, onMapChange: { _ in }) else {
            Issue.record("The map did not open")
            return
        }
        let url = try write(try await MapArchive.exportData(original), as: "Trip.json")
        let transfer = FileTransfer(createMap: { _ in nil }, openMap: { _ in })

        await transfer.importFile(at: url, into: .openMap(session))

        #expect(transfer.failure == .backupIntoMap(fileName: "Trip.json"))
        #expect(!session.canUndo)
    }

    @Test func otherJSONIsNotABackup() async throws {
        let url = try write(Data(#"{"name": "Trip"}"#.utf8), as: "Trip.json")
        let transfer = FileTransfer(createMap: { _ in nil }, openMap: { _ in })

        await transfer.importFile(at: url, into: .newMap)

        #expect(transfer.failure == .notABackup(fileName: "Trip.json"))
    }

    @Test func aBackupFromANewerVersionSaysSo() async throws {
        let url = try write(Data(#"{"format": "asia.xdev.mindmapai.map", "version": 99}"#.utf8), as: "Trip.json")
        let transfer = FileTransfer(createMap: { _ in nil }, openMap: { _ in })

        await transfer.importFile(at: url, into: .newMap)

        #expect(transfer.failure == .newerBackup(fileName: "Trip.json"))
    }

    @Test func everyBackupFailureIsWorded() {
        let failures: [ImportFailure] = [
            .notABackup(fileName: "a.json"), .newerBackup(fileName: "a.json"),
            .damagedBackup(fileName: "a.json"), .backupIntoMap(fileName: "a.json"),
        ]
        for failure in failures {
            #expect(failure.title.contains("a.json"))
            #expect(!failure.message.isEmpty)
        }
    }
}

private extension GraphState {
    func firstNodeTitled(_ title: String) -> MindNode? {
        nodes.values.first { $0.title == title }
    }
}
