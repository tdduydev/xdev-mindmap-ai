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
    var selection: NodeID?
    /// A node whose title field should take focus, such as one just created.
    var focusRequest: NodeID?
    private(set) var saveFailed = false

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
    }

    /// Deletes the selected branch; the root stays, the map itself is deleted from the library.
    func deleteSelection() {
        guard let id = selection, canDeleteSelection else { return }
        let next = neighbour(replacing: id)
        if perform(DeleteNodeCommand(nodeID: id), named: String(localized: "Delete Topic")) {
            selection = next
        }
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
