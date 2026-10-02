import MindMapDomain
import MindMapGraph

extension GraphChangeSet {
    /// The topics to pass as `changed` to `MindMapLayoutEngine.update` after
    /// this change: each touched topic, plus its old and new parent, because a
    /// topic that moves or disappears changes the branch it left as well.
    ///
    /// A topic whose tag links changed is included: its tag chips are part of
    /// its measured size. Renaming a tag changes chips without touching a link,
    /// so the caller compares measured sizes too.
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
        return result
    }
}
