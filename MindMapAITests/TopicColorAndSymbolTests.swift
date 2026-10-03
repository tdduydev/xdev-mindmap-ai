import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI
import Testing

/// MM-32 (FR-ORG-01..03): a topic's colour and symbol, set for one or many
/// topics as one named step, drawn on the canvas and in export, never by
/// colour alone.
@Suite("Topic colour and symbol")
struct TopicColorAndSymbolTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    /// Central "Plan" with "A" (children "A1", "A2" under it, "A11" under
    /// "A1") and "B".
    private func map() throws -> (GraphState, [String: NodeID]) {
        var engine = try GraphEngine(state: .newMap(title: "Plan"))
        let root = try #require(engine.state.map.rootNodeID)
        var ids = ["Plan": root]
        for (title, parent) in [("A", "Plan"), ("A1", "A"), ("A11", "A1"), ("A2", "A"), ("B", "Plan")] {
            let id = NodeID()
            let parentID = try #require(ids[parent])
            _ = try engine.execute(AddNodeCommand(nodeID: id, .child(of: parentID), title: title))
            ids[title] = id
        }
        return (engine.state, ids)
    }

    private func open(_ graph: GraphState) async throws -> EditorSession {
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

    private func scene(_ graph: GraphState, showsColorShapes: Bool = false) -> CanvasScene {
        CanvasLayoutPass(
            graph: graph, previous: nil, measures: [:], changed: [],
            specs: .designSizes(showsColorShapes: showsColorShapes), options: CanvasModel.layoutOptions
        ).run().scene
    }

    // MARK: Commands

    @Test func colorOnSeveralTopicsIsOneNamedStepThatUndoesAndRedoes() async throws {
        let (graph, ids) = try map()
        let session = try await open(graph)
        let undoManager = undoManager(for: session)
        let a = try #require(ids["A"]), b = try #require(ids["B"]), root = try #require(ids["Plan"])
        session.selectAll()

        step(undoManager) { session.setColor(.rose) }
        #expect(undoManager.undoActionName == String(localized: "Change Color"))
        #expect(session.engine.state.node(a)?.color == .rose)
        #expect(session.engine.state.node(b)?.color == .rose)
        // The central topic keeps its card.
        #expect(session.engine.state.node(root)?.color == nil)
        #expect(session.colorCoverage() == .all(.rose))

        undoManager.undo()
        #expect(session.engine.state.node(a)?.color == nil)
        #expect(session.engine.state.node(b)?.color == nil)
        undoManager.redo()
        #expect(session.engine.state.node(a)?.color == .rose)
        #expect(session.engine.state.node(b)?.color == .rose)

        step(undoManager) { session.setColor(nil, on: [a]) }
        #expect(session.engine.state.node(a)?.color == nil)
        #expect(session.colorCoverage([a, b]) == .mixed)
        undoManager.undo()
        #expect(session.engine.state.node(a)?.color == .rose)
    }

    @Test func choosingTheSameColorAddsNoStep() async throws {
        let (graph, ids) = try map()
        let session = try await open(graph)
        let a = try #require(ids["A"])
        session.setColor(.teal, on: [a])
        let steps = session.engine.undoStepNames.count
        session.setColor(.teal, on: [a])
        #expect(session.engine.undoStepNames.count == steps)
    }

    @Test func colorOnTheCentralTopicAloneDoesNothing() async throws {
        let (graph, ids) = try map()
        let session = try await open(graph)
        let root = try #require(ids["Plan"])
        session.selection = root
        #expect(!session.canColorSelection)
        #expect(session.canSetSelectionSymbol)
        session.setColor(.blue)
        #expect(session.engine.state.node(root)?.color == nil)
    }

    @Test func symbolIsNormalizedAndOneNamedStepThatUndoesAndRedoes() async throws {
        let (graph, ids) = try map()
        let session = try await open(graph)
        let undoManager = undoManager(for: session)
        let a = try #require(ids["A"]), root = try #require(ids["Plan"])

        step(undoManager) { session.setSymbol("flag.fill", on: [a, root]) }
        #expect(undoManager.undoActionName == String(localized: "Change Symbol"))
        #expect(session.engine.state.node(a)?.symbol == "flag.fill")
        #expect(session.engine.state.node(root)?.symbol == "flag.fill")

        // An emoji keeps only its first character.
        step(undoManager) { session.setSymbol(" 🚀🔥 ", on: [a]) }
        #expect(session.engine.state.node(a)?.symbol == "🚀")
        #expect(session.symbolCoverage([a, root]) == .mixed)

        step(undoManager) { session.setSymbol(nil, on: [a]) }
        #expect(session.engine.state.node(a)?.symbol == nil)

        undoManager.undo()
        #expect(session.engine.state.node(a)?.symbol == "🚀")
        undoManager.undo()
        #expect(session.engine.state.node(a)?.symbol == "flag.fill")
        undoManager.redo()
        #expect(session.engine.state.node(a)?.symbol == "🚀")
    }

    @Test func chooseSymbolOpensThePickerForTheTargets() async throws {
        let (graph, ids) = try map()
        let session = try await open(graph)
        let a = try #require(ids["A"]), b = try #require(ids["B"])
        session.beginChoosingSymbol(for: [a, b])
        #expect(session.symbolPickerTargets == [a, b])
    }

    // MARK: Canvas

    @Test func aColorFlowsDownUntilATopicSetsItsOwn() throws {
        var (graph, ids) = try map()
        var engine = try GraphEngine(state: graph)
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [try #require(ids["A"])], color: .set(.violet)))
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [try #require(ids["A1"])], color: .set(.green)))
        // A token from a newer version reads as none: B follows the theme.
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [try #require(ids["B"])], color: .set(TopicColor(rawValue: "ultraviolet"))))
        // The central topic passes nothing down.
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [try #require(ids["Plan"])], color: .set(.amber)))
        graph = engine.state
        let scene = scene(graph)
        func topic(_ title: String) throws -> CanvasTopic {
            let id = try #require(ids[title])
            return try #require(scene.topic(id))
        }
        func drawn(_ title: String) throws -> TopicColor? { try topic(title).color }
        func own(_ title: String) throws -> TopicColor? { try topic(title).ownColor }

        #expect(try drawn("Plan") == nil)
        #expect(try drawn("A") == .violet)
        #expect(try drawn("A1") == .green)
        #expect(try drawn("A11") == .green)
        #expect(try drawn("A2") == .violet)
        #expect(try drawn("B") == nil)
        #expect(try own("A2") == nil)
        #expect(try own("A1") == .green)
    }

    @Test func aColorReplacesTheBranchColorInEveryAppearance() {
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let variant = ColorVariant(colorScheme: scheme, contrast: contrast)
                let style = TopicStyle.resolve(level: 2, branch: 0, color: .rose, theme: .standard, colorScheme: scheme, contrast: contrast)
                let expected = BranchColors(line: TopicColor.rose.token, variant: variant)
                #expect(style.edgeColor == expected.line)
                #expect(style.fill == expected.subFill)
                #expect(style.badgeFill == expected.badgeFill)
            }
        }
    }

    @Test func theSymbolIsMeasuredWithTheTitle() throws {
        var (graph, ids) = try map()
        let a = try #require(ids["A"])
        let before = try #require(scene(graph).topic(a))
        var engine = try GraphEngine(state: graph)
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [a], symbol: .set("star.fill")))
        graph = engine.state
        let after = try #require(scene(graph).topic(a))

        #expect(after.marks == TopicMark(shape: nil, symbol: .system("star.fill")))
        #expect(after.frame.width > before.frame.width)
    }

    @Test func aSymbolOutsideTheCatalogueDrawsNothingAndIsKept() throws {
        var (graph, ids) = try map()
        let a = try #require(ids["A"])
        var engine = try GraphEngine(state: graph)
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [a], symbol: .set("future.symbol.v99")))
        graph = engine.state
        #expect(graph.node(a)?.symbol == "future.symbol.v99")
        #expect(try #require(scene(graph).topic(a)).marks == .none)
    }

    @Test func theColorShapeShowsOnlyWithDifferentiateWithoutColor() throws {
        var (graph, ids) = try map()
        let a = try #require(ids["A"]), a2 = try #require(ids["A2"])
        var engine = try GraphEngine(state: graph)
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [a], color: .set(.amber)))
        graph = engine.state

        #expect(try #require(scene(graph).topic(a)).marks == .none)
        let shown = scene(graph, showsColorShapes: true)
        #expect(try #require(shown.topic(a)).marks.shape == .amber)
        // Only the topic the colour was set on carries the shape.
        #expect(try #require(shown.topic(a2)).marks == .none)
    }

    @Test func canvasMeasuresAgainWhenTheSymbolChanges() async throws {
        let (graph, ids) = try map()
        let session = try await open(graph)
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        let a = try #require(ids["A"])
        let width = try #require(canvas.scene.topic(a)).frame.width

        session.setSymbol("🚀", on: [a])
        await canvas.layoutSettled()
        #expect(try #require(canvas.scene.topic(a)).frame.width > width)

        session.setSymbol(nil, on: [a])
        await canvas.layoutSettled()
        #expect(try #require(canvas.scene.topic(a)).frame.width == width)
    }

    // MARK: Export and catalogue

    @Test func exportAlwaysDrawsTheColorShape() async throws {
        var (graph, ids) = try map()
        let a = try #require(ids["A"])
        var engine = try GraphEngine(state: graph)
        _ = try engine.execute(SetNodeStyleCommand(nodeIDs: [a], color: .set(.blue), symbol: .set("💡")))
        graph = engine.state

        let picture = await MapPicture.make(graph)
        let topic = try #require(picture.scene.topic(a))
        #expect(topic.marks == TopicMark(shape: .blue, symbol: .emoji("💡")))
        #expect(topic.color == .blue)
    }

    @Test func catalogueNamesAreUniqueAndDrawable() {
        let names = TopicSymbolCatalog.entries.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy(TopicSymbol.isSymbolName))
        #expect(TopicSymbolCatalog.drawable("flag.fill") == .system("flag.fill"))
        #expect(TopicSymbolCatalog.drawable("🔥") == .emoji("🔥"))
        #expect(TopicSymbolCatalog.drawable(nil) == nil)
        #expect(TopicSymbolCatalog.spokenName(of: .emoji("🔥")) == "🔥")
        // Each colour has its own shape, so none is told by hue alone.
        #expect(Set(TopicColor.all.map(\.shapeSymbol)).count == TopicColor.all.count)
    }

    private struct OpenFailed: Error {}
}
