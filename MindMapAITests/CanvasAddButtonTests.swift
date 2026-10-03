import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapLayout
import MindMapPersistence
import SwiftUI
import Testing

/// The + buttons on a hovered or selected topic (MM-57, FR-CNV-05, FR-EDT-02):
/// when they show, on which side, and that pressing one is the same command
/// as Add Child Topic or Add Sibling Topic.
@Suite("Canvas add buttons")
struct CanvasAddButtonTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    private func open() async throws -> CanvasModel {
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        return canvas
    }

    @discardableResult
    private func addChild(_ title: String, to parent: NodeID, in canvas: CanvasModel) async throws -> NodeID {
        canvas.select(parent)
        canvas.session.addChild()
        let id = try #require(canvas.session.selection)
        canvas.takeFocusRequest()
        await canvas.layoutSettled()
        canvas.editingDraft = title
        canvas.commitEditing()
        await canvas.layoutSettled()
        return id
    }

    private func topic(_ id: NodeID, in canvas: CanvasModel) throws -> CanvasTopic {
        try #require(canvas.scene.topic(id))
    }

    // MARK: When they show

    @Test func hoverShowsTheButtonsAndLeavingHidesThemAfterAMoment() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Idea", to: rootID, in: canvas)
        canvas.select(rootID)

        #expect(canvas.addButtons(for: try topic(child, in: canvas)) == nil)

        canvas.setHovering(child, part: .card, true)
        #expect(canvas.addButtons(for: try topic(child, in: canvas)) != nil)

        canvas.setHovering(child, part: .card, false)
        // Still there while the pointer may be crossing to a button.
        #expect(canvas.hoveredID == child)
        await canvas.hoverSettled()
        #expect(canvas.hoveredID == nil)
        #expect(canvas.addButtons(for: try topic(child, in: canvas)) == nil)
    }

    @Test func movingFromTheCardOntoAButtonKeepsTheButtons() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Idea", to: rootID, in: canvas)
        canvas.select(rootID)

        // Either order of the two events, as SwiftUI does not promise one.
        canvas.setHovering(child, part: .card, true)
        canvas.setHovering(child, part: .addChild, true)
        canvas.setHovering(child, part: .card, false)
        await canvas.hoverSettled()
        #expect(canvas.hoveredID == child)

        canvas.setHovering(child, part: .card, true)
        canvas.setHovering(child, part: .addChild, false)
        canvas.setHovering(child, part: .card, false)
        canvas.setHovering(child, part: .addSibling, true)
        await canvas.hoverSettled()
        #expect(canvas.hoveredID == child)
    }

    @Test func movingToAnotherTopicMovesTheButtonsAtOnce() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let first = try await addChild("First", to: rootID, in: canvas)
        let second = try await addChild("Second", to: rootID, in: canvas)
        canvas.select(rootID)

        canvas.setHovering(first, part: .card, true)
        canvas.setHovering(second, part: .card, true)
        canvas.setHovering(first, part: .card, false)
        await canvas.hoverSettled()

        #expect(canvas.hoveredID == second)
        #expect(canvas.addButtons(for: try topic(first, in: canvas)) == nil)
        #expect(canvas.addButtons(for: try topic(second, in: canvas)) != nil)
    }

    /// Touch has no hover, so the selected topic shows them too.
    @Test func theSelectedTopicShowsTheButtonsWithoutHover() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Idea", to: rootID, in: canvas)
        canvas.select(child)

        #expect(canvas.addButtons(for: try topic(child, in: canvas)) == .init(childEdge: .trailing, showsSibling: true))
        #expect(canvas.addButtons(for: try topic(rootID, in: canvas)) == nil)
    }

    @Test func theCentralTopicHasNoSiblingButton() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        canvas.select(rootID)

        #expect(canvas.addButtons(for: try topic(rootID, in: canvas)) == .init(childEdge: .trailing, showsSibling: false))
    }

    @Test func noButtonsWhileTheTitleIsEditedOrBelowTheDetailZoom() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Idea", to: rootID, in: canvas)

        canvas.beginEditing(child)
        #expect(canvas.addButtons(for: try topic(child, in: canvas)) == nil)
        canvas.commitEditing()
        #expect(canvas.addButtons(for: try topic(child, in: canvas)) != nil)

        canvas.zoom(to: CanvasMetrics.detailZoomThreshold / 2, anchor: canvas.viewport.center)
        #expect(canvas.addButtons(for: try topic(child, in: canvas)) == nil)
    }

    @Test func noButtonsWhileDragging() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Idea", to: rootID, in: canvas)
        let frame = try topic(child, in: canvas).frame

        canvas.beginDrag(child, at: canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY)))
        #expect(canvas.addButtons(for: try topic(child, in: canvas)) == nil)
        canvas.endDrag()
    }

    // MARK: Where

    /// Four level-1 topics, sorted top to bottom on the right of the central topic.
    private func rightColumn(in canvas: CanvasModel) async throws -> [CanvasTopic] {
        let rootID = try #require(canvas.session.rootID)
        for title in ["Short", "A much longer topic title that wraps to multiple lines", "Third", "Fourth"] {
            try await addChild(title, to: rootID, in: canvas)
        }
        let column = canvas.scene.topics
            .filter { $0.parentID == rootID && $0.side == .right }
            .sorted { $0.frame.minY < $1.frame.minY }
        try #require(column.count >= 2)
        return column
    }

    private func zoomed(_ canvas: CanvasModel, to scale: CGFloat) -> CanvasViewport {
        var viewport = canvas.viewport
        viewport.scale = scale
        return viewport
    }

    /// MM-68: the sibling + goes under the card with a whole tap area, and
    /// never into another topic, its title or the next topic, at any detail zoom.
    @Test func siblingTapAreaIsWholeAndClearOfEveryTopic() async throws {
        let canvas = try await open()
        let column = try await rightColumn(in: canvas)
        let zooms: [CGFloat] = [CanvasMetrics.detailZoomThreshold, 0.5, 1, 2, CanvasMetrics.zoomLimits.upperBound]
        var shown = 0
        for scale in zooms {
            let viewport = zoomed(canvas, to: scale)
            for topic in column {
                guard let hit = CanvasAddButtonPlacement.siblingFrame(for: topic, among: canvas.scene.topics, viewport: viewport) else { continue }
                shown += 1
                let card = CanvasAddButtonPlacement.viewFrame(topic.frame, viewport: viewport)
                #expect(hit.width >= Metrics.minimumHitTarget)
                #expect(hit.height >= Metrics.minimumHitTarget)
                #expect(hit.minY > card.maxY)
                #expect(abs(hit.midX - card.midX) < 0.5)
                for other in canvas.scene.topics {
                    #expect(!hit.intersects(CanvasAddButtonPlacement.viewFrame(other.frame, viewport: viewport)))
                }
            }
        }
        #expect(shown > 0)
    }

    /// The last topic of a column has room below at every detail zoom; one
    /// with a sibling 10 pt (scaled) below never does once the selection ring
    /// is cleared, so it shows no sibling +.
    @Test func siblingButtonShowsOnlyWhereItFits() async throws {
        let canvas = try await open()
        let column = try await rightColumn(in: canvas)
        let first = try #require(column.first)
        let last = try #require(column.last)
        for scale in [CanvasMetrics.detailZoomThreshold, 1, CanvasMetrics.zoomLimits.upperBound] {
            let viewport = zoomed(canvas, to: scale)
            #expect(CanvasAddButtonPlacement.siblingFrame(for: first, among: canvas.scene.topics, viewport: viewport) == nil)
            let hit = try #require(CanvasAddButtonPlacement.siblingFrame(for: last, among: canvas.scene.topics, viewport: viewport))
            let card = CanvasAddButtonPlacement.viewFrame(last.frame, viewport: viewport)
            let ring = (CanvasMetrics.selectionRingGap + CanvasMetrics.selectionRingWidthHighContrast) * scale
            #expect(hit.minY >= card.maxY + ring)
        }
    }

    /// The add-child tap area keeps its size and stays off the card through zoom.
    @Test func childTapAreaIsWholeAndOutsideTheCard() async throws {
        let canvas = try await open()
        let column = try await rightColumn(in: canvas)
        for scale in [CanvasMetrics.detailZoomThreshold, 1, CanvasMetrics.zoomLimits.upperBound] {
            let viewport = zoomed(canvas, to: scale)
            for topic in column {
                let hit = CanvasAddButtonPlacement.childFrame(for: topic, viewport: viewport)
                let card = CanvasAddButtonPlacement.viewFrame(topic.frame, viewport: viewport)
                #expect(hit.width >= Metrics.minimumHitTarget)
                #expect(hit.height >= Metrics.minimumHitTarget)
                #expect(!hit.intersects(card))
                #expect(hit.minX > card.maxX)
            }
        }
    }

    /// The add-child button goes on the side away from the parent.
    @Test func aLeftBranchHasItsChildButtonOnTheLeft() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        for title in ["One", "Two", "Three", "Four"] {
            try await addChild(title, to: rootID, in: canvas)
        }
        let topics = canvas.scene.topics.filter { $0.parentID == rootID }
        let left = try #require(topics.first { $0.side == .left })
        let right = try #require(topics.first { $0.side == .right })

        canvas.select(left.id)
        #expect(canvas.addButtons(for: left)?.childEdge == .leading)
        canvas.select(right.id)
        #expect(canvas.addButtons(for: right)?.childEdge == .trailing)
    }

    // MARK: Pressing

    @Test func addChildButtonIsOneUndoStepAndOpensTheNewTopic() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Idea", to: rootID, in: canvas)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        canvas.session.undoManager = undoManager
        canvas.select(rootID)
        canvas.setHovering(child, part: .addChild, true)

        undoManager.beginUndoGrouping()
        canvas.addFromButton(child, sibling: false)
        undoManager.endUndoGrouping()
        let added = try #require(canvas.session.selection)
        canvas.takeFocusRequest()
        await canvas.layoutSettled()

        #expect(canvas.session.engine.state.node(added)?.parentID == child)
        #expect(canvas.editingID == added)
        #expect(canvas.hoveredID == nil)
        #expect(undoManager.undoActionName == String(localized: "Add Topic"))

        canvas.commitEditing()
        undoManager.undo()
        #expect(canvas.session.engine.state.node(added) == nil)
        #expect(canvas.session.engine.state.node(child) != nil)

        undoManager.redo()
        #expect(canvas.session.engine.state.node(added)?.parentID == child)
    }

    @Test func addSiblingButtonIsOneUndoStepAndOpensTheNewTopic() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let first = try await addChild("First", to: rootID, in: canvas)
        try await addChild("Last", to: rootID, in: canvas)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        canvas.session.undoManager = undoManager

        undoManager.beginUndoGrouping()
        canvas.addFromButton(first, sibling: true)
        undoManager.endUndoGrouping()
        let added = try #require(canvas.session.selection)
        canvas.takeFocusRequest()
        await canvas.layoutSettled()

        let state = canvas.session.engine.state
        #expect(state.node(added)?.parentID == rootID)
        // Right after the topic the button was on.
        #expect(Array(state.childIDs(of: rootID).prefix(2)) == [first, added])
        #expect(canvas.editingID == added)

        canvas.commitEditing()
        undoManager.undo()
        #expect(canvas.session.engine.state.node(added) == nil)
        undoManager.redo()
        #expect(canvas.session.engine.state.node(added)?.parentID == rootID)
    }

    private struct OpenFailed: Error {}
}
