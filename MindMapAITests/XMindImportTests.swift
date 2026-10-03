import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing
import UniformTypeIdentifiers

/// XMind in File ▸ Import…: every sheet a new map, a summary of what was not
/// kept, and the messages of FR-IO-09 (FR-IO-11, FR-IO-13). The reader itself
/// is tested in `XMindMapTests`.
@Suite("XMind import")
struct XMindImportTests {
    let repository: SwiftDataMapRepository
    let folder: URL

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        folder = FileManager.default.temporaryDirectory.appending(path: "XMindImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    private func transfer(_ library: LibraryModel, opened: @escaping (MapID) -> Void = { _ in }) -> FileTransfer {
        FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: opened)
    }

    private let trip = #"""
        [{ "id": "s1", "title": "Sheet 1",
           "rootTopic": { "id": "root", "title": "Trip", "children": { "attached": [
             { "id": "a", "title": "Tokyo", "labels": ["Japan"], "markers": [{ "markerId": "flag-red" }] },
             { "id": "b", "title": "Kyoto" } ] } },
           "relationships": [ { "id": "r", "end1Id": "a", "end2Id": "b", "title": "train" } ] },
         { "id": "s2", "title": "Sheet 2", "rootTopic": { "id": "r2", "title": "Budget" } }]
        """#

    @Test func theOpenPanelOffersXMind() {
        #expect(MapImporter.contentTypes.contains(.xmind))
        #expect(UTType.xmind.conforms(to: .zip))
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.xmind")) == .xmind)
    }

    @Test func everySheetIsANewMapAndTheFirstOpens() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = transfer(library) { opened = $0 }

        await transfer.importFile(at: try file("trip.xmind", StoredZip.make(["content.json": Data(trip.utf8)])), into: .newMap)

        #expect(transfer.failure == nil)
        #expect(Set(library.maps.map(\.title)) == ["Trip", "Budget"])
        let id = try #require(opened)
        let graph = try #require(try await repository.loadGraph(for: id))
        #expect(graph.map.title == "Trip")
        let rootID = try #require(graph.map.rootNodeID)
        #expect(graph.children(of: rootID).map(\.title) == ["Tokyo", "Kyoto"])
        #expect(graph.edges.values.first?.label == "train")
        let tokyo = try #require(graph.children(of: rootID).first)
        #expect(graph.tags(of: tokyo.id).map(\.name) == ["Japan"])

        let summary = try #require(transfer.importSummary)
        #expect(summary.report.entries == [.init(loss: .icon, count: 1)])
    }

    @Test func badFilesSayWhatIsWrong() async throws {
        let library = LibraryModel(repository: repository)
        let transfer = transfer(library)

        await transfer.importFile(at: try file("note.xmind", Data("plain text".utf8)), into: .newMap)
        #expect(transfer.failure == .wrongFormat(fileName: "note.xmind", format: .xmind))

        await transfer.importFile(at: try file("cut.xmind", StoredZip.make(["content.json": Data("[{".utf8)])), into: .newMap)
        #expect(transfer.failure == .damagedFile(fileName: "cut.xmind"))

        await transfer.importFile(at: try file("empty.xmind", StoredZip.make(["content.json": Data("[]".utf8)])), into: .newMap)
        #expect(transfer.failure == .noTopics(fileName: "empty.xmind"))

        #expect(library.maps.isEmpty)
        for failure: ImportFailure in [.wrongFormat(fileName: "a.xmind", format: .xmind), .fileTooLarge(fileName: "a.xmind")] {
            #expect(failure.title.contains("a.xmind"))
            #expect(!failure.message.isEmpty)
        }
        #expect(ImportFailure.unsupportedType(fileName: "a.rtf").message.contains(".xmind"))
    }

    @Test func importIntoMapRefusesXMind() async throws {
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            Issue.record("The map did not open")
            return
        }
        let transfer = FileTransfer(createMap: { _, _ in nil }, openMap: { _ in })

        await transfer.importFile(at: try file("trip.xmind", StoredZip.make(["content.json": Data(trip.utf8)])), into: .openMap(session))

        #expect(transfer.failure == .foreignIntoMap(fileName: "trip.xmind"))
        #expect(session.engine.state.nodes.count == 1)
    }
}

/// A ZIP with stored (uncompressed) entries, as PKWARE APPNOTE.TXT lays it
/// out; enough for these tests, where deflate is covered by `XMindMapTests`.
private enum StoredZip {
    static func make(_ files: [String: Data]) -> Data {
        var archive = Data()
        var directory = Data()
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            let offset = UInt32(archive.count)
            let name = Data(path.utf8)
            let crc = crc32(data)
            var header = Data()
            header.le(0x0403_4B50, 4); header.le(20, 2); header.le(0, 2); header.le(0, 2); header.le(0, 4)
            header.le(crc, 4); header.le(UInt32(data.count), 4); header.le(UInt32(data.count), 4)
            header.le(UInt32(name.count), 2); header.le(0, 2)
            archive.append(header); archive.append(name); archive.append(data)

            directory.le(0x0201_4B50, 4); directory.le(20, 2); directory.le(20, 2); directory.le(0, 2); directory.le(0, 2)
            directory.le(0, 4); directory.le(crc, 4); directory.le(UInt32(data.count), 4); directory.le(UInt32(data.count), 4)
            directory.le(UInt32(name.count), 2); directory.le(0, 2); directory.le(0, 2); directory.le(0, 2); directory.le(0, 2)
            directory.le(0, 4); directory.le(offset, 4)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.le(0x0605_4B50, 4); archive.le(0, 2); archive.le(0, 2)
        archive.le(UInt32(files.count), 2); archive.le(UInt32(files.count), 2)
        archive.le(UInt32(directory.count), 4); archive.le(directoryOffset, 4); archive.le(0, 2)
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func le(_ value: UInt32, _ byteCount: Int) {
        append(contentsOf: (0 ..< byteCount).map { UInt8((value >> (8 * $0)) & 0xFF) })
    }
}
