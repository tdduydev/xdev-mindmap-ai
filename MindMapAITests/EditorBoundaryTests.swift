import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

@Suite("Editor boundaries")
struct EditorBoundaryTests {
    let repository: SwiftDataMapRepository
    let mapID: MapID

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    /// Plan ▸ A, B, C, with an undo manager attached.
    private func open() async throws -> (EditorSession, UndoManager, [NodeID]) {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        var ids: [NodeID] = []
        session.addChild()
        for title in ["A", "B", "C"] {
            if !ids.isEmpty { session.addSibling() }
            let id = try #require(session.selection)
            session.rename(id, to: title)
            ids.append(id)
        }
        // Attached after the setup: without event grouping, registering
        // outside a group would raise.
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return (session, undoManager, ids)
    }

    private func step(_ undoManager: UndoManager, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    @Test func addsAroundARunAndUndoRedoes() async throws {
        let (session, undoManager, ids) = try await open()
        session.setSelection([ids[0], ids[1]], primary: ids[1])
        #expect(session.canAddBoundary)

        step(undoManager) { session.toggleBoundary() }

        let group = try #require(session.engine.state.groups.values.first)
        #expect(group.firstNodeID == ids[0])
        #expect(group.lastNodeID == ids[1])
        #expect(session.activeBoundary == group.id)
        #expect(undoManager.undoActionName == "Add Boundary")

        undoManager.undo()
        #expect(session.engine.state.groups.isEmpty)
        #expect(session.activeBoundary == nil)
        undoManager.redo()
        #expect(session.engine.state.group(group.id) != nil)
    }

    @Test func aGapOrTheCentralTopicIsNoRun() async throws {
        let (session, _, ids) = try await open()
        session.setSelection([ids[0], ids[2]], primary: ids[0])
        #expect(!session.canAddBoundary)
        session.selection = session.rootID
        #expect(!session.canAddBoundary)
        session.selection = ids[1]
        #expect(session.canAddBoundary)
    }

    @Test func renameRecolourAndDeleteKeyAreOneStepEach() async throws {
        let (session, undoManager, ids) = try await open()
        session.selection = ids[1]
        step(undoManager) { session.addBoundary() }
        let id = try #require(session.activeBoundary)

        step(undoManager) { session.renameBoundary(id, to: "  Phase 1 ") }
        #expect(session.engine.state.group(id)?.title == "Phase 1")
        #expect(undoManager.undoActionName == "Rename Boundary")
        step(undoManager) { session.setBoundaryColor(.teal, for: id) }
        #expect(session.engine.state.group(id)?.color == .teal)

        undoManager.undo()
        #expect(session.engine.state.group(id)?.color == nil)
        undoManager.redo()
        #expect(session.engine.state.group(id)?.color == .teal)

        // Delete with the boundary selected removes it; the topic stays.
        step(undoManager) { session.deleteSelection() }
        #expect(session.engine.state.group(id) == nil)
        #expect(session.engine.state.node(ids[1]) != nil)
        #expect(undoManager.undoActionName == "Remove Boundary")
        undoManager.undo()
        #expect(session.engine.state.group(id)?.title == "Phase 1")
    }

    @Test func toggleRemovesTheBoundaryFramingTheSelection() async throws {
        let (session, undoManager, ids) = try await open()
        session.selection = ids[2]
        step(undoManager) { session.toggleBoundary() }
        session.selection = ids[2]
        #expect(session.boundaryToRemove != nil)
        step(undoManager) { session.toggleBoundary() }
        #expect(session.engine.state.groups.isEmpty)
    }

    @Test func selectingATopicClearsTheBoundary() async throws {
        let (session, _, ids) = try await open()
        session.selection = ids[0]
        session.addBoundary()
        #expect(session.activeBoundary != nil)
        session.selection = ids[2]
        #expect(session.activeBoundary == nil)
    }

    /// The canvas scene carries the frame, and a click on its stroke finds it.
    @Test func sceneHitTestsTheOutlineAndTitle() throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let boundary = CanvasBoundary(id: GroupID(), frame: frame, title: "Phase", color: nil, isSuggestion: false)
        let scene = CanvasScene(layout: nil, topics: [], crossLinkLooks: [:], boundaries: [boundary])
        #expect(scene.boundary(at: CGPoint(x: 1, y: 50), tolerance: 4) == boundary.id)
        #expect(scene.boundary(at: CGPoint(x: 20, y: 10), tolerance: 4) == boundary.id)
        #expect(scene.boundary(at: CGPoint(x: 100, y: 60), tolerance: 4) == nil)
        #expect(scene.boundary(at: CGPoint(x: 300, y: 60), tolerance: 4) == nil)
    }

    private struct OpenFailed: Error {}
}
