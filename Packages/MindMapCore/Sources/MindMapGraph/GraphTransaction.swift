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

    public init(state: GraphState, now: Date) {
        self.state = state
        self.now = now
    }

    // MARK: Nodes

    public mutating func insertNode(_ node: MindNode) throws {
        guard node.mapID == state.map.id else { throw GraphError.belongsToAnotherMap }
        guard state.node(node.id) == nil else { throw GraphError.nodeAlreadyExists(node.id) }
        state.insertNode(node)
        changes.recordNode(node.id, before: nil, after: node)
    }

    /// Edits one node. A body that changes nothing records nothing.
    public mutating func updateNode(_ id: NodeID, _ body: (inout MindNode) -> Void) throws {
        guard let old = state.node(id) else { throw GraphError.nodeNotFound(id) }
        var new = old
        body(&new)
        guard new != old else { return }
        new.updatedAt = now
        state.replaceNode(new)
        changes.recordNode(id, before: old, after: new)
    }

    @discardableResult
    public mutating func removeNode(_ id: NodeID) throws -> MindNode {
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

    @discardableResult
    public mutating func removeEdge(_ id: EdgeID) throws -> MindEdge {
        guard let removed = state.removeEdge(id) else { throw GraphError.edgeNotFound(id) }
        changes.recordEdge(id, before: removed, after: nil)
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
