import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

@Suite("Editor session")
struct EditorSessionTests {
    let repository: SwiftDataMapRepository
    let mapID: MapID

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    private func open() async throws -> EditorSession {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    @Test func opensWithTheRootSelected() async throws {
        let session = try await open()

        #expect(session.selection == session.rootID)
        #expect(session.rows.map(\.node.title) == ["Plan"])
    }

    @Test func editsAreSavedAndReopenTheSame() async throws {
        let session = try await open()

        session.addChild()
        let first = try #require(session.selection)
        session.rename(first, to: "Research")
        session.addSibling()
        let second = try #require(session.selection)
        session.rename(second, to: "Design")
        session.addChild()
        let nested = try #require(session.selection)
        session.rename(nested, to: "Wireframes")
        await session.flush()

        let reopened = try await open()
        #expect(reopened.rows.map(\.node.title) == ["Plan", "Research", "Design", "Wireframes"])
        #expect(reopened.rows.map(\.depth) == [0, 1, 1, 2])
        #expect(reopened.engine.state.nodes == session.engine.state.nodes)
    }

    @Test func newNodesAskForFocus() async throws {
        let session = try await open()

        session.addChild()

        #expect(session.focusRequest == session.selection)
        #expect(session.focusRequest != session.rootID)
    }

    @Test func rootCannotBeDeleted() async throws {
        let session = try await open()

        #expect(!session.canDeleteSelection)
        session.deleteSelection()

        #expect(session.rows.count == 1)
    }

    @Test func deletingMovesSelectionToANeighbour() async throws {
        let session = try await open()
        session.addChild()
        let first = try #require(session.selection)
        session.addSibling()
        let second = try #require(session.selection)

        session.deleteSelection()

        #expect(session.engine.state.node(second) == nil)
        #expect(session.selection == first)
    }

    @Test func collapsingHidesChildren() async throws {
        let session = try await open()
        session.addChild()
        let child = try #require(session.selection)
        session.addChild()
        #expect(session.rows.count == 3)

        session.toggleCollapsed(child)

        #expect(session.rows.map(\.id) == [session.rootID, child])
    }

    /// The Edit menu and ⌘Z go through the window's undo manager.
    @Test func undoManagerDrivesTheEngine() async throws {
        let session = try await open()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager

        undoManager.beginUndoGrouping()
        session.addChild()
        undoManager.endUndoGrouping()
        #expect(session.rows.count == 2)
        #expect(undoManager.undoActionName == String(localized: "Add Topic"))

        undoManager.undo()
        #expect(session.rows.count == 1)
        #expect(session.selection == session.rootID)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(session.rows.count == 2)

        await session.flush()
        let reopened = try await open()
        #expect(reopened.rows.count == 2)
    }

    @Test func undoWithoutAnUndoManagerUsesTheEngine() async throws {
        let session = try await open()
        session.addChild()

        session.undo()
        #expect(session.rows.count == 1)
        session.redo()
        #expect(session.rows.count == 2)
    }

    @Test func missingMapOpensAsMissing() async throws {
        let opening = await EditorSession.open(mapID: MapID(), repository: repository, onMapChange: { _ in })

        guard case .missing = opening else {
            Issue.record("Expected .missing")
            return
        }
    }

    private struct OpenFailed: Error {}
}
