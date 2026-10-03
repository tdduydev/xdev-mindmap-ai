import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapLayout
import MindMapSearch
import Observation
import SwiftUI

/// The canvas of one open map: the laid-out scene, the camera, and inline
/// editing. Edits still go through `EditorSession` as commands; this type only
/// turns gestures into session intents and keeps the layout in step with the graph.
@Observable
final class CanvasModel {
    enum InitialPlacement {
        /// The whole map fitted to the view, never above actual size (Mac, iPad).
        case wholeMap
        /// The central topic and its children fitted to the width (iPhone).
        case firstLevelWidth
        /// The central topic and its children fitted to the view, at
        /// accessibility text sizes where actual size shows only a few topics.
        case firstLevel
    }

    let session: EditorSession
    /// AI suggestions to draw with the map; nil where AI is not offered.
    let assistant: AIAssistant?
    private(set) var scene: CanvasScene = .empty
    private(set) var viewport = CanvasViewport() {
        didSet {
            if !isPlacingInitially, viewport != oldValue { keepsInitialPlacement = false }
        }
    }
    /// The topic whose title is being edited in place.
    private(set) var editingID: NodeID? {
        didSet { reportKeyboardFocus() }
    }
    /// The connection whose label is being edited in place (double-click).
    var editingConnectionLabel: EdgeID?
    /// The boundary whose title is being edited in place (double-click, Space).
    var editingBoundaryTitle: GroupID?
    /// Whether the canvas itself holds keyboard focus. Set by the view.
    var hasKeyboardFocus = false {
        didSet { reportKeyboardFocus() }
    }
    /// The title as typed so far; committed as one Rename Topic command.
    var editingDraft = ""
    /// True while a drag pans the canvas, for the closed-hand pointer.
    private(set) var isPanning = false
    /// Topics being dragged to a new place, while the drag lasts.
    private(set) var drag: TopicDrag?
    /// The selection rectangle being dragged, in view points.
    private(set) var marquee: CGRect?
    /// Counts drops refused because they aim into a moving branch, so the view
    /// can play feedback each time.
    private(set) var refusedDrops = 0
    /// The topic under the pointer, for its + buttons (MM-57).
    private(set) var hoveredID: NodeID?

    @ObservationIgnored var initialPlacement = InitialPlacement.wholeMap
    @ObservationIgnored private var needsInitialPlacement = true
    /// Until the person moves the camera or edits the map, the first view is
    /// placed again when the view or the layout changes: a window opens at one
    /// size and settles at another, an inspector takes width, Dynamic Type
    /// remeasures. Otherwise the map fitted to the first size ends up cut off.
    @ObservationIgnored private var keepsInitialPlacement = false
    @ObservationIgnored private var isPlacingInitially = false
    @ObservationIgnored private var specs: TopicTextSpecs?
    /// Bumped when the text settings change, so a pass started with the old
    /// ones does not store its sizes.
    @ObservationIgnored private var specsGeneration = 0
    @ObservationIgnored private var measures: [NodeID: TopicMeasure] = [:]
    @ObservationIgnored private var pendingChanges: Set<NodeID> = []
    @ObservationIgnored private var needsPass = false
    @ObservationIgnored private var needsFullLayout = true
    /// Whether the last pass drew suggestions; the next one then starts over,
    /// since the previous layout holds topics the map does not.
    @ObservationIgnored private var lastPassHadSuggestions = false
    @ObservationIgnored private var lastPassWasFiltered = false
    @ObservationIgnored private var isLayingOut = false
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    /// A topic to scroll into view (and maybe edit) once the layout has it.
    @ObservationIgnored private var pendingReveal: (id: NodeID, edit: Bool)?
    @ObservationIgnored private var styles: [StyleKey: TopicStyle] = [:]
    /// What was selected before a marquee drag that adds to the selection.
    @ObservationIgnored private var marqueeBase: (ids: Set<NodeID>, primary: NodeID?) = ([], nil)
    @ObservationIgnored private var hoveredParts: Set<HoverPart> = []
    @ObservationIgnored private var hoverExit: Task<Void, Never>?
    @ObservationIgnored let layoutOptions = CanvasModel.layoutOptions

    /// Shared with export, so a picture of the map has the canvas's layout.
    static let layoutOptions = LayoutOptions(
        horizontalSpacing: CanvasMetrics.layoutParentGap,
        verticalSpacing: CanvasMetrics.layoutSiblingGap,
        calloutSpacing: CanvasMetrics.calloutSpacing,
        boundaryPadding: CanvasMetrics.boundaryPadding,
        boundaryTitleHeight: CanvasMetrics.boundaryTitleHeight,
        summaryBracketGap: CanvasMetrics.summaryBracketGap,
        summaryBracketWidth: CanvasMetrics.summaryBracketWidth
    )

    init(session: EditorSession, assistant: AIAssistant? = nil) {
        self.session = session
        self.assistant = assistant
        session.onGraphChange = { [weak self] changes in
            self?.graphDidChange(changes)
        }
        assistant?.onSuggestionsChange = { [weak self] in
            self?.suggestionsDidChange()
        }
        session.onViewFilterChange = { [weak self] in
            self?.suggestionsDidChange()
        }
        session.floatingTopicPlacement = { [weak self] in
            self?.freeFloatingSpot()
        }
    }

    // MARK: Reading

    var isDetailed: Bool { viewport.scale >= CanvasMetrics.detailZoomThreshold }

    /// Topics to draw: those in the view plus a margin (FR-CNV-06).
    var visibleTopics: [CanvasTopic] {
        scene.topics(in: viewport.cullingRect(margin: CanvasMetrics.cullingMargin))
    }

    var cullingRect: CGRect { viewport.cullingRect(margin: CanvasMetrics.cullingMargin) }

    var canZoomIn: Bool { viewport.scale < CanvasMetrics.zoomLimits.upperBound }
    var canZoomOut: Bool { viewport.scale > CanvasMetrics.zoomLimits.lowerBound }
    var canZoomToFit: Bool { !scene.isEmpty }

    /// Waits for every layout pass scheduled so far, for tests.
    func layoutSettled() async {
        while let task = layoutTask, isLayingOut {
            await task.value
        }
    }

    // MARK: Layout

    /// The measured text settings. Changing them (Dynamic Type) measures and
    /// lays out every topic again.
    func setTextSpecs(_ newSpecs: TopicTextSpecs) {
        guard newSpecs != specs else { return }
        specs = newSpecs
        specsGeneration += 1
        measures = [:]
        styles = [:]
        needsFullLayout = true
        scheduleLayout()
    }

    private func suggestionsDidChange() {
        needsFullLayout = true
        scheduleLayout()
    }

    private func graphDidChange(_ changes: GraphChangeSet) {
        // Refitting after an edit would zoom away from what was just changed.
        keepsInitialPlacement = false
        pendingChanges.formUnion(changes.layoutInvalidation)
        if let map = changes.map, map.before?.theme != map.after?.theme { styles = [:] }
        scheduleLayout()
    }

    /// Passes run one at a time; edits made while one runs are folded into the
    /// next, so a burst of commands costs one extra pass, not one each.
    private func scheduleLayout() {
        needsPass = true
        guard specs != nil, !isLayingOut else { return }
        isLayingOut = true
        layoutTask = Task { [weak self] in
            await self?.runLayoutPasses()
        }
    }

    private func runLayoutPasses() async {
        while needsPass, let specs {
            needsPass = false
            let generation = specsGeneration
            // Suggestions are laid out as topics of a preview graph, so they
            // take their place in the tree without being part of the map.
            var graph = session.engine.state
            var suggested: Set<NodeID> = []
            var suggestedBoundaries: Set<GroupID> = []
            if let suggestions = assistant?.suggestions, !suggestions.isEmpty {
                graph = suggestions.preview(in: session.engine)
                suggested = Set(suggestions.drawableTopics(in: graph).keys)
            } else if let preview = assistant?.boundaryPreview() {
                // Suggest Groups moves topics, so the preview is the map after Accept.
                graph = preview.state
                suggestedBoundaries = preview.boundaries
            }
            let hasPreview = !suggested.isEmpty || !suggestedBoundaries.isEmpty
            // Filter and focus draw a projection of the map (MM-36). An edit can
            // make a topic match or stop matching without naming it in the change
            // set, so a filtered pass always lays out from scratch.
            var dimmed: Set<NodeID> = []
            let isFiltered = session.isViewFiltered
            if isFiltered {
                let view = MapFilterView(
                    state: graph, filter: session.filter, mode: session.filterMode,
                    focusID: session.focusID, today: .today()
                )
                graph = view.project(graph)
                dimmed = view.shown.filter { view.isDimmed($0) && !suggested.contains($0) }
            }
            let startOver = needsFullLayout || lastPassHadSuggestions || hasPreview || isFiltered || lastPassWasFiltered
            let pass = CanvasLayoutPass(
                graph: graph,
                previous: startOver ? nil : scene.layout,
                measures: measures,
                changed: pendingChanges,
                specs: specs,
                options: layoutOptions,
                suggestions: suggested,
                tagSuggestions: assistant?.tagSuggestionChips ?? [:],
                boundarySuggestions: suggestedBoundaries,
                calloutDraft: session.calloutEditorTarget,
                dimmed: dimmed
            )
            pendingChanges = []
            needsFullLayout = false
            lastPassHadSuggestions = hasPreview
            lastPassWasFiltered = isFiltered
            let output = await pass.runInBackground()
            if generation == specsGeneration { measures = output.measures }
            apply(output.scene)
        }
        isLayingOut = false
        // The last pass did not lay the topic out, so it is hidden or gone;
        // keeping the request would jump to it after some later, unrelated edit.
        if let request = pendingReveal, scene.topic(request.id) == nil { pendingReveal = nil }
    }

    private func apply(_ newScene: CanvasScene) {
        scene = newScene
        if let editingID, newScene.topic(editingID) == nil {
            // Undo removed the topic being edited.
            self.editingID = nil
        }
        placeInitiallyIfNeeded()
        handlePendingReveal()
    }

    // MARK: Camera

    func setViewSize(_ size: CGSize) {
        if keepsInitialPlacement {
            placeInitially { $0.size = size }
            return
        }
        if viewport.size == .zero {
            viewport.size = size
        } else {
            viewport.resize(to: size)
        }
        placeInitiallyIfNeeded()
    }

    /// FR-CNV-01: the first time the map shows, the whole map is in view (MM-84).
    private func placeInitiallyIfNeeded() {
        if keepsInitialPlacement {
            placeInitially()
            return
        }
        guard needsInitialPlacement, viewport.size.width > 0, viewport.size.height > 0, !scene.isEmpty else { return }
        needsInitialPlacement = false
        keepsInitialPlacement = true
        placeInitially()
    }

    private func placeInitially(adjusting change: (inout CanvasViewport) -> Void = { _ in }) {
        isPlacingInitially = true
        defer { isPlacingInitially = false }
        change(&viewport)
        switch initialPlacement {
        case .wholeMap:
            viewport.fit(scene.bounds, padding: CanvasMetrics.fitPadding, limits: CanvasMetrics.fitZoomLimits)
        case .firstLevelWidth:
            viewport.fitWidth(scene.firstLevelBounds, padding: CanvasMetrics.revealMargin, limits: CanvasMetrics.fitZoomLimits)
        case .firstLevel:
            viewport.fit(scene.firstLevelBounds, padding: CanvasMetrics.revealMargin, limits: CanvasMetrics.fitZoomLimits)
        }
    }

    func pan(by delta: CGSize) {
        viewport.pan(by: delta)
    }

    func setPanning(_ panning: Bool) {
        if isPanning != panning { isPanning = panning }
    }

    func zoom(to scale: CGFloat, anchor: CGPoint) {
        viewport.zoom(to: scale, anchor: anchor, limits: CanvasMetrics.zoomLimits)
    }

    func zoomIn() {
        zoom(to: viewport.zoomStep(up: true, steps: CanvasMetrics.zoomSteps), anchor: viewport.center)
    }

    func zoomOut() {
        zoom(to: viewport.zoomStep(up: false, steps: CanvasMetrics.zoomSteps), anchor: viewport.center)
    }

    /// ⌘0: 100%, keeping the middle of the view where it is.
    func zoomToActualSize() {
        zoom(to: 1, anchor: viewport.center)
    }

    func zoomToFit() {
        guard !scene.isEmpty else { return }
        viewport.fit(scene.bounds, padding: CanvasMetrics.fitPadding, limits: CanvasMetrics.fitZoomLimits)
    }

    /// Scrolls a topic into view, for the VoiceOver rotor and new topics.
    func reveal(_ id: NodeID) {
        guard let topic = scene.topic(id) else { return }
        let frame = topic.calloutFrame.map { topic.frame.union($0) } ?? topic.frame
        viewport.reveal(frame, margin: CanvasMetrics.revealMargin)
    }

    // MARK: Selection and editing

    func select(_ id: NodeID) {
        if editingID != nil, editingID != id { commitEditing() }
        if let suggestion = assistant?.suggestionID(forPreview: id) {
            assistant?.selectedSuggestion = suggestion
            return
        }
        assistant?.selectedSuggestion = nil
        session.selection = id
    }

    /// The preview ID of the suggestion selected on the canvas.
    var selectedSuggestionPreviewID: NodeID? {
        guard let assistant, let id = assistant.selectedSuggestion else { return nil }
        return assistant.suggestions?.topic(id)?.previewID
    }

    // MARK: Tags

    /// The canvas's chip settings, once it has its text settings.
    var chipSpec: TopicChipSpec? { specs?.chip }
    var markSpec: TopicMarkSpec? { specs?.mark }
    /// The callout bubble's text settings, once the canvas has them.
    var calloutSpec: TopicCalloutSpec? { specs?.callout }

    /// What a topic's context menu tags: the selection when the topic is in
    /// it, else the topic alone, as `performFromContextMenu` decides.
    func contextTargets(for id: NodeID) -> [NodeID] {
        session.isSelected(id) ? session.orderedSelection : [id]
    }

    func addTag(to id: NodeID) {
        performFromContextMenu(on: id) { $0.beginAddingTag() }
    }

    func acceptTagSuggestion(_ id: String) {
        assistant?.acceptTag(id)
    }

    func discardTagSuggestion(_ id: String) {
        assistant?.discardTag(id)
    }

    func renameTagSuggestion(_ id: String, to name: String) {
        assistant?.renameTagSuggestion(id, to: name)
    }

    func acceptSuggestion(_ previewID: NodeID) {
        guard let assistant, let id = assistant.suggestionID(forPreview: previewID) else { return }
        assistant.accept(id)
    }

    func discardSuggestion(_ previewID: NodeID) {
        guard let assistant, let id = assistant.suggestionID(forPreview: previewID) else { return }
        assistant.discard(id)
    }

    /// A click or tap that no topic view took: on empty canvas it ends editing
    /// and clears the selection; below the detail zoom, where topics are
    /// shapes rather than views, it selects the topic under it.
    func tap(at viewPoint: CGPoint) {
        if let topic = topic(at: viewPoint) {
            select(topic.id)
        } else if let connection = connection(at: viewPoint) {
            commitEditing()
            session.selectConnection(connection)
            assistant?.selectedSuggestion = nil
        } else if let boundary = boundary(at: viewPoint) {
            commitEditing()
            session.selectBoundary(boundary)
            assistant?.selectedSuggestion = nil
        } else {
            commitEditing()
            session.selection = nil
            assistant?.selectedSuggestion = nil
        }
    }

    /// On a topic it edits the title; on empty canvas it makes a floating
    /// topic centred there and opens its title (FR-ORG-27).
    func doubleTap(at viewPoint: CGPoint) {
        if let topic = topic(at: viewPoint) { return beginEditing(topic.id) }
        if let connection = connection(at: viewPoint) {
            commitEditing()
            session.selectConnection(connection)
            editingConnectionLabel = connection
            return
        }
        if let boundary = boundary(at: viewPoint) {
            commitEditing()
            session.selectBoundary(boundary)
            editingBoundaryTitle = boundary
            return
        }
        guard session.canAddFloatingTopic, let position = position(at: viewport.toCanvas(viewPoint)) else { return }
        commitEditing()
        session.addFloatingTopic(at: position)
    }

    // MARK: Floating topics

    /// A stored position is relative to the central topic's centre (ADR 0010),
    /// so this needs the central topic laid out.
    func position(at canvasPoint: CGPoint) -> TopicPosition? {
        guard let root = session.rootID.flatMap(scene.topic) else { return nil }
        return TopicPosition(x: Double(canvasPoint.x - root.frame.midX), y: Double(canvasPoint.y - root.frame.midY))
    }

    /// Where Add Floating Topic puts a topic: the middle of the view, moved
    /// down a step at a time until a new main topic there overlaps no topic.
    func freeFloatingSpot() -> TopicPosition? {
        guard let specs, viewport.size.width > 0 else { return nil }
        let size = TopicMeasurer(specs: specs).size(of: "", level: 1)
        var centre = viewport.toCanvas(CGPoint(x: viewport.size.width / 2, y: viewport.size.height / 2))
        let gap = layoutOptions.verticalSpacing / 2
        for _ in 0..<CanvasMetrics.floatingTopicNudgeLimit {
            let frame = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
                .insetBy(dx: -gap, dy: -gap)
            if !scene.topics(in: frame).contains(where: { $0.frame.intersects(frame) }) { break }
            centre.y += CanvasMetrics.floatingTopicNudge
        }
        return position(at: centre)
    }

    /// The menu's Add Floating Topic, and the empty canvas's context menu.
    func addFloatingTopic() {
        commitEditing()
        session.addFloatingTopic()
    }

    /// The context menu's and VoiceOver's Detach Topic.
    func detach(_ id: NodeID) {
        performFromContextMenu(on: id) { $0.selection = id; $0.detachSelection() }
    }

    /// The topic drawn under a view point; the last drawn wins, as on screen.
    /// Hit width `Metrics.minimumHitTarget` on screen, whatever the zoom.
    func connection(at viewPoint: CGPoint) -> EdgeID? {
        let tolerance = Metrics.minimumHitTarget / 2 / max(viewport.scale, .ulpOfOne)
        return scene.connection(at: viewport.toCanvas(viewPoint), tolerance: tolerance)
    }

    func boundary(at viewPoint: CGPoint) -> GroupID? {
        let tolerance = Metrics.minimumHitTarget / 2 / max(viewport.scale, .ulpOfOne)
        return scene.boundary(at: viewport.toCanvas(viewPoint), tolerance: tolerance)
    }

    /// Where a boundary's title field goes, in view points: over its title band.
    func boundaryTitleAnchor(_ id: GroupID) -> CGPoint? {
        guard let boundary = scene.boundaries.first(where: { $0.id == id }) else { return nil }
        let band = boundary.titleBand
        return viewport.toView(CGPoint(x: band.minX + CanvasMetrics.boundaryTitleMaxWidth / 2, y: band.midY))
    }

    /// Where a connection's label field goes, in view points.
    func connectionLabelAnchor(_ id: EdgeID) -> CGPoint? {
        scene.crossLinkPath(id).map { viewport.toView($0.midpoint) }
    }

    func topic(at viewPoint: CGPoint) -> CanvasTopic? {
        let point = viewport.toCanvas(viewPoint)
        return scene.topics(in: CGRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)).last { $0.frame.contains(point) }
    }

    /// Scrolls to the selection once it is laid out, when the canvas comes
    /// back from the outline (FR-CNV-12).
    func revealSelection() {
        guard let id = session.selection else { return }
        pendingReveal = (id, false)
        handlePendingReveal()
    }

    /// Takes the session's request to focus a new topic: once the layout has
    /// it, scroll it into view and open its title for editing (FR-CNV-05).
    func takeFocusRequest() {
        guard let id = session.focusRequest else { return }
        session.focusRequest = nil
        commitEditing()
        pendingReveal = (id, true)
        handlePendingReveal()
    }

    private func handlePendingReveal() {
        guard let request = pendingReveal else { return }
        guard scene.topic(request.id) != nil else {
            // Not laid out yet; the next pass tries again. If nothing is coming,
            // the topic is hidden or gone and the request is dropped.
            if !isLayingOut { pendingReveal = nil }
            return
        }
        pendingReveal = nil
        if request.edit {
            beginEditing(request.id)
            AccessibilityNotification.Announcement(String(localized: "Topic added")).post()
        } else {
            reveal(request.id)
        }
    }

    /// A title being typed keeps Delete for the text; the focused canvas
    /// lets it be Delete Topic's shortcut (see `EditorSession.deleteKeyDeletesTopic`).
    private func reportKeyboardFocus() {
        let focus: EditorSession.KeyboardFocus = editingID != nil ? .editingText : hasKeyboardFocus ? .content : .elsewhere
        session.reportKeyboardFocus(focus, from: .canvas)
    }

    /// Space on the canvas, or the Rename Topic menu item.
    @discardableResult
    func beginEditingSelection() -> Bool {
        // Space on a selected boundary renames it.
        if editingID == nil, let boundary = session.activeBoundary {
            editingBoundaryTitle = boundary
            return true
        }
        guard editingID == nil, let id = session.selection, scene.topic(id) != nil else { return false }
        beginEditing(id)
        return true
    }

    /// Double-click or double-tap (FR-CNV-04).
    func beginEditing(_ id: NodeID) {
        guard editingID != id, let topic = scene.topic(id) else { return }
        // A suggestion is edited the same way, but its title goes back to the
        // suggestions, not to the map.
        let suggestion = assistant?.suggestionID(forPreview: id)
        guard suggestion != nil || session.engine.state.node(id) != nil else { return }
        commitEditing()
        if let suggestion {
            assistant?.selectedSuggestion = suggestion
        } else {
            session.selection = id
        }
        // A title field at 10% would be unreadable; come in to actual size around the topic.
        if !isDetailed {
            zoom(to: 1, anchor: viewport.toView(CGPoint(x: topic.frame.midX, y: topic.frame.midY)))
        }
        viewport.reveal(topic.frame, margin: CanvasMetrics.revealMargin)
        editingDraft = topic.title
        editingID = id
    }

    /// Return in the title field, or focus leaving it.
    func commitEditing() {
        guard let id = editingID else { return }
        editingID = nil
        if let suggestion = assistant?.suggestionID(forPreview: id) {
            assistant?.renameSuggestion(suggestion, to: editingDraft)
            return
        }
        guard let node = session.engine.state.node(id), node.title != editingDraft else { return }
        session.rename(id, to: editingDraft)
    }

    /// Esc: the title stays as it was.
    func cancelEditing() {
        editingID = nil
    }

    // MARK: Topic actions

    func toggleCollapsed(_ id: NodeID) {
        commitEditing()
        session.toggleCollapsed(id)
    }

    func addChild(of id: NodeID) {
        select(id)
        session.addChild()
    }

    func addSibling(of id: NodeID) {
        select(id)
        session.addSibling()
    }

    func delete(_ id: NodeID) {
        select(id)
        session.deleteSelection()
    }

    // MARK: Add buttons (MM-57)

    /// The parts of a topic the pointer can be over. The + buttons sit outside
    /// the card, so each reports its own hover.
    enum HoverPart: Hashable {
        case card, addChild, addSibling
    }

    /// The + buttons a topic shows, and where.
    struct AddButtons: Equatable {
        /// The side away from the parent, where children go; trailing for the central topic.
        let childEdge: HorizontalEdge
        /// The central topic has no siblings.
        let showsSibling: Bool
    }

    /// Records pointer movement over a topic and its buttons. Leaving waits a
    /// moment before the buttons go, so the pointer can cross the gap from the
    /// card to a button, or pass over an edge, without them blinking.
    func setHovering(_ id: NodeID, part: HoverPart, _ inside: Bool) {
        if inside {
            hoverExit?.cancel()
            hoverExit = nil
            if hoveredID != id {
                hoveredParts = []
                hoveredID = id
            }
            hoveredParts.insert(part)
            return
        }
        guard hoveredID == id else { return }
        hoveredParts.remove(part)
        guard hoveredParts.isEmpty else { return }
        hoverExit?.cancel()
        hoverExit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Motion.hoverExitDelay))
            guard !Task.isCancelled, let self, self.hoveredParts.isEmpty, self.hoveredID == id else { return }
            self.hoveredID = nil
        }
    }

    /// Waits for a pending hover exit, for tests.
    func hoverSettled() async {
        await hoverExit?.value
    }

    /// The + buttons for a topic: on the one under the pointer, and on the
    /// primary selection, since touch has no hover. None on suggestions, on a
    /// title being edited, while dragging or drawing a rectangle, or below the
    /// detail zoom, where topics are shapes.
    func addButtons(for topic: CanvasTopic) -> AddButtons? {
        guard isDetailed, !topic.isSuggestion, drag == nil, marquee == nil, topic.id != editingID,
              topic.id == hoveredID || topic.id == session.selection else { return nil }
        let isRoot = topic.id == session.rootID
        return AddButtons(childEdge: topic.side == .left ? .leading : .trailing, showsSibling: !isRoot && !topic.isFloating)
    }

    /// A + button: the same command as Add Child Topic or Add Sibling Topic,
    /// so one undo step, and the new topic opens for editing.
    func addFromButton(_ id: NodeID, sibling: Bool) {
        hoverExit?.cancel()
        hoveredID = nil
        hoveredParts = []
        if sibling { addSibling(of: id) } else { addChild(of: id) }
    }

    func editNote(_ id: NodeID) {
        select(id)
        session.editSelectionNote()
    }

    /// Always the picker: the context menu and VoiceOver name one topic, so a
    /// second selected topic must not become the target unasked.
    func addConnection(from id: NodeID) {
        commitEditing()
        session.selection = id
        session.beginAddingConnection()
    }

    func editLink(_ id: NodeID) {
        performFromContextMenu(on: id) { $0.selection = id; $0.beginEditingSelectionLink() }
    }

    func removeLink(_ id: NodeID) {
        commitEditing()
        session.removeLink(from: id)
    }

    // MARK: Callouts

    func editCallout(_ id: NodeID) {
        performFromContextMenu(on: id) { $0.selection = id; $0.beginEditingSelectionCallout() }
    }

    func removeCallout(_ id: NodeID) {
        commitEditing()
        session.removeCallout(from: id)
    }

    /// A bubble opened or closed for typing: it takes or gives back room in
    /// the layout, and an opened one scrolls into view.
    func calloutEditingDidChange() {
        if let id = session.calloutEditorTarget {
            commitEditing()
            pendingReveal = (id, false)
        }
        scheduleLayout()
    }

    // MARK: Multi-selection

    /// How a click or tap on a topic changes the selection.
    enum SelectionGesture {
        /// A plain click: that topic alone.
        case replace
        /// ⌘-click: in or out of the selection.
        case toggle
        /// ⇧-click: added to the selection.
        case add
    }

    func click(_ id: NodeID, _ gesture: SelectionGesture) {
        // A suggestion is not a topic yet, so it never joins a multi-selection.
        if assistant?.suggestionID(forPreview: id) != nil { return select(id) }
        if editingID != nil, editingID != id { commitEditing() }
        assistant?.selectedSuggestion = nil
        switch gesture {
        case .replace: session.selection = id
        case .toggle: session.toggleSelected(id)
        case .add: session.addToSelection(id)
        }
    }

    /// Starts a selection rectangle on empty canvas. With `adding`, topics
    /// already selected stay selected (⇧-drag); otherwise the rectangle alone
    /// decides (⌘-drag, or a hold and drag on touch).
    func beginMarquee(at viewPoint: CGPoint, adding: Bool) {
        commitEditing()
        marqueeBase = adding ? (session.selectedIDs, session.selection) : ([], nil)
        marquee = CGRect(origin: viewPoint, size: .zero)
        session.setSelection(marqueeBase.ids, primary: marqueeBase.primary)
    }

    func updateMarquee(from start: CGPoint, to current: CGPoint) {
        guard marquee != nil else { return }
        let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
        marquee = rect
        let canvasRect = CGRect(origin: viewport.toCanvas(rect.origin), size: CGSize(width: rect.width / viewport.scale, height: rect.height / viewport.scale))
        // Topics faded by the filter are not picked, as Select All leaves them out.
        let hit = scene.topics(in: canvasRect).filter { !$0.isSuggestion && !$0.isDimmed }
        let primary = marqueeBase.primary ?? hit.first?.id
        session.setSelection(marqueeBase.ids.union(hit.map(\.id)), primary: primary)
    }

    func endMarquee() {
        marquee = nil
        marqueeBase = ([], nil)
    }

    /// ⌘A on the canvas.
    func selectAll() {
        commitEditing()
        session.selectAll()
    }

    // MARK: Keyboard

    /// The keys the canvas handles itself rather than through the menu bar, so
    /// they never reach the menu while a title field is typing (FR-KBD-01).
    enum Key {
        /// Return.
        case addSibling
        /// Tab.
        case addChild
        /// ⇧Tab.
        case promote
        /// Space.
        case rename
        /// An arrow; with ⇧ it adds the topic it reaches to the selection.
        case move(CanvasDirection, extending: Bool)
        /// Esc: back to the primary topic alone, or the end of a drag.
        case cancel
    }

    /// Acts on a key; false when the key is not the canvas's to take, so it
    /// goes on to the system. Nothing happens while a title is being edited.
    func handle(_ key: Key) -> Bool {
        guard editingID == nil else { return false }
        if case .cancel = key, drag != nil {
            drag = nil
            return true
        }
        guard drag == nil, marquee == nil else { return true }
        switch key {
        case .addSibling:
            session.addSibling()
        case .addChild:
            session.addChild()
        case .promote:
            // Tab keys are always taken, so focus does not jump out of the canvas.
            session.promoteSelection()
        case .rename:
            return beginEditingSelection()
        case .move(let direction, let extending):
            return moveSelection(direction, extending: extending)
        case .cancel:
            guard session.selectedIDs.count > 1 else { return false }
            session.selection = session.selection
        }
        return true
    }

    /// Arrow keys walk the map as drawn (see `CanvasScene.neighbour`).
    private func moveSelection(_ direction: CanvasDirection, extending: Bool) -> Bool {
        guard let current = session.selection, scene.topic(current) != nil else {
            guard let root = session.rootID, scene.topic(root) != nil else { return false }
            session.selection = root
            reveal(root)
            return true
        }
        // At the end of a row the key is still the canvas's; nothing to beep about.
        guard let next = scene.neighbour(of: current, toward: direction) else { return true }
        if extending {
            session.addToSelection(next.id)
        } else {
            session.selection = next.id
        }
        reveal(next.id)
        return true
    }

    // MARK: Drag and drop

    /// Dragged topics and where they would land if dropped now.
    struct TopicDrag: Equatable {
        /// The branches that move, in outline order.
        let ids: [NodeID]
        /// The topic under the pointer, drawn following it.
        let leadID: NodeID
        /// Pointer position minus the lead topic's centre, in view points.
        let grabOffset: CGSize
        /// The pointer, in view points.
        var location: CGPoint
        var drop: TopicDrop?
        /// The pointer is over one of the moving branches, where nothing can go.
        var isRefused = false
    }

    /// A drag starting on a topic moves the selection if the topic is in it,
    /// else the topic alone. The central topic does not move.
    func beginDrag(_ id: NodeID, at viewPoint: CGPoint) {
        guard drag == nil, id != session.rootID, let topic = scene.topic(id), !topic.isSuggestion else { return }
        commitEditing()
        if !session.isSelected(id) { session.selection = id }
        let ids = session.movableBranchRoots
        guard !ids.isEmpty else { return }
        let centre = viewport.toView(CGPoint(x: topic.frame.midX, y: topic.frame.midY))
        drag = TopicDrag(ids: ids, leadID: id, grabOffset: CGSize(width: viewPoint.x - centre.x, height: viewPoint.y - centre.y), location: viewPoint)
    }

    func updateDrag(to viewPoint: CGPoint) {
        guard var drag else { return }
        drag.location = viewPoint
        (drag.drop, drag.isRefused) = dropTarget(at: viewPoint, moving: drag.ids)
        // A floating topic moved a little is still over its own branch; that
        // is a move, not a drop into itself.
        if drag.isRefused, movesFreely(drag) { drag.isRefused = false }
        self.drag = drag
    }

    /// One floating topic dragged alone goes wherever it is dropped.
    private func movesFreely(_ drag: TopicDrag) -> Bool {
        drag.ids == [drag.leadID] && session.isFloating(drag.leadID)
    }

    /// Drops where the indicator shows. A refused drop moves nothing and plays
    /// feedback (FR-KBD-04). On empty canvas a floating topic moves there, and
    /// with `detaching` (⌥ on the Mac) a branch of the tree becomes floating
    /// there; otherwise a drop on empty canvas is cancelled, as before MM-62.
    func endDrag(detaching: Bool = false) {
        guard let drag else { return }
        self.drag = nil
        if let drop = drag.drop {
            session.move(drag.ids, to: drop)
        } else if !drag.isRefused, drag.ids == [drag.leadID], let position = dropPosition(of: drag) {
            if session.isFloating(drag.leadID) {
                session.moveFloatingTopic(drag.leadID, to: position)
            } else if detaching {
                session.detach(drag.leadID, to: position)
            }
        } else if drag.isRefused {
            refusedDrops += 1
            AccessibilityNotification.Announcement(String(localized: "A topic can’t move into its own branch.")).post()
        }
    }

    /// Where the dragged topic's centre is, as a stored position.
    private func dropPosition(of drag: TopicDrag) -> TopicPosition? {
        let centre = CGPoint(x: drag.location.x - drag.grabOffset.width, y: drag.location.y - drag.grabOffset.height)
        return position(at: viewport.toCanvas(centre))
    }

    /// The drop under a view point, or whether it is refused.
    func dropTarget(at viewPoint: CGPoint, moving ids: [NodeID]) -> (drop: TopicDrop?, refused: Bool) {
        let point = viewport.toCanvas(viewPoint)
        guard let (topic, zone) = scene.dropZone(at: point, slack: layoutOptions.verticalSpacing / 2, edgeFraction: CanvasMetrics.dropEdgeFraction) else {
            return (nil, false)
        }
        // Suggestions are drawn in the gaps but are not topics to drop on.
        guard !topic.isSuggestion else { return (nil, false) }
        let drop: TopicDrop = switch zone {
        case .before: .before(topic.id)
        case .after: .after(topic.id)
        case .inside: .child(of: topic.id)
        }
        return session.canMove(ids, to: drop) ? (drop, false) : (nil, true)
    }

    /// Where the drop indicator goes, in canvas points: the new parent's frame
    /// for `.child`, a bar in the gap before or after the anchor otherwise.
    func dropIndicator(for drop: TopicDrop) -> (frame: CGRect, isBar: Bool)? {
        guard let anchor = scene.topic(drop.anchor) else { return nil }
        let gap = layoutOptions.verticalSpacing / 2
        switch drop {
        case .child:
            return (anchor.frame, false)
        case .before:
            return (CGRect(x: anchor.frame.minX, y: anchor.frame.minY - gap, width: anchor.frame.width, height: 0), true)
        case .after:
            return (CGRect(x: anchor.frame.minX, y: anchor.frame.maxY + gap, width: anchor.frame.width, height: 0), true)
        }
    }

    // MARK: Context menu

    /// A context menu acts on the selection when it opens on a selected topic,
    /// else on that topic alone, as Finder does.
    func performFromContextMenu(on id: NodeID, _ action: (EditorSession) -> Void) {
        commitEditing()
        if !session.isSelected(id) { session.selection = id }
        action(session)
    }

    // MARK: Styles

    private struct StyleKey: Hashable {
        let level: Int
        let branch: Int
        let color: TopicColor?
        let variant: ColorVariant
    }

    /// Resolved once per level, branch and appearance rather than per topic per frame.
    func style(for topic: CanvasTopic, colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> TopicStyle {
        // Levels past 3 look like level 3.
        let key = StyleKey(
            level: min(topic.level, 3), branch: topic.branch, color: topic.color,
            variant: ColorVariant(colorScheme: colorScheme, contrast: contrast)
        )
        if let style = styles[key] { return style }
        let style = TopicStyle.resolve(
            level: key.level,
            branch: key.branch,
            color: key.color,
            theme: MapTheme(session.map.theme),
            colorScheme: colorScheme,
            contrast: contrast
        )
        styles[key] = style
        return style
    }

    func textSpec(for topic: CanvasTopic) -> TopicTextSpec? {
        specs?.spec(level: topic.level)
    }
}
