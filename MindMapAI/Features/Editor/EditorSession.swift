import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
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
    /// The topic that single-topic actions (rename, add, promote) act on, and
    /// the anchor of a multi-selection. Setting it selects that topic alone.
    var selection: NodeID? {
        get { primarySelection }
        set { setSelection(newValue.map { [$0] } ?? [], primary: newValue) }
    }
    private(set) var primarySelection: NodeID?
    /// Every selected topic, the primary one included (FR-CNV-03). Delete,
    /// duplicate, copy, cut and move act on all of them as one undo step.
    private(set) var selectedIDs: Set<NodeID> = []
    /// A node whose title field should take focus, such as one just created.
    var focusRequest: NodeID?
    private(set) var saveFailed = false
    /// Canvas or outline; both show the same map and selection (FR-CNV-12).
    var presentation: EditorPresentation = .canvas

    /// Called with every change the map goes through (command, undo, redo),
    /// so the canvas lays out only what changed.
    @ObservationIgnored var onGraphChange: ((GraphChangeSet) -> Void)?

    /// The window's undo manager, so the Edit menu, ⌘Z and the iOS undo gestures
    /// drive the engine's history. Set by the view.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private let repository: any MapRepository
    @ObservationIgnored let clipboard: any TextClipboard
    @ObservationIgnored private let onMapChange: (MindMap) -> Void
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    init(
        engine: GraphEngine,
        repository: any MapRepository,
        clipboard: any TextClipboard = SystemClipboard(),
        onMapChange: @escaping (MindMap) -> Void
    ) {
        self.engine = engine
        self.repository = repository
        self.clipboard = clipboard
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
        clipboard: any TextClipboard = SystemClipboard(),
        onMapChange: @escaping (MindMap) -> Void
    ) async -> Opening {
        do {
            guard let stored = try await repository.loadGraph(for: mapID) else { return .missing }
            let repair = try GraphRepair.repair(stored, now: .now)
            let session = EditorSession(
                engine: try GraphEngine(state: repair.state),
                repository: repository,
                clipboard: clipboard,
                onMapChange: onMapChange
            )
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
    var canDeleteSelection: Bool { !movableBranchRoots.isEmpty }
    var canRenameSelection: Bool { selection.flatMap { engine.state.node($0) } != nil }

    var canToggleSelection: Bool {
        guard let selection else { return false }
        return !engine.state.childIDs(of: selection).isEmpty
    }

    var selectionIsCollapsed: Bool {
        selection.flatMap { engine.state.node($0)?.isCollapsed } ?? false
    }

    /// The root has no siblings, so it cannot be copied next to itself.
    var canDuplicateSelection: Bool { !movableBranchRoots.isEmpty }

    var canCopySelection: Bool { !selectedBranchRoots.isEmpty }
    /// Cut deletes, so it follows Delete: the central topic stays.
    var canCutSelection: Bool { canDeleteSelection }
    var canPaste: Bool { (selection ?? rootID) != nil && clipboard.hasText }

    func isSelected(_ id: NodeID) -> Bool { selectedIDs.contains(id) }

    /// The selected topics that are not inside another selected branch, in
    /// outline order: what a branch action copies, moves or deletes.
    var selectedBranchRoots: [NodeID] {
        branchRoots(of: selectedIDs)
    }

    /// The same without the central topic, which cannot move or go: with it
    /// selected, the other selected branches still move, duplicate or delete.
    var movableBranchRoots: [NodeID] {
        var ids = selectedIDs
        if let rootID { ids.remove(rootID) }
        return branchRoots(of: ids)
    }

    private func branchRoots(of ids: Set<NodeID>) -> [NodeID] {
        let state = engine.state
        return inOutlineOrder(ids).filter { id in
            !state.ancestors(of: id).contains(where: ids.contains)
        }
    }

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

    /// Deletes the selected branches as one undo step (FR-EDT-04); the root
    /// stays, the map itself is deleted from the library.
    func deleteSelection() {
        deleteSelection(named: nil)
    }

    private func deleteSelection(named name: String?) {
        let targets = movableBranchRoots
        guard let first = targets.first else { return }
        let fallbacks = [neighbour(replacing: first)].compactMap { $0 } + engine.state.ancestors(of: first)
        let name = name ?? (targets.count == 1 ? String(localized: "Delete Topic") : String(localized: "Delete Topics"))
        if perform(DeleteNodeCommand(nodeIDs: targets), named: name) {
            selection = fallbacks.first { engine.state.node($0) != nil } ?? rootID
        }
    }

    /// Copies each selected branch right after itself and selects the copies,
    /// as one undo step.
    func duplicateSelection() {
        let originals = movableBranchRoots
        guard !originals.isEmpty else { return }
        let copies = originals.map { (original: $0, copy: NodeID()) }
        let command = BatchCommand(copies.map { DuplicateBranchCommand(nodeID: $0.original, copyID: $0.copy) })
        let name = originals.count == 1 ? String(localized: "Duplicate Topic") : String(localized: "Duplicate Topics")
        if perform(command, named: name) {
            let primary = copies.first { $0.original == primarySelection }?.copy ?? copies[0].copy
            setSelection(Set(copies.map(\.copy)), primary: primary)
        }
    }

    // MARK: Moving

    /// Whether `ids` can go to `drop`: never the central topic, and never into
    /// or next to a topic inside one of the moving branches (FR-EDT-11).
    func canMove(_ ids: [NodeID], to drop: TopicDrop) -> Bool {
        let state = engine.state
        guard !ids.isEmpty, let anchor = state.node(drop.anchor) else { return false }
        if case .child = drop {} else if anchor.parentID == nil { return false }
        return ids.allSatisfy { id in
            state.node(id) != nil && id != rootID && id != anchor.id && !state.isAncestor(id, of: anchor.id)
        }
    }

    /// Moves the branches of `ids` to `drop`, in outline order, as one undo
    /// step. A drop that leaves every topic where it was is not an undo step.
    func move(_ ids: [NodeID], to drop: TopicDrop) {
        guard canMove(ids, to: drop) else { return }
        let state = engine.state
        let branches = branchRoots(of: Set(ids))
        guard let parentID = drop.parentID(in: state) else { return }

        var commands: [any GraphCommand] = []
        if case .child = drop, state.node(parentID)?.isCollapsed == true {
            // Topics dropped into a closed branch would vanish from view.
            commands.append(UpdateNodeCommand(nodeID: parentID, .isCollapsed(false)))
        }
        var previous: NodeID?
        for id in branches {
            let placement: ChildPlacement = switch (previous, drop) {
            case (let previous?, _): .after(previous)
            case (nil, .child): .last
            case (nil, .before(let anchor)): .before(anchor)
            case (nil, .after(let anchor)): .after(anchor)
            }
            commands.append(ReparentNodeCommand(nodeID: id, newParentID: parentID, placement: placement))
            previous = id
        }
        let command = BatchCommand(commands)
        guard changesTree(command, moving: branches) else { return }
        let name = branches.count == 1 ? String(localized: "Move Topic") : String(localized: "Move Topics")
        perform(command, named: name)
    }

    /// Runs the command on a copy and compares parents and sibling order, so
    /// dropping a topic where it already is costs no undo step.
    private func changesTree(_ command: any GraphCommand, moving ids: [NodeID]) -> Bool {
        var probe = engine
        guard (try? probe.execute(command)) != nil else { return false }
        let before = engine.state
        let after = probe.state
        return ids.contains { id in
            let oldParent = before.node(id)?.parentID
            let newParent = after.node(id)?.parentID
            guard oldParent == newParent, let parent = newParent else { return true }
            return before.childIDs(of: parent) != after.childIDs(of: parent)
        } || after.nodes.values.contains { before.node($0.id)?.isCollapsed != $0.isCollapsed }
    }

    // MARK: Clipboard

    /// The selected branches as a Markdown list (FR-EDT-14).
    var selectionMarkdown: String? {
        let branches = selectedBranchRoots
        return branches.isEmpty ? nil : BranchText.markdown(for: branches, in: engine.state)
    }

    func copySelection() {
        if let text = selectionMarkdown { clipboard.setText(text) }
    }

    func cutSelection() {
        if let text = cutSelectionReturningText() { clipboard.setText(text) }
    }

    /// Deletes the selected branches and returns them as Markdown, for a
    /// caller that writes the clipboard itself (the Mac's Cut command). The
    /// central topic is neither copied nor deleted.
    func cutSelectionReturningText() -> String? {
        let branches = movableBranchRoots
        guard !branches.isEmpty else { return nil }
        let text = BranchText.markdown(for: branches, in: engine.state)
        deleteSelection(named: branches.count == 1 ? String(localized: "Cut Topic") : String(localized: "Cut Topics"))
        return text
    }

    func paste() {
        guard let text = clipboard.text else { return }
        paste(text)
    }

    /// Text on the clipboard becomes children of the selected topic, nested by
    /// indentation, as one undo step; the new top-level topics are selected.
    func paste(_ text: String) {
        guard let parent = selection ?? rootID, engine.state.node(parent) != nil else { return }
        let items = BranchText.outline(from: text)
        guard !items.isEmpty else { return }

        var commands: [AddNodeCommand] = []
        var openParents: [NodeID] = []
        var topLevel: [NodeID] = []
        for item in items {
            let id = NodeID()
            // Depths are clamped, so the parent of an item is always open.
            openParents.removeSubrange(min(item.depth, openParents.count)...)
            let parentID = openParents.last ?? parent
            commands.append(AddNodeCommand(nodeID: id, .child(of: parentID), title: item.title, note: item.note))
            openParents.append(id)
            if item.depth == 0 { topLevel.append(id) }
        }
        let name = items.count == 1 ? String(localized: "Paste Topic") : String(localized: "Paste Topics")
        if perform(BatchCommand(commands), named: name) {
            setSelection(Set(topLevel), primary: topLevel.first)
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

    // MARK: Engine and history

    @discardableResult
    private func perform(_ command: any GraphCommand, named name: String) -> Bool {
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

    /// Selects `ids`; `primary` is the one single-topic actions use, and is
    /// added if missing. Without one, the first selected topic in outline order.
    func setSelection(_ ids: Set<NodeID>, primary: NodeID?) {
        var ids = ids
        if let primary { ids.insert(primary) }
        selectedIDs = ids
        primarySelection = primary ?? inOutlineOrder(ids).first
    }

    /// ⌘-click: adds a topic to the selection, or takes it out.
    func toggleSelected(_ id: NodeID) {
        guard engine.state.node(id) != nil else { return }
        guard selectedIDs.contains(id) else { return setSelection(selectedIDs, primary: id) }
        var remaining = selectedIDs
        remaining.remove(id)
        setSelection(remaining, primary: primarySelection == id ? nil : primarySelection)
    }

    /// ⇧-click and ⇧-arrow: adds a topic and makes it the primary one.
    func addToSelection(_ id: NodeID) {
        guard engine.state.node(id) != nil else { return }
        setSelection(selectedIDs, primary: id)
    }

    /// ⌘A: every topic in view; topics inside collapsed branches go with them anyway.
    func selectAll() {
        let visible = engine.state.visibleOutline().map(\.nodeID)
        guard !visible.isEmpty else { return }
        let primary = primarySelection.flatMap { visible.contains($0) ? $0 : nil } ?? rootID
        setSelection(Set(visible), primary: primary)
    }

    private func select(_ id: NodeID, focus: Bool) {
        selection = id
        if focus { focusRequest = id }
    }

    /// Undo and redo can remove selected topics; keep the ones still there.
    private func keepSelectionValid() {
        let state = engine.state
        let remaining = selectedIDs.filter { state.node($0) != nil }
        guard remaining != selectedIDs || primarySelection.map({ state.node($0) == nil }) == true else { return }
        if remaining.isEmpty {
            selection = rootID
        } else {
            setSelection(remaining, primary: primarySelection.flatMap { state.node($0) == nil ? nil : $0 })
        }
    }

    /// After collapsing, a selected topic inside a closed branch would be
    /// invisible; select its nearest visible ancestor instead.
    private func keepSelectionVisible() {
        let state = engine.state
        func visible(_ id: NodeID) -> NodeID {
            let ancestors = state.ancestors(of: id)
            guard let outermostClosed = ancestors.lastIndex(where: { state.node($0)?.isCollapsed == true }) else { return id }
            return ancestors[outermostClosed]
        }
        let ids = Set(selectedIDs.map(visible))
        let primary = primarySelection.map(visible)
        if ids != selectedIDs || primary != primarySelection { setSelection(ids, primary: primary) }
    }

    /// Topics in outline (pre-order) order, hidden ones included.
    private func inOutlineOrder(_ ids: Set<NodeID>) -> [NodeID] {
        guard ids.count > 1 else { return Array(ids) }
        guard let rootID else { return ids.sorted() }
        let state = engine.state
        var result: [NodeID] = []
        var stack = [rootID]
        while let id = stack.popLast(), result.count < ids.count {
            if ids.contains(id) { result.append(id) }
            stack.append(contentsOf: state.childIDs(of: id).reversed())
        }
        return result
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

/// Where dragged topics go (FR-KBD-04).
enum TopicDrop: Hashable {
    /// The last children of a topic.
    case child(of: NodeID)
    /// Siblings just before or after a topic.
    case before(NodeID)
    case after(NodeID)

    /// The topic the drop indicator is drawn on.
    var anchor: NodeID {
        switch self {
        case .child(let id), .before(let id), .after(let id): id
        }
    }

    func parentID(in state: GraphState) -> NodeID? {
        switch self {
        case .child(let id): id
        case .before(let id), .after(let id): state.node(id)?.parentID
        }
    }
}

enum EditorPresentation: String, CaseIterable, Identifiable {
    case canvas
    case outline

    var id: Self { self }
}
