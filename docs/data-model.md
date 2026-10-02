# Data model

## Domain values

| Type | Fields | Notes |
| --- | --- | --- |
| `MindMap` | id, title, rootNodeID, createdAt, updatedAt, isFavorite, theme, layoutConfiguration | `updatedAt` moves on every edit, undo included. |
| `MindNode` | id, mapID, parentID, title, note, sortOrder, isCollapsed, nodeType, metadata, createdAt, updatedAt | No canvas position: layout is derived. |
| `MindEdge` | id, mapID, sourceNodeID, targetNodeID, edgeType, label, createdAt, updatedAt | Cross-links only. |
| `NodeMetadata` | origin (`user`, `ai`, `imported`) | Kept after an AI suggestion is accepted. |

IDs are typed UUIDs (`MapID`, `NodeID`, `EdgeID`), so a node ID cannot be passed where an edge ID is expected. They encode as bare UUIDs.

## Hierarchy

The tree is `MindNode.parentID` plus `sortOrder`, and nothing else. `MindEdge` holds only `relationship` and `reference` links. Hierarchy is not also stored as edges, because two copies of one fact can disagree after a sync merge (ADR 0004).

### Sibling order

`sortOrder` is a fractional key. A node placed between two siblings gets the midpoint of their keys, so moving or inserting a node rewrites one record. When repeated inserts at one spot exhaust `Double` precision (about 50 halvings), the siblings are renumbered 0, 1, 2… inside the same command, which undo reverses with it.

Ties (two devices giving siblings the same key) sort by `createdAt`, then ID, the same way on every device.

## Stored records (SwiftData, schema V1)

One record per map, node and edge: `MapRecord`, `NodeRecord`, `EdgeRecord`. A map is never one JSON blob, so sync, conflicts, search and history work per record.

Rules that keep the schema CloudKit-ready:

- Every property has a default value or is optional.
- No unique constraints.
- Records refer to each other by UUID (`mapID`, `parentID`, `sourceNodeID`), not through SwiftData relationships. A node that syncs before its parent is stored as it is; `GraphRepair` decides how to show it.
- Enums are stored as raw strings. A value written by a newer app version on another device falls back to the default (or, for an unknown edge type, the edge is left untouched in storage) instead of making the map unreadable.
- Deletes go record by record, not through batch deletes, which bypass the change tracking CloudKit mirroring relies on.

## Loading a map

```
records ─▶ GraphState(map:nodes:edges:)   duplicates: newest updatedAt wins; other maps' records dropped
        ─▶ GraphRepair.repair             detached branches and loops re-attached under the root
        ─▶ save repair changes            so the repair does not run again
        ─▶ GraphEngine(state:)            refuses a graph that is still invalid
```

`GraphRepair` never drops a node. It removes only edges whose endpoints are gone. Its choices depend on timestamps and IDs only, so two devices repairing the same data reach the same result.

## Migrations

`SchemaV1` is a `VersionedSchema`; `MindMapMigrationPlan` lists every shipped schema. A schema change adds `SchemaV2`, a migration stage and a test that opens a V1 store with the new plan. A shipped schema is never edited in place.

### Migration harness

`MigrationHarnessTests` opens stores that shipped schemas wrote, through `PersistenceController` and so through today's plan, the way an update opens a user's library:

- `currentPlanOpensTheV1Store` copies `Tests/MindMapPersistenceTests/Fixtures/V1.store` to a temporary folder (opening a store can migrate it in place and adds `-wal`/`-shm` files), opens it, and expects exactly the map, nodes and edge listed in `V1Fixture`.
- `migratedStoreKeepsNewEdits` saves a command into the opened store and reads it back from a second container.
- `planEndsAtTheSchemaTheAppOpens` checks that the plan's versions increase, that there is one stage per step, and that the container the app opens uses the plan's last schema.

When SchemaV2 arrives (MM-19), these tests stay as they are and keep passing through the new stage; MM-19 adds what V2 must hold after migration (for example, an empty `deletedAt` on every V1 map) and, once V2 ships, a `V2.store` fixture made the same way. The test target copies the whole `Fixtures` folder, so a new fixture needs no change to `Package.swift`.

The V1 fixture is 76 KB: one map (favorite, Graphite theme), a root, a child with a note that is collapsed and came from AI, a sibling, and a reference link between them, with fixed IDs and dates and non-default values where possible, so a stage that resets a field fails the test. `V1Fixture.write(to:)` writes it with the `SchemaV1` types and raw values only, never the current typealiases or mapping, so it still writes V1 after V2 ships. To regenerate it (only if the fixture is lost; a changed V1 fixture would test nothing that shipped):

```sh
MINDMAP_WRITE_V1_FIXTURE=/tmp/V1.store \
  swift test --package-path Packages/MindMapCore --filter writeV1Fixture
sqlite3 /tmp/V1.store 'PRAGMA wal_checkpoint(TRUNCATE);'   # move the WAL into the file
cp /tmp/V1.store Packages/MindMapCore/Tests/MindMapPersistenceTests/Fixtures/V1.store
```

Inspect a copy, not the fixture: `sqlite3` leaves `-shm` and `-wal` files beside whatever it opens.

## Change stream

`MapRepository.changes()` returns an `AsyncStream<MapRepositoryChange>` with every change committed after the call, in commit order:

| Change | When | Library does |
| --- | --- | --- |
| `.saved(MindMap)` | this repository created a map, saved an edit or set a favorite; carries the summary as stored | adds or replaces the row |
| `.deleted(MapID)` | this repository deleted a map | removes the row |
| `.storeChanged` | someone else wrote to the store: another `ModelContext`, another container or process on the file, later iCloud | fetches the list again |

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
