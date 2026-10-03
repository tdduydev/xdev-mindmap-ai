import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing
import UniformTypeIdentifiers

/// MindNode, SimpleMind and iThoughts in File ▸ Import… (FR-IO-12, MM-104).
/// The readers are tested in `MindNodeMapTests` and `SimpleMindIThoughtsTests`.
@Suite("MindNode, SimpleMind and iThoughts import")
struct OtherMindMapImportTests {
    let repository: SwiftDataMapRepository
    let folder: URL

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        folder = FileManager.default.temporaryDirectory.appending(path: "OtherMindMapImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func transfer(_ library: LibraryModel, opened: @escaping (MapID) -> Void = { _ in }) -> FileTransfer {
        FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: opened)
    }

    /// A `.mindnode` package as MindNode saves it: a folder with a binary `contents.xml`.
    private func mindNodeDocument(_ name: String) throws -> URL {
        let node: [String: Any] = [
            "nodeID": "R",
            "title": ["text": "<p style='font: 24px \"Helvetica\"'>Trip</p>"],
            "subnodes": [["nodeID": "A", "title": ["text": "<p>Tokyo</p>"], "subnodes": [[String: Any]]()]],
        ]
        let root: [String: Any] = ["version": 6, "canvas": ["mindMaps": [["mainNode": node]]]]
        let package = folder.appending(path: name)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
            .write(to: package.appending(path: "contents.xml"))
        try Data().write(to: package.appending(path: "viewState.plist"))
        return package
    }

    @Test func theOpenPanelOffersTheThreeFormats() {
        #expect(MapImporter.contentTypes.contains(.mindNodeDocument))
        #expect(MapImporter.contentTypes.contains(.simpleMindMap))
        #expect(MapImporter.contentTypes.contains(.iThoughtsMap))
        #expect(UTType.mindNodeDocument.conforms(to: .package))
        #expect(UTType.simpleMindMap.conforms(to: .zip))
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.mindnode")) == .mindNode)
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.smmx")) == .simpleMind)
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.itmz")) == .iThoughts)
    }

    @Test func aMindNodePackageBecomesAMap() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = transfer(library) { opened = $0 }

        await transfer.importFile(at: try mindNodeDocument("Trip.mindnode"), into: .newMap)

        #expect(transfer.failure == nil)
        let id = try #require(opened)
        let graph = try #require(try await repository.loadGraph(for: id))
        #expect(graph.map.title == "Trip")
        let rootID = try #require(graph.map.rootNodeID)
        #expect(graph.children(of: rootID).map(\.title) == ["Tokyo"])
        #expect(transfer.importSummary == nil)
    }

    @Test func badFilesSayWhatIsWrong() async throws {
        let library = LibraryModel(repository: repository)
        let transfer = transfer(library)

        let notZip = folder.appending(path: "note.smmx")
        try Data("plain text".utf8).write(to: notZip)
        await transfer.importFile(at: notZip, into: .newMap)
        #expect(transfer.failure == .wrongFormat(fileName: "note.smmx", format: .simpleMind))

        let empty = folder.appending(path: "Empty.mindnode")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await transfer.importFile(at: empty, into: .newMap)
        #expect(transfer.failure == .couldNotRead(fileName: "Empty.mindnode"))

        #expect(library.maps.isEmpty)
        for format in [ForeignFormat.mindNode, .simpleMind, .iThoughts] {
            let failure = ImportFailure.wrongFormat(fileName: "a." + format.fileExtension, format: format)
            #expect(failure.message.contains("." + format.fileExtension))
        }
        #expect(ImportFailure.unsupportedType(fileName: "a.rtf").message.contains(".mindnode"))
    }
}
