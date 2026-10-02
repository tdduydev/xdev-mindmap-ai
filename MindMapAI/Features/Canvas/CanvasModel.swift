import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapLayout
import Observation
import SwiftUI

/// The canvas of one open map: the laid-out scene, the camera, and inline
/// editing. Edits still go through `EditorSession` as commands; this type only
/// turns gestures into session intents and keeps the layout in step with the graph.
@Observable
final class CanvasModel {
    enum InitialPlacement {
        /// Actual size with the central topic in the middle (Mac, iPad).
        case centralTopic
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
    private(set) var viewport = CanvasViewport()
    /// The topic whose title is being edited in place.
    private(set) var editingID: NodeID? {
        didSet { reportKeyboardFocus() }
    }
    /// Whether the canvas itself holds keyboard focus. Set by the view.
    var hasKeyboardFocus = false {
        didSet { reportKeyboardFocus() }
    }
    /// The title as typed so far; committed as one Rename Topic command.
    var editingDraft = ""
    /// True while a drag pans the canvas, for the closed-hand pointer.
    private(set) var isPanning = false

    @ObservationIgnored var initialPlacement = InitialPlacement.centralTopic
    @ObservationIgnored private var needsInitialPlacement = true
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
    @ObservationIgnored private var isLayingOut = false
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    /// A topic to scroll into view (and maybe edit) once the layout has it.
    @ObservationIgnored private var pendingReveal: (id: NodeID, edit: Bool)?
    @ObservationIgnored private var styles: [StyleKey: TopicStyle] = [:]
    @ObservationIgnored let layoutOptions = LayoutOptions(
        horizontalSpacing: CanvasMetrics.layoutParentGap,
        verticalSpacing: CanvasMetrics.layoutSiblingGap
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
            if let suggestions = assistant?.suggestions, !suggestions.isEmpty {
                graph = suggestions.preview(in: session.engine)
                suggested = Set(suggestions.drawableTopics(in: graph).keys)
            }
            let startOver = needsFullLayout || lastPassHadSuggestions || !suggested.isEmpty
            let pass = CanvasLayoutPass(
                graph: graph,
                previous: startOver ? nil : scene.layout,
                measures: measures,
                changed: pendingChanges,
                specs: specs,
                options: layoutOptions,
                suggestions: suggested
            )
            pendingChanges = []
            needsFullLayout = false
            lastPassHadSuggestions = !suggested.isEmpty
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
        if viewport.size == .zero {
            viewport.size = size
        } else {
            viewport.resize(to: size)
        }
        placeInitiallyIfNeeded()
    }

    /// FR-CNV-01: the first time the map shows, the central topic is in the middle.
    private func placeInitiallyIfNeeded() {
        guard needsInitialPlacement, viewport.size.width > 0, viewport.size.height > 0,
              let root = session.rootID.flatMap(scene.topic) else { return }
        needsInitialPlacement = false
        switch initialPlacement {
        case .centralTopic:
            viewport.scale = 1
            viewport.center(on: CGPoint(x: root.frame.midX, y: root.frame.midY))
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
        viewport.reveal(topic.frame, margin: CanvasMetrics.revealMargin)
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
        } else {
            commitEditing()
            session.selection = nil
            assistant?.selectedSuggestion = nil
        }
    }

    func doubleTap(at viewPoint: CGPoint) {
        if let topic = topic(at: viewPoint) { beginEditing(topic.id) }
    }

    /// The topic drawn under a view point; the last drawn wins, as on screen.
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

    /// Return on the canvas, or the Rename Topic menu item.
    @discardableResult
    func beginEditingSelection() -> Bool {
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

    func delete(_ id: NodeID) {
        select(id)
        session.deleteSelection()
    }

    // MARK: Styles

    private struct StyleKey: Hashable {
        let level: Int
        let branch: Int
        let variant: ColorVariant
    }

    /// Resolved once per level, branch and appearance rather than per topic per frame.
    func style(for topic: CanvasTopic, colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> TopicStyle {
        // Levels past 3 look like level 3.
        let key = StyleKey(level: min(topic.level, 3), branch: topic.branch, variant: ColorVariant(colorScheme: colorScheme, contrast: contrast))
        if let style = styles[key] { return style }
        let style = TopicStyle.resolve(
            level: key.level,
            branch: key.branch,
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
