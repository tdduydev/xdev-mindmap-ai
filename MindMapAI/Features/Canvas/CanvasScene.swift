import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
import MindMapLayout

/// One visible topic as the canvas draws it.
nonisolated struct CanvasTopic: Identifiable, Equatable, Sendable {
    let id: NodeID
    let title: String
    /// 0 for the central topic.
    let level: Int
    /// Index of the level-1 branch the topic belongs to, which picks its colour.
    let branch: Int
    let frame: CGRect
    let side: LayoutSide
    let childCount: Int
    let isCollapsed: Bool
    /// Topics a collapsed branch hides, for the badge.
    let hiddenDescendantCount: Int
}

/// Everything the canvas draws for one state of the map: the layout and the
/// visible topics in reading order. Built off the main actor; culling queries
/// it every frame.
nonisolated struct CanvasScene: Sendable {
    private(set) var layout: MapLayout?
    /// Visible topics in outline order (pre-order), which is also the
    /// VoiceOver and rotor order.
    private(set) var topics: [CanvasTopic]
    private var index: [NodeID: Int]
    private(set) var crossLinkTypes: [EdgeID: EdgeType]

    static let empty = CanvasScene(layout: nil, topics: [], crossLinkTypes: [:])

    init(layout: MapLayout?, topics: [CanvasTopic], crossLinkTypes: [EdgeID: EdgeType]) {
        self.layout = layout
        self.topics = topics
        self.crossLinkTypes = crossLinkTypes
        var index: [NodeID: Int] = [:]
        index.reserveCapacity(topics.count)
        for (position, topic) in topics.enumerated() { index[topic.id] = position }
        self.index = index
    }

    var bounds: CGRect { layout?.bounds ?? .zero }
    var isEmpty: Bool { topics.isEmpty }

    func topic(_ id: NodeID) -> CanvasTopic? {
        index[id].map { topics[$0] }
    }

    // MARK: Culling
    //
    // A linear scan: 1,000 rectangle tests take microseconds, well inside a
    // frame, so a spatial index would add code without a measurable gain.

    /// Topics whose frame meets `rect`, in reading order.
    func topics(in rect: CGRect) -> [CanvasTopic] {
        topics.filter { $0.frame.intersects(rect) }
    }

    /// Connectors into visible topics whose curve may cross `rect`. A cubic
    /// Bézier stays inside the box of its four points, so that box is the test.
    func connectors(in rect: CGRect) -> [(child: NodeID, path: EdgePath)] {
        guard let layout else { return [] }
        return layout.connectors.compactMap { child, path in
            path.controlBounds.intersects(rect) ? (child, path) : nil
        }
    }

    func crossLinks(in rect: CGRect) -> [(id: EdgeID, path: EdgePath)] {
        guard let layout else { return [] }
        return layout.crossLinks.compactMap { id, path in
            path.controlBounds.intersects(rect) ? (id, path) : nil
        }
    }

    /// The central topic and its children, which the iPhone fits to the width at first.
    var firstLevelBounds: CGRect {
        topics.filter { $0.level <= 1 }.reduce(CGRect.null) { $0.union($1.frame) }
    }
}

extension EdgePath {
    nonisolated var controlBounds: CGRect {
        let xs = [start.x, control1.x, control2.x, end.x]
        let ys = [start.y, control1.y, control2.y, end.y]
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        // A horizontal or vertical line has zero area, which `intersects` treats
        // as empty; give it a hairline so it is still found.
        return CGRect(x: minX, y: minY, width: max((xs.max() ?? 0) - minX, 1), height: max((ys.max() ?? 0) - minY, 1))
    }
}

/// Topic sizes measured on an earlier pass, kept while title and level stay
/// the same so an edit re-measures only what it touched.
nonisolated struct TopicMeasure: Equatable, Sendable {
    let title: String
    let level: Int
    let size: CGSize
}

/// One measure-and-layout run, as plain values so it runs off the main actor
/// (NFR-PERF-04).
nonisolated struct CanvasLayoutPass: Sendable {
    let graph: GraphState
    /// Nil for a full layout.
    let previous: MapLayout?
    /// Sizes from earlier passes; empty when the text settings changed.
    let measures: [NodeID: TopicMeasure]
    /// Topics the edits since the last pass touched (`layoutInvalidation`).
    let changed: Set<NodeID>
    let specs: TopicTextSpecs
    let options: LayoutOptions

    struct Output: Sendable {
        let scene: CanvasScene
        let measures: [NodeID: TopicMeasure]
    }

    @concurrent
    func runInBackground() async -> Output {
        run()
    }

    func run() -> Output {
        let outline = graph.visibleOutline()
        let measurer = TopicMeasurer(specs: specs)
        var measures = self.measures
        var sizes: [NodeID: CGSize] = [:]
        sizes.reserveCapacity(outline.count)
        var changed = changed

        for item in outline {
            guard let node = graph.node(item.nodeID) else { continue }
            if let known = measures[item.nodeID], known.title == node.title, known.level == item.depth {
                sizes[item.nodeID] = known.size
                continue
            }
            // A move changes the level of a whole branch, and the level picks the
            // font, so a topic the change set never named can still change size.
            let size = measurer.size(of: node.title, level: item.depth)
            if measures[item.nodeID]?.size != size { changed.insert(item.nodeID) }
            measures[item.nodeID] = TopicMeasure(title: node.title, level: item.depth, size: size)
            sizes[item.nodeID] = size
        }
        // Forget deleted topics; hidden ones keep their measure for when they reappear.
        if measures.count > graph.nodes.count {
            measures = measures.filter { graph.nodes[$0.key] != nil }
        }

        let engine = graph.map.layoutConfiguration.style.engine
        let layout = if let previous {
            engine.update(previous, graph: graph, sizes: sizes, options: options, changed: changed)
        } else {
            engine.layout(graph, sizes: sizes, options: options)
        }
        return Output(scene: Self.scene(outline: outline, graph: graph, layout: layout), measures: measures)
    }

    private static func scene(outline: [OutlineItem], graph: GraphState, layout: MapLayout) -> CanvasScene {
        var topics: [CanvasTopic] = []
        topics.reserveCapacity(outline.count)
        var branch = -1
        for item in outline {
            guard let node = graph.node(item.nodeID), let placed = layout.nodes[item.nodeID] else { continue }
            if item.depth == 1 { branch += 1 }
            topics.append(CanvasTopic(
                id: node.id,
                title: node.title,
                level: item.depth,
                branch: max(branch, 0),
                frame: placed.frame,
                side: placed.side,
                childCount: graph.childIDs(of: node.id).count,
                isCollapsed: node.isCollapsed,
                hiddenDescendantCount: placed.hiddenDescendantCount
            ))
        }
        let types = layout.crossLinks.keys.reduce(into: [EdgeID: EdgeType]()) { types, id in
            types[id] = graph.edges[id]?.edgeType
        }
        return CanvasScene(layout: layout, topics: topics, crossLinkTypes: types)
    }
}
