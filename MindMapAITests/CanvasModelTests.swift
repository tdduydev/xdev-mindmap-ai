import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapLayout
import MindMapPersistence
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
        let wholeMap = output.scene.topics(in: output.scene.bounds).count

        print("""
        [MM-3 timings, 1,000 topics, \(Self.buildKind)] \
        measure + full layout: \(fullTime); \
        one rename, re-measure + partial layout: \(updateTime); \
        culling per frame: \(cullTime / frames) (\(drawn / frames) topics and edges per frame at 100%); \
        topics at Zoom to Fit: \(wholeMap)
        """)
        #expect(drawn > 0)
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
