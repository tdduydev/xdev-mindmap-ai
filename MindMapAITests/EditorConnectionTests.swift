import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI
import Testing

@Suite("Editor connections")
struct EditorConnectionTests {
    let repository: SwiftDataMapRepository
    let mapID: MapID

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    /// Plan ▸ First ▸ Inner, Plan ▸ Second, with Second selected.
    private func open() async throws -> (EditorSession, first: NodeID, inner: NodeID, second: NodeID) {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        session.addChild()
        let first = try #require(session.selection)
        session.rename(first, to: "First")
        session.addChild()
        let inner = try #require(session.selection)
        session.rename(inner, to: "Inner")
        session.selection = first
        session.addSibling()
        let second = try #require(session.selection)
        session.rename(second, to: "Second")
        return (session, first, inner, second)
    }

    @Test func twoSelectedTopicsConnectWithoutThePicker() async throws {
        let (session, first, _, second) = try await open()
        session.setSelection([first, second], primary: first)

        session.beginAddingConnection()

        #expect(session.connectionSource == nil)
        let edge = try #require(session.engine.state.edges.values.first)
        #expect(edge.sourceNodeID == first)
        #expect(edge.targetNodeID == second)
    }

    @Test func oneSelectedTopicAsksForTheTarget() async throws {
        let (session, first, _, second) = try await open()
        session.selection = first

        session.beginAddingConnection()
        #expect(session.connectionSource == first)
        session.finishAddingConnection(to: second)

        #expect(session.connectionSource == nil)
        #expect(session.connections(of: first).map(\.otherID) == [second])
        #expect(session.connections(of: second).map(\.isOutgoing) == [false])
    }

    @Test func pickerListsEveryOtherTopicWithItsPath() async throws {
        let (session, first, _, _) = try await open()
        // Hidden topics are still targets: the picker is how to reach them.
        session.toggleCollapsed(first)

        let candidates = session.connectionCandidates(from: first)

        #expect(candidates.map(\.title) == ["Plan", "Inner", "Second"])
        #expect(candidates.map(\.path) == [[], ["Plan", "First"], ["Plan"]])
    }

    @Test func blankLabelRemovesItAndSameLabelIsNoStep() async throws {
        let (session, first, _, second) = try await open()
        let id = try #require(session.connect(first, to: second))
        session.setConnectionLabel("  needs ", for: id)
        #expect(session.engine.state.edges[id]?.label == "needs")

        let undoManager = UndoManager()
        session.undoManager = undoManager
        session.setConnectionLabel("needs", for: id)
        #expect(!undoManager.canUndo)

        session.setConnectionLabel(" ", for: id)
        #expect(session.engine.state.edges[id]?.label == nil)
    }

    @Test func voiceOverNamesTheOtherEndAndTheLabel() async throws {
        let (session, first, _, second) = try await open()
        let id = try #require(session.connect(first, to: second))
        session.setConnectionLabel("depends on", for: id)

        let outgoing = try #require(session.connections(of: first).first)
        let incoming = try #require(session.connections(of: second).first)
        #expect(outgoing.spokenDescription == "Connection to Second, label: depends on")
        #expect(incoming.spokenDescription == "Connection from First, label: depends on")
    }

    @Test func canvasTopicsCarryTheSameDescriptions() async throws {
        let (session, first, _, second) = try await open()
        _ = try #require(session.connect(first, to: second))
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 800, height: 600))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(first)?.connectionDescriptions == ["Connection to Second"])
    }

    @Test func aConnectionIntoACollapsedBranchIsDimmedWithABadge() async throws {
        let (session, first, inner, second) = try await open()
        let id = try #require(session.connect(second, to: inner))
        session.setConnectionLabel("needs", for: id)
        session.setConnectionLineStyle(.solid, for: id)
        session.toggleCollapsed(first)
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 800, height: 600))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()

        let drawing = CanvasDrawing.make(model: canvas, colorScheme: .light, contrast: .standard)

        #expect(drawing.crossLinks.keys.map(\.isDimmed) == [true])
        #expect(drawing.crossLinks.keys.map(\.lineStyle) == [.solid])
        #expect(drawing.connectionLabels.map(\.text) == ["needs"])
        #expect(drawing.connectionBadges.map(\.count) == [1])
        #expect(drawing.connectionBadges.first?.corner == canvas.scene.topic(first)?.frame.origin)
    }

    @Test func deleteRemovesTheSelectedConnectionAndSelectingATopicClearsIt() async throws {
        let (session, first, _, second) = try await open()
        let id = try #require(session.connect(first, to: second))

        session.selectConnection(id)
        #expect(session.selectedIDs.isEmpty)
        #expect(session.activeConnection == id)
        session.selection = first
        #expect(session.activeConnection == nil)

        session.selectConnection(id)
        session.deleteSelection()
        #expect(session.engine.state.edges.isEmpty)
        #expect(session.engine.state.node(first) != nil, "no topic deleted")
    }

    @Test func clickingTheLineSelectsTheConnection() async throws {
        let (session, first, _, second) = try await open()
        let id = try #require(session.connect(first, to: second))
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 800, height: 600))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        // A point on the line outside every topic: this one passes the central topic.
        let path = try #require(canvas.scene.crossLinkPath(id))
        let anchor = try #require((1..<20).lazy
            .map { canvas.viewport.toView(path.point(at: CGFloat($0) / 20)) }
            .first { canvas.topic(at: $0) == nil })

        canvas.tap(at: CGPoint(x: 0, y: 0))
        #expect(session.activeConnection == nil, "empty canvas selects nothing")
        canvas.tap(at: anchor)
        #expect(session.activeConnection == id)
        canvas.doubleTap(at: anchor)
        #expect(canvas.editingConnectionLabel == id)
    }

    private struct OpenFailed: Error {}
}

