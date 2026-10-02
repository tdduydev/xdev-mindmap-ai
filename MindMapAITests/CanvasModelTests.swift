import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapLayout
import MindMapPersistence
import SwiftUI
import Testing

/// The canvas without a window: layout, camera, selection, inline editing and
/// culling, driven through `CanvasModel` and a real session on an in-memory store.
@Suite("Canvas")
struct CanvasModelTests {
    static let viewSize = CGSize(width: 1000, height: 700)
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    private func open(_ graph: GraphState = .newMap(title: "Plan")) async throws -> CanvasModel {
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(Self.viewSize)
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        return canvas
    }

    /// Adds a child of `parent` named `title` the way the canvas does, and returns its ID.
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

    // MARK: Opening

    @Test func firstViewCentresTheCentralTopicAtActualSize() async throws {
        let canvas = try await open()
        let root = try #require(canvas.session.rootID.flatMap(canvas.scene.topic))

        #expect(canvas.viewport.scale == 1)
        #expect(canvas.viewport.toView(CGPoint(x: root.frame.midX, y: root.frame.midY)) == CGPoint(x: 500, y: 350))
    }

    @Test func iPhonePlacementFitsTheFirstLevelToTheWidth() async throws {
        var graph = GraphState.newMap(title: "Plan")
        let rootID = try #require(graph.map.rootNodeID)
        var engine = try GraphEngine(state: graph)
        for index in 0..<6 {
            _ = try engine.execute(AddNodeCommand(nodeID: NodeID(), .child(of: rootID), title: "A fairly long main topic \(index)"))
        }
        graph = engine.state
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let canvas = CanvasModel(session: session)
        canvas.initialPlacement = .firstLevelWidth
        canvas.setViewSize(CGSize(width: 390, height: 800))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()

        let firstLevel = canvas.scene.firstLevelBounds
        #expect(canvas.viewport.scale < 1)
        #expect(canvas.viewport.visibleRect.minX <= firstLevel.minX)
        #expect(canvas.viewport.visibleRect.maxX >= firstLevel.maxX)
    }

    @Test func accessibilityTextSizesFitTheFirstLevelInView() async throws {
        var engine = try GraphEngine(state: .newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        for index in 0..<8 {
            _ = try engine.execute(AddNodeCommand(nodeID: NodeID(), .child(of: rootID), title: "Main topic \(index)"))
        }
        try await repository.create(engine.state)
        guard case .ready(let session) = await EditorSession.open(mapID: engine.state.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let canvas = CanvasModel(session: session)
        canvas.initialPlacement = .firstLevel
        canvas.setViewSize(CGSize(width: 390, height: 300))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()

        #expect(canvas.viewport.visibleRect.contains(canvas.scene.firstLevelBounds))
        #expect(canvas.viewport.scale < 1)
    }

    // MARK: Measuring

    @Test func topicsAreMeasuredWithTheirLevelsFont() {
        let measurer = TopicMeasurer(specs: .designSizes())

        let central = measurer.size(of: "Plan", level: 0)
        let deep = measurer.size(of: "Plan", level: 3)
        #expect(central.width > deep.width)
        #expect(central.height > deep.height)
        #expect(measurer.size(of: "A much longer title", level: 2).width > measurer.size(of: "Short", level: 2).width)
    }

    @Test func longTitlesWrapAtTheMaximumWidth() {
        let specs = TopicTextSpecs.designSizes()
        let measurer = TopicMeasurer(specs: specs)
        let oneLine = measurer.size(of: "Word", level: 2)

        let long = measurer.size(of: String(repeating: "wrapping words ", count: 20), level: 2)

        #expect(long.width <= specs.spec(level: 2).maximumWidth)
        #expect(long.height > oneLine.height * 2)
    }

    @Test func untitledTopicsAreMeasuredWithThePlaceholder() {
        let measurer = TopicMeasurer(specs: .designSizes())

        #expect(measurer.size(of: "", level: 1) == measurer.size(of: String(localized: "Untitled Topic"), level: 1))
        #expect(measurer.size(of: "", level: 1).width >= CanvasMetrics.main.minimumWidth)
    }

    /// A picture sits above the title inside the box (MM-63), sized from the
    /// stored pixel size before its bytes load.
    @Test func aTopicWithAnImageIsMeasuredWithIt() {
        let specs = TopicTextSpecs.designSizes()
        let measurer = TopicMeasurer(specs: specs)
        var noChips: [TopicChip] = []
        let plain = measurer.size(of: "Plan", level: 1)
        let photo = MindImage(mapID: MapID(), nodeID: NodeID(), pixelWidth: 400, pixelHeight: 300)

        let frame = measurer.imageSize(of: photo, level: 1)
        let withImage = measurer.size(of: "Plan", level: 1, chips: &noChips, image: frame)

        #expect(frame == CGSize(width: CanvasMetrics.imageWidthMedium, height: CanvasMetrics.imageWidthMedium * 0.75))
        #expect(withImage.height == plain.height + frame.height + CanvasMetrics.imageGap)
        #expect(withImage.width == frame.width + 2 * CanvasMetrics.main.horizontalPadding)

        // Large on a sub-topic shrinks to the box; a tall picture is cropped to the maximum aspect.
        var tall = photo
        tall.displayWidth = CanvasMetrics.imageWidthLarge
        tall.pixelHeight = 4_000
        let sub = CanvasMetrics.sub
        let tallFrame = measurer.imageSize(of: tall, level: 2)
        #expect(tallFrame.width == sub.maximumWidth - 2 * sub.horizontalPadding)
        #expect(abs(Double(tallFrame.height) - Double(tallFrame.width) * CanvasMetrics.imageMaxAspect) < 1)
        #expect(measurer.size(of: "Plan", level: 2, chips: &noChips, image: tallFrame).width <= sub.maximumWidth)
    }

    @Test func addingAnImageMeasuresTheTopicAgain() throws {
        var engine = try GraphEngine(state: .newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let specs = TopicTextSpecs.designSizes()
        let first = CanvasLayoutPass(graph: engine.state, previous: nil, measures: [:], changed: [], specs: specs, options: LayoutOptions()).run()

        let image = MindImage(mapID: engine.state.map.id, nodeID: rootID, data: Data([1]), pixelWidth: 100, pixelHeight: 100)
        let changes = try engine.execute(SetNodeImageCommand(nodeID: rootID, image: image))
        #expect(changes.layoutInvalidation.contains(rootID))
        let second = CanvasLayoutPass(
            graph: engine.state, previous: nil, measures: first.measures, changed: changes.layoutInvalidation,
            specs: specs, options: LayoutOptions()
        ).run()

        let before = try #require(first.measures[rootID]?.size)
        let after = try #require(second.measures[rootID]?.size)
        #expect(after.height > before.height)
        #expect(second.measures[rootID]?.imageSize != nil)
    }

    // MARK: Selection and editing

    @Test func addingFromTheCanvasSelectsEditsAndReveals() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        // Pan the root far away, so the new topic starts out of view.
        canvas.pan(by: CGSize(width: 5000, height: 0))

        canvas.select(rootID)
        canvas.session.addChild()
        let id = try #require(canvas.session.selection)
        canvas.takeFocusRequest()
        await canvas.layoutSettled()

        #expect(id != rootID)
        #expect(canvas.editingID == id)
        let topic = try #require(canvas.scene.topic(id))
        #expect(canvas.viewport.visibleRect.contains(topic.frame))
        #expect(canvas.visibleTopics.contains { $0.id == id })
    }

    @Test func inlineEditIsOneRenameThatUndoesAndRedoes() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let id = try await addChild("Research", to: rootID, in: canvas)
        #expect(canvas.scene.topic(id)?.title == "Research")

        canvas.beginEditing(id)
        canvas.editingDraft = "Design research"
        canvas.commitEditing()
        await canvas.layoutSettled()
        let renamed = try #require(canvas.scene.topic(id))
        #expect(renamed.title == "Design research")

        canvas.session.undo()
        await canvas.layoutSettled()
        let undone = try #require(canvas.scene.topic(id))
        #expect(undone.title == "Research")
        #expect(undone.frame.width < renamed.frame.width)

        canvas.session.redo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(id)?.title == "Design research")
        #expect(canvas.scene.topic(id)?.frame == renamed.frame)
    }

    @Test func cancellingAnEditKeepsTheTitle() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let id = try await addChild("Research", to: rootID, in: canvas)
        let undoable = canvas.session.canUndo

        canvas.beginEditing(id)
        canvas.editingDraft = "Something else"
        canvas.cancelEditing()
        canvas.commitEditing()
        await canvas.layoutSettled()

        #expect(canvas.editingID == nil)
        #expect(canvas.scene.topic(id)?.title == "Research")
        #expect(canvas.session.canUndo == undoable)
    }

    @Test func returnEditsTheSelection() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        canvas.select(rootID)

        #expect(canvas.beginEditingSelection())
        #expect(canvas.editingID == rootID)
        #expect(canvas.editingDraft == "Plan")
        // While a title is being edited, Return belongs to the field.
        #expect(!canvas.beginEditingSelection())
    }

    /// The menu's Delete key follows the canvas's focus and leaves a title
    /// being typed alone (FR-KBD-01).
    @Test func editingATitleKeepsTheDeleteKeyForTheText() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let id = try await addChild("Research", to: rootID, in: canvas)
        canvas.select(id)
        #expect(!canvas.session.deleteKeyDeletesTopic, "the canvas does not have focus yet")

        canvas.hasKeyboardFocus = true
        #expect(canvas.session.keyboardFocus == .content)
        #expect(canvas.session.deleteKeyDeletesTopic)

        canvas.beginEditing(id)
        #expect(canvas.session.keyboardFocus == .editingText)
        #expect(!canvas.session.deleteKeyDeletesTopic)

        canvas.commitEditing()
        #expect(canvas.session.deleteKeyDeletesTopic)

        canvas.hasKeyboardFocus = false
        #expect(canvas.session.keyboardFocus == .elsewhere)
    }

    @Test func deletingFromTheCanvasRemovesTheBranchAndUndoRestoresIt() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let branch = try await addChild("Research", to: rootID, in: canvas)
        let leaf = try await addChild("Interviews", to: branch, in: canvas)

        canvas.delete(branch)
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(branch) == nil)
        #expect(canvas.scene.topic(leaf) == nil)
        #expect(canvas.session.selection == rootID)

        canvas.session.undo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(branch) != nil)
        #expect(canvas.scene.topic(leaf) != nil)

        canvas.session.redo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(branch) == nil)
    }

    @Test func undoOfTheTopicBeingEditedEndsEditing() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        canvas.select(rootID)
        canvas.session.addChild()
        canvas.takeFocusRequest()
        await canvas.layoutSettled()
        #expect(canvas.editingID != nil)

        canvas.session.undo()
        await canvas.layoutSettled()

        #expect(canvas.editingID == nil)
    }

    @Test func tappingEmptyCanvasClearsTheSelection() async throws {
        let canvas = try await open()

        canvas.tap(at: CGPoint(x: 20, y: 20))

        #expect(canvas.session.selection == nil)
    }

    @Test func tappingAShapeBelowTheDetailZoomSelectsIt() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Research", to: rootID, in: canvas)
        canvas.zoom(to: 0.2, anchor: canvas.viewport.center)
        #expect(!canvas.isDetailed)
        let frame = try #require(canvas.scene.topic(child)?.frame)

        canvas.tap(at: canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY)))
        #expect(canvas.session.selection == child)

        // Editing comes back to actual size, so the field is readable.
        canvas.doubleTap(at: canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY)))
        #expect(canvas.editingID == child)
        #expect(canvas.viewport.scale == 1)
    }

    @Test func tappingATopicSelectsIt() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Research", to: rootID, in: canvas)
        canvas.select(rootID)
        #expect(canvas.isDetailed)
        let frame = try #require(canvas.scene.topic(child)?.frame)

        canvas.tap(at: canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY)))

        #expect(canvas.session.selection == child)
        #expect(canvas.topic(at: canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY)))?.id == child)
    }

    @Test func selectingAnotherTopicCommitsTheEdit() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let first = try await addChild("Research", to: rootID, in: canvas)
        let second = try await addChild("Design", to: rootID, in: canvas)

        canvas.beginEditing(first)
        canvas.editingDraft = "User research"
        canvas.select(second)
        await canvas.layoutSettled()

        #expect(canvas.editingID == nil)
        #expect(canvas.session.selection == second)
        #expect(canvas.scene.topic(first)?.title == "User research")
    }

    @Test func addingAChildFromTheTopicActionUndoesAndRedoes() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let branch = try await addChild("Research", to: rootID, in: canvas)
        canvas.select(rootID)

        canvas.addChild(of: branch)
        let id = try #require(canvas.session.selection)
        canvas.takeFocusRequest()
        await canvas.layoutSettled()
        #expect(id != branch)
        #expect(canvas.session.engine.state.node(id)?.parentID == branch)
        #expect(canvas.scene.topic(id)?.level == 2)
        #expect(canvas.editingID == id)

        canvas.commitEditing()
        canvas.session.undo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(id) == nil)
        #expect(canvas.editingID == nil)

        canvas.session.redo()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(id)?.level == 2)
    }

    @Test func theCentralTopicCannotBeDeleted() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)

        canvas.delete(rootID)
        await canvas.layoutSettled()

        #expect(canvas.scene.topic(rootID) != nil)
        #expect(!canvas.session.canUndo)
    }

    @Test func collapsingAnAncestorMovesTheSelectionToIt() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let branch = try await addChild("Research", to: rootID, in: canvas)
        let leaf = try await addChild("Interviews", to: branch, in: canvas)
        canvas.select(leaf)

        canvas.toggleCollapsed(branch)
        await canvas.layoutSettled()

        #expect(canvas.scene.topic(leaf) == nil)
        #expect(canvas.session.selection == branch)
    }

    @Test func aRevealForATopicThatIsNotLaidOutIsDropped() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let branch = try await addChild("Research", to: rootID, in: canvas)
        let hidden = try await addChild("Interviews", to: branch, in: canvas)
        canvas.toggleCollapsed(branch)
        await canvas.layoutSettled()

        // A focus request for a topic the next pass will not lay out.
        canvas.session.rename(rootID, to: "Plan B")
        canvas.session.focusRequest = hidden
        canvas.takeFocusRequest()
        await canvas.layoutSettled()

        // Showing the topic later must not jump to it or open its title.
        canvas.pan(by: CGSize(width: 3000, height: 0))
        let camera = canvas.viewport
        canvas.toggleCollapsed(branch)
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(hidden) != nil)
        #expect(canvas.editingID == nil)
        #expect(canvas.viewport == camera)
    }

    @Test func collapsingShowsTheHiddenCountAndExpandingRestores() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let branch = try await addChild("Research", to: rootID, in: canvas)
        let first = try await addChild("Interviews", to: branch, in: canvas)
        try await addChild("Notes", to: first, in: canvas)

        canvas.toggleCollapsed(branch)
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(branch)?.hiddenDescendantCount == 2)
        #expect(canvas.scene.topic(first) == nil)

        canvas.toggleCollapsed(branch)
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(branch)?.hiddenDescendantCount == 0)
        #expect(canvas.scene.topic(first) != nil)
    }

    @Test func switchingToTheOutlineKeepsTheSelection() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Research", to: rootID, in: canvas)
        canvas.select(child)

        canvas.session.presentation = .outline
        #expect(canvas.session.selection == child)
        canvas.session.presentation = .canvas
        #expect(canvas.session.selection == child)
    }

    // MARK: Camera

    @Test func zoomCommandsStepAndFit() async throws {
        let canvas = try await open()

        canvas.zoomIn()
        #expect(canvas.viewport.scale == 1.25)
        canvas.zoomToActualSize()
        canvas.zoomOut()
        #expect(canvas.viewport.scale == 0.75)
        canvas.zoomToActualSize()
        #expect(canvas.viewport.scale == 1)

        for _ in 0..<20 { canvas.zoomOut() }
        #expect(canvas.viewport.scale == CanvasMetrics.zoomLimits.lowerBound)
        #expect(!canvas.canZoomOut)

        canvas.zoomToFit()
        #expect(canvas.viewport.visibleRect.contains(canvas.scene.bounds))
        #expect(canvas.viewport.scale <= 1)
    }

    @Test func pinchAndScrollZoomStayWithinTheLimits() async throws {
        let canvas = try await open()

        canvas.zoom(to: 40, anchor: CGPoint(x: 100, y: 100))
        #expect(canvas.viewport.scale == CanvasMetrics.zoomLimits.upperBound)
        #expect(!canvas.canZoomIn)
        canvas.zoomIn()
        #expect(canvas.viewport.scale == CanvasMetrics.zoomLimits.upperBound)

        canvas.zoom(to: 0.001, anchor: CGPoint(x: 100, y: 100))
        #expect(canvas.viewport.scale == CanvasMetrics.zoomLimits.lowerBound)
        #expect(!canvas.isDetailed)
    }

    @Test func zoomKeepsTheTopicUnderThePointerInPlace() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let child = try await addChild("Research", to: rootID, in: canvas)
        let frame = try #require(canvas.scene.topic(child)?.frame)
        let pointer = canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY))

        canvas.zoom(to: 2.5, anchor: pointer)

        #expect(canvas.topic(at: pointer)?.id == child)
        let after = canvas.viewport.toView(CGPoint(x: frame.midX, y: frame.midY))
        #expect(abs(after.x - pointer.x) < 1e-9 && abs(after.y - pointer.y) < 1e-9)
    }

    @Test func zoomToFitOnALargeMapLeavesTheDetailZoom() async throws {
        let canvas = try await open(Self.largeMap(count: 1_000))

        canvas.zoomToFit()

        let fitting = min(
            (Self.viewSize.width - 2 * CanvasMetrics.fitPadding) / canvas.scene.bounds.width,
            (Self.viewSize.height - 2 * CanvasMetrics.fitPadding) / canvas.scene.bounds.height
        )
        #expect(canvas.viewport.scale == max(fitting, CanvasMetrics.fitZoomLimits.lowerBound))
        let centre = canvas.viewport.toView(CGPoint(x: canvas.scene.bounds.midX, y: canvas.scene.bounds.midY))
        #expect(abs(centre.x - Self.viewSize.width / 2) < 1e-6 && abs(centre.y - Self.viewSize.height / 2) < 1e-6)
        // Topics are shapes in the edge layer here, not 1,000 views.
        #expect(!canvas.isDetailed)
    }

    // MARK: Layout and culling

    @Test func partialLayoutsMatchAFullLayout() async throws {
        let canvas = try await open()
        let rootID = try #require(canvas.session.rootID)
        let a = try await addChild("Research", to: rootID, in: canvas)
        let b = try await addChild("Design", to: rootID, in: canvas)
        try await addChild("Interviews with a long title that wraps onto two lines", to: a, in: canvas)
        let c = try await addChild("Wireframes", to: b, in: canvas)
        canvas.select(c)
        canvas.session.promoteSelection()
        canvas.toggleCollapsed(a)
        await canvas.layoutSettled()

        let full = CanvasLayoutPass(
            graph: canvas.session.engine.state, previous: nil, measures: [:], changed: [],
            specs: .designSizes(), options: canvas.layoutOptions
        ).run()
        #expect(canvas.scene.layout == full.scene.layout)
        #expect(canvas.scene.topics == full.scene.topics)
    }

    @Test func onlyTopicsAndEdgesInViewAreDrawn() async throws {
        let canvas = try await open(Self.largeMap(count: 1_000))
        #expect(canvas.scene.topics.count == 1_000)

        canvas.zoomToActualSize()
        let rect = canvas.cullingRect
        let visible = canvas.visibleTopics
        #expect(!visible.isEmpty)
        #expect(visible.count < 1_000)
        #expect(visible.allSatisfy { $0.frame.intersects(rect) })
        #expect(canvas.scene.topics.filter { $0.frame.intersects(rect) }.count == visible.count)

        let connectors = canvas.scene.connectors(in: rect)
        #expect(connectors.count < canvas.scene.layout?.connectors.count ?? 0)
        #expect(connectors.allSatisfy { $0.path.controlBounds.intersects(rect) })
        // Every connector left out lies wholly outside the culling rectangle.
        let drawn = Set(connectors.map(\.child))
        let skipped = canvas.scene.layout?.connectors.filter { !drawn.contains($0.key) } ?? [:]
        #expect(skipped.values.allSatisfy { !$0.controlBounds.intersects(rect) })
    }

    @Test func panningOffTheMapDrawsNothingAndPanningBackRestores() async throws {
        let canvas = try await open(Self.largeMap(count: 200))
        let before = canvas.visibleTopics.map(\.id)
        #expect(!before.isEmpty)

        canvas.pan(by: CGSize(width: 100_000, height: 0))
        #expect(canvas.visibleTopics.isEmpty)
        #expect(canvas.scene.connectors(in: canvas.cullingRect).isEmpty)
        let drawing = CanvasDrawing.make(model: canvas, colorScheme: .light, contrast: .standard)
        #expect(drawing.edges.isEmpty)

        canvas.pan(by: CGSize(width: -100_000, height: 0))
        #expect(canvas.visibleTopics.map(\.id) == before)
    }

    @Test func belowTheDetailZoomTopicsAreDrawnAsShapes() async throws {
        let canvas = try await open(Self.largeMap(count: 200))
        #expect(CanvasDrawing.make(model: canvas, colorScheme: .light, contrast: .standard).fills.isEmpty)

        canvas.zoomToFit()
        #expect(!canvas.isDetailed)
        let drawing = CanvasDrawing.make(model: canvas, colorScheme: .light, contrast: .standard)
        #expect(!drawing.fills.isEmpty)
        // The central topic is selected on open, so it gets the ring.
        #expect(!drawing.selection.isEmpty)
    }

    /// NFR-PERF-01 cannot be measured without a screen; this times the work the
    /// canvas does per frame and per edit at 1,000 topics, and prints it for the
    /// task note. It does not fail on time: debug builds and machines vary.
    @Test func timingsForAThousandTopics() async throws {
        let graph = Self.largeMap(count: 1_000)
        let specs = TopicTextSpecs.designSizes()
        let options = LayoutOptions(horizontalSpacing: CanvasMetrics.layoutParentGap, verticalSpacing: CanvasMetrics.layoutSiblingGap)
        let clock = ContinuousClock()

        var full: CanvasLayoutPass.Output?
        let fullTime = clock.measure {
            full = CanvasLayoutPass(graph: graph, previous: nil, measures: [:], changed: [], specs: specs, options: options).run()
        }
        let output = try #require(full)

        var engine = try GraphEngine(state: graph)
        let target = try #require(output.scene.topics.last?.id)
        let changes = try engine.execute(UpdateNodeCommand(nodeID: target, .title("A renamed topic with more words")))
        var partial: CanvasLayoutPass.Output?
        let updateTime = clock.measure {
            partial = CanvasLayoutPass(
                graph: engine.state, previous: output.scene.layout, measures: output.measures,
                changed: changes.layoutInvalidation, specs: specs, options: options
            ).run()
        }
        #expect(partial?.scene.topic(target)?.title == "A renamed topic with more words")

        var camera = CanvasViewport(scale: 1, offset: CGPoint(x: 500, y: 350), size: Self.viewSize)
        var drawn = 0
        let frames = 600
        let cullTime = clock.measure {
            for frame in 0..<frames {
                camera.pan(by: CGSize(width: 0, height: frame.isMultiple(of: 2) ? -7 : 5))
                let rect = camera.cullingRect(margin: 0.25)
                drawn += output.scene.topics(in: rect).count + output.scene.connectors(in: rect).count
            }
        }
        // What Zoom to Fit shows: the zoom stops at its lower limit, so a tall
        // map may not fit in the view.
        var fitted = CanvasViewport(size: Self.viewSize)
        fitted.fit(output.scene.bounds, padding: CanvasMetrics.fitPadding, limits: CanvasMetrics.fitZoomLimits)
        let atFit = output.scene.topics(in: fitted.cullingRect(margin: CanvasMetrics.cullingMargin)).count
        let mapSize = output.scene.bounds.size

        print("""
        [MM-3 timings, 1,000 topics, \(Self.buildKind)] \
        measure + full layout: \(fullTime); \
        one rename, re-measure + partial layout: \(updateTime); \
        culling per frame: \(cullTime / frames) (\(drawn / frames) topics and edges per frame at 100%); \
        map \(Int(mapSize.width)) × \(Int(mapSize.height)) pt, Zoom to Fit at \(Int((fitted.scale * 100).rounded()))% \
        builds \(atFit) of 1,000 topics in a \(Int(Self.viewSize.width)) × \(Int(Self.viewSize.height)) view
        """)
        #expect(drawn > 0)
    }

    /// The main-actor work of one pan frame through the model: culling plus
    /// building the edge layer's paths, at 100% and at Zoom to Fit (where the
    /// topics are shapes too). It times the model only; SwiftUI's own layout
    /// and rendering are not in it, so it is not a frame rate.
    @Test func frameWorkForAThousandTopics() async throws {
        let canvas = try await open(Self.largeMap(count: 1_000))
        let clock = ContinuousClock()
        let frames = 120

        func perFrame() -> (Duration, Int) {
            var topics = 0
            let time = clock.measure {
                for frame in 0..<frames {
                    canvas.pan(by: CGSize(width: 0, height: frame.isMultiple(of: 2) ? -7 : 5))
                    topics += canvas.visibleTopics.count
                    _ = CanvasDrawing.make(model: canvas, colorScheme: .light, contrast: .standard)
                }
            }
            return (time / frames, topics / frames)
        }

        canvas.zoomToActualSize()
        let (actualSize, actualTopics) = perFrame()
        canvas.zoomToFit()
        let (fitted, fittedTopics) = perFrame()

        print("""
        [MM-3 frame work, 1,000 topics, \(Self.buildKind)] \
        at 100%: \(actualSize) per frame (\(actualTopics) topics built); \
        at Zoom to Fit (\(Int((canvas.viewport.scale * 100).rounded()))%): \(fitted) per frame (\(fittedTopics) topic shapes)
        """)
        #expect(actualTopics > 0 && fittedTopics > actualTopics)
    }

    // MARK: Fixtures

    private struct OpenFailed: Error {}

    #if DEBUG
    static let buildKind = "debug"
    #else
    static let buildKind = "release"
    #endif

    /// A balanced map: 8 main branches, then 4 children per topic, with titles
    /// of varied length so measuring and wrapping do real work.
    static func largeMap(count: Int) -> GraphState {
        let mapID = MapID()
        let rootID = NodeID()
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let words = ["Plan", "Research user interviews", "Design", "Ship the first beta to testers", "Budget", "Marketing", "Notes", "Risks and open questions"]
        var nodes = [MindNode(id: rootID, mapID: mapID, parentID: nil, title: "Product launch", createdAt: date)]
        var queue: [(id: NodeID, children: Int)] = [(rootID, 8)]
        var head = 0
        while nodes.count < count, head < queue.count {
            let parent = queue[head]
            head += 1
            for index in 0..<parent.children where nodes.count < count {
                let id = NodeID()
                nodes.append(MindNode(
                    id: id, mapID: mapID, parentID: parent.id,
                    title: "\(words[nodes.count % words.count]) \(nodes.count)",
                    sortOrder: Double(index), createdAt: date
                ))
                queue.append((id, 4))
            }
        }
        let map = MindMap(id: mapID, title: "Product launch", rootNodeID: rootID, createdAt: date)
        return GraphState(map: map, nodes: nodes, edges: [])
    }
}
