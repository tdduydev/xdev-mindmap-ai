import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
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

    /// PNG and PDF lay out and draw through the canvas scene, boundaries included.
    @Test func exportPictureFramesTheBoundary() async throws {
        let (session, _, ids) = try await open()
        session.selection = ids[1]
        session.addBoundary()
        let id = try #require(session.activeBoundary)
        session.renameBoundary(id, to: "Middle")

        let picture = await MapPicture.make(session.engine.state)

        let boundary = try #require(picture.scene.boundaries.first)
        #expect(boundary.id == id)
        #expect(boundary.title == "Middle")
        #expect(picture.frame.contains(boundary.frame))
        let topic = try #require(picture.scene.topic(ids[1]))
        #expect(boundary.frame.contains(topic.frame))
    }

    // MARK: AI

    private func assistant(for session: EditorSession, provider: MockAIProvider) async throws -> AIAssistant {
        let defaults = try #require(UserDefaults(suiteName: "EditorBoundaryTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
        let service = AIService(provider: { provider }, entitlements: EverythingUnlocked())
        await service.refresh()
        return AIAssistant(session: session, service: service, defaults: defaults, locale: Locale(identifier: "en_US"))
    }

    private func titles(under parent: NodeID, in session: EditorSession) -> [String] {
        session.engine.state.childIDs(of: parent).compactMap { session.engine.state.node($0)?.title }
    }

    @Test func suggestedGroupsPreviewThenAcceptInOneUndoStep() async throws {
        let (session, undoManager, ids) = try await open()
        session.selection = ids[2]
        step(undoManager) { session.addSibling() }
        let d = try #require(session.selection)
        step(undoManager) { session.rename(d, to: "D") }
        let root = try #require(session.rootID)
        let provider = MockAIProvider()
        let assistant = try await assistant(for: session, provider: provider)
        let canvas = CanvasModel(session: session, assistant: assistant)
        canvas.setTextSpecs(.designSizes())
        #expect(assistant.canRun(.suggestGroups, on: root))
        #expect(!assistant.canRun(.suggestGroups, on: ids[0]), "no children to group")
        provider.enqueue(.groups(AIGroupSuggestions(parentID: root, groups: [
            .init(title: "Ends", nodeIDs: [ids[0], d]),
        ])), for: .suggestGroups)

        assistant.suggestGroups(root)
        await assistant.requestSettled()

        guard case .suggestGroups(let request) = provider.requests.last else { throw OpenFailed() }
        #expect(request.children.map(\.title) == ["A", "B", "C", "D"])
        let suggestion = try #require(assistant.boundarySuggestions?.groups.first)
        #expect(assistant.boundarySuggestionMoves == 3)
        await canvas.layoutSettled()
        #expect(canvas.scene.boundaries.map(\.isSuggestion) == [true], "drawn as an AI preview")
        #expect(titles(under: root, in: session) == ["A", "B", "C", "D"], "nothing moves before Accept")
        #expect(session.engine.state.groups.isEmpty)

        assistant.renameBoundarySuggestion(suggestion.id, to: "First and last")
        step(undoManager) { assistant.acceptAll() }
        #expect(titles(under: root, in: session) == ["A", "D", "B", "C"])
        let group = try #require(session.engine.state.group(suggestion.id))
        #expect(group.title == "First and last")
        #expect(group.origin == .ai)
        #expect(undoManager.undoActionName == "Add AI Groups")
        #expect(!assistant.hasSuggestions)
        await canvas.layoutSettled()
        #expect(canvas.scene.boundaries.map(\.isSuggestion) == [false], "the accepted boundary is drawn as the map's own")

        undoManager.undo()
        #expect(titles(under: root, in: session) == ["A", "B", "C", "D"])
        #expect(session.engine.state.groups.isEmpty)
        undoManager.redo()
        #expect(session.engine.state.group(suggestion.id)?.title == "First and last")
    }

    @Test func summarizedBoundaryTitleIsEditedBeforeAccept() async throws {
        let (session, undoManager, ids) = try await open()
        session.setSelection([ids[0], ids[1]], primary: ids[0])
        step(undoManager) { session.addBoundary() }
        let id = try #require(session.activeBoundary)
        let provider = MockAIProvider()
        let assistant = try await assistant(for: session, provider: provider)
        #expect(assistant.canRun(.summarizeBoundary))
        provider.enqueue(.boundaryTitle(AIBoundaryTitle(groupID: id, title: "Letters")), for: .summarizeBoundary)

        assistant.summarizeBoundary()
        await assistant.requestSettled()

        guard case .summarizeBoundary(let request) = provider.requests.last else { throw OpenFailed() }
        #expect(request.outline.map(\.title) == ["A", "B"])
        #expect(session.engine.state.group(id)?.title == nil)
        assistant.renameBoundarySuggestion(id, to: "Early letters")
        step(undoManager) { assistant.acceptAll() }
        #expect(session.engine.state.group(id)?.title == "Early letters")
        #expect(undoManager.undoActionName == "Rename Boundary")
        undoManager.undo()
        #expect(session.engine.state.group(id)?.title == nil)
        undoManager.redo()
        #expect(session.engine.state.group(id)?.title == "Early letters")
    }

    private struct EverythingUnlocked: ProEntitlements {
        func allows(_ feature: ProFeature) -> Bool { true }
    }

    private struct OpenFailed: Error {}
}
