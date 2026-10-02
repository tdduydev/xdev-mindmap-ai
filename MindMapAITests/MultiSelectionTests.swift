import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

/// MM-5 in the session: a selection of several topics, branch actions on all
/// of them as one undo step, moving, and copy, cut and paste as Markdown.
@Suite("Multi-selection and clipboard")
struct MultiSelectionTests {
    let repository: SwiftDataMapRepository
    let mapID: MapID
    let clipboard = MemoryClipboard()

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    private func open() async throws -> EditorSession {
        let opening = await EditorSession.open(mapID: mapID, repository: repository, clipboard: clipboard, onMapChange: { _ in })
        guard case .ready(let session) = opening else { throw OpenFailed() }
        return session
    }

    private struct Map {
        let session: EditorSession
        let undoManager: UndoManager
        let a: NodeID, a1: NodeID, a2: NodeID, b: NodeID, c: NodeID
    }

    /// Plan ▸ A (A1, A2), B, C, with a window undo manager.
    private func openMap() async throws -> Map {
        let session = try await open()
        func add(_ title: String, under parent: NodeID?) throws -> NodeID {
            session.selection = parent
            session.addChild()
            let id = try #require(session.selection)
            session.rename(id, to: title)
            return id
        }
        let root = try #require(session.rootID)
        let a = try add("A", under: root)
        let a1 = try add("A1", under: a)
        let a2 = try add("A2", under: a)
        let b = try add("B", under: root)
        let c = try add("C", under: root)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return Map(session: session, undoManager: undoManager, a: a, a1: a1, a2: a2, b: b, c: c)
    }

    /// Runs one intent as its own undo group, as one menu click would. With
    /// `groupsByEvent` off, registering undo outside a group throws.
    private func step(_ undoManager: UndoManager, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    private func titles(_ session: EditorSession) -> [String] {
        session.rows.map { String(repeating: "  ", count: $0.depth) + $0.node.title }
    }

    /// One undo restores `before`, one redo `after`: the action was one step.
    /// `check` runs right after the action, before undo moves the selection.
    private func expectOneStep(_ map: Map, named name: String, _ body: () -> Void, check: () -> Void = {}) {
        let before = map.session.engine.state
        step(map.undoManager, body)
        let after = map.session.engine.state
        check()
        #expect(!sameContent(before, after), "\(name) changed the map")
        #expect(map.undoManager.undoActionName == String(localized: String.LocalizationValue(name)))
        map.undoManager.undo()
        #expect(sameContent(map.session.engine.state, before), "undo of \(name)")
        map.undoManager.redo()
        #expect(sameContent(map.session.engine.state, after), "redo of \(name)")
    }

    // MARK: Selection

    @Test func commandClickTogglesAndShiftClickAdds() async throws {
        let map = try await openMap()
        let session = map.session
        session.selection = map.a

        session.toggleSelected(map.b)
        #expect(session.selectedIDs == [map.a, map.b])
        #expect(session.selection == map.b)

        session.addToSelection(map.c)
        #expect(session.selectedIDs == [map.a, map.b, map.c])
        #expect(session.selection == map.c)

        session.toggleSelected(map.c)
        #expect(session.selectedIDs == [map.a, map.b])
        #expect(session.selection == map.a, "the first remaining topic in outline order")

        session.selection = map.c
        #expect(session.selectedIDs == [map.c], "setting the selection selects one topic")
    }

    @Test func selectAllTakesEveryVisibleTopic() async throws {
        let map = try await openMap()
        step(map.undoManager) { map.session.toggleCollapsed(map.a) }

        map.session.selectAll()

        let rootID = try #require(map.session.rootID)
        #expect(map.session.selectedIDs == [rootID, map.a, map.b, map.c])
    }

    @Test func branchRootsSkipTopicsInsideSelectedBranches() async throws {
        let map = try await openMap()
        map.session.setSelection([map.c, map.a1, map.a], primary: map.c)

        #expect(map.session.selectedBranchRoots == [map.a, map.c])
    }

    @Test func collapsingMovesHiddenSelectedTopicsToTheirBranch() async throws {
        let map = try await openMap()
        map.session.setSelection([map.a1, map.a2, map.b], primary: map.a1)

        step(map.undoManager) { map.session.toggleCollapsed(map.a) }

        #expect(map.session.selectedIDs == [map.a, map.b])
        #expect(map.session.selection == map.a)
    }

    @Test func undoDropsSelectedTopicsThatNoLongerExist() async throws {
        let map = try await openMap()
        map.session.selection = map.c
        step(map.undoManager) { map.session.duplicateSelection() }
        let copy = try #require(map.session.selection)
        map.session.setSelection([copy, map.b], primary: copy)

        map.undoManager.undo()

        #expect(map.session.selectedIDs == [map.b])
        #expect(map.session.selection == map.b)
    }

    // MARK: Branch actions

    @Test func deletingSeveralTopicsIsOneStep() async throws {
        let map = try await openMap()
        let rootID = try #require(map.session.rootID)
        map.session.setSelection([rootID, map.a1, map.c], primary: map.c)

        expectOneStep(map, named: "Delete Topics") { map.session.deleteSelection() } check: {
            #expect(map.session.selectedIDs == [map.a2])
        }

        #expect(titles(map.session) == ["Plan", "  A", "    A2", "  B"])
    }

    @Test func duplicatingSeveralTopicsIsOneStepAndSelectsTheCopies() async throws {
        let map = try await openMap()
        map.session.setSelection([map.a, map.c], primary: map.a)

        expectOneStep(map, named: "Duplicate Topics") { map.session.duplicateSelection() } check: {
            #expect(map.session.selectedIDs.count == 2)
            #expect(!map.session.isSelected(map.a) && !map.session.isSelected(map.c))
        }

        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "  A", "    A1", "    A2", "  B", "  C", "  C"])
    }

    // MARK: Moving

    @Test func movingIntoATopicIsOneStep() async throws {
        let map = try await openMap()
        map.session.setSelection([map.b, map.c], primary: map.b)

        expectOneStep(map, named: "Move Topics") { map.session.move([map.c, map.b], to: .child(of: map.a1)) }

        #expect(titles(map.session) == ["Plan", "  A", "    A1", "      B", "      C", "    A2"])
    }

    @Test func movingBeforeAndAfterASibling() async throws {
        let map = try await openMap()

        expectOneStep(map, named: "Move Topic") { map.session.move([map.c], to: .before(map.a)) }
        #expect(titles(map.session) == ["Plan", "  C", "  A", "    A1", "    A2", "  B"])

        step(map.undoManager) { map.session.move([map.a1], to: .after(map.b)) }
        #expect(titles(map.session) == ["Plan", "  C", "  A", "    A2", "  B", "  A1"])
    }

    @Test func movingIntoACollapsedTopicOpensIt() async throws {
        let map = try await openMap()
        step(map.undoManager) { map.session.toggleCollapsed(map.a) }

        expectOneStep(map, named: "Move Topic") { map.session.move([map.b], to: .child(of: map.a)) }

        #expect(map.session.engine.state.node(map.a)?.isCollapsed == false)
        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "    B", "  C"])
    }

    @Test func aBranchCannotMoveIntoItselfOrMoveTheCentralTopic() async throws {
        let map = try await openMap()
        let rootID = try #require(map.session.rootID)

        #expect(!map.session.canMove([map.a], to: .child(of: map.a)))
        #expect(!map.session.canMove([map.a], to: .child(of: map.a1)))
        #expect(!map.session.canMove([map.a], to: .before(map.a2)))
        #expect(!map.session.canMove([map.b, map.a], to: .after(map.a1)))
        #expect(!map.session.canMove([rootID], to: .child(of: map.b)))
        #expect(!map.session.canMove([map.b], to: .before(rootID)), "the central topic has no siblings")
        #expect(map.session.canMove([map.a1], to: .child(of: map.b)))

        let before = map.session.engine.state
        map.session.move([map.a], to: .child(of: map.a1))
        #expect(map.session.engine.state == before)
    }

    @Test func droppingATopicWhereItIsIsNoUndoStep() async throws {
        let session = try await open()
        let rootID = try #require(session.rootID)
        // Built without an undo manager, so the history so far is the engine's alone.
        session.addChild()
        let first = try #require(session.selection)
        session.addSibling()
        let second = try #require(session.selection)
        let undoManager = UndoManager()
        session.undoManager = undoManager

        session.move([second], to: .after(first))
        session.move([first], to: .before(second))
        session.move([second], to: .child(of: rootID))

        #expect(!undoManager.canUndo)
    }

    // MARK: Clipboard

    @Test func copyWritesTheSelectedBranchesAsMarkdown() async throws {
        let map = try await openMap()
        step(map.undoManager) { map.session.rename(map.a2, to: "- not a bullet") }
        map.session.setSelection([map.a, map.c], primary: map.a)

        map.session.copySelection()

        #expect(clipboard.text == "- A\n  - A1\n  - \\- not a bullet\n- C\n")
    }

    @Test func cutIsOneStepAndKeepsTheCentralTopic() async throws {
        let map = try await openMap()
        let rootID = try #require(map.session.rootID)
        map.session.setSelection([rootID, map.b], primary: map.b)

        expectOneStep(map, named: "Cut Topic") { map.session.cutSelection() }

        #expect(clipboard.text == "- B\n")
        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "  C"])
    }

    @Test func pasteNestsByIndentationAsOneStep() async throws {
        let map = try await openMap()
        clipboard.setText("Launch\n\tPress\n\tSocial\n\t\tVideo\nRetro")
        map.session.selection = map.b

        expectOneStep(map, named: "Paste Topics") { map.session.paste() } check: {
            #expect(map.session.selectedIDs.count == 2, "the new top-level topics")
        }

        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "  B", "    Launch", "      Press", "      Social", "        Video", "    Retro", "  C"])
    }

    @Test func copyThenPasteGivesTheSameBranch() async throws {
        let map = try await openMap()
        map.session.selection = map.a
        map.session.copySelection()
        map.session.selection = map.c

        step(map.undoManager) { map.session.paste() }

        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "  B", "  C", "    A", "      A1", "      A2"])
    }

    @Test func pasteWithoutTextOrMapDoesNothing() async throws {
        let session = try await open()
        let before = session.engine.state

        session.paste("   \n\n")

        #expect(session.engine.state == before)
        #expect(!session.canPaste)
    }

    private struct OpenFailed: Error {}
}

private func sameContent(_ lhs: GraphState, _ rhs: GraphState) -> Bool {
    var leftMap = lhs.map
    leftMap.updatedAt = rhs.map.updatedAt
    return leftMap == rhs.map && lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
}
