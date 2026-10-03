import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing
import UniformTypeIdentifiers

/// FreeMind and Freeplane maps in File ▸ Import… (free, one new map per file,
/// a summary of what was lost) (FR-IO-10, FR-IO-13).
@Suite("FreeMind import")
struct FreeMindImportTests {
    let repository: SwiftDataMapRepository
    let folder: URL

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        folder = FileManager.default.temporaryDirectory.appending(path: "FreeMindImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func transfer(_ library: LibraryModel, opened: @escaping (MapID) -> Void = { _ in }) -> FileTransfer {
        FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: opened)
    }

    private let plan = """
        <map version="1.0.1">
        <node ID="ID_1" TEXT="Plan">
        <node ID="ID_2" TEXT="Goals" FOLDED="true">
        <edge COLOR="#0000ff"/>
        <icon BUILTIN="idea"/>
        <arrowlink DESTINATION="ID_4"/>
        <node ID="ID_3" TEXT="Ship" LINK="https://example.com"/>
        </node>
        <node ID="ID_4" TEXT="Risks"/>
        </node>
        </map>
        """

    @Test func theOpenPanelOffersMMFiles() {
        #expect(MapImporter.contentTypes.contains(.freeMindMap))
        #expect(UTType.freeMindMap.conforms(to: .xml))
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.mm")) == .freeMind)
        #expect(ImportFailure.unsupportedType(fileName: "a.rtf").message.contains(".mm"))
    }

    @Test func importsAsANewMapAndSummarizesIcons() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = transfer(library) { opened = $0 }

        await transfer.importFile(at: try file("plan.mm", plan), into: .newMap)

        #expect(transfer.failure == nil)
        let id = try #require(opened)
        let graph = try #require(try await repository.loadGraph(for: id))
        let rootID = try #require(graph.map.rootNodeID)
        #expect(graph.map.title == "Plan")
        let goals = try #require(graph.children(of: rootID).first)
        #expect(graph.children(of: rootID).map(\.title) == ["Goals", "Risks"])
        #expect(goals.color == .blue)
        #expect(goals.isCollapsed)
        #expect(graph.children(of: goals.id).first?.link?.string == "https://example.com")
        #expect(graph.edges.count == 1)

        let summary = try #require(transfer.importSummary)
        #expect(summary.report.entries == [.init(loss: .icon, count: 1)])
        #expect(summary.message.contains("1"))
    }

    @Test func eachFileIsAMapOfItsOwn() async throws {
        let library = LibraryModel(repository: repository)
        let transfer = transfer(library)

        await transfer.importFile(at: try file("one.mm", plan), into: .newMap)
        await transfer.importFile(at: try file("two.mm", plan), into: .newMap)

        #expect(library.maps.count == 2)
    }

    @Test func badFilesSayWhatIsWrong() async throws {
        let library = LibraryModel(repository: repository)
        let transfer = transfer(library)

        await transfer.importFile(at: try file("notes.mm", #"<opml version="2.0"/>"#), into: .newMap)
        #expect(transfer.failure == .wrongFormat(fileName: "notes.mm", format: .freeMind))
        #expect(transfer.failure?.message.contains("Freeplane") == true)

        await transfer.importFile(at: try file("cut.mm", #"<map version="1.0.1"><node TEXT="A">"#), into: .newMap)
        #expect(transfer.failure == .damagedFile(fileName: "cut.mm"))

        await transfer.importFile(at: try file("empty.mm", #"<map version="1.0.1"/>"#), into: .newMap)
        #expect(transfer.failure == .noTopics(fileName: "empty.mm"))

        #expect(library.maps.isEmpty)
    }

    @Test func iconLossIsWorded() {
        let line = ImportSummary.line(for: .init(loss: .icon, count: 3))
        #expect(line.contains("3"))
    }
}
