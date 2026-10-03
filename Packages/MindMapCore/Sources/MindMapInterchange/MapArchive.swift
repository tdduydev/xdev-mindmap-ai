import Foundation
import MindMapDomain
import MindMapGraph

/// One map, every record of it, as a JSON file: the backup format (MM-54).
///
/// Markdown keeps titles and notes only, so it is not a backup. This is the
/// domain values as they are stored, so nothing the map holds is dropped:
/// theme, colours, symbols, tasks, tags, links, boundaries and images included.
/// See "Map archive" in docs/interchange.md.
public struct MapArchive: Hashable, Sendable, Codable {
    /// Marks the file as ours, so a JSON file of another app is refused
    /// instead of being read as an empty map.
    public static let formatName = "asia.xdev.mindmapai.map"
    /// Raised only when a field changes meaning or goes away. A new optional
    /// field does not need a new version: older builds skip it, newer ones
    /// read its absence as nil.
    public static let currentVersion = 1
    public static let fileExtension = "json"

    public var format: String
    public var version: Int
    public var map: MindMap
    public var nodes: [MindNode]
    public var edges: [MindEdge]
    /// The map's own tags and the shared tags its topics carry.
    public var tags: [MindTag]
    public var nodeTags: [MindNodeTag]
    public var groups: [MindGroup]
    /// With their bytes, base64 in the JSON (MM-63): one file stays one file,
    /// so Export, Import and the share sheet need no folder or package type.
    /// Nil when the map has none, so such a file is byte for byte what a
    /// build before images wrote.
    public var images: [MindImage]?

    /// Records sorted by ID, so the same map always writes the same bytes and
    /// two backups can be compared with `diff`.
    /// - Parameter imageData: The bytes of the map's images, which the graph
    ///   does not hold (`MapRepository.imageData(for:)`). An image missing
    ///   here is written without them and comes back as a record with no file.
    public init(_ graph: GraphState, imageData: [ImageID: Data] = [:]) {
        let usedTags = Set(graph.nodeTags.values.map(\.tagID))
        format = Self.formatName
        version = Self.currentVersion
        map = graph.map
        nodes = graph.nodes.values.sorted { $0.id < $1.id }
        edges = graph.edges.values.sorted { $0.id < $1.id }
        // Unused shared tags belong to the library, not to this map.
        tags = graph.tags.values
            .filter { !$0.isShared || usedTags.contains($0.id) }
            .sorted { $0.id < $1.id }
        nodeTags = graph.nodeTags.values.sorted { $0.id < $1.id }
        groups = graph.groups.values.sorted { $0.id < $1.id }
        let images = graph.images.values.sorted { $0.id < $1.id }.map { image in
            var image = image
            image.data = imageData[image.id]
            return image
        }
        self.images = images.isEmpty ? nil : images
    }

    /// The map exactly as it was written, same IDs, images without bytes
    /// (as a graph holds them; `imageData` has the bytes).
    public var graph: GraphState {
        GraphState(map: map, nodes: nodes, edges: edges, tags: tags, nodeTags: nodeTags, groups: groups, images: images ?? [])
    }

    /// The bytes of the archive's images, by image ID.
    public var imageData: [ImageID: Data] {
        var result: [ImageID: Data] = [:]
        for image in images ?? [] {
            if let data = image.data { result[image.id] = data }
        }
        return result
    }
}

// MARK: Files

extension MapArchive {
    @concurrent
    public static func exportData(_ graph: GraphState, imageData: [ImageID: Data] = [:]) async throws -> Data {
        try encoder.encode(MapArchive(graph, imageData: imageData))
    }

    /// Reads a file of any version up to `currentVersion`.
    @concurrent
    public static func decode(_ data: Data) async throws(MapArchiveError) -> MapArchive {
        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: data)
        } catch {
            throw .notAnArchive
        }
        guard header.format == formatName else { throw .notAnArchive }
        guard header.version <= currentVersion else { throw .newerVersion(header.version) }
        do {
            // Version 1 is the only layout so far. A later version that renames
            // a field decodes the old layout here and converts it.
            return try decoder.decode(MapArchive.self, from: data)
        } catch {
            throw .damaged
        }
    }

    /// Whether the bytes start like an archive, without decoding the whole map.
    /// Lets an importer tell an archive from other JSON by content.
    public static func isArchive(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Header.self, from: data))?.format == formatName
    }

    private struct Header: Decodable {
        var format: String
        var version: Int
    }

    // Dates stay `Double` seconds (the default): ISO 8601 would round them to
    // the millisecond, and an edit time that changes breaks "newest wins".
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder { JSONDecoder() }
}

public enum MapArchiveError: Error, Hashable, Sendable {
    /// Not JSON, or JSON without our format name.
    case notAnArchive
    /// Written by a newer version of the app.
    case newerVersion(Int)
    /// Our format, but a record is missing a field or has a wrong value.
    case damaged
}

// MARK: Importing

extension MapArchive {
    /// The archive as a new map in this library. Every ID is new, so importing
    /// never overwrites a map, even the one the file was made from, and the
    /// same file can be imported twice. The map comes back live (not in
    /// Recently Deleted); everything else, edit times included, is kept.
    ///
    /// - Parameter sharedTags: The library's shared tags. A shared tag of the
    ///   file joins the library tag with the same key; one the library does
    ///   not have becomes a tag of the new map, since this map cannot create
    ///   library tags (they are library actions, not map records).
    public func importedGraph(sharedTags: [MindTag] = []) -> GraphState {
        imported(sharedTags: sharedTags).graph
    }

    /// `importedGraph(sharedTags:)` with the images' bytes under their new
    /// IDs, for `MapRepository.create(_:imageData:)`.
    public func imported(sharedTags: [MindTag] = []) -> (graph: GraphState, imageData: [ImageID: Data]) {
        let mapID = MapID()
        var nodeIDs: [NodeID: NodeID] = [:]
        for node in nodes { nodeIDs[node.id] = NodeID() }
        let newNode = { (id: NodeID?) in id.flatMap { nodeIDs[$0] } }

        var libraryTags: [String: MindTag] = [:]
        for tag in sharedTags where tag.isShared {
            libraryTags[tag.key] = libraryTags[tag.key] ?? tag
        }
        var tagIDs: [TagID: TagID] = [:]
        var newTags: [MindTag] = []
        for tag in tags {
            if tag.isShared, let libraryTag = libraryTags[tag.key] {
                tagIDs[tag.id] = libraryTag.id
                newTags.append(libraryTag)
                continue
            }
            let id = TagID()
            tagIDs[tag.id] = id
            newTags.append(MindTag(
                id: id, mapID: mapID, name: tag.name, color: tag.color, symbol: tag.symbol,
                sortOrder: tag.sortOrder, createdAt: tag.createdAt, updatedAt: tag.updatedAt
            ))
        }

        let newMap = MindMap(
            id: mapID, title: map.title, rootNodeID: newNode(map.rootNodeID),
            createdAt: map.createdAt, updatedAt: map.updatedAt, isFavorite: map.isFavorite,
            theme: map.theme, layoutConfiguration: map.layoutConfiguration
        )

        // A reference to an ID the file does not hold gets a fresh, dangling
        // ID, so `GraphRepair` treats it as it would a record lost in sync.
        let newNodes = nodes.map { node in
            MindNode(
                id: nodeIDs[node.id] ?? NodeID(), mapID: mapID,
                parentID: node.parentID.map { nodeIDs[$0] ?? NodeID() },
                title: node.title, note: node.note, sortOrder: node.sortOrder,
                isCollapsed: node.isCollapsed, nodeType: node.nodeType, metadata: node.metadata,
                createdAt: node.createdAt, updatedAt: node.updatedAt,
                color: node.color, symbol: node.symbol, taskState: node.taskState,
                priority: node.priority, startDate: node.startDate, dueDate: node.dueDate,
                link: node.link, position: node.position, callout: node.callout
            )
        }
        let newEdges = edges.map { edge in
            MindEdge(
                mapID: mapID,
                sourceNodeID: nodeIDs[edge.sourceNodeID] ?? NodeID(),
                targetNodeID: nodeIDs[edge.targetNodeID] ?? NodeID(),
                edgeType: edge.edgeType, label: edge.label,
                createdAt: edge.createdAt, updatedAt: edge.updatedAt,
                lineStyle: edge.lineStyle, arrowHeads: edge.arrowHeads, color: edge.color
            )
        }
        let newNodeTags = nodeTags.map { link in
            MindNodeTag(
                mapID: mapID,
                nodeID: nodeIDs[link.nodeID] ?? NodeID(),
                tagID: tagIDs[link.tagID] ?? TagID(),
                origin: link.origin, createdAt: link.createdAt, updatedAt: link.updatedAt
            )
        }
        let newGroups = groups.map { group in
            MindGroup(
                mapID: mapID, kind: group.kind,
                parentNodeID: newNode(group.parentNodeID),
                firstNodeID: newNode(group.firstNodeID),
                lastNodeID: newNode(group.lastNodeID),
                title: group.title, color: group.color, origin: group.origin,
                createdAt: group.createdAt, updatedAt: group.updatedAt,
                summaryNodeID: group.summaryNodeID.map { nodeIDs[$0] ?? NodeID() }
            )
        }
        var newImageData: [ImageID: Data] = [:]
        let newImages = (images ?? []).map { image in
            let copy = MindImage(
                mapID: mapID, nodeID: nodeIDs[image.nodeID] ?? NodeID(),
                uniformType: image.uniformType, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight,
                byteCount: image.byteCount, displayWidth: image.displayWidth, altText: image.altText,
                createdAt: image.createdAt, updatedAt: image.updatedAt
            )
            newImageData[copy.id] = image.data
            return copy
        }
        let graph = GraphState(
            map: newMap, nodes: newNodes, edges: newEdges,
            tags: newTags, nodeTags: newNodeTags, groups: newGroups, images: newImages
        )
        return (graph, newImageData)
    }
}
