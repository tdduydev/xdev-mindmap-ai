import MindMapDomain
import MindMapGraph

extension GraphChangeSet {
    /// The topics to pass as `changed` to `MindMapLayoutEngine.update` after
    /// this change: each touched topic, plus its old and new parent, because a
    /// topic that moves or disappears changes the branch it left as well.
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
        return result
    }
}
