import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI
import Testing

/// FR-ORG-30: a short remark in a bubble above a topic, set as one named
/// command, with its room reserved on the canvas and in pictures of the map.
@Suite("Topic callout")
struct TopicCalloutTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    private func open(_ graph: GraphState = .newMap(title: "Plan")) async throws -> EditorSession {
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    private func canvas(_ graph: GraphState) async throws -> CanvasModel {
        let canvas = CanvasModel(session: try await open(graph))
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        return canvas
    }

    private func graph(children: [String] = ["Flights", "Hotels", "Visas"]) throws -> GraphState {
        var engine = try GraphEngine(state: .newMap(title: "Trip"))
        let rootID = try #require(engine.state.map.rootNodeID)
        for child in children {
            try engine.execute(AddNodeCommand(.child(of: rootID), title: child))
        }
        return engine.state
    }

    private func undoManager(for session: EditorSession) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return undoManager
    }

    private func step(_ undoManager: UndoManager, _ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    @Test func addEditAndRemoveAreNamedStepsThatUndoAndRedo() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let rootID = try #require(session.rootID)

        step(undoManager) { session.setCallout("  Check the budget ", for: rootID) }
        #expect(session.selectedNode?.callout == "Check the budget")
        #expect(undoManager.undoActionName == String(localized: "Add Callout"))

        step(undoManager) { session.setCallout("Due Friday", for: rootID) }
        #expect(undoManager.undoActionName == String(localized: "Edit Callout"))

        step(undoManager) { session.removeCallout(from: rootID) }
        #expect(session.selectedNode?.callout == nil)
        #expect(undoManager.undoActionName == String(localized: "Remove Callout"))

        undoManager.undo()
        #expect(session.selectedNode?.callout == "Due Friday")
        undoManager.undo()
        #expect(session.selectedNode?.callout == "Check the budget")
        undoManager.redo()
        undoManager.redo()
        #expect(session.selectedNode?.callout == nil)
        undoManager.undo()

        await session.flush()
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.node(rootID)?.callout == "Due Friday")
    }

    /// Closing an empty new bubble, or committing the same text, is no step.
    @Test func blankOrUnchangedTextLeavesNoStep() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)

        session.beginEditingSelectionCallout()
        #expect(session.calloutEditorTarget == rootID)
        session.setCallout("   ", for: rootID)
        #expect(session.calloutEditorTarget == nil)
        #expect(!session.engine.canUndo)

        session.setCallout("Later", for: rootID)
        let changes = session.engine.state
        session.setCallout(" Later", for: rootID)
        #expect(session.engine.state == changes)
    }

    @Test func menuStateFollowsTheSelection() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)
        #expect(session.canEditSelectionCallout && !session.selectionHasCallout)
        session.setCallout("Later", for: rootID)
        #expect(session.selectionHasCallout)
        session.selection = nil
        #expect(!session.canEditSelectionCallout && !session.selectionHasCallout)
    }

    /// The bubble sits above its card, the sibling above makes room, and
    /// deleting the topic takes the bubble in the same step.
    @Test func canvasReservesTheBubbleAndDeleteTakesIt() async throws {
        let graph = try graph()
        let canvas = try await canvas(graph)
        let session = canvas.session
        let rootID = try #require(graph.map.rootNodeID)
        let hotels = try #require(graph.children(of: rootID).dropFirst().first?.id)
        let before = try #require(canvas.scene.topic(hotels)?.frame)

        session.setCallout("Ask about breakfast", for: hotels)
        await canvas.layoutSettled()
        let topic = try #require(canvas.scene.topic(hotels))
        let bubble = try #require(topic.calloutFrame)
        #expect(topic.callout == "Ask about breakfast")
        #expect(bubble.maxY == topic.frame.minY - CanvasMetrics.calloutSpacing)
        #expect(topic.frame.size == before.size)
        for other in canvas.scene.topics where other.id != hotels {
            #expect(!other.frame.intersects(bubble))
        }

        session.selection = hotels
        session.deleteSelection()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(hotels) == nil)
        #expect(!session.engine.state.nodes.values.contains { $0.callout != nil })
        session.undo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(hotels)?.calloutFrame == bubble)
    }

    /// Add Callout opens an empty bubble that already has its room; Esc
    /// (closing without text) gives it back and stores nothing.
    @Test func anOpenBubbleHasRoomBeforeItHasText() async throws {
        let graph = try graph()
        let canvas = try await canvas(graph)
        let session = canvas.session
        let rootID = try #require(graph.map.rootNodeID)
        let flights = try #require(graph.children(of: rootID).first?.id)

        canvas.editCallout(flights)
        canvas.calloutEditingDidChange()
        await canvas.layoutSettled()
        #expect(session.calloutEditorTarget == flights)
        #expect(canvas.scene.topic(flights)?.callout == "")
        #expect(canvas.scene.topic(flights)?.calloutFrame != nil)
        #expect(session.engine.state.node(flights)?.callout == nil)

        session.calloutEditorTarget = nil
        canvas.calloutEditingDidChange()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(flights)?.calloutFrame == nil)
        #expect(!session.engine.canUndo)
    }

    /// PNG and PDF draw the bubble inside the picture; Markdown leaves it out.
    @Test func picturesHaveTheBubbleAndMarkdownDoesNot() async throws {
        var engine = try GraphEngine(state: try graph())
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(SetCalloutCommand(nodeIDs: [rootID], text: "Draft for Monday"))
        let state = engine.state

        let picture = await MapPicture.make(state)
        let root = try #require(picture.scene.topic(rootID))
        let bubble = try #require(root.calloutFrame)
        let inner = picture.frame.insetBy(dx: CanvasMetrics.exportPadding - 1, dy: CanvasMetrics.exportPadding - 1)
        #expect(inner.contains(bubble))

        var options = ExportOptions()
        options.format = .markdown
        let markdown = String(decoding: try await MapExporter.data(for: state, options: options, colorScheme: .light), as: UTF8.self)
        #expect(!markdown.contains("Draft for Monday"))

        options.format = .png
        options.imageScale = .standard
        let png = try await MapExporter.data(for: state, options: options, colorScheme: .light)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    private struct OpenFailed: Error {}
}
