import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapSearch
import Observation
import OSLog

/// One open map: the graph engine, the selection, and the saving queue.
///
/// Views call intent methods here; this type turns them into graph commands.
/// It never edits the graph or the store directly.
@Observable
final class EditorSession {
    struct Row: Identifiable, Hashable {
        let node: MindNode
        let depth: Int
        let hasChildren: Bool
        var id: NodeID { node.id }
    }

    private(set) var engine: GraphEngine
    var selection: NodeID?
    /// A node whose title field should take focus, such as one just created.
    var focusRequest: NodeID?
    private(set) var saveFailed = false
    /// Where the window's keyboard focus is, as far as this editor knows.
    /// The canvas and the outline report it through `reportKeyboardFocus`.
    private(set) var keyboardFocus: KeyboardFocus = .elsewhere
    /// Canvas or outline; both show the same map and selection (FR-CNV-12).
    var presentation: EditorPresentation = .canvas {
        // The view that had focus is gone; the one that replaces it reports its own.
        didSet { if presentation != oldValue { keyboardFocus = .elsewhere } }
    }
    /// Whether the inspector shows beside the map.
    var isInspectorPresented = false

    /// Called with every change the map goes through (command, undo, redo),
    /// so the canvas lays out only what changed.
    @ObservationIgnored var onGraphChange: ((GraphChangeSet) -> Void)?

    /// Whether the find bar shows.
    private(set) var isFinding = false
    /// What the find field holds; matches follow it as it changes.
    var findText = "" {
        didSet { if findText != oldValue { updateFind(selectingFirst: true) } }
    }
    /// Topics matching `findText`, in reading order with every branch open.
    private(set) var findMatches: [NodeID] = []
    private(set) var findMatchSet: Set<NodeID> = []
    /// The match Find Next and Find Previous last went to.
    private(set) var currentMatch: NodeID?
    /// Asks the find field to take focus, as ⌘F does when the bar is already open.
    var findFocusRequest = false
    /// A topic the outline should scroll into view.
    var scrollRequest: NodeID?

    /// The window's undo manager, so the Edit menu, ⌘Z and the iOS undo gestures
    /// drive the engine's history. Set by the view.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private let repository: any MapRepository
    @ObservationIgnored private let onMapChange: (MindMap) -> Void
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    init(engine: GraphEngine, repository: any MapRepository, onMapChange: @escaping (MindMap) -> Void) {
        self.engine = engine
        self.repository = repository
        self.onMapChange = onMapChange
        self.selection = engine.state.map.rootNodeID
    }

    enum Opening {
        case ready(EditorSession)
        case missing
        case failed
    }

    /// Loads, repairs and opens a map. Repairs are saved straight away so they
    /// do not run again on the next open.
    static func open(
        mapID: MapID,
        repository: any MapRepository,
        onMapChange: @escaping (MindMap) -> Void
    ) async -> Opening {
        do {
            guard let stored = try await repository.loadGraph(for: mapID) else { return .missing }
            let repair = try GraphRepair.repair(stored, now: .now)
            let session = EditorSession(engine: try GraphEngine(state: repair.state), repository: repository, onMapChange: onMapChange)
            if !repair.changes.isEmpty {
                Log.graph.notice("Repaired \(repair.issues.count) structural issues on open")
                session.persist(repair.changes)
            }
            return .ready(session)
        } catch {
            Log.persistence.error("Opening a map failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    // MARK: Reading

    var map: MindMap { engine.state.map }
    var rootID: NodeID? { engine.state.map.rootNodeID }
    var canUndo: Bool { engine.canUndo }
    var canRedo: Bool { engine.canRedo }
    var canDeleteSelection: Bool { selection != nil && selection != rootID }
    var canRenameSelection: Bool { selection.flatMap { engine.state.node($0) } != nil }

    /// A bare Delete in the menu bar is matched before the focused view sees
    /// the key, so it is the Delete Topic shortcut only while the editor holds
    /// focus outside a text field: otherwise it would eat Delete in a title
    /// being typed, or delete a topic while the library list is focused.
    var deleteKeyDeletesTopic: Bool { keyboardFocus == .content && canDeleteSelection }

    /// The display name of the map, also the editor's window title.
    var displayTitle: String {
        map.title.isEmpty ? String(localized: "Untitled Map") : map.title
    }

    /// Takes a view's report of where focus is. The canvas and the outline
    /// swap with no set order of appearing and disappearing, so a late report
    /// from the one no longer shown is ignored.
    func reportKeyboardFocus(_ focus: KeyboardFocus, from source: EditorPresentation) {
        guard source == presentation else { return }
        keyboardFocus = focus
    }

    var canToggleSelection: Bool {
        guard let selection else { return false }
        return !engine.state.childIDs(of: selection).isEmpty
    }

    var selectionIsCollapsed: Bool {
        selection.flatMap { engine.state.node($0)?.isCollapsed } ?? false
    }

    /// The root has no siblings, so it cannot be copied next to itself.
    var canDuplicateSelection: Bool { selection != nil && selection != rootID }

    var canPromoteSelection: Bool {
        selection.map { PromoteNodeCommand.canPromote($0, in: engine.state) } ?? false
    }

    var canDemoteSelection: Bool {
        selection.map { DemoteNodeCommand.canDemote($0, in: engine.state) } ?? false
    }

    var canSplitSelection: Bool {
        guard let selection, selection != rootID, let node = engine.state.node(selection) else { return false }
        return SplitNodeCommand.lines(of: node.title).count > 1
    }

    var rows: [Row] {
        let state = engine.state
        return state.visibleOutline().compactMap { item in
            state.node(item.nodeID).map { Row(node: $0, depth: item.depth, hasChildren: item.hasChildren) }
        }
    }

    // MARK: Intents

    func addRoot() {
        let id = NodeID()
        if perform(AddNodeCommand(nodeID: id, .root, title: map.title), named: String(localized: "Add Topic")) {
            select(id, focus: true)
        }
    }

    func addChild() {
        guard let parent = selection ?? rootID else { return addRoot() }
        let id = NodeID()
        if perform(AddNodeCommand(nodeID: id, .child(of: parent), title: ""), named: String(localized: "Add Topic")) {
            select(id, focus: true)
        }
    }

    /// The root has no siblings, so on the root this adds a child instead.
    func addSibling() {
        guard let anchor = selection, anchor != rootID else { return addChild() }
        let id = NodeID()
        if perform(AddNodeCommand(nodeID: id, .sibling(after: anchor), title: ""), named: String(localized: "Add Topic")) {
            select(id, focus: true)
        }
    }

    func rename(_ id: NodeID, to title: String) {
        perform(UpdateNodeCommand(nodeID: id, .title(title)), named: String(localized: "Rename Topic"))
    }

    func toggleCollapsed(_ id: NodeID) {
        guard let node = engine.state.node(id) else { return }
        let name = node.isCollapsed ? String(localized: "Expand Topic") : String(localized: "Collapse Topic")
        perform(UpdateNodeCommand(nodeID: id, .isCollapsed(!node.isCollapsed)), named: name)
        // Collapsing an ancestor of the selection (the canvas badge, a VoiceOver
        // action) would leave Delete and Rename acting on a topic nobody sees.
        keepSelectionVisible()
    }

    func toggleSelectionCollapsed() {
        guard let selection, canToggleSelection else { return }
        toggleCollapsed(selection)
    }

    /// Deletes the selected branch; the root stays, the map itself is deleted from the library.
    func deleteSelection() {
        guard let id = selection, canDeleteSelection else { return }
        let next = neighbour(replacing: id)
        if perform(DeleteNodeCommand(nodeID: id), named: String(localized: "Delete Topic")) {
            selection = next
        }
    }

    /// Copies the selected branch right after it and selects the copy.
    func duplicateSelection() {
        guard let id = selection, canDuplicateSelection else { return }
        let copyID = NodeID()
        if perform(DuplicateBranchCommand(nodeID: id, copyID: copyID), named: String(localized: "Duplicate Topic")) {
            selection = copyID
        }
    }

    func promoteSelection() {
        guard let id = selection, canPromoteSelection else { return }
        perform(PromoteNodeCommand(nodeID: id), named: String(localized: "Promote Topic"))
    }

    func demoteSelection() {
        guard let id = selection, canDemoteSelection else { return }
        perform(DemoteNodeCommand(nodeID: id), named: String(localized: "Demote Topic"))
    }

    /// One topic per line of the selected title; the selection stays on the first line.
    func splitSelection() {
        guard let id = selection, canSplitSelection else { return }
        perform(SplitNodeCommand(nodeID: id), named: String(localized: "Split Topic"))
    }

    /// Merges sibling topics into the first one, which becomes the selection.
    /// Takes IDs because multi-selection arrives later (MM-5).
    func merge(_ ids: [NodeID]) {
        guard let survivor = ids.first, ids.count > 1 else { return }
        if perform(MergeNodesCommand(into: survivor, merging: Array(ids.dropFirst())), named: String(localized: "Merge Topics")) {
            selection = survivor
        }
    }

    @discardableResult
    func connect(_ source: NodeID, to target: NodeID, type: EdgeType = .relationship, label: String? = nil) -> EdgeID? {
        let id = EdgeID()
        let command = ConnectNodesCommand(edgeID: id, from: source, to: target, type: type, label: label)
        return perform(command, named: String(localized: "Add Link")) ? id : nil
    }

    func removeLink(_ id: EdgeID) {
        perform(RemoveEdgeCommand(edgeID: id), named: String(localized: "Remove Link"))
    }

    func collapseAll() {
        perform(SetAllCollapsedCommand.collapseAll, named: String(localized: "Collapse All"))
        keepSelectionVisible()
    }

    func expandAll() {
        perform(SetAllCollapsedCommand.expandAll, named: String(localized: "Expand All"))
    }

    func renameMap(to title: String) {
        perform(RenameMapCommand(title: title), named: String(localized: "Rename Map"))
    }

    /// Only branch colours change, so the layout and selection stay as they are (FR-THM-03).
    func changeTheme(to theme: MindMapTheme) {
        perform(ChangeThemeCommand(theme: theme), named: String(localized: "Change Theme"))
    }

    func undo() {
        if let undoManager, undoManager.canUndo {
            undoManager.undo()
        } else {
            stepBack(named: nil)
        }
    }

    func redo() {
        if let undoManager, undoManager.canRedo {
            undoManager.redo()
        } else {
            stepForward(named: nil)
        }
    }

    // MARK: Find

    var hasFindMatches: Bool { !findMatches.isEmpty }

    /// Position of the current match, from 1, for "2 of 5".
    var currentMatchNumber: Int? {
        currentMatch.flatMap { findMatches.firstIndex(of: $0) }.map { $0 + 1 }
    }

    func showFind() {
        isFinding = true
        findFocusRequest = true
    }

    func endFind() {
        isFinding = false
        findText = ""
    }

    func findNext() {
        stepThroughMatches(forward: true)
    }

    func findPrevious() {
        stepThroughMatches(forward: false)
    }

    private func stepThroughMatches(forward: Bool) {
        guard !findMatches.isEmpty else { return }
        let count = findMatches.count
        // Step from the selected match if there is one, so clicking a match and
        // pressing ⌘G continues from there.
        let anchor = selection.flatMap { findMatches.firstIndex(of: $0) }
            ?? currentMatch.flatMap { findMatches.firstIndex(of: $0) }
        let index = anchor.map { (forward ? $0 + 1 : $0 - 1 + count) % count } ?? (forward ? 0 : count - 1)
        showMatch(findMatches[index])
    }

    /// Selects a match and scrolls to it. A match inside a collapsed branch is
    /// revealed first, which changes the map and so is an undo step: the
    /// branch stays open after Find closes, as the person last saw it.
    private func showMatch(_ id: NodeID) {
        if RevealNodeCommand.isHidden(id, in: engine.state) {
            perform(RevealNodeCommand(nodeID: id), named: String(localized: "Reveal Topic"))
        }
        currentMatch = id
        selection = id
        scrollRequest = id
    }

    /// Typing in the find field selects the first visible match but opens no
    /// branch: each keystroke would otherwise leave an undo step behind.
    private func updateFind(selectingFirst: Bool) {
        findMatches = MapFind.matches(SearchQuery(findText), in: engine.state)
        findMatchSet = Set(findMatches)
        if let currentMatch, !findMatchSet.contains(currentMatch) {
            self.currentMatch = nil
        }
        guard selectingFirst else { return }
        currentMatch = nil
        if let first = findMatches.first(where: { !RevealNodeCommand.isHidden($0, in: engine.state) }) {
            currentMatch = first
            selection = first
            scrollRequest = first
        }
    }

    // MARK: Engine and history

    /// Runs a command as one named undo step. Intents above use it; so does
    /// `AIAssistant` for accepted suggestions, which are commands like any other.
    @discardableResult
    func perform(_ command: any GraphCommand, named name: String) -> Bool {
        do {
            let changes = try engine.execute(command)
            guard !changes.isEmpty else { return true }
            persist(changes)
            registerUndo(named: name)
            return true
        } catch {
            // The graph is unchanged; this is a programming error worth seeing in logs, not a user-facing one.
            Log.graph.error("Command \(String(describing: type(of: command)), privacy: .public) refused: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private func registerUndo(named name: String?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.stepBack(named: name) }
        }
        if let name { undoManager.setActionName(name) }
    }

    private func stepBack(named name: String?) {
        guard let changes = engine.undo() else { return }
        persist(changes)
        // Registering while the undo manager is undoing puts this on its redo stack.
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { session in
                MainActor.assumeIsolated { session.stepForward(named: name) }
            }
            if let name { undoManager.setActionName(name) }
        }
        keepSelectionValid()
    }

    private func stepForward(named name: String?) {
        guard let changes = engine.redo() else { return }
        persist(changes)
        registerUndo(named: name)
        keepSelectionValid()
    }

    /// Waits until every change made so far is saved, for example before the app quits.
    func flush() async {
        await lastSave?.value
    }

    /// Saves run one after another, in the order the changes happened.
    private func persist(_ changes: GraphChangeSet) {
        guard !changes.isEmpty else { return }
        let map = engine.state.map
        onMapChange(map)
        onGraphChange?(changes)
        if !findText.isEmpty { updateFind(selectingFirst: false) }
        let previous = lastSave
        lastSave = Task { [repository, weak self] in
            await previous?.value
            do {
                try await repository.save(changes, map: map)
            } catch {
                Log.persistence.error("Saving changes failed: \(error.localizedDescription, privacy: .public)")
                self?.saveFailed = true
            }
        }
    }

    // MARK: Selection

    private func select(_ id: NodeID, focus: Bool) {
        selection = id
        if focus { focusRequest = id }
    }

    private func keepSelectionValid() {
        if let selection, engine.state.node(selection) != nil { return }
        selection = rootID
    }

    /// After collapsing, a selected topic inside a closed branch would be
    /// invisible; select its nearest visible ancestor instead.
    private func keepSelectionVisible() {
        guard let selection else { return }
        let state = engine.state
        let ancestors = state.ancestors(of: selection)
        if let outermostClosed = ancestors.lastIndex(where: { state.node($0)?.isCollapsed == true }) {
            self.selection = ancestors[outermostClosed]
        }
    }

    /// Where the selection goes after `id` is deleted: the previous sibling,
    /// else the next one, else the parent.
    private func neighbour(replacing id: NodeID) -> NodeID? {
        let state = engine.state
        guard let parentID = state.node(id)?.parentID else { return nil }
        let siblings = state.childIDs(of: parentID)
        guard let index = siblings.firstIndex(of: id) else { return parentID }
        if index > 0 { return siblings[index - 1] }
        if index + 1 < siblings.count { return siblings[index + 1] }
        return parentID
    }
}

enum EditorPresentation: String, CaseIterable, Identifiable {
    case canvas
    case outline

    var id: Self { self }
}

extension EditorSession {
    enum KeyboardFocus {
        /// Focus is outside the editor, such as in the sidebar or the library.
        case elsewhere
        /// The editor's content has focus and no text is being edited.
        case content
        /// A topic title or another text field in the editor is being edited.
        case editingText
    }
}
