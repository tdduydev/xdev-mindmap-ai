import Foundation
import MindMapDomain
import MindMapGraph

/// What changed in the store, as the library needs to know it.
public enum MapRepositoryChange: Sendable, Equatable {
    /// This repository stored a map: created, edited, marked as a favorite,
    /// moved to Recently Deleted or restored. Carries the summary as stored,
    /// favorite flag and `deletedAt` included.
    case saved(MindMap)
    /// Deleted permanently, by Delete Permanently or after the retention period.
    case deleted(MapID)
    /// Something other than this repository wrote to the store (another
    /// context, another process, later iCloud). Which maps changed is not
    /// known, so a consumer fetches its list again.
    case storeChanged
    /// This repository changed tags as library data (`SharedTagActions`).
    /// Every open map applies the part it holds; the library's search
    /// learns new tag names.
    case tagsChanged(LibraryTagChange)
}

/// Where maps live. Features talk to this protocol, never to SwiftData, so the
/// store can change and tests can use an in-memory one.
public protocol MapRepository: SharedTagActions {
    /// Every change committed after this call returns, in commit order, until
    /// the stream's task ends. Each window subscribes before its first fetch,
    /// so a write cannot fall between the fetch and the subscription.
    func changes() async -> AsyncStream<MapRepositoryChange>

    /// Every live map, most recently edited first; maps in Recently Deleted
    /// are left out, so intents, the Share Extension and Spotlight never offer
    /// them. Nodes are not loaded.
    func fetchMaps() async throws -> [MindMap]

    /// Maps in Recently Deleted, most recently deleted first.
    func fetchDeletedMaps() async throws -> [MindMap]

    /// Nil when the map does not exist, for example after another device
    /// deleted it. A map in Recently Deleted still loads; callers that edit
    /// check `map.deletedAt`.
    func loadGraph(for mapID: MapID) async throws -> GraphState?

    /// An image's bytes, which `loadGraph` leaves out. Nil when the image is
    /// not stored or its bytes have not synced yet.
    func imageData(for imageID: ImageID) async throws -> Data?

    /// Stores a whole new graph: a new map, a template or an import.
    func create(_ graph: GraphState) async throws

    /// Writes only the records in `changes`, plus the map's graph fields (title,
    /// root, edit time, theme, layout). Library flags such as favorite are left
    /// alone, so an editor holding an older copy of the map cannot reset them.
    func save(_ changes: GraphChangeSet, map: MindMap) async throws

    /// Marking a map as a favorite is not an edit: it does not move `updatedAt`.
    func setFavorite(_ isFavorite: Bool, for mapID: MapID) async throws

    /// Moves a map to Recently Deleted (FR-LIB-11). Its records stay, so
    /// `restoreMap` brings it back as it was. Like a favorite, not an edit.
    func moveToRecentlyDeleted(_ mapID: MapID, at date: Date) async throws

    /// Takes a map out of Recently Deleted.
    func restoreMap(_ mapID: MapID) async throws

    /// Deletes a map and every record of it for good (DR-07).
    func deleteMap(_ mapID: MapID) async throws

    /// Deletes for good every map that went to Recently Deleted before
    /// `cutoff`, and returns their IDs.
    @discardableResult
    func purgeDeletedMaps(deletedBefore cutoff: Date) async throws -> [MapID]

    /// The title and note of every topic, by map, for library search, and the
    /// name of every tag the map's topics carry. Empty texts are left out.
    func fetchTopicTexts() async throws -> [MapID: [String]]

    /// How many topics each map has, central topic included, without loading
    /// any graph, so a list of maps can show sizes (MCP `list_maps`). Maps with
    /// no topics are left out.
    func fetchTopicCounts() async throws -> [MapID: Int]
}

/// Why a library tag action changed nothing.
public enum LibraryTagError: Error, Hashable, Sendable {
    case tagNotFound(TagID)
    /// Blank, or longer than `MindTag.maximumNameLength`.
    case invalidName
    /// Another tag of the same scope has this name's key.
    case nameTaken(TagID)
    /// A map tag where a shared one is needed, or the other way round.
    case wrongScope(TagID)
    /// A shared tag that topics of other maps carry cannot become one map's.
    case usedInOtherMaps(count: Int)
}

/// Shared tags are library data, like the favorite flag: these change them
/// outside every map's undo history. Each action stores its change, returns
/// it, and publishes it as `.tagsChanged`, so every open map applies it with
/// `GraphEngine.apply(_:)`. Callers save their pending map edits first.
public protocol SharedTagActions: Sendable {
    /// How many maps carry each shared tag on at least one topic.
    func sharedTagMapCounts() async throws -> [TagID: Int]

    @discardableResult
    func renameSharedTag(_ id: TagID, to name: String) async throws -> LibraryTagChange

    @discardableResult
    func setSharedTagColor(_ id: TagID, to color: TopicColor?) async throws -> LibraryTagChange

    /// Deletes the tag and its links in every map; the topics stay.
    @discardableResult
    func deleteSharedTag(_ id: TagID) async throws -> LibraryTagChange

    /// Moves the merged shared tags' links, in every map, to the survivor (one
    /// link per topic, the older kept) and deletes them.
    @discardableResult
    func mergeSharedTags(into survivorID: TagID, merging mergedIDs: [TagID]) async throws -> LibraryTagChange

    /// Make Shared: a map tag becomes a library tag, offered in every map.
    @discardableResult
    func makeTagShared(_ id: TagID) async throws -> LibraryTagChange

    /// Make Map Tag: a shared tag becomes one map's, if no other map uses it.
    @discardableResult
    func makeMapTag(_ id: TagID, in mapID: MapID) async throws -> LibraryTagChange

    /// Merges shared tags with equal keys, created on two devices offline, into
    /// the oldest, as `GraphRepair` does for a map's tags. Run on load and
    /// after a change from outside.
    @discardableResult
    func repairSharedTags() async throws -> LibraryTagChange
}
