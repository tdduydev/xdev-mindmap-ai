import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import OSLog

/// Changes to the open map from outside this app's repository: another device
/// through iCloud, the Share Extension, an intent in another process
/// (cloudkit-sync.md, FR-SYN-04).
extension EditorSession {
    /// Follows the store for as long as the editor is on screen: library tag
    /// changes from other windows, and writes from outside. A tag change this
    /// window made arrives here too and changes nothing the second time.
    func observeStore() async {
        for await change in await repository.changes() {
            switch change {
            case .tagsChanged(let tags):
                applyLibraryChange(tags)
            case .storeChanged:
                await takeStoredChanges()
            case .saved, .deleted:
                // This repository's own writes: this editor's, or the library's.
                continue
            }
        }
    }

    /// Loads the map as stored and takes in what changed. Pending saves go
    /// first, so the difference is only what came from outside. A notice that
    /// comes in while one is being taken in runs once more afterwards, so a
    /// burst of iCloud imports loads the map twice, not once per import.
    func takeStoredChanges() async {
        guard !isTakingStoredChanges else {
            takesStoredChangesAgain = true
            return
        }
        isTakingStoredChanges = true
        defer { isTakingStoredChanges = false }
        repeat {
            takesStoredChangesAgain = false
            await flush()
            let generation = editGeneration
            let stored: GraphState?
            do {
                stored = try await repository.loadGraph(for: map.id)
            } catch {
                Log.persistence.error("Loading a changed map failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            // An edit while loading may not be in what was loaded; load again after its save.
            guard generation == editGeneration else {
                takesStoredChangesAgain = true
                continue
            }
            guard let stored else {
                removedElsewhere = .deleted
                return
            }
            guard stored.map.deletedAt == nil else {
                removedElsewhere = .recentlyDeleted
                return
            }
            do {
                let result = try takeStored(stored)
                if result.historyChanged { rebuildUndoActions() }
                if result.droppedSteps > 0 {
                    Log.graph.notice("A change from outside dropped \(result.droppedSteps) undo steps")
                }
            } catch {
                Log.graph.error("Taking in a changed map failed: \(String(describing: error), privacy: .private)")
            }
        } while takesStoredChangesAgain
    }

    /// The engine dropped undo steps; `UndoManager` cannot drop single
    /// actions, so this window's are registered again from the steps left,
    /// one group each, with their names. Redo is gone in both.
    func rebuildUndoActions() {
        guard let undoManager else { return }
        undoManager.removeAllActions(withTarget: self)
        let names = engine.undoStepNames
        guard !names.isEmpty else { return }
        // Inside an open group (an event that already registered an action)
        // the steps would merge into that one; better none than a wrong one.
        guard undoManager.groupingLevel == 0, !undoManager.isUndoing, !undoManager.isRedoing else {
            clearHistory()
            return
        }
        let groupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        for name in names {
            undoManager.beginUndoGrouping()
            registerUndo(named: name)
            undoManager.endUndoGrouping()
        }
        undoManager.groupsByEvent = groupsByEvent
    }
}
