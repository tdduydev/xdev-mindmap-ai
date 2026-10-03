import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapSearch
import Testing

/// Filter bar and Focus on Branch (MM-36): view state that changes what the
/// canvas, outline, Select All and Find reach, never the map.
@Suite("Filter and focus")
struct FilterTests {
    let repository: SwiftDataMapRepository
    let plan = NodeID()
    let budget = NodeID()
    let hotels = NodeID()
    let ideas = NodeID()
    let venue = NodeID()

    private struct OpenFailed: Error {}

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    /// Root ─ Plan ─ Budget (task, high) / Hotels (task, done); Ideas ─ Venue.
    private func open() async throws -> CanvasModel {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Trip"))
        let root = try #require(engine.state.map.rootNodeID)
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: plan, .child(of: root), title: "Plan"),
            AddNodeCommand(nodeID: budget, .child(of: plan), title: "Budget"),
            AddNodeCommand(nodeID: hotels, .child(of: plan), title: "Hotels"),
            AddNodeCommand(nodeID: ideas, .child(of: root), title: "Ideas"),
            AddNodeCommand(nodeID: venue, .child(of: ideas), title: "Venue"),
            SetTaskCommand(nodeIDs: [budget], state: .set(.open), priority: .set(.high)),
            SetTaskCommand(nodeIDs: [hotels], state: .set(.done)),
        ]))
        try await repository.create(engine.state)
        guard case .ready(let session) = await EditorSession.open(mapID: engine.state.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        return canvas
    }

    @Test func dimKeepsEveryTopicOnTheCanvasAndFadesTheRest() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.filter.tasks = [.open]
        await canvas.layoutSettled()

        #expect(canvas.scene.topics.count == 6)
        #expect(canvas.scene.topic(budget)?.isDimmed == false)
        #expect(canvas.scene.topic(hotels)?.isDimmed == true)
        #expect(session.filterCounts.matches == 1)
        #expect(session.engine.state.nodes.count == 6, "a filter never changes the map")
        #expect(!session.canUndo, "a filter is no undo step")
    }

    @Test func hideLaysOutOnlyMatchesAndTheirAncestors() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.filterMode = .hide
        session.filter.text = "venue"
        await canvas.layoutSettled()

        #expect(Set(canvas.scene.topics.map(\.id)) == [try #require(session.rootID), ideas, venue])
        #expect(canvas.scene.topic(ideas)?.isDimmed == true, "context ancestors are faded")
        #expect(session.rows.map(\.id) == [try #require(session.rootID), ideas, venue], "the outline follows")

        session.clearFilter()
        await canvas.layoutSettled()
        #expect(canvas.scene.topics.count == 6)
    }

    @Test func selectAllAndTheRectangleReachOnlyShownMatches() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.filter.priorities = [.high]
        await canvas.layoutSettled()

        session.selectAll()
        #expect(session.selectedIDs == [budget])

        canvas.beginMarquee(at: CGPoint(x: -10_000, y: -10_000), adding: false)
        canvas.updateMarquee(from: CGPoint(x: -10_000, y: -10_000), to: CGPoint(x: 10_000, y: 10_000))
        canvas.endMarquee()
        #expect(session.selectedIDs == [budget])
    }

    @Test func bulkActionsOnASelectAllNeverTouchHiddenTopics() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.filterMode = .hide
        session.filter.text = "budget"
        session.selectAll()
        session.toggleTask()

        #expect(session.engine.state.node(budget)?.taskState == nil)
        #expect(session.engine.state.node(hotels)?.taskState == .done, "hidden topic untouched")
        #expect(session.engine.state.node(venue)?.taskState == nil)
    }

    @Test func findWalksOnlyShownTopicsAndCountsTheHiddenOnes() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.filterMode = .hide
        session.filter.tasks = [.done]
        session.showFind()
        session.findText = "e"

        #expect(session.findMatches.allSatisfy { session.filterView.shown.contains($0) })
        #expect(session.findMatches.contains(hotels))
        #expect(!session.findMatches.contains(venue))
        #expect(session.findHiddenCount > 0)
    }

    @Test func focusDrawsOneBranchAndEndsWhenItsTopicGoes() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.selection = plan
        session.toggleFocus()
        await canvas.layoutSettled()

        #expect(session.focusID == plan)
        #expect(Set(canvas.scene.topics.map(\.id)) == [plan, budget, hotels])
        #expect(session.focusPath.map(\.id) == [try #require(session.rootID), plan])
        #expect(session.rows.map(\.id) == [plan, budget, hotels])

        session.deleteSelection()
        #expect(session.focusID == nil, "deleting the focused topic ends focus")
        session.undo()
        #expect(session.focusID == nil, "undo brings the topic back, not the focus")
        await canvas.layoutSettled()
        #expect(canvas.scene.topics.count == 6)
    }

    @Test func focusingTheCentralTopicIsTheWholeMap() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.focus(on: try #require(session.rootID))

        #expect(session.focusID == nil)
        #expect(!session.isViewFiltered)
    }

    @Test func filterAndFocusComeBackFromWindowStateWithoutTheirText() async throws {
        let canvas = try await open()
        let session = canvas.session
        session.filter.tasks = [.done]
        session.filter.text = "secret words"
        session.filterMode = .hide
        session.focus(on: plan)
        let data = try #require(EditorRestoration(session).data)

        #expect(!String(decoding: data, as: UTF8.self).contains("secret"), "no map content in window state")

        session.clearFilter()
        session.filterMode = .dim
        session.exitFocus()
        let restoration = try #require(EditorRestoration(data: data))
        restoration.apply(to: session)
        #expect(session.filter.tasks == [.done])
        #expect(session.filter.text.isEmpty)
        #expect(session.filterMode == .hide)
        #expect(session.focusID == plan)
    }

    @Test func windowStateFromBeforeTheFilterStillReads() async throws {
        let canvas = try await open()
        let data = try #require(EditorRestoration(canvas.session).data)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["filter", "filterMode", "isFilterBarShown", "focusID"] { object[key] = nil }
        let old = try JSONSerialization.data(withJSONObject: object)

        #expect(EditorRestoration(data: old) != nil)
    }
}
