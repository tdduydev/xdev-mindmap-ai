import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapLayout
import MindMapPersistence
import Testing

/// MM-5 on the canvas, without a window: clicks with modifiers, the selection
/// rectangle, drag and drop, and the keys the canvas handles itself.
@Suite("Canvas interaction")
struct CanvasInteractionTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    private struct Map {
        let canvas: CanvasModel
        let root: NodeID
        let a: NodeID, a1: NodeID, a2: NodeID, b: NodeID
        var session: EditorSession { canvas.session }
    }

    /// Plan ▸ A (A1, A2), B, laid out on a 1000 × 700 view at 100%. With two
    /// main topics the layout puts A on the right and B on the left.
    private func open() async throws -> Map {
        var engine = try GraphEngine(state: .newMap(title: "Plan"))
        let root = try #require(engine.state.map.rootNodeID)
        let (a, a1, a2, b) = (NodeID(), NodeID(), NodeID(), NodeID())
        _ = try engine.execute(AddNodeCommand(nodeID: a, .child(of: root), title: "A"))
        _ = try engine.execute(AddNodeCommand(nodeID: a1, .child(of: a), title: "A1"))
        _ = try engine.execute(AddNodeCommand(nodeID: a2, .child(of: a), title: "A2"))
        _ = try engine.execute(AddNodeCommand(nodeID: b, .child(of: root), title: "B"))
        try await repository.create(engine.state)
        let opening = await EditorSession.open(mapID: engine.state.map.id, repository: repository, clipboard: MemoryClipboard(), onMapChange: { _ in })
        guard case .ready(let session) = opening else { throw OpenFailed() }
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        return Map(canvas: canvas, root: root, a: a, a1: a1, a2: a2, b: b)
    }

    /// A point inside a topic, in view points; `y` 0 is its top edge, 1 its bottom.
    private func point(in id: NodeID, y: CGFloat = 0.5, of canvas: CanvasModel) throws -> CGPoint {
        let frame = try #require(canvas.scene.topic(id)).frame
        return canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.minY + frame.height * y))
    }

    private func titles(_ session: EditorSession) -> [String] {
        session.rows.map { String(repeating: "  ", count: $0.depth) + $0.node.title }
    }

    // MARK: Selection

    @Test func clicksWithModifiersBuildASelection() async throws {
        let map = try await open()

        map.canvas.click(map.a1, .replace)
        map.canvas.click(map.b, .toggle)
        map.canvas.click(map.a2, .add)
        #expect(map.session.selectedIDs == [map.a1, map.b, map.a2])

        map.canvas.click(map.b, .toggle)
        #expect(map.session.selectedIDs == [map.a1, map.a2])

        map.canvas.click(map.b, .replace)
        #expect(map.session.selectedIDs == [map.b])
    }

    @Test func aRectangleSelectsTheTopicsItMeets() async throws {
        let map = try await open()
        let a1 = try point(in: map.a1, of: map.canvas)
        let a2 = try point(in: map.a2, of: map.canvas)
        map.canvas.click(map.b, .replace)

        map.canvas.beginMarquee(at: CGPoint(x: a1.x - 2, y: a1.y - 2), adding: false)
        map.canvas.updateMarquee(from: CGPoint(x: a1.x - 2, y: a1.y - 2), to: CGPoint(x: a2.x + 2, y: a2.y + 2))
        #expect(map.session.selectedIDs == [map.a1, map.a2])
        #expect(map.canvas.marquee != nil)

        map.canvas.endMarquee()
        #expect(map.canvas.marquee == nil)
        #expect(map.session.selectedIDs == [map.a1, map.a2])
    }

    @Test func anAddingRectangleKeepsTheSelection() async throws {
        let map = try await open()
        let a1 = try point(in: map.a1, of: map.canvas)
        map.canvas.click(map.b, .replace)

        map.canvas.beginMarquee(at: a1, adding: true)
        map.canvas.updateMarquee(from: a1, to: CGPoint(x: a1.x + 1, y: a1.y + 1))
        map.canvas.endMarquee()

        #expect(map.session.selectedIDs == [map.b, map.a1])
        #expect(map.session.selection == map.b)
    }

    // MARK: Drag and drop

    @Test func droppingOnTheMiddleOfATopicMakesAChildAsOneStep() async throws {
        let map = try await open()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        map.session.undoManager = undoManager

        map.canvas.beginDrag(map.b, at: try point(in: map.b, of: map.canvas))
        map.canvas.updateDrag(to: try point(in: map.a1, of: map.canvas))
        #expect(map.canvas.drag?.drop == .child(of: map.a1))
        #expect(map.canvas.dropIndicator(for: .child(of: map.a1))?.isBar == false)
        undoManager.beginUndoGrouping()
        map.canvas.endDrag()
        undoManager.endUndoGrouping()
        await map.canvas.layoutSettled()

        #expect(map.canvas.drag == nil)
        #expect(titles(map.session) == ["Plan", "  A", "    A1", "      B", "    A2"])
        undoManager.undo()
        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "  B"])
        undoManager.redo()
        #expect(titles(map.session) == ["Plan", "  A", "    A1", "      B", "    A2"])
    }

    @Test func theEdgesOfATopicInsertBesideIt() async throws {
        let map = try await open()

        map.canvas.beginDrag(map.a2, at: try point(in: map.a2, of: map.canvas))
        map.canvas.updateDrag(to: try point(in: map.a1, y: 0.05, of: map.canvas))
        #expect(map.canvas.drag?.drop == .before(map.a1))
        #expect(map.canvas.dropIndicator(for: .before(map.a1))?.isBar == true)
        map.canvas.endDrag()

        #expect(titles(map.session) == ["Plan", "  A", "    A2", "    A1", "  B"])
    }

    @Test func droppingIntoItsOwnBranchIsRefused() async throws {
        let map = try await open()
        let before = map.session.engine.state

        map.canvas.beginDrag(map.a, at: try point(in: map.a, of: map.canvas))
        map.canvas.updateDrag(to: try point(in: map.a1, of: map.canvas))
        #expect(map.canvas.drag?.isRefused == true)
        #expect(map.canvas.drag?.drop == nil)
        map.canvas.endDrag()

        #expect(map.canvas.refusedDrops == 1)
        #expect(map.session.engine.state == before)
    }

    @Test func droppingOnEmptyCanvasDoesNothing() async throws {
        let map = try await open()
        let before = map.session.engine.state

        map.canvas.beginDrag(map.a1, at: try point(in: map.a1, of: map.canvas))
        map.canvas.updateDrag(to: CGPoint(x: 1, y: 1))
        map.canvas.endDrag()

        #expect(map.canvas.refusedDrops == 0)
        #expect(map.session.engine.state == before)
    }

    @Test func draggingASelectedTopicMovesTheWholeSelection() async throws {
        let map = try await open()
        map.canvas.click(map.a1, .replace)
        map.canvas.click(map.a2, .add)

        map.canvas.beginDrag(map.a2, at: try point(in: map.a2, of: map.canvas))
        #expect(map.canvas.drag?.ids == [map.a1, map.a2])
        map.canvas.updateDrag(to: try point(in: map.b, of: map.canvas))
        map.canvas.endDrag()

        #expect(titles(map.session) == ["Plan", "  A", "  B", "    A1", "    A2"])
    }

    @Test func theCentralTopicDoesNotDrag() async throws {
        let map = try await open()

        map.canvas.beginDrag(map.root, at: try point(in: map.root, of: map.canvas))

        #expect(map.canvas.drag == nil)
    }

    @Test func escapeCancelsADrag() async throws {
        let map = try await open()
        let before = map.session.engine.state
        map.canvas.beginDrag(map.b, at: try point(in: map.b, of: map.canvas))
        map.canvas.updateDrag(to: try point(in: map.a1, of: map.canvas))

        #expect(map.canvas.handle(.cancel))
        map.canvas.endDrag()

        #expect(map.session.engine.state == before)
    }

    // MARK: Keys

    @Test func returnAndTabAddTopicsOnlyWhileNotTyping() async throws {
        let map = try await open()
        map.canvas.click(map.a1, .replace)

        #expect(map.canvas.handle(.addSibling))
        let sibling = try #require(map.session.selection)
        #expect(map.session.engine.state.node(sibling)?.parentID == map.a)

        map.canvas.takeFocusRequest()
        await map.canvas.layoutSettled()
        #expect(map.canvas.editingID == sibling)
        let before = map.session.engine.state
        #expect(!map.canvas.handle(.addSibling), "Return goes to the title field")
        #expect(!map.canvas.handle(.addChild), "and so does Tab")
        #expect(map.session.engine.state == before)

        map.canvas.commitEditing()
        #expect(map.canvas.handle(.addChild))
        #expect(map.session.engine.state.node(try #require(map.session.selection))?.parentID == sibling)
    }

    @Test func shiftTabPromotes() async throws {
        let map = try await open()
        map.canvas.click(map.a1, .replace)

        #expect(map.canvas.handle(.promote))

        #expect(map.session.engine.state.node(map.a1)?.parentID == map.root)
    }

    @Test func spaceRenames() async throws {
        let map = try await open()
        map.canvas.click(map.b, .replace)

        #expect(map.canvas.handle(.rename))

        #expect(map.canvas.editingID == map.b)
    }

    @Test func arrowsWalkTheMapAsDrawn() async throws {
        let map = try await open()
        let aSide = try #require(map.canvas.scene.topic(map.a)).side
        let away: CanvasDirection = aSide == .right ? .right : .left
        let toward: CanvasDirection = aSide == .right ? .left : .right
        map.canvas.click(map.root, .replace)

        #expect(map.canvas.handle(.move(away, extending: false)))
        #expect(map.session.selection == map.a)
        #expect(map.canvas.handle(.move(away, extending: false)))
        let child = try #require(map.session.selection)
        #expect([map.a1, map.a2].contains(child))
        #expect(map.canvas.handle(.move(child == map.a1 ? .down : .up, extending: true)))
        #expect(map.session.selectedIDs == [map.a1, map.a2])
        #expect(map.canvas.handle(.move(toward, extending: false)))
        #expect(map.session.selection == map.a)
        #expect(map.canvas.handle(.move(toward, extending: false)))
        #expect(map.session.selection == map.root)
        #expect(map.canvas.handle(.move(toward, extending: false)))
        #expect(map.session.selection == map.b)
    }

    @Test func escapeKeepsOnlyThePrimaryTopic() async throws {
        let map = try await open()
        map.canvas.click(map.a1, .replace)
        map.canvas.click(map.b, .add)

        #expect(map.canvas.handle(.cancel))

        #expect(map.session.selectedIDs == [map.b])
        #expect(!map.canvas.handle(.cancel), "nothing left to cancel")
    }

    @Test func selectAllEndsEditing() async throws {
        let map = try await open()
        map.canvas.beginEditing(map.b)
        map.canvas.editingDraft = "Bee"

        map.canvas.selectAll()

        #expect(map.canvas.editingID == nil)
        #expect(map.session.engine.state.node(map.b)?.title == "Bee")
        #expect(map.session.selectedIDs.count == 5)
    }

    @Test func aContextMenuOnAnUnselectedTopicActsOnThatTopic() async throws {
        let map = try await open()
        map.canvas.click(map.a1, .replace)
        map.canvas.click(map.a2, .add)

        map.canvas.performFromContextMenu(on: map.b) { $0.duplicateSelection() }
        #expect(titles(map.session) == ["Plan", "  A", "    A1", "    A2", "  B", "  B"])

        map.canvas.click(map.a1, .replace)
        map.canvas.click(map.a2, .add)
        map.canvas.performFromContextMenu(on: map.a2) { $0.deleteSelection() }
        #expect(titles(map.session) == ["Plan", "  A", "  B", "  B"])
    }

    private struct OpenFailed: Error {}
}
