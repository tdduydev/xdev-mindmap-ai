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
            layoutConfiguration: LayoutConfiguration(style: LayoutStyle(rawValue: layoutStyleRaw) ?? .horizontalTree),
            deletedAt: deletedAt
        )
    }

    /// Every field; for a map stored for the first time.
    func update(from map: MindMap) {
        updateGraphFields(from: map)
        isFavorite = map.isFavorite
        deletedAt = map.deletedAt
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
            nodeType: NodeType(rawValue: nodeTypeRaw),
            metadata: NodeMetadata(origin: NodeOrigin(rawValue: originRaw) ?? .user),
            createdAt: createdAt,
            updatedAt: updatedAt,
            color: colorToken.map(TopicColor.init),
            symbol: symbol,
            taskState: taskStateRaw.map(TaskState.init),
            priority: priority.map(TaskPriority.init),
            startDate: startDate.flatMap(CalendarDay.init(isoString:)),
            dueDate: dueDate.flatMap(CalendarDay.init(isoString:)),
            link: linkURL.map(TopicLink.init(string:)),
            position: storedPosition,
            callout: calloutText
        )
    }

    /// One coordinate alone, from a half-synced or damaged record, is no position.
    private var storedPosition: TopicPosition? {
        guard let positionX, let positionY else { return nil }
        return TopicPosition(x: positionX, y: positionY)
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
        colorToken = node.color?.rawValue
        symbol = node.symbol
        taskStateRaw = node.taskState?.rawValue
        priority = node.priority?.rawValue
        Self.store(node.startDate, in: &startDate)
        Self.store(node.dueDate, in: &dueDate)
        linkURL = node.link?.string
        // A clamped or zeroed read of the same stored pair is not an edit.
        if storedPosition != node.position {
            positionX = node.position?.x
            positionY = node.position?.y
        }
        calloutText = node.callout
    }

    /// A stored day this build cannot read showed as nil; it is kept unless
    /// the topic's day was really changed.
    private static func store(_ day: CalendarDay?, in stored: inout String?) {
        guard stored.flatMap(CalendarDay.init(isoString:)) != day else { return }
        stored = day?.isoString
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
            updatedAt: updatedAt,
            lineStyle: lineStyleRaw.map(EdgeLineStyle.init),
            arrowHeads: arrowHeadsRaw.map(EdgeArrowHeads.init),
            color: colorToken.map(TopicColor.init)
        )
    }

    func update(from edge: MindEdge) {
        sourceNodeID = edge.sourceNodeID.rawValue
        targetNodeID = edge.targetNodeID.rawValue
        edgeTypeRaw = edge.edgeType.rawValue
        label = edge.label
        createdAt = edge.createdAt
        updatedAt = edge.updatedAt
        lineStyleRaw = edge.lineStyle?.rawValue
        arrowHeadsRaw = edge.arrowHeads?.rawValue
        colorToken = edge.color?.rawValue
    }
}

extension TagRecord {
    var domainValue: MindTag {
        MindTag(
            id: TagID(tagID),
            mapID: mapID.map(MapID.init),
            name: name,
            color: colorToken.map(TopicColor.init),
            symbol: symbol,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from tag: MindTag) {
        mapID = tag.mapID?.rawValue
        name = tag.name
        colorToken = tag.color?.rawValue
        symbol = tag.symbol
        sortOrder = tag.sortOrder
        createdAt = tag.createdAt
        updatedAt = tag.updatedAt
    }
}

extension NodeTagRecord {
    var domainValue: MindNodeTag {
        MindNodeTag(
            id: NodeTagID(linkID),
            mapID: MapID(mapID),
            nodeID: NodeID(nodeID),
            tagID: TagID(tagID),
            origin: NodeOrigin(rawValue: originRaw) ?? .user,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from link: MindNodeTag) {
        nodeID = link.nodeID.rawValue
        tagID = link.tagID.rawValue
        originRaw = link.origin.rawValue
        createdAt = link.createdAt
        updatedAt = link.updatedAt
    }
}

extension GroupRecord {
    var domainValue: MindGroup {
        MindGroup(
            id: GroupID(groupID),
            mapID: MapID(mapID),
            kind: GroupKind(rawValue: kindRaw),
            parentNodeID: parentNodeID.map(NodeID.init),
            firstNodeID: firstNodeID.map(NodeID.init),
            lastNodeID: lastNodeID.map(NodeID.init),
            title: title,
            color: colorToken.map(TopicColor.init),
            origin: NodeOrigin(rawValue: originRaw) ?? .user,
            createdAt: createdAt,
            updatedAt: updatedAt,
            summaryNodeID: summaryNodeID.map(NodeID.init)
        )
    }

    func update(from group: MindGroup) {
        kindRaw = group.kind.rawValue
        parentNodeID = group.parentNodeID?.rawValue
        firstNodeID = group.firstNodeID?.rawValue
        lastNodeID = group.lastNodeID?.rawValue
        title = group.title
        colorToken = group.color?.rawValue
        originRaw = group.origin.rawValue
        createdAt = group.createdAt
        updatedAt = group.updatedAt
        summaryNodeID = group.summaryNodeID?.rawValue
    }
}

extension ImageRecord {
    /// Without `data`: reading it would load the file of every image in the map.
    var domainValue: MindImage {
        MindImage(
            id: ImageID(imageID),
            mapID: MapID(mapID),
            nodeID: NodeID(nodeID),
            uniformType: uniformType,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            byteCount: byteCount,
            displayWidth: displayWidth,
            altText: altText,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Bytes are written only when the value carries them, so a size or
    /// description edit never rewrites the file.
    func update(from image: MindImage) {
        nodeID = image.nodeID.rawValue
        if let bytes = image.data { data = bytes }
        uniformType = image.uniformType
        pixelWidth = image.pixelWidth
        pixelHeight = image.pixelHeight
        byteCount = image.byteCount
        displayWidth = image.displayWidth
        altText = image.altText
        createdAt = image.createdAt
        updatedAt = image.updatedAt
    }
}
