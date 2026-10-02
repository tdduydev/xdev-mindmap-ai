import Foundation
import MindMapDomain
import MindMapGraph

/// Adds an imported outline under one topic, as a single undo step.
///
/// IDs are chosen when the command is made, so the caller can select the new
/// topics afterwards and running the command twice (redo after a rebuild)
/// creates the same nodes.
public struct InsertOutlineCommand: GraphCommand {
    public let parentID: NodeID
    public let placement: ChildPlacement
    public let origin: NodeOrigin
    /// Every new node, in reading order, with its draft.
    public let entries: [(id: NodeID, item: OutlineDraft.Item)]
    /// The new top-level topics, in order.
    public let topNodeIDs: [NodeID]

    /// `placement` is where the first top-level topic goes; the others follow it in order.
    public init(
        _ draft: OutlineDraft,
        under parentID: NodeID,
        at placement: ChildPlacement = .last,
        origin: NodeOrigin = .imported
    ) {
        self.parentID = parentID
        self.placement = placement
        self.origin = origin
        let entries = draft.items.map { (id: NodeID(), item: $0) }
        self.entries = entries
        self.topNodeIDs = entries.filter { $0.item.depth == 0 }.map(\.id)
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        // Most recent node at each depth; draft depths never skip a level.
        var path: [NodeID] = []
        var previousTop: NodeID?
        for (id, item) in entries {
            path.removeLast(path.count - item.depth)
            let insertion: NodeInsertion
            if let parent = path.last {
                insertion = .child(of: parent)
            } else {
                insertion = .child(of: parentID, at: previousTop.map { .after($0) } ?? placement)
                previousTop = id
            }
            try AddNodeCommand(
                nodeID: id,
                insertion,
                title: item.title,
                note: item.note,
                metadata: NodeMetadata(origin: origin)
            ).execute(in: &transaction)
            if let link = item.link {
                try transaction.updateNode(id) { $0.link = link }
            }
            path.append(id)
        }
    }
}

extension GraphState {
    /// A new map built from an imported outline.
    ///
    /// A single top-level topic becomes the central topic, which is how a
    /// Markdown file with one `#` title reads. Several become children of a
    /// central topic named `title`. The map takes its central topic's name.
    /// Throws `InterchangeError.emptyDocument` when there is nothing to import.
    public static func imported(
        from draft: OutlineDraft,
        title: String,
        id: MapID = MapID(),
        now: Date = .now
    ) throws -> GraphState {
        guard let first = draft.items.first else { throw InterchangeError.emptyDocument }

        let rootTitle: String
        let rootNote: String?
        let children: OutlineDraft
        if draft.topLevelCount == 1 {
            rootTitle = first.title
            rootNote = first.note
            children = OutlineDraft(items: draft.items.dropFirst().map { item in
                var item = item
                item.depth -= 1
                return item
            })
        } else {
            rootTitle = title
            rootNote = nil
            children = draft
        }

        let rootID = NodeID()
        var engine = try GraphEngine(
            state: GraphState(map: MindMap(id: id, title: rootTitle, createdAt: now)),
            clock: { now }
        )
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: rootID, .root, title: rootTitle, note: rootNote, metadata: NodeMetadata(origin: .imported)),
            SetNodeLinkCommand(nodeIDs: [rootID], link: draft.topLevelCount == 1 ? first.link : nil),
            InsertOutlineCommand(children, under: rootID),
        ]))
        return engine.state
    }
}
