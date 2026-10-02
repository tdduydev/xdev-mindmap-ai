import Foundation
import MindMapDomain

/// One stored record of a map, whatever its kind, so change sets can be
/// compared for the records they touch.
public enum GraphRecordKey: Hashable, Sendable {
    case map
    case node(NodeID)
    case edge(EdgeID)
    case tag(TagID)
    case nodeTag(NodeTagID)
    case group(GroupID)
    case image(ImageID)
}

extension GraphChangeSet {
    /// Every record that differs between two states of one map, as a change
    /// from `old` to `new`.
    public static func difference(from old: GraphState, to new: GraphState) -> GraphChangeSet {
        var changes = GraphChangeSet()
        for id in Set(old.nodes.keys).union(new.nodes.keys) where old.nodes[id] != new.nodes[id] {
            changes.recordNode(id, before: old.nodes[id], after: new.nodes[id])
        }
        for id in Set(old.edges.keys).union(new.edges.keys) where old.edges[id] != new.edges[id] {
            changes.recordEdge(id, before: old.edges[id], after: new.edges[id])
        }
        for id in Set(old.tags.keys).union(new.tags.keys) where old.tags[id] != new.tags[id] {
            changes.recordTag(id, before: old.tags[id], after: new.tags[id])
        }
        for id in Set(old.nodeTags.keys).union(new.nodeTags.keys) where old.nodeTags[id] != new.nodeTags[id] {
            changes.recordNodeTag(id, before: old.nodeTags[id], after: new.nodeTags[id])
        }
        for id in Set(old.groups.keys).union(new.groups.keys) where old.groups[id] != new.groups[id] {
            changes.recordGroup(id, before: old.groups[id], after: new.groups[id])
        }
        for id in Set(old.images.keys).union(new.images.keys) where old.images[id] != new.images[id] {
            changes.recordImage(id, before: old.images[id], after: new.images[id])
        }
        if old.map != new.map {
            changes.recordMap(before: old.map, after: new.map)
        }
        return changes
    }

    /// The records this change writes. The map counts only when a field the
    /// graph owns changed: every edit moves `updatedAt`, and the favorite flag
    /// and Recently Deleted are library data no step records.
    public var writtenRecords: Set<GraphRecordKey> {
        var keys = Set<GraphRecordKey>()
        keys.formUnion(nodes.keys.map(GraphRecordKey.node))
        keys.formUnion(edges.keys.map(GraphRecordKey.edge))
        keys.formUnion(tags.keys.map(GraphRecordKey.tag))
        keys.formUnion(nodeTags.keys.map(GraphRecordKey.nodeTag))
        keys.formUnion(groups.keys.map(GraphRecordKey.group))
        keys.formUnion(images.keys.map(GraphRecordKey.image))
        if let map, map.before?.graphFields != map.after?.graphFields { keys.insert(.map) }
        return keys
    }

    /// The records this change deletes.
    var removedRecords: Set<GraphRecordKey> {
        var keys = Set<GraphRecordKey>()
        keys.formUnion(nodes.filter { $0.value.after == nil }.keys.map(GraphRecordKey.node))
        keys.formUnion(edges.filter { $0.value.after == nil }.keys.map(GraphRecordKey.edge))
        keys.formUnion(tags.filter { $0.value.after == nil }.keys.map(GraphRecordKey.tag))
        keys.formUnion(nodeTags.filter { $0.value.after == nil }.keys.map(GraphRecordKey.nodeTag))
        keys.formUnion(groups.filter { $0.value.after == nil }.keys.map(GraphRecordKey.group))
        keys.formUnion(images.filter { $0.value.after == nil }.keys.map(GraphRecordKey.image))
        return keys
    }

    /// The records this change writes plus those its values point at (parent,
    /// link ends, tagged topic and tag, group ends and summary topic, an
    /// image's topic). Replaying it is only
    /// safe while those still are as they were.
    var referencedRecords: Set<GraphRecordKey> {
        var keys = writtenRecords
        for change in nodes.values {
            for node in [change.before, change.after].compactMap(\.self) {
                if let parentID = node.parentID { keys.insert(.node(parentID)) }
            }
        }
        for change in edges.values {
            for edge in [change.before, change.after].compactMap(\.self) {
                keys.insert(.node(edge.sourceNodeID))
                keys.insert(.node(edge.targetNodeID))
            }
        }
        for change in nodeTags.values {
            for link in [change.before, change.after].compactMap(\.self) {
                keys.insert(.node(link.nodeID))
                keys.insert(.tag(link.tagID))
            }
        }
        for change in groups.values {
            for group in [change.before, change.after].compactMap(\.self) {
                for id in [group.parentNodeID, group.firstNodeID, group.lastNodeID, group.summaryNodeID].compactMap(\.self) {
                    keys.insert(.node(id))
                }
            }
        }
        for change in images.values {
            for image in [change.before, change.after].compactMap(\.self) {
                keys.insert(.node(image.nodeID))
            }
        }
        return keys
    }
}

private extension MindMap {
    struct GraphFields: Equatable {
        let title: String
        let rootNodeID: NodeID?
        let theme: MindMapTheme
        let layoutConfiguration: LayoutConfiguration
    }

    var graphFields: GraphFields {
        GraphFields(title: title, rootNodeID: rootNodeID, theme: theme, layoutConfiguration: layoutConfiguration)
    }
}

extension GraphEngine {
    /// What taking in the stored map did.
    public struct StoredChangeResult: Sendable {
        /// From the state before to the state now, for the canvas and the
        /// outline. Already stored, so not to be saved again.
        public let changes: GraphChangeSet
        /// Undo steps dropped because they touch what changed.
        public let droppedSteps: Int
        /// Steps were dropped or redo was emptied: the window rebuilds its
        /// undo actions from `undoStepNames`.
        public let historyChanged: Bool
    }

    /// Takes in the map as stored after a write from outside this editor (another
    /// device through iCloud, the Share Extension, an intent). The caller
    /// saves its own pending changes first, so whatever differs came from outside.
    ///
    /// The stored graph is repaired before it is shown, but the repair is not
    /// saved: a topic that arrived before its parent hangs under the root
    /// only until the parent arrives (cloudkit-sync.md, *Conflicts*).
    ///
    /// Undo (decided 2026-10-02, FR-UND-05): the steps that touch a record the
    /// outside change touched are dropped and the rest are kept. A step
    /// touches a record when it writes it, or points at one that is gone
    /// now. A step also goes when it depends on a dropped one (one writes a
    /// record the other points at), so the steps left can still be replayed;
    /// `undo()` checks each of them before it lands. Redo is emptied whenever
    /// a step goes, or a redo step touches the change, since the window's undo
    /// manager cannot rebuild its redo actions.
    public mutating func takeStored(_ stored: GraphState, now: Date) throws -> StoredChangeResult {
        precondition(stored.map.id == state.map.id, "A graph cannot switch to another map")
        let repaired = try GraphRepair.repair(stored, now: now).state
        let changes = GraphChangeSet.difference(from: state, to: repaired)
        guard !changes.isEmpty else {
            return StoredChangeResult(changes: changes, droppedSteps: 0, historyChanged: false)
        }

        let remote = RemoteTouch(changes)
        let dropped = Self.stepsToDrop(history.undoStack.map(\.changes), touching: remote)
        let redoTouched = !Self.stepsToDrop(history.redoStack.map(\.changes), touching: remote).isEmpty
        if !dropped.isEmpty || redoTouched {
            history.retainUndoSteps { !dropped.contains($0) }
        }
        state = repaired
        return StoredChangeResult(changes: changes, droppedSteps: dropped.count, historyChanged: !dropped.isEmpty || redoTouched)
    }

    /// What an outside change did, as steps are checked against it.
    struct RemoteTouch {
        let written: Set<GraphRecordKey>
        let removed: Set<GraphRecordKey>

        init(_ changes: GraphChangeSet) {
            written = changes.writtenRecords
            removed = changes.removedRecords
        }

        /// A step that only points at a record another device edited (adds a
        /// topic under a topic renamed elsewhere) stays; one that points at a
        /// record that is gone could not be replayed.
        func touches(written stepWritten: Set<GraphRecordKey>, referenced stepReferenced: Set<GraphRecordKey>) -> Bool {
            !stepWritten.isDisjoint(with: written) || !stepReferenced.isDisjoint(with: removed)
        }
    }

    /// Indices of the steps that touch the outside change, and then of those
    /// that share a record with a dropped step, until nothing more goes.
    static func stepsToDrop(_ steps: [GraphChangeSet], touching remote: RemoteTouch) -> Set<Int> {
        let written = steps.map(\.writtenRecords)
        let referenced = steps.map(\.referencedRecords)
        var dropped = Set(steps.indices.filter { remote.touches(written: written[$0], referenced: referenced[$0]) })
        var queue = Array(dropped)
        while let index = queue.popLast() {
            for other in steps.indices where !dropped.contains(other) {
                let dependent = !referenced[other].isDisjoint(with: written[index])
                    || !written[other].isDisjoint(with: referenced[index])
                if dependent {
                    dropped.insert(other)
                    queue.append(other)
                }
            }
        }
        return dropped
    }
}
