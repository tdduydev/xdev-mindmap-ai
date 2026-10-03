import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
import MindMapLayout

/// One visible topic as the canvas draws it.
nonisolated struct CanvasTopic: Identifiable, Equatable, Sendable {
    let id: NodeID
    /// Nil for the central topic and floating topics.
    let parentID: NodeID?
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
    /// An AI suggestion drawn from the preview graph, not a topic of the map.
    var isSuggestion = false
    /// A topic beside the tree with no parent (FR-ORG-27), drawn as a main topic.
    var isFloating = false
    /// Marked on the card and read by VoiceOver (FR-EDT-13).
    var hasNote = false
    /// Only a link this build can open; drawn on the corner, so not measured.
    var link: TopicLink?
    var topicImage: MindImage?
    /// The callout text (FR-ORG-30); "" while a new bubble is being typed in.
    var callout: String?
    /// Where the bubble sits, above the card; nil without a callout.
    var calloutFrame: CGRect?
    /// Tag chips under the title: up to `maximumTopicTagChips` tags, "+n",
    /// then suggested tags. Part of the measured size.
    var chips: [TopicChip] = []
    /// Every tag name, for VoiceOver, including those past "+n".
    var tagNames: [String] = []
    /// Task fields (MM-35); drawn as the first chips, read in the VoiceOver value.
    var taskState: TaskState?
    var priority: TaskPriority?
    var dueDate: CalendarDay?
    var isOverdue = false
    /// Done over total for the leaf tasks below, computed for this scene only.
    var progress: TaskProgress?
}

/// One chip under a topic's title (MM-34).
nonisolated struct TopicChip: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case tag(TagID)
        /// "+n" for tags past the first few.
        case more(Int)
        /// An AI suggestion, by `TagSuggestionState.Suggestion.id`.
        case suggestion(String)
        /// The task box; a click toggles done (MM-35).
        case checkbox(done: Bool)
        /// `!` marks, by level.
        case priority(Int)
        /// "3/5" with a ring.
        case progress(done: Int, total: Int)
        case due(overdue: Bool)
    }

    let kind: Kind
    let label: String
    let color: TopicColor?
    /// Set by `TopicMeasurer`; the view draws the chip at this width.
    var width: CGFloat = 0

    var id: Kind { kind }

    var isSuggestion: Bool {
        if case .suggestion = kind { return true }
        return false
    }

    /// Chips drawn with a symbol before the label, measured with `symbolWidth`.
    var hasSymbol: Bool {
        switch kind {
        case .suggestion, .checkbox, .progress, .due: true
        case .tag, .more, .priority: false
        }
    }

    /// The task chips, before any tag: box, priority, progress, due date.
    static func taskChips(
        state: TaskState?, priority: TaskPriority?, progress: TaskProgress?, due: CalendarDay?, today: CalendarDay
    ) -> [TopicChip] {
        var chips: [TopicChip] = []
        if let state {
            chips.append(TopicChip(kind: .checkbox(done: state.isDone), label: "", color: nil))
        }
        if let priority {
            chips.append(TopicChip(kind: .priority(priority.level.rawValue), label: priority.marks, color: nil))
        }
        if let progress {
            chips.append(TopicChip(kind: .progress(done: progress.done, total: progress.total), label: "\(progress.done)/\(progress.total)", color: nil))
        }
        if let due, state != nil || progress != nil {
            let overdue = CalendarDay.isOverdue(due, state: state, today: today)
            // The word as well as the symbol and the colour (WCAG 1.4.1).
            let date = due.shortText(today: today)
            let label = overdue ? String(localized: "Overdue \(date)") : date
            chips.append(TopicChip(kind: .due(overdue: overdue), label: label, color: nil))
        }
        return chips
    }

    /// The chips for a topic's tags and suggested tag names.
    static func chips(tags: [MindTag], suggestions: [(id: String, name: String)]) -> [TopicChip] {
        let limit = CanvasMetrics.maximumTopicTagChips
        var chips = tags.prefix(limit).map { TopicChip(kind: .tag($0.id), label: $0.name, color: $0.color) }
        if tags.count > limit {
            let more = tags.count - limit
            chips.append(TopicChip(kind: .more(more), label: "+\(more)", color: nil))
        }
        chips += suggestions.map { TopicChip(kind: .suggestion($0.id), label: $0.name, color: nil) }
        return chips
    }
}

/// Everything the canvas draws for one state of the map: the layout and the
/// visible topics in reading order. Built off the main actor; culling queries
/// it every frame.
nonisolated struct CanvasScene: Sendable {
    /// A curve with the box culling tests it against, worked out once per
    /// layout rather than on every frame of a pan.
    struct Curve<ID: Sendable>: Sendable {
        let id: ID
        let path: EdgePath
        let bounds: CGRect
    }

    private(set) var layout: MapLayout?
    /// Visible topics in outline order (pre-order), which is also the
    /// VoiceOver and rotor order.
    private(set) var topics: [CanvasTopic]
    private var index: [NodeID: Int]
    private(set) var crossLinkTypes: [EdgeID: EdgeType]
    /// Hierarchy connectors, keyed by the child they lead to.
    private let connectorCurves: [Curve<NodeID>]
    private let crossLinkCurves: [Curve<EdgeID>]

    static let empty = CanvasScene(layout: nil, topics: [], crossLinkTypes: [:])

    init(layout: MapLayout?, topics: [CanvasTopic], crossLinkTypes: [EdgeID: EdgeType]) {
        self.layout = layout
        self.topics = topics
        self.crossLinkTypes = crossLinkTypes
        var index: [NodeID: Int] = [:]
        index.reserveCapacity(topics.count)
        for (position, topic) in topics.enumerated() { index[topic.id] = position }
        self.index = index
        connectorCurves = layout?.connectors.map { Curve(id: $0.key, path: $0.value, bounds: $0.value.controlBounds) } ?? []
        crossLinkCurves = layout?.crossLinks.map { Curve(id: $0.key, path: $0.value, bounds: $0.value.controlBounds) } ?? []
    }

    var bounds: CGRect { layout?.bounds ?? .zero }
    var isEmpty: Bool { topics.isEmpty }

    func topic(_ id: NodeID) -> CanvasTopic? {
        index[id].map { topics[$0] }
    }

    // MARK: Culling
    //
    // A linear scan over precomputed boxes: at 1,000 topics it stays far
    // inside a frame (see `timingsForAThousandTopics`), so a spatial index
    // would add code without a measurable gain.

    /// Topics whose frame or callout meets `rect`, in reading order.
    func topics(in rect: CGRect) -> [CanvasTopic] {
        topics.filter { $0.frame.intersects(rect) || $0.calloutFrame?.intersects(rect) == true }
    }

    /// Connectors into visible topics whose curve may cross `rect`. A cubic
    /// Bézier stays inside the box of its four points, so that box is the test.
    func connectors(in rect: CGRect) -> [(child: NodeID, path: EdgePath)] {
        connectorCurves.compactMap { $0.bounds.intersects(rect) ? ($0.id, $0.path) : nil }
    }

    func crossLinks(in rect: CGRect) -> [(id: EdgeID, path: EdgePath)] {
        crossLinkCurves.compactMap { $0.bounds.intersects(rect) ? ($0.id, $0.path) : nil }
    }

    /// The central topic and its children, which the iPhone fits to the width at first.
    var firstLevelBounds: CGRect {
        topics.filter { $0.level <= 1 }.reduce(CGRect.null) { $0.union($1.frame) }
    }
}

extension EdgePath {
    nonisolated var controlBounds: CGRect {
        let minX = min(start.x, control1.x, control2.x, end.x)
        let maxX = max(start.x, control1.x, control2.x, end.x)
        let minY = min(start.y, control1.y, control2.y, end.y)
        let maxY = max(start.y, control1.y, control2.y, end.y)
        // A horizontal or vertical line has zero area, which `intersects` treats
        // as empty; give it a hairline so it is still found.
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }
}

/// Topic sizes measured on an earlier pass, kept while title and level stay
/// the same so an edit re-measures only what it touched.
nonisolated struct TopicMeasure: Equatable, Sendable {
    let title: String
    let level: Int
    /// What the chips say; a renamed tag measures the topic again.
    var chipLabels: [String] = []
    /// The picture's frame, nil without one; a resize measures the topic again.
    var imageSize: CGSize?
    let size: CGSize
    /// The callout text the bubble was measured for, and the bubble.
    var callout: String?
    var calloutSize: CGSize?
    /// The chips with their measured widths.
    var chips: [TopicChip] = []
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
    /// Topics of `graph` that are AI suggestions (`SuggestionState.preview`).
    var suggestions: Set<NodeID> = []
    /// Suggested tag names per topic, drawn as AI chips.
    var tagSuggestions: [NodeID: [(id: String, name: String)]] = [:]
    /// A topic whose bubble is open for typing: it gets a bubble even before
    /// it has callout text, so the room is there while the person types.
    var calloutDraft: NodeID?

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

        let tags = graph.tagsByNode()
        let images = graph.imagesByNode()
        let progress = graph.taskProgressByNode()
        let today = CalendarDay.today()
        var chips: [NodeID: [TopicChip]] = [:]
        var callouts: [NodeID: CGSize] = [:]
        var calloutTexts: [NodeID: String] = [:]
        for item in outline {
            guard let node = graph.node(item.nodeID) else { continue }
            let callout = node.callout ?? (item.nodeID == calloutDraft ? "" : nil)
            if let callout {
                calloutTexts[item.nodeID] = callout
                if let known = measures[item.nodeID], known.callout == callout, known.level == item.depth,
                   let measured = known.calloutSize {
                    callouts[item.nodeID] = measured
                } else {
                    callouts[item.nodeID] = measurer.calloutSize(of: callout, level: item.depth)
                }
            }
            // A draft bubble opening or closing is no graph change, so the
            // layout learns of it here.
            if measures[item.nodeID].map({ $0.calloutSize != callouts[item.nodeID] }) ?? false {
                changed.insert(item.nodeID)
            }
            var topicChips = TopicChip.taskChips(
                state: node.taskState, priority: node.priority, progress: progress[item.nodeID], due: node.dueDate, today: today
            ) + TopicChip.chips(tags: tags[item.nodeID] ?? [], suggestions: tagSuggestions[item.nodeID] ?? [])
            let labels = topicChips.map(\.label)
            let imageSize = images[item.nodeID].map { measurer.imageSize(of: $0, level: item.depth) }
            if let known = measures[item.nodeID], known.title == node.title, known.level == item.depth, known.chipLabels == labels,
               known.imageSize == imageSize {
                sizes[item.nodeID] = known.size
                measures[item.nodeID]?.callout = callout
                measures[item.nodeID]?.calloutSize = callouts[item.nodeID]
                // The kinds can change under the same labels (a tag renamed to another's name).
                chips[item.nodeID] = zip(topicChips, known.chips).map { chip, measured in
                    var chip = chip
                    chip.width = measured.width
                    return chip
                }
                continue
            }
            // A move changes the level of a whole branch, and the level picks the
            // font, so a topic the change set never named can still change size.
            let size = measurer.size(of: node.title, level: item.depth, chips: &topicChips, image: imageSize)
            if measures[item.nodeID]?.size != size { changed.insert(item.nodeID) }
            measures[item.nodeID] = TopicMeasure(
                title: node.title, level: item.depth, chipLabels: labels, imageSize: imageSize, size: size,
                callout: callout, calloutSize: callouts[item.nodeID], chips: topicChips
            )
            sizes[item.nodeID] = size
            chips[item.nodeID] = topicChips
        }
        // Forget deleted topics; hidden ones keep their measure for when they reappear.
        if measures.count > graph.nodes.count {
            measures = measures.filter { graph.nodes[$0.key] != nil }
        }

        let engine = graph.map.layoutConfiguration.style.engine
        let layout = if let previous {
            engine.update(previous, graph: graph, sizes: sizes, callouts: callouts, options: options, changed: changed)
        } else {
            engine.layout(graph, sizes: sizes, callouts: callouts, options: options)
        }
        let scene = Self.scene(
            outline: outline, graph: graph, layout: layout, suggestions: suggestions, chips: chips, tags: tags,
            callouts: calloutTexts, progress: progress, today: today
        )
        return Output(scene: scene, measures: measures)
    }

    private static func scene(
        outline: [OutlineItem],
        graph: GraphState,
        layout: MapLayout,
        suggestions: Set<NodeID>,
        chips: [NodeID: [TopicChip]],
        tags: [NodeID: [MindTag]],
        callouts: [NodeID: String],
        progress: [NodeID: TaskProgress],
        today: CalendarDay
    ) -> CanvasScene {
        var topics: [CanvasTopic] = []
        let images = graph.imagesByNode()
        topics.reserveCapacity(outline.count)
        var branch = -1
        for item in outline {
            guard let node = graph.node(item.nodeID), let placed = layout.nodes[item.nodeID] else { continue }
            if item.depth == 1 { branch += 1 }
            topics.append(CanvasTopic(
                id: node.id,
                parentID: node.parentID,
                title: node.title,
                level: item.depth,
                branch: max(branch, 0),
                frame: placed.frame,
                side: placed.side,
                childCount: graph.childIDs(of: node.id).count,
                isCollapsed: node.isCollapsed,
                hiddenDescendantCount: placed.hiddenDescendantCount,
                isSuggestion: suggestions.contains(node.id),
                isFloating: node.isFloating(rootID: graph.map.rootNodeID),
                hasNote: node.hasNote,
                link: node.link?.url == nil ? nil : node.link,
                topicImage: images[node.id],
                callout: callouts[node.id],
                calloutFrame: placed.calloutFrame,
                chips: chips[node.id] ?? [],
                tagNames: tags[node.id]?.map(\.name) ?? [],
                taskState: node.taskState,
                priority: node.priority,
                dueDate: node.dueDate,
                isOverdue: CalendarDay.isOverdue(node.dueDate, state: node.taskState, today: today),
                progress: progress[node.id]
            ))
        }
        let types = layout.crossLinks.keys.reduce(into: [EdgeID: EdgeType]()) { types, id in
            types[id] = graph.edges[id]?.edgeType
        }
        return CanvasScene(layout: layout, topics: topics, crossLinkTypes: types)
    }
}
