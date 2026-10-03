import MindMapDomain
import MindMapGraph

extension GraphChangeSet {
    /// The topics to pass as `changed` to `MindMapLayoutEngine.update` after
    /// this change: each touched topic, plus its old and new parent, because a
    /// topic that moves or disappears changes the branch it left as well.
    ///
    /// A topic whose tag links or image changed is included: its tag chips
    /// and its picture are part of its measured size. Renaming a tag changes chips without touching a link,
    /// so the caller compares measured sizes too.
    /// A boundary or summary change marks its parent, whose children make room
    /// for it, and the summary topic it names.
    ///
    /// Topic sizes are the caller's input; a topic whose measured size changed
    /// for another reason (Dynamic Type, font) must be added by the caller.
    public var layoutInvalidation: Set<NodeID> {
        var result: Set<NodeID> = []
        for (id, change) in nodes {
            result.insert(id)
            if let parentID = change.before?.parentID { result.insert(parentID) }
            if let parentID = change.after?.parentID { result.insert(parentID) }
        }
        for change in nodeTags.values {
            if let nodeID = change.before?.nodeID { result.insert(nodeID) }
            if let nodeID = change.after?.nodeID { result.insert(nodeID) }
        }
        for change in images.values {
            if let nodeID = change.before?.nodeID { result.insert(nodeID) }
            if let nodeID = change.after?.nodeID { result.insert(nodeID) }
        }
        // A boundary's padding and title room are part of its parent's block.
        for change in groups.values {
            if let parentID = change.before?.parentNodeID { result.insert(parentID) }
            if let parentID = change.after?.parentNodeID { result.insert(parentID) }
            // A summary topic leaves or joins its parent's column with its group.
            if let topicID = change.before?.summaryNodeID { result.insert(topicID) }
            if let topicID = change.after?.summaryNodeID { result.insert(topicID) }
        }
        return result
    }
}
