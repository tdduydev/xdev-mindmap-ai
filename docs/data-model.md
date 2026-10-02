# Data model

## Domain values

| Type | Fields | Notes |
| --- | --- | --- |
| `MindMap` | id, title, rootNodeID, createdAt, updatedAt, isFavorite, theme, layoutConfiguration, deletedAt | `updatedAt` moves on every edit, undo included. `isFavorite` and `deletedAt` are library data, never set by a command. |
| `MindNode` | id, mapID, parentID, title, note, sortOrder, isCollapsed, nodeType, metadata, createdAt, updatedAt, color, symbol, taskState, priority, startDate, dueDate | No canvas position: layout is derived. |
| `MindEdge` | id, mapID, sourceNodeID, targetNodeID, edgeType, label, createdAt, updatedAt, lineStyle, arrowHeads, color | Cross-links only. |
| `NodeMetadata` | origin (`user`, `ai`, `imported`) | Kept after an AI suggestion is accepted. |
| `MindTag` | id, mapID (nil: shared), name, color, symbol, sortOrder, createdAt, updatedAt | `key` is the tag identity (NFC, case folded, marks kept). |
| `MindNodeTag` | id, mapID, nodeID, tagID, origin, createdAt, updatedAt | One per topic and tag. |
| `MindGroup` | id, mapID, kind, parentNodeID, firstNodeID, lastNodeID, title, color, origin, createdAt, updatedAt | A boundary over a run of siblings; members are positional. |

IDs are typed UUIDs (`MapID`, `NodeID`, `EdgeID`, `TagID`, `NodeTagID`, `GroupID`), so a node ID cannot be passed where an edge ID is expected. They encode as bare UUIDs.

Open-ended stored values (`TopicColor`, `TaskState`, `TaskPriority`, `EdgeLineStyle`, `EdgeArrowHeads`, `GroupKind`) are structs over their raw value, not enums, so a value a newer version wrote survives a round trip through this build; each type says how an unknown value reads (`TaskState.isDone` is false, `TaskPriority.level` clamps to 1–3, `TopicColor.isKnown` is false and the app draws the theme colour). `CalendarDay` is a day with no time zone, encoded as `YYYY-MM-DD`.

## Hierarchy

The tree is `MindNode.parentID` plus `sortOrder`, and nothing else. `MindEdge` holds only `relationship` and `reference` links. Hierarchy is not also stored as edges, because two copies of one fact can disagree after a sync merge (ADR 0004).

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

`GraphValidator` reports four new issues, and `GraphRepair` fixes them after the tree: `danglingTagLink` (topic gone: deleted), `duplicateTagLink` (same topic and tag: the oldest kept), `duplicateTag` (map tags with one key: merged into the oldest, by `createdAt` then ID, links moved), `invalidGroup` (ends not a run under the parent: shrunk to the end still there, swapped if out of order, deleted with no member left). A link whose tag is missing is not an issue; repair deletes it once it is older than `GraphRepair.orphanedTagLinkLifetime` (30 days [Đề xuất]). A group kind this build does not know is never reported or changed. Crossing boundaries are not repaired.

Commands keep the same rules inside `GraphTransaction`, so the engine's validation after each command covers them too: `removeNode` deletes the topic's tag links and the boundaries under it and moves the ends of boundaries it ends inward; `updateNode` does the same when a topic changes parent, and when an endpoint is reordered among its siblings the boundary keeps its members if the topic stays inside the run, otherwise the run becomes the siblings between the two ends. `removeTag` deletes every link to the tag.

### Migration test

`MigrationHarnessTests` keeps opening `V1.store` through the plan, now `[SchemaV1, SchemaV2]` with one stage. MM-31 asserts that the V1 fixture's map, nodes and edge come through with every value, that every V1 map has `deletedAt == nil`, every node and edge has `nil` in the new fields (so it draws as before), and that there are no tags, tag links or groups. `V1Fixture.write` keeps using `SchemaV1` types only. When V2 ships, a `V2.store` fixture with a tag, a shared tag, a tag link, a task, a styled link and a boundary is added the same way, so V3 is tested against real V2 data.

### Not in V2

Kept out on purpose. A property shipped to CloudKit production can never be removed, so fields wait for the feature that uses them:

| Feature | Needs (in a later schema) |
| --- | --- |
| Apple Pencil sketches (MM-9, iPad) | A drawing record with external storage, with attachments |
| Summary topics | `GroupRecord.summaryNodeID` and a `summary` node type |
| Floating topics, several main topics | Node position (`positionX`, `positionY`) and `floating` node type |
| Saved filters and views | A `SavedViewRecord` |
| Links to other maps | `EdgeRecord.targetMapID` |
| Structure per branch | A per-node layout override |
| Images and attachments | An `AttachmentRecord` with external storage |
| Custom properties | Property definition and value records |

## Change stream

`MapRepository.changes()` returns an `AsyncStream<MapRepositoryChange>` with every change committed after the call, in commit order:

| Change | When | Library does |
| --- | --- | --- |
| `.saved(MindMap)` | this repository created a map, saved an edit or set a favorite; carries the summary as stored | adds or replaces the row |
| `.deleted(MapID)` | this repository deleted a map | removes the row |
| `.storeChanged` | someone else wrote to the store: another `ModelContext`, another container or process on the file, later iCloud | fetches the list again |

`.tagsChanged(LibraryTagChange)` carries what a shared tag action stored (`SharedTagActions`: rename, recolour, delete, merge, make shared, make map tag, repair); every open editor applies its part with `GraphEngine.apply(_:)`, and the library refreshes its search, which includes tag names.

Each window's `LibraryModel.observeChanges()` subscribes, then fetches, then applies changes until the window's `RootView` task ends; there is no polling. All windows share one repository, so an edit in one window reaches the others as `.saved`. A summary older than the row (the editor reports an edit before it is stored) keeps the row's title and edit time and takes only the stored favorite flag.

Foreign writes: Core Data posts `NSPersistentStoreRemoteChange` for every commit to the store through any container in the process, the repository's own included. Remote-change notices exist to report commits from other processes too; that case is not tested here. The repository signs its transactions with a per-instance `ModelContext.author`, and on each notice fetches from persistent history only the newest transaction not signed by it (`fetchLimit` 1, newer than the last one reported). Own transactions are never fetched, because loading one loads all its changes. If history cannot be read, it sends `.storeChanged` anyway, since a fetch is always correct. Persistent history is not pruned yet; that belongs with sync.

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
