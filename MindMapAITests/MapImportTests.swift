import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing

/// File ▸ Import…: reading a picked file, a new map from it, or its topics in
/// the open map as one undo step (FR-IO-07, FR-IO-09).
@Suite("Map import")
struct MapImportTests {
    let repository: SwiftDataMapRepository
    let folder: URL

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        folder = FileManager.default.temporaryDirectory.appending(path: "MapImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        try file(name, Data(contents.utf8))
    }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    private func openSession(title: String = "Plan") async throws -> EditorSession {
        let graph = GraphState.newMap(title: title)
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    // MARK: Reading

    @Test func picksTheFormatByExtension() {
        #expect(MapImporter.format(of: URL(filePath: "/a/Notes.md")) == .markdown)
        #expect(MapImporter.format(of: URL(filePath: "/a/Notes.markdown")) == .markdown)
        #expect(MapImporter.format(of: URL(filePath: "/a/Notes.txt")) == .plainText)
        #expect(MapImporter.format(of: URL(filePath: "/a/Notes.rtf")) == nil)
        #expect(MapImporter.format(of: URL(filePath: "/a/Notes.png")) == nil)
    }

    @Test func readsMarkdown() async throws {
        let url = try file("Trip.md", "# Trip\n\n## Flights\n- Hanoi\n## Hotels\n")

        let imported = try await MapImporter.read(url)

        #expect(imported.name == "Trip")
        #expect(imported.format == .markdown)
        #expect(imported.draft.items.map(\.title) == ["Trip", "Flights", "Hanoi", "Hotels"])
    }

    @Test func refusesRichText() async throws {
        let url = try file("Trip.rtf", "{\\rtf1 Trip}")

        await #expect(throws: ImportFailure.unsupportedType(fileName: "Trip.rtf")) {
            try await MapImporter.read(url)
        }
    }

    @Test func refusesTextThatIsNotUnicode() async throws {
        // "Thiết kế" in a legacy single-byte encoding is not valid UTF-8.
        let url = try file("Legacy.txt", Data([0x54, 0x68, 0x69, 0xEA, 0xF0, 0x74, 0x0A]))

        await #expect(throws: ImportFailure.unreadableText(fileName: "Legacy.txt")) {
            try await MapImporter.read(url)
        }
    }

    @Test func refusesAnEmptyFile() async throws {
        let url = try file("Empty.md", "\n\n   \n")

        await #expect(throws: ImportFailure.emptyDocument(fileName: "Empty.md")) {
            try await MapImporter.read(url)
        }
    }

    @Test func reportsAFileThatIsGone() async throws {
        let url = folder.appending(path: "Gone.md")

        await #expect(throws: ImportFailure.couldNotRead(fileName: "Gone.md")) {
            try await MapImporter.read(url)
        }
    }

    @Test func everyFailureNamesWhatTheAppReads() {
        let failures: [ImportFailure] = [
            .unsupportedType(fileName: "a.rtf"), .unreadableText(fileName: "a.txt"),
            .emptyDocument(fileName: "a.md"), .couldNotRead(fileName: "a.md"),
            .couldNotOpenPanel, .couldNotSave,
        ]
        for failure in failures {
            #expect(!failure.title.isEmpty)
            #expect(!failure.message.isEmpty)
        }
        #expect(ImportFailure.unsupportedType(fileName: "a.rtf").title.contains("a.rtf"))
        #expect(ImportFailure.unsupportedType(fileName: "a.rtf").message.contains(".md"))
    }

    // MARK: A new map

    @Test func importAsANewMapStoresAndOpensIt() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: { opened = $0 })
        let url = try file("Ideas.txt", "Research\n\tInterviews\nDesign\n")

        await transfer.importFile(at: url, into: .newMap)

        #expect(transfer.failure == nil)
        let id = try #require(opened)
        #expect(library.maps.map(\.id) == [id])
        let graph = try #require(try await repository.loadGraph(for: id))
        let rootID = try #require(graph.map.rootNodeID)
        // Several top-level topics go under a central topic named after the file.
        #expect(graph.node(rootID)?.title == "Ideas")
        #expect(graph.children(of: rootID).map(\.title) == ["Research", "Design"])
        #expect(graph.children(of: rootID).first?.metadata.origin == .imported)
    }

    @Test func aFailedImportOpensNothing() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: { opened = $0 })
        let url = try file("Picture.png", Data([0x89, 0x50, 0x4E, 0x47]))

        await transfer.importFile(at: url, into: .newMap)

        #expect(transfer.failure == .unsupportedType(fileName: "Picture.png"))
        #expect(opened == nil)
        #expect(library.maps.isEmpty)
    }

    // MARK: Into the open map

    @Test func importIntoTheOpenMapIsOneUndoStep() async throws {
        let session = try await openSession()
        let rootID = try #require(session.rootID)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        let transfer = FileTransfer(createMap: { _, _ in nil }, openMap: { _ in })
        let url = try file("Steps.md", "- One\n  - One A\n- Two\n")

        undoManager.beginUndoGrouping()
        await transfer.importFile(at: url, into: .openMap(session))
        undoManager.endUndoGrouping()

        #expect(transfer.failure == nil)
        let state = session.engine.state
        #expect(state.children(of: rootID).map(\.title) == ["One", "Two"])
        #expect(session.selection == state.children(of: rootID).first?.id)
        #expect(undoManager.undoActionName == String(localized: "Import"))

        undoManager.undo()
        #expect(session.engine.state.children(of: rootID).isEmpty)
        #expect(session.engine.state.nodes.count == 1)

        undoManager.redo()
        #expect(session.engine.state.children(of: rootID).map(\.title) == ["One", "Two"])
        #expect(session.engine.state.nodes.count == 4)

        await session.flush()
        let reopened = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(reopened.nodes.count == 4)
    }

    @Test func importGoesUnderTheSelectedTopic() async throws {
        let session = try await openSession()
        session.addChild()
        let selected = try #require(session.selection)

        #expect(session.importOutline(PlainTextOutline.parse("Alpha\nBeta")))

        #expect(session.engine.state.children(of: selected).map(\.title) == ["Alpha", "Beta"])
    }

    @Test func anEmptyOutlineChangesNothing() async throws {
        let session = try await openSession()

        #expect(!session.importOutline(OutlineDraft()))
        #expect(!session.canUndo)
    }

    private struct OpenFailed: Error {}
}
