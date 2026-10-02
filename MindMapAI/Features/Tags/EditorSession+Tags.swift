import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapSearch
import OSLog

/// Why a tag action changed nothing, as one message.
enum TagFailure: Equatable, Identifiable {
    case invalidName
    case nameTaken(String)
    case usedInOtherMaps(Int)
    case couldNotSave

    var id: String { message }

    var message: String {
        switch self {
        case .invalidName:
            String(localized: "A tag name needs 1 to 40 characters.")
        case .nameTaken(let name):
            String(localized: "There is already a tag named “\(name)”.")
        case .usedInOtherMaps(let count):
            String(localized: "This tag is used in \(count) other maps, so it stays shared.")
        case .couldNotSave:
            String(localized: "Couldn’t change the tag.")
        }
    }
}

/// Whether a tag is on the selected topics, for menu checkmarks and the
/// inspector's mixed state.
enum TagCoverage {
    case none
    case some
    case all
}

// Tagging topics is a map edit: a command with an undo name. Map tags are
// renamed, recoloured, merged and deleted the same way. Shared tags are
// library data (docs/node-organization.md, *Tags*): those actions go to the
// repository and are not undo steps.
extension EditorSession {
    var canTagSelection: Bool { !orderedSelection.isEmpty }

    /// Every tag this map can use: its own in list order, then the library's.
    var availableTags: [MindTag] {
        engine.state.mapTags + engine.state.sharedTags
    }

    /// The tags most used in this map first, for the Tags menu.
    func mostUsedTags(limit: Int = 10) -> [MindTag] {
        let counts = engine.state.tagUseCounts()
        return availableTags
            .filter { counts[$0.id] != nil }
            .sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    func coverage(of tagID: TagID, on ids: [NodeID]? = nil) -> TagCoverage {
        let targets = ids ?? orderedSelection
        guard !targets.isEmpty else { return .none }
        let tagged = engine.state.nodeIDs(taggedWith: tagID)
        let count = targets.filter(tagged.contains).count
        return count == 0 ? .none : count == targets.count ? .all : .some
    }

    /// The tags on any of the topics, in the order the first one shows them.
    func tags(on ids: [NodeID]) -> [MindTag] {
        var seen: Set<TagID> = []
        return ids.flatMap { engine.state.tags(of: $0) }.filter { seen.insert($0.id).inserted }
    }

    /// Tags whose name holds what is typed, by search folding ("viec" finds
    /// "việc"), shared ones first as the tag field offers them; tags every
    /// target already carries are left out.
    func tagMatches(for text: String, on ids: [NodeID]? = nil) -> [MindTag] {
        let query = SearchQuery(text.hasPrefix("#") ? String(text.dropFirst()) : text)
        let targets = ids ?? orderedSelection
        let candidates = engine.state.sharedTags + engine.state.mapTags
        return candidates.filter { tag in
            (query.isEmpty || query.matches(tag.name)) && coverage(of: tag.id, on: targets) != .all
        }
    }

    /// Whether typing `text` and pressing Return would make a new tag.
    func wouldCreateTag(named text: String) -> Bool {
        MindTag.normalizedName(text) != nil && engine.state.tag(named: text) == nil
    }

    // MARK: Tagging topics

    /// A typed name: the tag with that name (shared first) or a new map tag,
    /// on every target, as one "Add Tag" step.
    @discardableResult
    func addTag(named text: String, to ids: [NodeID]? = nil) -> Bool {
        let targets = ids ?? orderedSelection
        guard !targets.isEmpty else { return false }
        guard MindTag.normalizedName(text) != nil else {
            tagFailure = .invalidName
            return false
        }
        return perform(TagNodesCommand(nodeIDs: targets, add: [.named(text)]), named: String(localized: "Add Tag"))
    }

    @discardableResult
    func addTag(_ tagID: TagID, to ids: [NodeID]? = nil) -> Bool {
        let targets = ids ?? orderedSelection
        guard !targets.isEmpty else { return false }
        return perform(TagNodesCommand(nodeIDs: targets, add: [.existing(tagID)]), named: String(localized: "Add Tag"))
    }

    func removeTag(_ tagID: TagID, from ids: [NodeID]? = nil) {
        let targets = ids ?? orderedSelection
        guard !targets.isEmpty else { return }
        perform(TagNodesCommand(nodeIDs: targets, remove: [tagID]), named: String(localized: "Remove Tag"))
    }

    /// The Tags menu's toggle: on every target unless all of them have it.
    func toggleTag(_ tagID: TagID, on ids: [NodeID]? = nil) {
        if coverage(of: tagID, on: ids) == .all {
            removeTag(tagID, from: ids)
        } else {
            addTag(tagID, to: ids)
        }
    }

    /// Topic ▸ Add Tag…: the inspector's tag field, with the cursor in it.
    func beginAddingTag() {
        guard canTagSelection else { return }
        isInspectorPresented = true
        tagFieldFocusRequest = true
    }

    // MARK: Editing tags

    func renameTag(_ tagID: TagID, to name: String) async {
        guard let tag = engine.state.tag(tagID), name != tag.name else { return }
        guard let clean = MindTag.normalizedName(name) else {
            tagFailure = .invalidName
            return
        }
        guard !tag.isShared else {
            return await libraryAction { try await $0.renameSharedTag(tagID, to: clean) }
        }
        if let other = engine.state.mapTags.first(where: { $0.key == MindTag.key(for: clean) && $0.id != tagID }) {
            tagFailure = .nameTaken(other.name)
            return
        }
        perform(UpdateTagCommand(tagID: tagID, name: .set(clean)), named: String(localized: "Rename Tag"))
    }

    func setTagColor(_ tagID: TagID, to color: TopicColor?) async {
        guard let tag = engine.state.tag(tagID), tag.color != color else { return }
        guard !tag.isShared else {
            return await libraryAction { try await $0.setSharedTagColor(tagID, to: color) }
        }
        perform(UpdateTagCommand(tagID: tagID, color: .set(color)), named: String(localized: "Change Tag Color"))
    }

    /// A map tag goes with one undo step; a shared tag goes from every map,
    /// so the caller asks first (`sharedTagMapCount`).
    func deleteTag(_ tagID: TagID) async {
        guard let tag = engine.state.tag(tagID) else { return }
        guard !tag.isShared else {
            return await libraryAction { try await $0.deleteSharedTag(tagID) }
        }
        perform(DeleteTagCommand(tagID: tagID), named: String(localized: "Delete Tag"))
    }

    /// Whether `mergedID` can fold into `survivorID`: a shared tag only into
    /// another shared tag, since its other maps would lose it otherwise.
    func canMerge(_ mergedID: TagID, into survivorID: TagID) -> Bool {
        guard mergedID != survivorID, let merged = engine.state.tag(mergedID), engine.state.tag(survivorID) != nil else { return false }
        return !merged.isShared || engine.state.tag(survivorID)?.isShared == true
    }

    /// Map tags merge as one undo step; shared ones through the library.
    func mergeTag(_ mergedID: TagID, into survivorID: TagID) async {
        guard canMerge(mergedID, into: survivorID), let merged = engine.state.tag(mergedID) else { return }
        guard merged.isShared else {
            perform(MergeTagsCommand(into: survivorID, merging: [mergedID]), named: String(localized: "Merge Tags"))
            return
        }
        await libraryAction { try await $0.mergeSharedTags(into: survivorID, merging: [mergedID]) }
    }

    func makeShared(_ tagID: TagID) async {
        guard engine.state.tag(tagID)?.isShared == false else { return }
        await libraryAction { try await $0.makeTagShared(tagID) }
    }

    func makeMapTag(_ tagID: TagID) async {
        guard engine.state.tag(tagID)?.isShared == true else { return }
        let mapID = map.id
        await libraryAction { try await $0.makeMapTag(tagID, in: mapID) }
    }

    /// How many maps carry each shared tag, for Delete Shared Tag's question.
    func sharedTagMapCounts() async -> [TagID: Int] {
        (try? await repository.sharedTagMapCounts()) ?? [:]
    }

    // MARK: Library

    /// Runs a library action after this map's pending saves, so a save of an
    /// older copy of the tag cannot land on top of it, then applies its
    /// change here at once. Other windows get it from the change stream.
    func libraryAction(_ action: (any SharedTagActions) async throws -> LibraryTagChange) async {
        await flush()
        do {
            applyLibraryChange(try await action(repository))
        } catch let error as LibraryTagError {
            tagFailure = TagFailure(error, in: engine.state)
        } catch {
            Log.persistence.error("A shared tag action failed: \(error.localizedDescription, privacy: .public)")
            tagFailure = .couldNotSave
        }
    }

    /// Follows library tag changes made in other windows, for as long as the
    /// editor is on screen. A change this window made arrives here too and
    /// changes nothing the second time.
    func observeLibraryTags() async {
        for await change in await repository.changes() {
            guard case .tagsChanged(let tags) = change else { continue }
            applyLibraryChange(tags)
        }
    }
}

extension TagFailure {
    init(_ error: LibraryTagError, in state: GraphState) {
        switch error {
        case .invalidName: self = .invalidName
        case .nameTaken(let id): self = .nameTaken(state.tag(id)?.name ?? "")
        case .usedInOtherMaps(let count): self = .usedInOtherMaps(count)
        case .tagNotFound, .wrongScope: self = .couldNotSave
        }
    }
}
