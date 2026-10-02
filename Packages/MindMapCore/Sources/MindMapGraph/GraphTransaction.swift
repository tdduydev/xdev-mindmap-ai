import Foundation
import MindMapDomain

/// The working copy a command edits. Every mutation is checked and recorded in
/// `changes`; if the command throws, the engine drops the copy, so a command is
/// all-or-nothing.
public struct GraphTransaction {
    public private(set) var state: GraphState
    public private(set) var changes = GraphChangeSet()
    /// The time stamped on everything this transaction creates or updates.
    public let now: Date
    /// Bytes of images the caller has loaded. Removing one of these images
    /// records its bytes, so undo restores it without the file.
    public let imageData: [ImageID: Data]

    public init(state: GraphState, now: Date, imageData: [ImageID: Data] = [:]) {
        self.state = state
        self.now = now
        self.imageData = imageData
    }

    // MARK: Nodes

    public mutating func insertNode(_ node: MindNode) throws {
        guard node.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.node(node.id) == nil else { throw GraphError.nodeAlreadyExists(node.id) }
        state.insertNode(node)
        changes.recordNode(node.id, before: nil, after: node)
    }

    /// Edits one node. A body that changes nothing records nothing.
    ///
    /// Moving or reordering the node also fixes the boundaries and summaries it
    /// ends, so every command that moves topics keeps them valid and undo
    /// restores them. A node given a parent loses its floating position, and a
    /// summary topic moved to another parent loses its summary (the tree wins).
    public mutating func updateNode(_ id: NodeID, _ body: (inout MindNode) -> Void) throws {
        guard let old = state.node(id) else { throw GraphError.nodeNotFound(id) }
        var new = old
        body(&new)
        if new.parentID != nil { new.position = nil }
        guard new != old else { return }
        new.updatedAt = now
        let reorder: GroupReorder?
        if new.parentID != old.parentID {
            try detachFromGroups(old)
            for summary in state.summaries(naming: id) {
                try removeGroup(summary.id)
            }
            reorder = nil
        } else if new.sortOrder != old.sortOrder {
            reorder = groupReorder(for: old)
        } else {
            reorder = nil
        }
        state.replaceNode(new)
        changes.recordNode(id, before: old, after: new)
        if let reorder {
            try finishGroupReorder(reorder)
        }
    }

    /// Removes one node, its tag links, its image, and the groups it held up:
    /// the ones it ends shrink, the ones over its children and the summaries
    /// naming it go.
    @discardableResult
    public mutating func removeNode(_ id: NodeID) throws -> MindNode {
        guard let node = state.node(id) else { throw GraphError.nodeNotFound(id) }
        try detachFromGroups(node)
        for group in state.groups(under: id) + state.summaries(naming: id) where state.groups[group.id] != nil {
            try removeGroup(group.id)
        }
        for image in state.images(of: id) {
            try removeImage(image.id)
        }
        for link in state.nodeTags.values where link.nodeID == id {
            try removeNodeTag(link.id)
        }
        guard let removed = state.removeNode(id) else { throw GraphError.nodeNotFound(id) }
        changes.recordNode(id, before: removed, after: nil)
        return removed
    }

    // MARK: Edges

    public mutating func insertEdge(_ edge: MindEdge) throws {
        guard edge.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.edges[edge.id] == nil else { throw GraphError.edgeAlreadyExists(edge.id) }
        state.upsertEdge(edge)
        changes.recordEdge(edge.id, before: nil, after: edge)
    }

    /// Edits one edge. A body that changes nothing records nothing.
    public mutating func updateEdge(_ id: EdgeID, _ body: (inout MindEdge) -> Void) throws {
        guard let old = state.edges[id] else { throw GraphError.edgeNotFound(id) }
        var new = old
        body(&new)
        guard new != old else { return }
        new.updatedAt = now
        state.upsertEdge(new)
        changes.recordEdge(id, before: old, after: new)
    }

    @discardableResult
    public mutating func removeEdge(_ id: EdgeID) throws -> MindEdge {
        guard let removed = state.removeEdge(id) else { throw GraphError.edgeNotFound(id) }
        changes.recordEdge(id, before: removed, after: nil)
        return removed
    }

    // MARK: Tags

    /// A map tag, or a shared tag (`mapID` nil).
    public mutating func insertTag(_ tag: MindTag) throws {
        guard tag.mapID == nil || tag.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.tags[tag.id] == nil else { throw GraphError.tagAlreadyExists(tag.id) }
        state.upsertTag(tag)
        changes.recordTag(tag.id, before: nil, after: tag)
    }

    /// Edits one tag. A body that changes nothing records nothing.
    public mutating func updateTag(_ id: TagID, _ body: (inout MindTag) -> Void) throws {
        guard let old = state.tags[id] else { throw GraphError.tagNotFound(id) }
        var new = old
        body(&new)
        guard new != old else { return }
        new.updatedAt = now
        state.upsertTag(new)
        changes.recordTag(id, before: old, after: new)
    }

    /// Removes a tag with every link to it in this map, one record at a time.
    @discardableResult
    public mutating func removeTag(_ id: TagID) throws -> MindTag {
        guard state.tags[id] != nil else { throw GraphError.tagNotFound(id) }
        for link in state.nodeTags.values where link.tagID == id {
            try removeNodeTag(link.id)
        }
        guard let removed = state.removeTag(id) else { throw GraphError.tagNotFound(id) }
        changes.recordTag(id, before: removed, after: nil)
        return removed
    }

    // MARK: Tag links

    public mutating func insertNodeTag(_ link: MindNodeTag) throws {
        guard link.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.nodeTags[link.id] == nil else { throw GraphError.nodeTagAlreadyExists(link.id) }
        guard state.node(link.nodeID) != nil else { throw GraphError.nodeNotFound(link.nodeID) }
        guard state.tags[link.tagID] != nil else { throw GraphError.tagNotFound(link.tagID) }
        state.upsertNodeTag(link)
        changes.recordNodeTag(link.id, before: nil, after: link)
    }

    public mutating func updateNodeTag(_ id: NodeTagID, _ body: (inout MindNodeTag) -> Void) throws {
        guard let old = state.nodeTags[id] else { throw GraphError.nodeTagNotFound(id) }
        var new = old
        body(&new)
        guard new != old else { return }
        new.updatedAt = now
        state.upsertNodeTag(new)
        changes.recordNodeTag(id, before: old, after: new)
    }

    @discardableResult
    public mutating func removeNodeTag(_ id: NodeTagID) throws -> MindNodeTag {
        guard let removed = state.removeNodeTag(id) else { throw GraphError.nodeTagNotFound(id) }
        changes.recordNodeTag(id, before: removed, after: nil)
        return removed
    }

    // MARK: Groups

    public mutating func insertGroup(_ group: MindGroup) throws {
        guard group.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.groups[group.id] == nil else { throw GraphError.groupAlreadyExists(group.id) }
        state.upsertGroup(group)
        changes.recordGroup(group.id, before: nil, after: group)
    }

    public mutating func updateGroup(_ id: GroupID, _ body: (inout MindGroup) -> Void) throws {
        guard let old = state.groups[id] else { throw GraphError.groupNotFound(id) }
        var new = old
        body(&new)
        guard new != old else { return }
        new.updatedAt = now
        state.upsertGroup(new)
        changes.recordGroup(id, before: old, after: new)
    }

    @discardableResult
    public mutating func removeGroup(_ id: GroupID) throws -> MindGroup {
        guard let removed = state.removeGroup(id) else { throw GraphError.groupNotFound(id) }
        changes.recordGroup(id, before: removed, after: nil)
        return removed
    }

    // MARK: Images

    /// One image per topic: replacing one is a remove and an insert.
    public mutating func insertImage(_ image: MindImage) throws {
        guard image.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.images[image.id] == nil else { throw GraphError.imageAlreadyExists(image.id) }
        guard state.node(image.nodeID) != nil else { throw GraphError.nodeNotFound(image.nodeID) }
        if let existing = state.image(of: image.nodeID) { throw GraphError.nodeHasImage(existing.id) }
        state.upsertImage(image)
        changes.recordImage(image.id, before: nil, after: image)
    }

    /// Edits an image's fields; its bytes cannot change here (replace instead).
    public mutating func updateImage(_ id: ImageID, _ body: (inout MindImage) -> Void) throws {
        guard let old = state.images[id] else { throw GraphError.imageNotFound(id) }
        var new = old
        body(&new)
        new.data = nil
        guard new != old else { return }
        guard state.node(new.nodeID) != nil else { throw GraphError.nodeNotFound(new.nodeID) }
        new.updatedAt = now
        state.upsertImage(new)
        // An image added earlier in this transaction still has to be saved with its bytes.
        new.data = changes.images[id]?.after?.data
        changes.recordImage(id, before: old, after: new)
    }

    @discardableResult
    public mutating func removeImage(_ id: ImageID) throws -> MindImage {
        guard var removed = state.removeImage(id) else { throw GraphError.imageNotFound(id) }
        removed.data = imageData[id]
        changes.recordImage(id, before: removed, after: nil)
        return removed
    }

    // MARK: Map

    public mutating func updateMap(_ body: (inout MindMap) -> Void) {
        let old = state.map
        var new = old
        body(&new)
        guard new != old else { return }
        state.setMap(new)
        changes.recordMap(before: old, after: new)
    }
}
