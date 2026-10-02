# Data model

## Domain values

| Type | Fields | Notes |
| --- | --- | --- |
| `MindMap` | id, title, rootNodeID, createdAt, updatedAt, isFavorite, theme, layoutConfiguration, deletedAt | `updatedAt` moves on every edit, undo included. `isFavorite` and `deletedAt` are library data, never set by a command. |
| `MindNode` | id, mapID, parentID, title, note, sortOrder, isCollapsed, nodeType, metadata, createdAt, updatedAt, color, symbol, taskState, priority, startDate, dueDate, link, position, callout | No canvas position, except a floating topic's (ADR 0010): layout is derived. |
| `MindEdge` | id, mapID, sourceNodeID, targetNodeID, edgeType, label, createdAt, updatedAt, lineStyle, arrowHeads, color | Cross-links only. |
| `NodeMetadata` | origin (`user`, `ai`, `imported`) | Kept after an AI suggestion is accepted. |
| `MindTag` | id, mapID (nil: shared), name, color, symbol, sortOrder, createdAt, updatedAt | `key` is the tag identity (NFC, case folded, marks kept). |
| `MindNodeTag` | id, mapID, nodeID, tagID, origin, createdAt, updatedAt | One per topic and tag. |
| `MindGroup` | id, mapID, kind, parentNodeID, firstNodeID, lastNodeID, title, color, origin, createdAt, updatedAt, summaryNodeID | A boundary, or a summary (MM-65), over a run of siblings; members are positional. |
| `MindImage` | id, mapID, nodeID, data, uniformType, pixelWidth, pixelHeight, byteCount, displayWidth, altText, createdAt, updatedAt; `data` nil unless loaded | One image on a topic, in its own record. |

IDs are typed UUIDs (`MapID`, `NodeID`, `EdgeID`, `TagID`, `NodeTagID`, `GroupID`), so a node ID cannot be passed where an edge ID is expected. They encode as bare UUIDs.

Open-ended stored values (`TopicColor`, `TaskState`, `TaskPriority`, `EdgeLineStyle`, `EdgeArrowHeads`, `GroupKind`) are structs over their raw value, not enums, so a value a newer version wrote survives a round trip through this build; each type says how an unknown value reads (`TaskState.isDone` is false, `TaskPriority.level` clamps to 1–3, `TopicColor.isKnown` is false and the app draws the theme colour). `CalendarDay` is a day with no time zone, encoded as `YYYY-MM-DD`.

## Hierarchy

The tree is `MindNode.parentID` plus `sortOrder`, and nothing else. A floating topic (MM-61) is the top of a second, unattached tree: `parentID` nil and a stored position (ADR 0010); a summary topic (MM-65) is an ordinary child of its run's parent that its summary group names. `MindEdge` holds only `relationship` and `reference` links. Hierarchy is not also stored as edges, because two copies of one fact can disagree after a sync merge (ADR 0004).

### Sibling order

`sortOrder` is a fractional key. A node placed between two siblings gets the midpoint of their keys, so moving or inserting a node rewrites one record. When repeated inserts at one spot exhaust `Double` precision (about 50 halvings), the siblings are renumbered 0, 1, 2… inside the same command, which undo reverses with it.

Ties (two devices giving siblings the same key) sort by `createdAt`, then ID, the same way on every device.

## Stored records (SwiftData)

One record per map, node and edge: `MapRecord`, `NodeRecord`, `EdgeRecord`; since V2 also `TagRecord`, `NodeTagRecord` and `GroupRecord` (see *Schema V2*). A map is never one JSON blob, so sync, conflicts, search and history work per record.

Rules that keep the schema CloudKit-ready:

- Every property has a default value or is optional.
- No unique constraints.
- Records refer to each other by UUID (`mapID`, `parentID`, `sourceNodeID`), not through SwiftData relationships. A node that syncs before its parent is stored as it is; `GraphRepair` decides how to show it.
- Enums are stored as raw strings. A value written by a newer app version on another device falls back to the default (or, for an unknown edge type, the edge is left untouched in storage) instead of making the map unreadable.
- Deletes go record by record, not through batch deletes, which bypass the change tracking CloudKit mirroring relies on.

## Loading a map

```
records ─▶ GraphState(map:nodes:edges:tags:nodeTags:groups:)
                                          duplicates: newest updatedAt wins; other maps' records dropped
        ─▶ GraphRepair.repair             detached branches and loops re-attached under the root;
                                          tag links, duplicate tags and boundaries fixed (see Schema V2)
        ─▶ save repair changes            so the repair does not run again
        ─▶ GraphEngine(state:)            refuses a graph that is still invalid
```

`GraphRepair` never drops a node. It removes only edges whose endpoints are gone, and organization records whose partner is gone (rules under *Schema V2*). Its choices depend on timestamps and IDs only, so two devices repairing the same data reach the same result.

## Migrations

`SchemaV1` and `SchemaV2` are `VersionedSchema`s; `MindMapMigrationPlan` (`MigrationPlan.swift`) lists every shipped schema, and `CurrentSchema` with the `…Record` typealiases there name the schema the app opens. A schema change adds `SchemaV2`, a migration stage and a test that opens a V1 store with the new plan. A shipped schema is never edited in place.

### Migration harness

`MigrationHarnessTests` opens stores that shipped schemas wrote, through `PersistenceController` and so through today's plan, the way an update opens a user's library:

- `currentPlanOpensTheV1Store` copies `Tests/MindMapPersistenceTests/Fixtures/V1.store` to a temporary folder (opening a store can migrate it in place and adds `-wal`/`-shm` files), opens it, and expects exactly the map, nodes and edge listed in `V1Fixture`.
- `migratedStoreKeepsNewEdits` saves a command into the opened store and reads it back from a second container.
- `planEndsAtTheSchemaTheAppOpens` checks that the plan's versions increase, that there is one stage per step, and that the container the app opens uses the plan's last schema.

Since SchemaV2 (MM-31) these tests run through the V1 → V2 stage unchanged, beside `v1StoreOpensAsV2WithEmptyNewFields` and `migratedStoreKeepsOrganization` (see *Migration test* below). Once V2 ships, a `V2.store` fixture is made the same way. The test target copies the whole `Fixtures` folder, so a new fixture needs no change to `Package.swift`.

The V1 fixture is 76 KB: one map (favorite, Graphite theme), a root, a child with a note that is collapsed and came from AI, a sibling, and a reference link between them, with fixed IDs and dates and non-default values where possible, so a stage that resets a field fails the test. `V1Fixture.write(to:)` writes it with the `SchemaV1` types and raw values only, never the current typealiases or mapping, so it still writes V1 after V2 ships. To regenerate it (only if the fixture is lost; a changed V1 fixture would test nothing that shipped):

```sh
MINDMAP_WRITE_V1_FIXTURE=/tmp/V1.store \
  swift test --package-path Packages/MindMapCore --filter writeV1Fixture
sqlite3 /tmp/V1.store 'PRAGMA wal_checkpoint(TRUNCATE);'   # move the WAL into the file
cp /tmp/V1.store Packages/MindMapCore/Tests/MindMapPersistenceTests/Fixtures/V1.store
```

Inspect a copy, not the fixture: `sqlite3` leaves `-shm` and `-wal` files beside whatever it opens.

## Schema V2 (MM-31)

Built in MM-31 (`SchemaV2.swift`); not shipped yet, so it can still change until the first release that writes it. One schema change for everything V1 needs beyond V1: Recently Deleted (MM-19) and node organization (MM-32 to MM-37, designed in [[node-organization]]). One version, so one migration stage, one fixture and one CloudKit schema deployment, instead of a migration per feature. MM-31 builds it; MM-19 and the organization tasks only use its fields.

Everything below is additive: new optional properties and new record types, no rename, no type change, no removed property. SwiftData migrates that with one `MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`, and CloudKit's production schema, which only ever grows, accepts it.

### New properties on V1 records

| Record | Property | Type, default | Meaning |
| --- | --- | --- | --- |
| `MapRecord` | `deletedAt` | `Date?` | Set when the map goes to Recently Deleted (FR-LIB-11, DR-07); `nil` for a live map |
| `NodeRecord` | `colorToken` | `String?` | `TopicColor` raw value; `nil` follows the theme |
| `NodeRecord` | `symbol` | `String?` | SF Symbol name from the catalogue, or one emoji |
| `NodeRecord` | `taskStateRaw` | `String?` | `nil` not a task, `open`, `done`; unknown reads as `open` |
| `NodeRecord` | `priority` | `Int?` | 1 high, 2 medium, 3 low; above 3 reads as low |
| `NodeRecord` | `startDate`, `dueDate` | `String?` | A calendar day, ISO 8601 `YYYY-MM-DD`, so it does not shift with the time zone |
| `EdgeRecord` | `lineStyleRaw` | `String?` | `solid`, `dashed`, `dotted`; `nil` derives the look from `edgeTypeRaw` as V1 draws it |
| `EdgeRecord` | `arrowHeadsRaw` | `String?` | `none`, `end`, `start`, `both`; `nil` derives from `edgeTypeRaw` |
| `EdgeRecord` | `colorToken` | `String?` | `nil` is the `crossLink` colour |

`EdgeRecord.label` is already in V1 and needs no change.

### New records

| Record (domain value) | Properties | Notes |
| --- | --- | --- |
| `TagRecord` (`MindTag`) | `tagID: UUID`, `mapID: UUID?`, `name: String = ""`, `colorToken: String?`, `symbol: String?`, `sortOrder: Double = 0`, `createdAt`, `updatedAt` | `mapID` nil is a shared tag, offered in every map. No unique name: duplicates from offline devices are merged by repair (tag key: NFC, case folded, diacritics kept) |
| `NodeTagRecord` (`MindNodeTag`) | `linkID: UUID`, `mapID: UUID`, `nodeID: UUID`, `tagID: UUID`, `originRaw: String = "user"`, `createdAt`, `updatedAt` | One per topic and tag, so concurrent tagging on two devices merges. `mapID` is the topic's map, also for shared tags, so loading a map fetches its links by `mapID` |
| `GroupRecord` (`MindGroup`) | `groupID: UUID`, `mapID: UUID`, `kindRaw: String = "boundary"`, `parentNodeID: UUID?`, `firstNodeID: UUID?`, `lastNodeID: UUID?`, `title: String?`, `colorToken: String?`, `originRaw: String = "user"`, `createdAt`, `updatedAt` | A boundary over the siblings from first to last under the parent. A kind this build does not know is hidden and kept |

New typed IDs: `TagID`, `NodeTagID`, `GroupID`. Dates default to `Date.distantPast` as in V1. The record names follow V1 (`…Record`); the domain values are `MindTag`, `MindNodeTag` and `MindGroup`, beside `MindNode` and `MindEdge`.

### Rules the new records keep

- The CloudKit rules above: every property optional or defaulted, no unique constraints, UUIDs instead of SwiftData relationships, raw strings with a fallback, deletes one record at a time (deleting a tag deletes each of its links as a record).
- A record whose partner is missing is stored as it is. `GraphRepair` drops tag links whose node is gone, ignores those whose tag is missing (and deletes them after 30 days [Đề xuất]), merges duplicate tags and links, and fixes boundary runs ([[node-organization]], *Sync and repair*). Shared tags are repaired by the library, since no single map owns them.
- Records stay far under CloudKit's 1 MB limit: names, titles and labels are short text; nothing large goes into these records.
- `GraphState` loads a map's tags (its own and every shared tag, since the tag field offers all of them), tag links and groups beside its nodes and edges; `GraphChangeSet` records before and after values for each, so undo, redo and incremental saves work as for nodes. Duplicate records resolve as today: newest `updatedAt` wins. `create` stores only the map's own tags; `deleteMap` deletes the map's tags, links and groups, never shared tags.
- A stored day (`startDate`, `dueDate`) this build cannot parse reads as nil and stays in storage until the topic's day is really changed; the same holds for every raw value above.

### What keeps them valid

`GraphValidator` reports four new issues, and `GraphRepair` fixes them after the tree: `danglingTagLink` (topic gone: deleted), `duplicateTagLink` (same topic and tag: the oldest kept), `duplicateTag` (map tags with one key: merged into the oldest, by `createdAt` then ID, links moved), `invalidGroup` (ends not a run under the parent: shrunk to the end still there, swapped if out of order, deleted with no member left). A link whose tag is missing is not an issue; repair deletes it once it is older than `GraphRepair.orphanLifetime` (30 days [Đề xuất]; named `orphanedTagLinkLifetime` until MM-59). A group kind this build does not know is never reported or changed. Crossing boundaries are not repaired.

Commands keep the same rules inside `GraphTransaction`, so the engine's validation after each command covers them too: `removeNode` deletes the topic's tag links and the boundaries under it and moves the ends of boundaries it ends inward; `updateNode` does the same when a topic changes parent, and when an endpoint is reordered among its siblings the boundary keeps its members if the topic stays inside the run, otherwise the run becomes the siblings between the two ends. `removeTag` deletes every link to the tag.

### Migration test

`MigrationHarnessTests` keeps opening `V1.store` through the plan, now `[SchemaV1, SchemaV2]` with one stage. MM-31 asserts that the V1 fixture's map, nodes and edge come through with every value, that every V1 map has `deletedAt == nil`, every node and edge has `nil` in the new fields (so it draws as before), and that there are no tags, tag links or groups. `V1Fixture.write` keeps using `SchemaV1` types only. When V2 ships, a `V2.store` fixture with a tag, a shared tag, a tag link, a task, a styled link and a boundary is added the same way, so V3 is tested against real V2 data.

### Not in V2

Kept out on purpose. A property shipped to CloudKit production can never be removed, so fields wait for the feature that uses them. Summary topics, floating topics and images moved to *Node types (MM-59)* on 2026-10-02:

| Feature | Needs (in a later schema) |
| --- | --- |
| Apple Pencil sketches (MM-9, iPad) | A drawing record with external storage, with attachments |
| Saved filters and views | A `SavedViewRecord` |
| Links to other maps | `EdgeRecord.targetMapID` |
| Structure per branch | A per-node layout override |
| File attachments, several images per topic | An `AttachmentRecord` with external storage, or a `sortOrder` on `ImageRecord` |
| Custom properties | Property definition and value records |

## Node types (MM-59)

Designed in MM-58 ([[node-organization]], *Node types*); built by MM-59 in `SchemaV2` (in place, see below), the domain and `MindMapGraph`, with no commands or UI (MM-60 to MM-66). *As built* at the end of this section lists where the code differs from or adds to the design. Additive like V2: new optional properties and one new record type.

### V2 or V3

As of 2026-10-02 SchemaV2 is in no uploaded build. [[release]] says the first upload was stopped while sending; the Hive note of MM-55 names a later upload, build `202610021848` from `a9f7028`, and `git ls-tree a9f7028` has only `SchemaV1.swift`. The CloudKit production schema has not been deployed ([[release]], *iCloud before it can ship*). [[release]] should list each upload with its commit, so this check needs no task notes. The rule for MM-59, checked when it starts, not now:

- **No build that contains `SchemaV2.swift` has been uploaded** (to TestFlight or the App Store; check every upload's commit with `git merge-base --is-ancestor <commit-with-SchemaV2> <upload commit>`, the upload commits being listed in [[release]] or App Store Connect): add the fields below to `SchemaV2` in place. No new stage, no new fixture; the V1 → V2 stage and its tests cover them.
- **Otherwise** (a tester may have a V2 store): add `SchemaV3` with the fields, a lightweight V2 → V3 stage, the `V2.store` fixture first (*Migration test* above), and a test that opens it. Editing a shipped V2 in place would change its version hash and the tester's store would no longer open.

Either way, deploying the CloudKit schema to production happens after these fields exist, so production gets them in its first deployment.

### New properties on `NodeRecord`

| Property | Type, default | Domain | Meaning |
| --- | --- | --- | --- |
| `linkURL` | `String?` | `MindNode.link: TopicLink?` | A normalised absolute URL, scheme `http`, `https` or `mailto`, at most 2,048 characters [Đề xuất]. `TopicLink` is a struct over the string: `url` is nil when the string does not parse or the scheme is not allowed, and the string is kept |
| `positionX`, `positionY` | `Double?` | `MindNode.position: TopicPosition?` | The centre of a floating topic in canvas points relative to the central topic's centre, y down. Both set means "has a position"; one alone reads as none. Non-finite reads as 0, values clamp to ±100,000 |
| `calloutText` | `String?` | `MindNode.callout: String?` | Trimmed, blank is nil, at most 280 characters [Đề xuất] |

No new node type. A floating topic is `parentID == nil` with a position, and a summary topic is the node a summary group names, so neither needs a second fact on the node that could disagree with the first after a merge (ADR 0004, ADR 0010). `NodeType` stays `topic`; MM-59 turns it into a `RawRepresentable` struct like `GroupKind` anyway, because today an unknown `nodeTypeRaw` reads as `topic` and is written back as `topic` on the next edit, which would erase a kind a newer build added.

### New property on `GroupRecord`

| Property | Type, default | Domain | Meaning |
| --- | --- | --- | --- |
| `summaryNodeID` | `UUID?` | `MindGroup.summaryNodeID: NodeID?` | For `kind = summary` (new `GroupKind.summary`): the summary topic, a child of `parentNodeID`. Ignored for other kinds |

### New record: `ImageRecord` (`MindImage`)

| Property | Type, default | Meaning |
| --- | --- | --- |
| `imageID` | `UUID` | `ImageID`, a new typed ID |
| `mapID`, `nodeID` | `UUID` | The topic it is on, by UUID, no SwiftData relationship (CloudKit rule above) |
| `data` | `Data?`, `@Attribute(.externalStorage)` | The encoded image after processing (longest side ≤ 2,048 px, no metadata, ≤ 5 MB [Đề xuất]); stored as a file beside the store, not in the SQLite row |
| `uniformType` | `String = "public.heic"` | `public.heic`, `public.png` or `public.jpeg` |
| `pixelWidth`, `pixelHeight` | `Int = 0` | Of the stored data, so layout can size the topic before the bytes load |
| `byteCount` | `Int = 0` | For the inspector and a library-size check, without reading `data` |
| `displayWidth` | `Double?` | Points on the canvas; nil is Medium (160 [Đề xuất]) |
| `altText` | `String?` | The person's description for VoiceOver, at most 250 characters [Đề xuất] |
| `createdAt`, `updatedAt` | `Date = .distantPast` | As every record |

- **Loading.** `GraphState` holds `images: [ImageID: MindImage]` **without** `data`; the repository's `imageData(for:)` reads the bytes when the canvas needs a thumbnail, and save writes `data` only when an image is added or replaced, never on a size or description edit. External-storage attributes are fetched lazily *[Inference: Core Data faults external binary data until accessed; MM-63 measures it]*. The undo change set of an add, remove or replace carries the bytes (*Images* in [[node-organization]]).
- **CloudKit.** With mirroring, external-storage data is synced as a `CKAsset` beside the record *[Unverified: from Apple's description of `NSPersistentCloudKitContainer`; MM-6 confirms with two devices]*, so the 1 MB record limit is not hit; the record itself holds only small fields. Assets count against the person's iCloud storage.
- **Deletes.** Deleting a topic deletes its image record in the same transaction; `deleteMap` deletes the map's images one record at a time, which removes the external files.

### What keeps them valid

New `GraphIssue`s, fixed by `GraphRepair` after the tree and before organization records, all by stored values, timestamps and IDs:

| Issue | Found when | Repair |
| --- | --- | --- |
| (none) | `parentID` nil, not the root, with a position | Not an issue: a floating topic. `GraphValidator.reachableNodes` starts from the root and from every floating topic |
| `detachedBranch` (unchanged) | `parentID` missing, or nil without a position | Moved under the root as today; a position on it is cleared |
| `strayPosition(NodeID)` | A position on a node that has a parent, or on the root | Position cleared (the tree wins) |
| `missingRoot` (rule extended) | No valid root | `rootCandidate` prefers parentless nodes without a position, then branch tops, then floating topics; the chosen node's position is cleared |
| `danglingImage(ImageID)` | Its node is gone | Deleted |
| `duplicateImage(ImageID)` | A second image on one node | Newest by `createdAt`, then ID, kept; others deleted [Đề xuất] |
| `invalidGroup` (extended to summaries) | A summary run that is not a run under its parent | Shrunk or deleted as for boundaries; the summary topic stays as an ordinary child |
| `invalidSummary(GroupID)` | `summaryNodeID` names a node under another parent, or a member of the run, or a topic another summary already names (the oldest group keeps it) | Group deleted, topic kept |
| (none) | `summaryNodeID` names a node that is not there | Drawn as a bracket only; deleted once older than `GraphRepair.orphanLifetime` (30 days [Đề xuất]) |

Links and callouts need no repair: they are fields of the node. Inside commands, `GraphTransaction.removeNode` also removes the node's image and any summary group naming it, `updateNode` clears the position when a parent is set, and the summary-topic exclusions of [[node-organization]] apply to the sibling-run rules of boundaries and summaries.

### As built (MM-59)

- **V2, in place.** Checked on 2026-10-02 against *Uploads* in [[release]]: all four uploads are V1, so the fields went into `SchemaV2` with no new stage or fixture. `SchemaV2.ImageRecord` is the seventh model.
- **Domain.** `TopicLink` (`string`; `url` nil when it cannot be opened; `normalized(_:)` trims, adds `https://` to a bare host, lowercases scheme and host, refuses other schemes, spaces and more than 2,048 characters), `TopicPosition` (clamps, non-finite reads as 0), `MindNode.normalizedCallout(_:)` (trim, 280), `MindNode.isFloating(rootID:)`, `MindImage` with `ImageID`, `normalizedAltText(_:)` (trim, 250), `defaultDisplayWidth` 160, `GroupKind.summary` and `isRun`. `NodeType` is a `RawRepresentable` struct: an unknown `nodeTypeRaw` is kept and written back as it was.
- **Image bytes.** `GraphState.images` never holds `data` (stripped on the way in). Change sets do: `insertImage` records the bytes it was given, an `updateImage` in the same transaction keeps them, a later `updateImage` records none (the repository then leaves the stored file alone: `ImageRecord.update(from:)` writes `data` only when the value has it). A removal records bytes only when they are in `GraphEngine.imageData`, a cache the editor fills from `MapRepository.imageData(for:)`; so MM-64 must load the bytes of an image before any step that can remove it (Remove Image, Delete Topic, Merge, Remove Summary), or undo brings the record back without its file. `create(_:)` stores images without bytes, since the graph has none; a whole-graph copy with images (template, duplicate map) must save them through a change set.
- **`GraphTransaction`.** `insertImage` refuses a second image on a topic (`GraphError.nodeHasImage`), an unknown topic and another map; `updateImage`, `removeImage`. `removeNode` also removes the topic's images and every summary naming it; `updateNode` clears `position` whenever the node has a parent, and a summary topic given another parent loses its summary group. `GraphState.runSiblingIDs(of:)` (children minus summary topics) is the sibling list for `members(of:)`, boundary upkeep and repair; `summaryTopicIDs(under:)`, `summaries(naming:)`, `image(of:)`, `floatingTopicIDs` read the new records. `GraphRecordKey.image` joins the undo pruning of a change from outside; a group's `summaryNodeID` and an image's `nodeID` count as references.
- **Validator and repair**, in this order after the root: stray positions cleared (sorted by ID), detached branches re-attached (their position cleared by `updateNode`), tag rules, expired summaries deleted, `invalidSummary` deleted (topic kept), runs shrunk, then dangling and duplicate images deleted. `invalidSummary` also covers a summary with no `summaryNodeID` at all, which no command writes. A summary topic named by a later summary is a duplicate even if that summary's run is elsewhere under the same parent.
- **Existing commands touched.** `DuplicateBranchCommand` copies `link` and `callout` and points a copied summary at the copied summary topic (images: MM-63, below). `AddGroupCommand` measures runs on `runSiblingIDs`, so a boundary ending on a summary topic is refused (`notSiblings`).
- **Images, as built (MM-63).** `SetNodeImageCommand` and `UpdateImageCommand` (*Images* in [[node-organization]]); a new image without bytes is refused (`GraphError.imageHasNoData`). `GraphEngine` keeps in `imageData` the bytes every step carries, so removing an image added in the same session is undone without the store; for images loaded from the store the editor still fills `imageData` first, and `GraphState.images(inBranchesOf:)` lists what a Delete, Merge or Remove Summary of those topics would remove. `MapRepository.create(_:imageData:)` stores a whole graph with bytes (`create(_:)` passes none); `imageData(of:)` reads every image of a graph. Measured: bytes over SwiftData's inline limit land in a file beside the store (`ImagePersistenceTests`), and a size or description edit leaves that file untouched. `MergeNodesCommand` moves the first merged topic's image to a survivor without one; `DuplicateBranchCommand` copies images whose bytes are in `imageData` and leaves the others out (a record with no file would never fill). `layoutInvalidation` includes a topic whose image changed.
- **Not done here:** the summary topic's place when its group goes ("becomes the last child") is left to `sortOrder`, so MM-65 gives a new summary topic a `sortOrder` after the parent's last child; layout, outline, export, search and AI context still treat a floating topic as unknown (MM-61, MM-62). The map archive (MM-54) carries link, position, callout and `summaryNodeID`; images with their bytes since MM-63 ([[interchange]], *Map archive*).

### Migration test

V1 → (V2 with these fields, or V3): every V1 node has nil link, position and callout, every group nil `summaryNodeID`, no image records. A save-and-reopen test keeps a link, a floating topic, an image with its bytes, a summary and a callout. If V3 is made, the `V2.store` fixture gains no new fields (it is V2 as shipped) and the V3 test opens it.

## Recently Deleted (MM-19)

Deleting a map sets `MapRecord.deletedAt` and keeps every record (FR-LIB-11, DR-07). `deletedAt` is library data like `isFavorite`: `save(_:map:)` never writes it, so an editor still open on the map in another window keeps saving without bringing the map back.

| `MapRepository` | Does |
| --- | --- |
| `fetchMaps()` | Live maps only (`deletedAt == nil`). Intents, the Share Extension (`QuickCapture`) and Spotlight read this, so they never offer a deleted map |
| `fetchDeletedMaps()` | Maps in Recently Deleted, newest deletion first |
| `moveToRecentlyDeleted(_:at:)`, `restoreMap(_:)` | Set or clear `deletedAt` on every record of the map (sync duplicates included); `updatedAt` does not move |
| `deleteMap(_:)` | Deletes the map and all its nodes, edges, tags, tag links and groups, one record at a time |
| `purgeDeletedMaps(deletedBefore:)` | `deleteMap` for every map deleted before the cutoff, in one commit; with nothing due it writes nothing |
| `fetchTopicCounts()` | Topics per map from node records alone, no graph loaded, for `list_maps` (MM-47). Counts deleted maps too; `MapQueries` filters by `fetchMaps()` |
| `loadGraph(for:)` | Still loads a deleted map; `EditorSession.open` returns `.recentlyDeleted` and `QuickCapture.add` throws `mapNotFound` for it |

`RecentlyDeleted.retention` is 30 days of elapsed time, not calendar days. `LibraryModel.load()` purges first, so maps past the period go whenever the app opens or comes back to the foreground; there is no background task. `LibraryModel` keeps live maps in `maps` and deleted ones in `deletedMaps`; search, sections other than Recently Deleted and Spotlight read only `maps`.

Delete in the library is not confirmed, because it can be undone: `LibraryModel.delete(_:undoManager:)` registers "Delete Map" on the window's `UndoManager` (Restore registers "Restore Map"). It is a library action, not a `GraphCommand`, like a favorite. Delete Permanently asks first and has no undo. With iCloud (MM-6), Delete Permanently and the purge delete the records on every device; which device purges first does not matter, since the cutoff only depends on `deletedAt`.

## Change stream

`MapRepository.changes()` returns an `AsyncStream<MapRepositoryChange>` with every change committed after the call, in commit order:

| Change | When | Library does |
| --- | --- | --- |
| `.saved(MindMap)` | this repository created a map, saved an edit, set a favorite, moved a map to Recently Deleted or restored it; carries the summary as stored, `deletedAt` included | adds or replaces the row, in the live list or in Recently Deleted by `deletedAt` |
| `.deleted(MapID)` | this repository deleted a map for good (Delete Permanently, or the 30-day purge) | removes the row from both lists |
| `.storeChanged` | someone else wrote to the store: another `ModelContext`, another container or process on the file, later iCloud | fetches the list again |

`.tagsChanged(LibraryTagChange)` carries what a shared tag action stored (`SharedTagActions`: rename, recolour, delete, merge, make shared, make map tag, repair); every open editor applies its part with `GraphEngine.apply(_:)`, and the library refreshes its search, which includes tag names.

Each window's `LibraryModel.observeChanges()` subscribes, then fetches, then applies changes until the window's `RootView` task ends; there is no polling. All windows share one repository, so an edit in one window reaches the others as `.saved`. A summary older than the row (the editor reports an edit before it is stored) keeps the row's title and edit time and takes only the stored favorite flag.

Foreign writes: Core Data posts `NSPersistentStoreRemoteChange` for every commit to the store through any container in the process, the repository's own included. Remote-change notices exist to report commits from other processes too; that case is not tested here. The repository signs its transactions with a per-instance `ModelContext.author`, and on each notice fetches from persistent history only the newest transaction not signed by it (`fetchLimit` 1, newer than the last one reported). Own transactions are never fetched, because loading one loads all its changes. If history cannot be read, it sends `.storeChanged` anyway, since a fetch is always correct. Each open editor takes `.storeChanged` in too: it loads its map and runs `GraphEngine.takeStored` ([[cloudkit-sync]]), so CloudKit's imports, which are foreign transactions, reach open maps as well as the library. Persistent history is not pruned: CloudKit mirroring reads it, and pruning waits for a measurement on a large store.

## Performance

`PersistenceBenchmarks` times an on-disk store with a 1,000- and a 10,000-topic map (a tree six wide, a note on every tenth topic, a cross-link per hundred). Load is `loadGraph` in a new container, as after a relaunch; open map adds `GraphRepair` and `GraphEngine(state:)`, which is what `EditorSession.open` does before drawing. Saves are `save(_:map:)` for one command: an added topic, and a renamed one. It prints and never asserts times, and is off by default:

```sh
MINDMAP_BENCHMARKS=1 swift test --package-path Packages/MindMapCore --filter PersistenceBenchmarks
# release build: add -c release -Xswiftc -enable-testing
```

Measured 2026-10-02 on the development Mac mini (Apple M1, 16 GB, macOS 27.0.1), three runs per build. Other builds were running on the machine throughout (load average 514 to 642), so these numbers are pessimistic and vary widely between runs. Each cell is the median of the three runs, with the lowest and highest run in brackets; within a run, open map is the median of three opens and a save the median of ten.

| Map | Build | Create, one insert | Open map | First save after open | Save, add / rename | Slowest single save |
| --- | --- | --- | --- | --- | --- | --- |
| 1,000 topics | release | 508 ms (340–514) | 110 ms (106–146) | 9.5 ms (6.3–38) | 4.7 / 5.2 ms | 46 ms |
| 10,000 topics | release | 3.9 s (3.1–12.4) | 739 ms (603–748) | 43 ms (35–49) | 5.9 / 3.8 ms | 49 ms |
| 1,000 topics | debug | 580 ms (188–2,297) | 93 ms (73–679) | 20 ms (15–39) | 9.3 / 7.3 ms | 285 ms |
| 10,000 topics | debug | 3.7 s (2.8–8.4) | 1.07 s (1.00–1.77) | 63 ms (29–79) | 12.5 / 8.3 ms | 87 ms |

Against the targets: in release, opening 1,000 topics (under 500 ms) and 10,000 (under 3 s) held in every run, and every single save stayed under the proposed 50 ms. In debug builds, one run opened 1,000 topics in 679 ms and one save took 285 ms. Creating a whole 10,000-topic map in one insert takes seconds; that is the import and AI generation path, not editing, and has no target yet. Measure again on an idle machine, and with Instruments in MM-12.
