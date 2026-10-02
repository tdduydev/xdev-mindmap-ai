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
