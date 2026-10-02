import Foundation
import MindMapDomain

/// Tag records the library changed outside every map's undo history: a shared
/// tag renamed, recoloured, merged or deleted, or a tag moved between a map
/// and the library. The repository stores it; each open map applies the part
/// it holds with `GraphEngine.apply(_:)`.
public struct LibraryTagChange: Hashable, Sendable {
    /// Tags as stored after the change. A tag whose `mapID` is now another
    /// map's leaves the maps that are not that map.
    public var savedTags: [MindTag]
    public var deletedTagIDs: [TagID]
    /// Links as stored after the change, of any map; a map takes its own.
    public var savedNodeTags: [MindNodeTag]
    public var deletedNodeTagIDs: [NodeTagID]

    public init(
        savedTags: [MindTag] = [],
        deletedTagIDs: [TagID] = [],
        savedNodeTags: [MindNodeTag] = [],
        deletedNodeTagIDs: [NodeTagID] = []
    ) {
        self.savedTags = savedTags
        self.deletedTagIDs = deletedTagIDs
        self.savedNodeTags = savedNodeTags
        self.deletedNodeTagIDs = deletedNodeTagIDs
    }

    public var isEmpty: Bool {
        savedTags.isEmpty && deletedTagIDs.isEmpty && savedNodeTags.isEmpty && deletedNodeTagIDs.isEmpty
    }
}

extension GraphEngine {
    /// What applying a library change did to one map.
    public struct LibraryChangeResult: Sendable {
        /// For the canvas and outline; already stored, so not to be saved again.
        public let changes: GraphChangeSet
        /// True when the map's history was cleared, so the window's undo
        /// manager must drop its steps too.
        public let clearedHistory: Bool
    }

    /// Takes in a change the library made, without recording an undo step.
    ///
    /// A rename or recolour of a shared tag leaves history alone: no step can
    /// hold a shared tag's record, since map commands refuse them. Anything
    /// else that touches this map (links moved or deleted, a tag deleted, a tag
    /// moved between map and library) clears history. Undoing across it would
    /// replay records the library has replaced, for example delete a tag that
    /// is shared now (graph-engine.md, *Undo and redo*).
    public mutating func apply(_ library: LibraryTagChange) -> LibraryChangeResult {
        let mapID = state.map.id
        var changes = GraphChangeSet()
        var touchesHistory = false

        for tag in library.savedTags {
            let before = state.tag(tag.id)
            if tag.mapID == nil || tag.mapID == mapID {
                guard before != tag else { continue }
                if before?.mapID != tag.mapID { touchesHistory = true }
                state.upsertTag(tag)
                changes.recordTag(tag.id, before: before, after: tag)
            } else if let before {
                state.removeTag(tag.id)
                changes.recordTag(tag.id, before: before, after: nil)
                touchesHistory = true
            }
        }
        for id in library.deletedTagIDs {
            guard let before = state.removeTag(id) else { continue }
            changes.recordTag(id, before: before, after: nil)
            touchesHistory = true
        }
        for link in library.savedNodeTags where link.mapID == mapID {
            let before = state.nodeTags[link.id]
            guard before != link else { continue }
            state.upsertNodeTag(link)
            changes.recordNodeTag(link.id, before: before, after: link)
            touchesHistory = true
        }
        for id in library.deletedNodeTagIDs {
            guard let before = state.removeNodeTag(id) else { continue }
            changes.recordNodeTag(id, before: before, after: nil)
            touchesHistory = true
        }

        if touchesHistory { history.clear() }
        return LibraryChangeResult(changes: changes, clearedHistory: touchesHistory)
    }
}
