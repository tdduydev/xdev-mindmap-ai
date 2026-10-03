import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapLayout
import MindMapPersistence
import SwiftUI
import Testing

@Suite("Editor summaries")
struct EditorSummaryTests {
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

    @Test func addsOverARunStartsTypingAndUndoRedoes() async throws {
        let (session, undoManager, ids) = try await open()
        session.setSelection([ids[0], ids[1]], primary: ids[1])
        #expect(session.canAddSummary)

        step(undoManager) { session.toggleSummary() }

        let group = try #require(session.engine.state.groups.values.first)
        let topicID = try #require(group.summaryNodeID)
        #expect(group.kind == .summary)
        #expect(group.firstNodeID == ids[0])
        #expect(group.lastNodeID == ids[1])
        #expect(session.selection == topicID)
        #expect(session.focusRequest == topicID)
        #expect(session.isSummaryTopic(topicID))
        #expect(session.summaryDescription(of: topicID) == "Summary of A to B")
        #expect(undoManager.undoActionName == "Add Summary")
        // The selected summary topic stands for its bracket.
        #expect(session.summaryToRemove == group.id)

        undoManager.undo()
        #expect(session.engine.state.groups.isEmpty)
        #expect(session.engine.state.node(topicID) == nil)
        undoManager.redo()
        #expect(session.engine.state.group(group.id) != nil)
        #expect(session.engine.state.node(topicID) != nil)
    }

    @Test func removeTakesTheSummaryTopicInOneStep() async throws {
        let (session, undoManager, ids) = try await open()
        session.setSelection([ids[2]], primary: ids[2])
        step(undoManager) { session.addSummary() }
        let group = try #require(session.engine.state.groups.values.first)
        let topicID = try #require(group.summaryNodeID)
        session.setSelection([ids[2]], primary: ids[2])
        #expect(session.summaryToRemove == group.id)
        #expect(!session.canAddSummary)

        step(undoManager) { session.toggleSummary() }

        #expect(session.engine.state.groups.isEmpty)
        #expect(session.engine.state.node(topicID) == nil)
        #expect(undoManager.undoActionName == "Remove Summary")
        undoManager.undo()
        #expect(session.engine.state.group(group.id) != nil)
        undoManager.redo()
        #expect(session.engine.state.group(group.id) == nil)
    }

    @Test func theCentralTopicAndAGapAreNoRun() async throws {
        let (session, _, ids) = try await open()
        session.setSelection([try #require(session.rootID)], primary: session.rootID)
        #expect(!session.canAddSummary)
        session.setSelection([ids[0], ids[2]], primary: ids[2])
        #expect(!session.canAddSummary)
    }

    /// Add Sibling on a summary topic adds a child: the summary topic stands
    /// apart from its parent's column.
    @Test func addSiblingOnASummaryTopicAddsAChild() async throws {
        let (session, _, ids) = try await open()
        session.setSelection([ids[0]], primary: ids[0])
        session.addSummary()
        let topicID = try #require(session.selection)

        session.addSibling()

        let added = try #require(session.selection)
        #expect(session.engine.state.node(added)?.parentID == topicID)
    }

    @Test func descriptionNamesOneOrTwoMembers() {
        #expect(EditorSession.summaryDescription(members: ["Design"]) == "Summary of Design")
        #expect(EditorSession.summaryDescription(members: ["Design", "Build", "Launch"]) == "Summary of Design to Launch")
        #expect(EditorSession.summaryDescription(members: []) == nil)
    }

    /// Export draws through the same `CanvasDrawing`, so the bracket is in the
    /// picture of the map too.
    @Test func theBracketIsDrawnWithTheEdges() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let a = NodeID()
        let b = NodeID()
        _ = try engine.execute(AddNodeCommand(nodeID: a, .child(of: rootID), title: "A"))
        _ = try engine.execute(AddNodeCommand(nodeID: b, .child(of: rootID), title: "B"))
        _ = try engine.execute(AddSummaryCommand(from: a, to: b))
        let layout = HorizontalTreeLayout().layout(engine.state, sizes: [:], options: CanvasModel.layoutOptions)
        #expect(layout.summaries.count == 1)
        // Without topics in the scene the bracket falls back to the boundary line.
        let scene = CanvasScene(layout: layout, topics: [], crossLinkLooks: [:])

        let drawing = CanvasDrawing.make(
            scene: scene, rect: layout.bounds, shapes: nil, selection: nil,
            variant: ColorVariant(colorScheme: .light, contrast: .standard)
        ) { _ in preconditionFailure("No topic to style") }

        #expect(drawing.edges.values.contains { !$0.isEmpty })
        let outside = CanvasDrawing.make(
            scene: scene, rect: layout.bounds.offsetBy(dx: 100_000, dy: 0), shapes: nil, selection: nil,
            variant: ColorVariant(colorScheme: .light, contrast: .standard)
        ) { _ in preconditionFailure("No topic to style") }
        #expect(outside.edges.isEmpty)
    }

    private struct OpenFailed: Error {}
}
