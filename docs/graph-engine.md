# Graph engine

`MindMapGraph` is the core of the app: a pure Swift module that knows nothing about SwiftUI, SwiftData, CloudKit, AI or screen coordinates.

## Pieces

| Type | Role |
| --- | --- |
| `GraphState` | One map's graph as a value: map, nodes, edges, tags, tag links, groups, and a derived child index in display order. Read-only outside the module. |
| `GraphCommand` | A described change. `execute(in: inout GraphTransaction)` and nothing else. |
| `GraphTransaction` | The working copy a command edits. Checks each mutation and records it in a `GraphChangeSet`. |
| `GraphChangeSet` | Before and after values of every touched node, edge, tag, tag link, group and map. Drives saving and undo. |
| `GraphValidator` | Finds structural issues: missing root, root with a parent, detached branch, parent loop, dangling or self-loop edge, tag link without its topic, duplicate tag link, duplicate map tag, boundary that is not a run of siblings. |
| `GraphRepair` | Fixes those issues without losing a node. Used when loading. |
| `GraphEngine` | Executes commands, validates the result, keeps undo and redo history. |

## Commands

| Command | Does | Refuses |
| --- | --- | --- |
| `AddNodeCommand(.root / .child(of:at:) / .sibling(after:))` | Creates a node with a caller-chosen ID; opens a collapsed parent | A second root, a missing parent, a sibling of the root, an anchor under another parent, a duplicate ID |
| `UpdateNodeCommand` | Sets title, note, collapsed, type or metadata | A missing node. Setting the current value is a no-op. |
| `DeleteNodeCommand` | Deletes nodes with their branches and touching edges; one undo step for a multi-selection | A missing node |
| `ReparentNodeCommand` | Moves or reorders a node with its branch | Moving the root; moving under itself or its own descendant |
| `DuplicateBranchCommand` | Copies a branch with new IDs right after the original; keeps notes, collapsed state, metadata, and links with both ends inside the branch | The root |
| `MergeNodesCommand(into:merging:)` | Folds siblings into the first: their children move under it, their titles and notes are appended to its note, their links move to it (self-links and repeats dropped), then they are deleted | A missing node, a non-sibling, the root |
| `SplitNodeCommand` | One topic per non-blank title line: the first line stays in the original (ID, children, note, links), the rest become siblings after it. One line is a no-op. | The root with several lines |
| `PromoteNodeCommand` | Moves a branch to right after its parent | The root, a child of the root |
| `DemoteNodeCommand` | Moves a branch to the end of its previous sibling, opening it | The root, a first child |
| `ConnectNodesCommand` | Adds a cross-link (relationship or reference, optional trimmed label) | A missing end, a link to itself, the same link (ends, direction, type) twice |
| `RemoveEdgeCommand` | Deletes a cross-link | A missing link |
| `SetAllCollapsedCommand.collapseAll / .expandAll` | Collapses every topic with children except the root, or expands all; leaves untouched | Nothing |
| `RevealNodeCommand` | Opens every collapsed ancestor of a topic, for Find; a visible topic is a no-op | A missing node |
| `RenameMapCommand` | Sets the map's title; the central topic keeps its own | Nothing |
| `SetNodeStyleCommand` | Sets colour and/or symbol on topics (`FieldChange.keep` leaves a field); a symbol is one SF Symbol name or one emoji | A missing node |
| `SetTaskCommand` | Sets task state, priority, start and due day on topics; removing the task keeps priority and days | A missing node |
| `CreateTagCommand` | Creates a map tag with a cleaned name; a map tag with the same key makes it a no-op | A blank or too long name |
| `UpdateTagCommand` | Renames, recolours, sets the symbol or order of a map tag | A shared tag, a name another map tag has, a bad name |
| `DeleteTagCommand` | Deletes a map tag and every link to it | A shared tag, a missing tag |
| `MergeTagsCommand(into:merging:)` | Moves the merged tags' links to the survivor (one link per topic, the older kept) and deletes them | A merged shared tag, a missing tag |
| `TagNodesCommand` | Removes and adds tags on topics; `.named` reuses a tag with the same key (shared first) or creates a map tag; `origin` marks AI tags | A missing node or tag, a bad name |
| `AddGroupCommand` | Adds a boundary over the siblings from one topic to another (either order), caller-chosen `GroupID` | The root, different parents, the same run twice, crossing another boundary |
| `UpdateGroupCommand` | Sets a boundary's title (trimmed, blank is none) and colour | A missing boundary |
| `RemoveGroupCommand` | Removes a boundary; the topics stay | A missing boundary |
| `BatchCommand` | Several commands as one atomic undo step | Anything any part refuses; nothing applies |

`DuplicateBranchCommand` also copies colour, symbol, task fields, tags and the boundaries whose parent is inside the branch; `MergeNodesCommand` moves the merged topics' tags to the survivor. Shared tags are library data: only `TagNodesCommand` touches them through a map. Boundaries are kept valid by `GraphTransaction` whenever a topic is deleted, moved or reordered ([[data-model]], *What keeps them valid*).

Each command only describes its change. `EditorSession` gives each one an undo action name for the Edit menu.

## Execution

```
execute(command)
  transaction = GraphTransaction(state, now: clock())
  command.execute(in: &transaction)        throws → nothing changes
  changes empty?                           → return, history untouched
  GraphValidator.validate(new state)       issues → throw .invalidGraph, nothing changes
  touch map.updatedAt, commit, record changes in history, clear redo
  return changes                           → the caller saves them
```

The full validation after each command is the safety net that keeps a buggy command, or a malformed AI proposal, from saving a broken graph. It is linear in the map size (about 1 ms per command at 1,000 nodes in a debug build). If profiling shows it matters, it can be narrowed to the touched branches.

## Undo and redo

Commands have no hand-written inverse. Undo applies the recorded change set reversed and redo applies it again, so both are exact by construction, including side effects such as renumbering siblings or opening a collapsed parent (ADR 0003). History is linear and capped (200 steps by default).

Shared tags change outside every map's history (library actions, [[node-organization]] *Tags*). `GraphEngine.apply(_ change: LibraryTagChange)` takes such a change into an open map without an undo step and without validating or saving (the repository already stored it). A rename or recolour of a shared tag keeps history, since no step can hold a shared tag's record; a change that moves, deletes or rescopes a tag or link of the map clears history, because undoing across it would replay records the library replaced (for example delete a tag that is shared now).

Once iCloud sync is on, a remote change can touch a node that local history also holds. Phase 6 decides between clearing history on remote changes and rebasing it; until then history assumes it is the only writer.

## Traversal

`ancestors(of:)` (parent first), `descendants(of:)` (pre-order, display order), `siblings(of:)`, `depth(of:)`, `isAncestor(_:of:)`, and `visibleOutline()` (pre-order, skipping the inside of collapsed branches). All are iterative and track visited nodes, so a deep map cannot overflow the stack and a corrupt loop cannot hang the app.
