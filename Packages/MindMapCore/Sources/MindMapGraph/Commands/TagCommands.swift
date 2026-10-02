import Foundation
import MindMapDomain

// Map tags change through these commands and the map's undo history. Shared
// tags are library data, like `isFavorite`: they are renamed, merged and
// deleted through the repository, so these commands refuse them, except for
// putting one on a topic, which is a map edit.

/// A tag to put on topics.
public enum TagReference: Hashable, Sendable {
    case existing(TagID)
    /// A typed name. A shared or map tag with the same key is used; otherwise a
    /// new map tag with `newTagID` is created in the same step.
    case named(String, newTagID: TagID = TagID())
}

/// Creates a map tag. A map tag with the same key already exists: nothing
/// happens, and callers find it with `GraphState.tag(named:)`.
public struct CreateTagCommand: GraphCommand {
    public let tagID: TagID
    public let name: String
    public let color: TopicColor?
    public let symbol: String?

    public init(tagID: TagID = TagID(), name: String, color: TopicColor? = nil, symbol: String? = nil) {
        self.tagID = tagID
        self.name = name
        self.color = color
        self.symbol = symbol
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let name = MindTag.normalizedName(name) else { throw GraphError.invalidTagName }
        guard transaction.mapTag(withKey: MindTag.key(for: name)) == nil else { return }
        try transaction.insertTag(MindTag(
            id: tagID,
            mapID: transaction.state.map.id,
            name: name,
            color: color,
            symbol: symbol.flatMap(TopicSymbol.normalized),
            sortOrder: transaction.nextTagSortOrder(),
            createdAt: transaction.now
        ))
    }
}

/// Renames, recolours, changes the symbol of, or reorders a map tag.
public struct UpdateTagCommand: GraphCommand {
    public let tagID: TagID
    public let name: FieldChange<String>
    public let color: FieldChange<TopicColor?>
    public let symbol: FieldChange<String?>
    public let sortOrder: FieldChange<Double>

    public init(
        tagID: TagID,
        name: FieldChange<String> = .keep,
        color: FieldChange<TopicColor?> = .keep,
        symbol: FieldChange<String?> = .keep,
        sortOrder: FieldChange<Double> = .keep
    ) {
        self.tagID = tagID
        self.name = name
        self.color = color
        self.symbol = symbol
        self.sortOrder = sortOrder
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        try transaction.requireMapTag(tagID)
        let name = try name.map { text in
            guard let name = MindTag.normalizedName(text) else { throw GraphError.invalidTagName }
            if let other = transaction.mapTag(withKey: MindTag.key(for: name)), other.id != tagID {
                throw GraphError.tagNameTaken(other.id)
            }
            return name
        }
        let symbol = symbol.map { $0.flatMap(TopicSymbol.normalized) }
        try transaction.updateTag(tagID) { tag in
            name.apply(to: &tag.name)
            color.apply(to: &tag.color)
            symbol.apply(to: &tag.symbol)
            sortOrder.apply(to: &tag.sortOrder)
        }
    }
}

/// Deletes a map tag and every link to it; the topics stay.
public struct DeleteTagCommand: GraphCommand {
    public let tagID: TagID

    public init(tagID: TagID) {
        self.tagID = tagID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        try transaction.requireMapTag(tagID)
        try transaction.removeTag(tagID)
    }
}

/// Folds map tags into one: their links move to the survivor (a topic tagged
/// with both keeps one link) and they are deleted. The survivor may be shared.
public struct MergeTagsCommand: GraphCommand {
    public let survivorID: TagID
    public let mergedIDs: [TagID]

    public init(into survivorID: TagID, merging mergedIDs: [TagID]) {
        self.survivorID = survivorID
        self.mergedIDs = mergedIDs
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard transaction.state.tag(survivorID) != nil else { throw GraphError.tagNotFound(survivorID) }
        for id in mergedIDs where id != survivorID {
            try transaction.requireMapTag(id)
        }
        var seen: Set<TagID> = [survivorID]
        for id in mergedIDs where seen.insert(id).inserted {
            try transaction.moveTagLinks(from: id, to: survivorID)
            try transaction.removeTag(id)
        }
    }
}

/// Puts tags on and takes tags off topics, as one undo step. Removals apply
/// first. A topic that already has a tag keeps its link (and its origin).
public struct TagNodesCommand: GraphCommand {
    public let nodeIDs: [NodeID]
    public let add: [TagReference]
    public let remove: [TagID]
    /// `ai` for accepted suggestions.
    public let origin: NodeOrigin

    public init(nodeIDs: [NodeID], add: [TagReference] = [], remove: [TagID] = [], origin: NodeOrigin = .user) {
        self.nodeIDs = nodeIDs
        self.add = add
        self.remove = remove
        self.origin = origin
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        for id in nodeIDs where transaction.state.node(id) == nil {
            throw GraphError.nodeNotFound(id)
        }
        let removing = Set(remove)
        let nodes = Set(nodeIDs)
        let doomed = transaction.state.nodeTags.values
            .filter { nodes.contains($0.nodeID) && removing.contains($0.tagID) }
            .sorted(by: GraphValidator.oldestFirst)
        for link in doomed {
            try transaction.removeNodeTag(link.id)
        }

        var tagIDs: [TagID] = []
        for reference in add {
            let id = try transaction.resolve(reference)
            if !tagIDs.contains(id) { tagIDs.append(id) }
        }
        for nodeID in nodeIDs {
            let present = Set(transaction.state.nodeTags.values.filter { $0.nodeID == nodeID }.map(\.tagID))
            for tagID in tagIDs where !present.contains(tagID) {
                try transaction.insertNodeTag(MindNodeTag(
                    mapID: transaction.state.map.id,
                    nodeID: nodeID,
                    tagID: tagID,
                    origin: origin,
                    createdAt: transaction.now
                ))
            }
        }
    }
}

extension GraphTransaction {
    func mapTag(withKey key: String) -> MindTag? {
        state.tags.values
            .filter { $0.mapID == state.map.id && $0.key == key }
            .min(by: GraphValidator.oldestFirst)
    }

    func requireMapTag(_ id: TagID) throws {
        guard let tag = state.tag(id) else { throw GraphError.tagNotFound(id) }
        guard !tag.isShared else { throw GraphError.sharedTagIsLibraryData(id) }
    }

    mutating func resolve(_ reference: TagReference) throws -> TagID {
        switch reference {
        case .existing(let id):
            guard state.tag(id) != nil else { throw GraphError.tagNotFound(id) }
            return id
        case .named(let text, let newTagID):
            guard let name = MindTag.normalizedName(text) else { throw GraphError.invalidTagName }
            if let existing = state.tag(named: name) { return existing.id }
            try CreateTagCommand(tagID: newTagID, name: name).execute(in: &self)
            return newTagID
        }
    }
}
