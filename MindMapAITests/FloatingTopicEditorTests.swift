import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

@Suite("Floating topic editor")
struct FloatingTopicEditorTests {
    private struct OpenFailure: Error {}

    private func open() async throws -> EditorSession {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailure()
        }
        return session
    }

    @Test func addMoveAndAttachEachUndoAndRedo() async throws {
        let session = try await open()
        let root = try #require(session.rootID)
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        let initial = TopicPosition(x: 180, y: 80)
        let moved = TopicPosition(x: 220, y: 140)

        undo.beginUndoGrouping()
        let floating = try #require(session.addFloatingTopic(at: initial))
        undo.endUndoGrouping()
        #expect(session.engine.state.node(floating)?.position == initial)
        #expect(session.rows.map(\.id) == [root, floating])
        #expect(undo.undoActionName == "Add Floating Topic")
        undo.undo()
        #expect(session.engine.state.node(floating) == nil)
        undo.redo()
        #expect(session.engine.state.node(floating)?.position == initial)

        undo.beginUndoGrouping()
        session.moveFloatingTopic(floating, to: moved)
        undo.endUndoGrouping()
        #expect(session.engine.state.node(floating)?.position == moved)
        #expect(undo.undoActionName == "Move Topic")
        undo.undo()
        #expect(session.engine.state.node(floating)?.position == initial)
        undo.redo()
        #expect(session.engine.state.node(floating)?.position == moved)

        #expect(session.canAttachSelection)
        undo.beginUndoGrouping()
        session.attach(floating, to: root)
        undo.endUndoGrouping()
        #expect(session.engine.state.node(floating)?.parentID == root)
        #expect(session.engine.state.node(floating)?.position == nil)
        #expect(undo.undoActionName == "Move Topic")
        undo.undo()
        #expect(session.engine.state.node(floating)?.parentID == nil)
        #expect(session.engine.state.node(floating)?.position == moved)
        undo.redo()
        #expect(session.engine.state.node(floating)?.parentID == root)
        #expect(session.engine.state.node(floating)?.position == nil)
    }

    @Test func detachBranchUndoAndRedo() async throws {
        let session = try await open()
        let root = try #require(session.rootID)
        session.addChild()
        let branch = try #require(session.selection)
        session.addChild()
        let child = try #require(session.selection)
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        let position = TopicPosition(x: -120, y: 200)

        undo.beginUndoGrouping()
        session.detach(branch, to: position)
        undo.endUndoGrouping()
        #expect(session.engine.state.node(branch)?.parentID == nil)
        #expect(session.engine.state.node(branch)?.position == position)
        #expect(session.engine.state.node(child)?.parentID == branch)
        #expect(session.rows.map(\.id) == [root, branch, child])
        #expect(undo.undoActionName == "Detach Topic")
        undo.undo()
        #expect(session.engine.state.node(branch)?.parentID == root)
        #expect(session.engine.state.node(branch)?.position == nil)
        undo.redo()
        #expect(session.engine.state.node(branch)?.parentID == nil)
        #expect(session.engine.state.node(branch)?.position == position)
    }
}
