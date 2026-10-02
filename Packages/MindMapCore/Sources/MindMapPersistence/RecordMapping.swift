import Foundation
import MindMapDomain

// Enum values are stored as raw strings. A value this build does not know,
// written by a newer version on another device, falls back to the default
// instead of making the whole map unreadable.

extension MapRecord {
    var domainValue: MindMap {
        MindMap(
            id: MapID(mapID),
            title: title,
            rootNodeID: rootNodeID.map(NodeID.init),
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
            theme: MindMapTheme(storedValue: themeRaw),
            layoutConfiguration: LayoutConfiguration(style: LayoutStyle(rawValue: layoutStyleRaw) ?? .horizontalTree)
        )
    }

    /// Every field; for a map stored for the first time.
    func update(from map: MindMap) {
        updateGraphFields(from: map)
        isFavorite = map.isFavorite
    }

    /// The fields the graph engine owns; library flags are not among them.
    func updateGraphFields(from map: MindMap) {
        title = map.title
        rootNodeID = map.rootNodeID?.rawValue
        createdAt = map.createdAt
        updatedAt = map.updatedAt
        themeRaw = map.theme.rawValue
        layoutStyleRaw = map.layoutConfiguration.style.rawValue
    }
}

extension NodeRecord {
    var domainValue: MindNode {
        MindNode(
            id: NodeID(nodeID),
            mapID: MapID(mapID),
            parentID: parentID.map(NodeID.init),
            title: title,
            note: note,
            sortOrder: sortOrder,
            isCollapsed: isCollapsed,
            nodeType: NodeType(rawValue: nodeTypeRaw) ?? .topic,
            metadata: NodeMetadata(origin: NodeOrigin(rawValue: originRaw) ?? .user),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from node: MindNode) {
        parentID = node.parentID?.rawValue
        title = node.title
        note = node.note
        sortOrder = node.sortOrder
        isCollapsed = node.isCollapsed
        nodeTypeRaw = node.nodeType.rawValue
        originRaw = node.metadata.origin.rawValue
        createdAt = node.createdAt
        updatedAt = node.updatedAt
    }
}

extension EdgeRecord {
    /// Nil for an edge type this build does not know; such an edge is kept in
    /// storage untouched rather than misread.
    var domainValue: MindEdge? {
        guard let edgeType = EdgeType(rawValue: edgeTypeRaw) else { return nil }
        return MindEdge(
            id: EdgeID(edgeID),
            mapID: MapID(mapID),
            sourceNodeID: NodeID(sourceNodeID),
            targetNodeID: NodeID(targetNodeID),
            edgeType: edgeType,
            label: label,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from edge: MindEdge) {
        sourceNodeID = edge.sourceNodeID.rawValue
        targetNodeID = edge.targetNodeID.rawValue
        edgeTypeRaw = edge.edgeType.rawValue
        label = edge.label
        createdAt = edge.createdAt
        updatedAt = edge.updatedAt
    }
}
