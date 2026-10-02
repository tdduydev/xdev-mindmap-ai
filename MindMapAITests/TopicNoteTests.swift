import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

/// FR-EDT-13: a topic's note edited from the inspector as one "Edit Note"
/// command, and marked on the canvas and in the outline.
@Suite("Topic note")
struct TopicNoteTests {
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

    private func undoManager(for session: EditorSession) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return undoManager
    }

    /// Runs one user action as its own undo group, as a run-loop event would.
    private func step(_ undoManager: UndoManager, _ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    @Test func editingANoteIsOneNamedUndoStep() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let rootID = try #require(session.rootID)

        step(undoManager) { session.setNote("Why it matters", for: rootID) }
        #expect(session.selectedNode?.note == "Why it matters")
        #expect(undoManager.undoActionName == String(localized: "Edit Note"))

        undoManager.undo()
        #expect(session.selectedNode?.note == nil)
        #expect(undoManager.redoActionName == String(localized: "Edit Note"))

        undoManager.redo()
        #expect(session.selectedNode?.note == "Why it matters")

        await session.flush()
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.node(rootID)?.note == "Why it matters")
    }

    @Test func undoAndRedoOfAChangedNoteRestoreEachVersion() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let rootID = try #require(session.rootID)

        step(undoManager) { session.setNote("First", for: rootID) }
        step(undoManager) { session.setNote("Second", for: rootID) }

        undoManager.undo()
        #expect(session.selectedNode?.note == "First")
        undoManager.undo()
        #expect(session.selectedNode?.note == nil)
        undoManager.redo()
        undoManager.redo()
        #expect(session.selectedNode?.note == "Second")
    }

    @Test func blankTextClearsTheNote() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let rootID = try #require(session.rootID)

        step(undoManager) { session.setNote("Draft", for: rootID) }
        step(undoManager) { session.setNote(" \n ", for: rootID) }

        #expect(session.selectedNode?.note == nil)
        #expect(session.selectedNode?.hasNote == false)
        undoManager.undo()
        #expect(session.selectedNode?.note == "Draft")
    }

    @Test func settingTheSameNoteLeavesNoUndoStep() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let rootID = try #require(session.rootID)

        step(undoManager) { session.setNote("", for: rootID) }
        #expect(!undoManager.canUndo)

        step(undoManager) { session.setNote("Kept", for: rootID) }
        step(undoManager) { session.setNote("Kept", for: rootID) }
        undoManager.undo()
        #expect(session.selectedNode?.note == nil)
    }

    @Test func aDeletedTopicIgnoresALateNote() async throws {
        let session = try await open()
        session.addChild()
        let child = try #require(session.selection)
        session.deleteSelection()

        session.setNote("Too late", for: child)

        #expect(session.engine.state.node(child) == nil)
    }

    @Test func editNoteOpensTheInspectorOnTheSelection() async throws {
        let session = try await open()
        session.addChild()
        let child = try #require(session.selection)

        session.editSelectionNote()

        #expect(session.isInspectorPresented)
        #expect(session.noteFocusRequest == child)
    }

    @Test func editNoteNeedsASelection() async throws {
        let session = try await open()
        session.selection = nil

        session.editSelectionNote()

        #expect(!session.canEditSelectionNote)
        #expect(!session.isInspectorPresented)
        #expect(session.noteFocusRequest == nil)
    }

    @Test func canvasMarksTopicsWithANoteAndTellsVoiceOver() async throws {
        let session = try await open()
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        let rootID = try #require(session.rootID)
        let sizeBefore = try #require(canvas.scene.topic(rootID)).frame.size
        #expect(canvas.scene.topic(rootID)?.hasNote == false)

        session.setNote("Why it matters", for: rootID)
        await canvas.layoutSettled()

        let root = try #require(canvas.scene.topic(rootID))
        #expect(root.hasNote)
        // The mark sits on the corner, so a note never resizes the topic.
        #expect(root.frame.size == sizeBefore)

        session.undo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(rootID)?.hasNote == false)
    }

    @Test func outlineRowsCarryTheNote() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)

        session.setNote("Why it matters", for: rootID)

        #expect(session.rows.first?.node.hasNote == true)
    }

    private struct OpenFailed: Error {}
}
