import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing

/// FR-ORG-26: a URL on a topic, set from Add Link… as one named command,
/// shown on the canvas and in the outline, and opened only on request.
@Suite("Topic link")
struct TopicLinkTests {
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

    private func step(_ undoManager: UndoManager, _ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    @Test func addEditAndRemoveAreNamedStepsThatUndoAndRedo() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let rootID = try #require(session.rootID)

        step(undoManager) { #expect(session.setLink("example.com/plan", for: rootID) == nil) }
        #expect(session.selectedNode?.link?.string == "https://example.com/plan")
        #expect(undoManager.undoActionName == String(localized: "Add Link"))

        step(undoManager) { #expect(session.setLink("team@example.com", for: rootID) == nil) }
        #expect(session.selectedNode?.link?.string == "mailto:team@example.com")
        #expect(undoManager.undoActionName == String(localized: "Edit Link"))

        step(undoManager) { session.removeLink(from: rootID) }
        #expect(session.selectedNode?.link == nil)
        #expect(undoManager.undoActionName == String(localized: "Remove Link"))

        undoManager.undo()
        #expect(session.selectedNode?.link?.string == "mailto:team@example.com")
        undoManager.undo()
        #expect(session.selectedNode?.link?.string == "https://example.com/plan")
        undoManager.redo()
        undoManager.redo()
        #expect(session.selectedNode?.link == nil)
        undoManager.undo()

        await session.flush()
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.node(rootID)?.link?.string == "mailto:team@example.com")
    }

    @Test func aRefusedLinkSaysWhyAndChangesNothing() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)

        #expect(session.setLink("javascript:alert(1)", for: rootID) == .unsupportedScheme)
        #expect(session.setLink("file:///etc/hosts", for: rootID) == .unsupportedScheme)
        #expect(session.selectedNode?.link == nil)
        #expect(!session.engine.canUndo)
        #expect(!TopicLinkError.unsupportedScheme.message.isEmpty)
    }

    @Test func anEmptyFieldRemovesTheLink() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)
        session.setLink("https://example.com", for: rootID)

        #expect(session.setLink("  ", for: rootID) == nil)
        #expect(session.selectedNode?.link == nil)
    }

    @Test func menuStateFollowsTheSelection() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)
        #expect(session.canEditSelectionLink)
        #expect(!session.selectionHasLink)
        #expect(session.selectionLinkURL == nil)

        session.beginEditingSelectionLink()
        #expect(session.linkEditorTarget == rootID)

        session.setLink("https://example.com", for: rootID)
        #expect(session.selectionHasLink)
        #expect(session.selectionLinkURL == URL(string: "https://example.com"))

        session.selection = nil
        #expect(!session.canEditSelectionLink)
        #expect(session.selectionLinkURL == nil)
    }

    /// A stored link this build cannot open (a newer build's scheme) shows no
    /// mark, but stays until the link is really changed.
    @Test func canvasMarksOnlyLinksItCanOpenWithoutResizing() async throws {
        let session = try await open()
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        let rootID = try #require(session.rootID)
        let sizeBefore = try #require(canvas.scene.topic(rootID)).frame.size

        session.setLink("https://example.com", for: rootID)
        await canvas.layoutSettled()
        let root = try #require(canvas.scene.topic(rootID))
        #expect(root.link?.url?.host() == "example.com")
        #expect(root.frame.size == sizeBefore)

        session.perform(SetNodeLinkCommand(nodeIDs: [rootID], link: TopicLink(string: "obsidian://open")), named: "Test")
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(rootID)?.link == nil)
        #expect(session.selectedNode?.link?.string == "obsidian://open")
    }

    @Test func copiedTopicsCarryTheirLinkAsMarkdown() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)
        session.rename(rootID, to: "Plan")
        session.setLink("https://example.com", for: rootID)

        let text = EditorSession.markdown(for: [rootID], in: session.engine.state)
        #expect(text.hasPrefix("- [Plan](https://example.com)"))
        let draft = MarkdownOutline.parse(text)
        #expect(draft.items.first?.link == TopicLink(string: "https://example.com"))
    }

    private struct OpenFailed: Error {}
}
