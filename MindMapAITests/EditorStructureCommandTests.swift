import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

@Suite("Editor structure commands")
struct EditorStructureCommandTests {
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

    /// Root ▸ First ▸ Second, with Second selected.
    private func openWithTwoTopics() async throws -> (EditorSession, first: NodeID, second: NodeID) {
        let session = try await open()
        session.addChild()
        let first = try #require(session.selection)
        session.rename(first, to: "First")
        session.addSibling()
        let second = try #require(session.selection)
        session.rename(second, to: "Second")
        return (session, first, second)
    }

    /// Runs one intent as its own undo group, as one menu click would.
    private func step(_ undoManager: UndoManager, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    /// Every new command shows its name in the Edit menu, and undo and redo
    /// through the window's undo manager restore it exactly.
    @Test func everyCommandIsNamedAndUndoable() async throws {
        let (session, first, second) = try await openWithTwoTopics()
        session.addChild()
        let nested = try #require(session.selection)
        let link = try #require(session.connect(first, to: nested, type: .reference))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager

        let intents: [(String, () -> Void)] = [
            ("Duplicate Topic", { session.duplicateSelection() }),
            ("Demote Topic", { session.demoteSelection() }),
            ("Promote Topic", { session.selection = nested; session.promoteSelection() }),
            ("Merge Topics", { session.merge([first, second]) }),
            ("Split Topic", { session.rename(first, to: "One\nTwo"); session.selection = first; session.splitSelection() }),
            ("Add Link", { _ = session.connect(first, to: second) }),
            ("Remove Link", { session.removeLink(link) }),
            ("Collapse All", { session.collapseAll() }),
            // Something has to be collapsed for Expand All to change anything.
            ("Expand All", { session.toggleCollapsed(second); session.expandAll() }),
            ("Rename Map", { session.renameMap(to: "Renamed") }),
        ]
        for (name, intent) in intents {
            session.selection = second
            let before = session.engine.state
            step(undoManager, intent)
            let after = session.engine.state
            #expect(!sameContent(before, after), "\(name) changed the map")
            #expect(undoManager.undoActionName == String(localized: String.LocalizationValue(name)), "action name of \(name)")

            undoManager.undo()
            #expect(sameContent(session.engine.state, before), "undo of \(name)")
            undoManager.redo()
            #expect(sameContent(session.engine.state, after), "redo of \(name)")
            undoManager.undo()
        }
    }

    @Test func duplicateSelectsTheCopy() async throws {
        let (session, _, second) = try await openWithTwoTopics()

        session.duplicateSelection()

        #expect(session.selection != second)
        #expect(session.rows.map(\.node.title) == ["Plan", "First", "Second", "Second"])
    }

    @Test func menuAvailabilityFollowsTheSelection() async throws {
        let (session, first, _) = try await openWithTwoTopics()

        session.selection = session.rootID
        #expect(!session.canDuplicateSelection)
        #expect(!session.canPromoteSelection)
        #expect(!session.canDemoteSelection)

        session.selection = first
        #expect(session.canDuplicateSelection)
        #expect(!session.canPromoteSelection)
        #expect(!session.canDemoteSelection)
    }

    @Test func splitKeepsTheFirstLineSelected() async throws {
        let (session, first, _) = try await openWithTwoTopics()
        session.rename(first, to: "One\nTwo")
        session.selection = first

        #expect(session.canSplitSelection)
        session.splitSelection()

        #expect(session.selection == first)
        #expect(session.rows.map(\.node.title) == ["Plan", "One", "Two", "Second"])
    }

    @Test func collapseAllMovesTheSelectionOutOfHiddenBranches() async throws {
        let (session, first, _) = try await openWithTwoTopics()
        session.selection = first
        session.addChild()
        let nested = try #require(session.selection)

        session.collapseAll()

        #expect(session.engine.state.node(nested) != nil)
        #expect(session.selection == first)
    }

    @Test func renamingTheMapIsSaved() async throws {
        let session = try await open()

        session.renameMap(to: "Roadmap")
        await session.flush()

        let reopened = try await open()
        #expect(reopened.map.title == "Roadmap")
        #expect(reopened.rows.first?.node.title == "Plan")
    }

    @Test func linksAreSavedAndRemoved() async throws {
        let (session, first, second) = try await openWithTwoTopics()

        let link = try #require(session.connect(first, to: second, type: .reference, label: "see"))
        await session.flush()
        #expect(try await open().engine.state.edges[link]?.label == "see")

        session.removeLink(link)
        await session.flush()
        #expect(try await open().engine.state.edges.isEmpty)
    }

    private struct OpenFailed: Error {}
}

/// Content equality that ignores the map's "last edited" time, which undo moves forward too.
private func sameContent(_ lhs: GraphState, _ rhs: GraphState) -> Bool {
    var leftMap = lhs.map
    leftMap.updatedAt = rhs.map.updatedAt
    return leftMap == rhs.map && lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
}
