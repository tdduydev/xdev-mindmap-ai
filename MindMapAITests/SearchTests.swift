import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapSearch
import Testing

@Suite("Find in the editor")
struct EditorFindTests {
    let repository: SwiftDataMapRepository
    let mapID: MapID
    let ids: [String: NodeID]

    /// Root "Kế hoạch" with "Thiết kế" (collapsed, holding "Đặc tả"), "Triển khai"
    /// and "Kiểm thử", whose note mentions "thiết kế".
    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        var engine = try GraphEngine(state: GraphState.newMap(title: "Kế hoạch"))
        let rootID = try #require(engine.state.map.rootNodeID)
        var ids = ["Kế hoạch": rootID]
        for title in ["Thiết kế", "Đặc tả", "Triển khai", "Kiểm thử"] { ids[title] = NodeID() }
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: ids["Thiết kế"]!, .child(of: rootID), title: "Thiết kế"),
            AddNodeCommand(nodeID: ids["Đặc tả"]!, .child(of: ids["Thiết kế"]!), title: "Đặc tả"),
            AddNodeCommand(nodeID: ids["Triển khai"]!, .child(of: rootID), title: "Triển khai"),
            AddNodeCommand(nodeID: ids["Kiểm thử"]!, .child(of: rootID), title: "Kiểm thử", note: "Theo bản thiết kế"),
            UpdateNodeCommand(nodeID: ids["Thiết kế"]!, .isCollapsed(true)),
        ]))
        try await repository.create(engine.state)
        mapID = engine.state.map.id
        self.ids = ids
    }

    private func open() async throws -> EditorSession {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    private func id(_ title: String) -> NodeID { ids[title]! }

    @Test func typingFindsTitlesAndNotesWithoutAccents() async throws {
        let session = try await open()

        session.showFind()
        session.findText = "thiet ke"

        #expect(session.isFinding)
        #expect(session.findMatches == [id("Thiết kế"), id("Kiểm thử")])
        #expect(session.selection == id("Thiết kế"))
        #expect(session.scrollRequest == id("Thiết kế"))
        #expect(session.currentMatchNumber == 1)
    }

    @Test func dMatchesTheVietnameseLetter() async throws {
        let session = try await open()

        session.findText = "dac ta"

        #expect(session.findMatches == [id("Đặc tả")])
    }

    @Test func typingDoesNotOpenBranches() async throws {
        let session = try await open()

        session.findText = "dac"

        // The only match is inside a collapsed branch: nothing is selected or opened yet.
        #expect(session.findMatches == [id("Đặc tả")])
        #expect(session.currentMatch == nil)
        #expect(session.engine.state.node(id("Thiết kế"))?.isCollapsed == true)
        #expect(!session.canUndo)
    }

    @Test func nextAndPreviousWrapAround() async throws {
        let session = try await open()
        session.findText = "thiet ke"

        session.findNext()
        #expect(session.selection == id("Kiểm thử"))
        #expect(session.currentMatchNumber == 2)
        session.findNext()
        #expect(session.selection == id("Thiết kế"))
        session.findPrevious()
        #expect(session.selection == id("Kiểm thử"))
    }

    @Test func nextContinuesFromAClickedMatch() async throws {
        let session = try await open()
        session.findText = "k"
        #expect(session.findMatches == [id("Kế hoạch"), id("Thiết kế"), id("Triển khai"), id("Kiểm thử")])

        session.selection = id("Triển khai")
        session.findNext()

        #expect(session.selection == id("Kiểm thử"))
    }

    @Test func goingToAHiddenMatchRevealsItAsOneUndoStep() async throws {
        let session = try await open()
        let undoManager = UndoManager()
        session.undoManager = undoManager
        session.findText = "dac ta"

        session.findNext()

        #expect(session.selection == id("Đặc tả"))
        #expect(session.engine.state.node(id("Thiết kế"))?.isCollapsed == false)
        #expect(session.rows.map(\.id).contains(id("Đặc tả")))
        #expect(undoManager.undoActionName == String(localized: "Reveal Topic"))

        undoManager.undo()
        #expect(session.engine.state.node(id("Thiết kế"))?.isCollapsed == true)
        #expect(!session.rows.map(\.id).contains(id("Đặc tả")))
        #expect(session.findMatches == [id("Đặc tả")])

        undoManager.redo()
        #expect(session.engine.state.node(id("Thiết kế"))?.isCollapsed == false)
    }

    @Test func matchesFollowEdits() async throws {
        let session = try await open()
        session.findText = "trien khai"
        #expect(session.findMatches == [id("Triển khai")])

        session.rename(id("Triển khai"), to: "Vận hành")
        #expect(session.findMatches.isEmpty)
        #expect(session.currentMatch == nil)

        session.undo()
        #expect(session.findMatches == [id("Triển khai")])
    }

    @Test func endingFindClearsMatches() async throws {
        let session = try await open()
        session.showFind()
        session.findText = "thiet"

        session.endFind()

        #expect(!session.isFinding)
        #expect(session.findText.isEmpty)
        #expect(session.findMatches.isEmpty)
        #expect(!session.hasFindMatches)
    }

    @Test func nothingToFindDoesNothing() async throws {
        let session = try await open()
        let selection = session.selection
        session.findText = "khong co"

        session.findNext()
        session.findPrevious()

        #expect(session.findMatches.isEmpty)
        #expect(session.selection == selection)
    }

    private struct OpenFailed: Error {}
}

@Suite("Library search")
struct LibrarySearchModelTests {
    let repository: SwiftDataMapRepository
    let library: LibraryModel

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        library = LibraryModel(repository: repository)
    }

    private func createMap(_ title: String, topics: [String]) async throws -> MapID {
        var engine = try GraphEngine(state: GraphState.newMap(title: title))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(BatchCommand(topics.map { AddNodeCommand(.child(of: rootID), title: $0) }))
        try await repository.create(engine.state)
        return engine.state.map.id
    }

    @Test func findsTitlesFirstThenTopics() async throws {
        let content = try await createMap("Weekly", topics: ["Thiết kế API"])
        let title = try await createMap("Thiết kế sản phẩm", topics: ["Người dùng"])
        _ = try await createMap("Đà Lạt", topics: ["Hotel"])
        await library.load()

        library.searchText = "THIET KE"
        await library.search()

        let rows = library.searchRows(in: .all)
        #expect(rows.map(\.map.id) == [title, content])
        #expect(rows.map(\.match) == [.title, .content(excerpt: "Thiết kế API")])
        #expect(library.searchedQuery == SearchQuery("thiet ke"))
    }

    @Test func dMatchesTheVietnameseLetter() async throws {
        let trip = try await createMap("Đà Lạt", topics: [])
        await library.load()

        library.searchText = "d"
        await library.search()

        #expect(library.searchRows(in: .all).map(\.map.id) == [trip])
    }

    @Test func searchFollowsEditsAndNewMaps() async throws {
        let id = try await createMap("Plan", topics: [])
        await library.load()
        library.searchText = "roadmap"
        await library.search()
        #expect(library.searchRows(in: .all).isEmpty)

        // An editor saving a change invalidates the index; the view searches again.
        var graph = try #require(try await repository.loadGraph(for: id))
        var engine = try GraphEngine(state: graph)
        let rootID = try #require(graph.map.rootNodeID)
        let changes = try engine.execute(AddNodeCommand(.child(of: rootID), title: "Roadmap"))
        try await repository.save(changes, map: engine.state.map)
        graph = engine.state
        let generation = library.searchGeneration
        library.didChange(graph.map)
        #expect(library.searchGeneration != generation)
        await library.search()

        #expect(library.searchRows(in: .all).map(\.map.id) == [id])
    }

    @Test func searchStaysInsideTheSection() async throws {
        let plain = try await createMap("Alpha notes", topics: [])
        let favorite = try await createMap("Alpha plan", topics: [])
        await library.load()
        let favoriteMap = try #require(library.maps.first { $0.id == favorite })
        await library.toggleFavorite(favoriteMap)

        library.searchText = "alpha"
        await library.search()

        #expect(library.searchRows(in: .all).map(\.map.id) == [plain, favorite])
        #expect(library.searchRows(in: .favorites).map(\.map.id) == [favorite])
    }

    @Test func clearingTheFieldEndsTheSearch() async throws {
        _ = try await createMap("Plan", topics: [])
        await library.load()
        library.searchText = "plan"
        await library.search()
        #expect(library.isSearching)

        library.searchText = "  "
        await library.search()

        #expect(!library.isSearching)
        #expect(library.searchResults == .empty)
        #expect(library.searchedQuery == nil)
    }
}
