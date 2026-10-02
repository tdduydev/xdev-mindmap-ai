# Graph engine

`MindMapGraph` is the core of the app: a pure Swift module that knows nothing about SwiftUI, SwiftData, CloudKit, AI or screen coordinates.

## Pieces

| Type | Role |
| --- | --- |
| `GraphState` | One map's graph as a value: map, nodes, edges, and a derived child index in display order. Read-only outside the module. |
| `GraphCommand` | A described change. `execute(in: inout GraphTransaction)` and nothing else. |
| `GraphTransaction` | The working copy a command edits. Checks each mutation and records it in a `GraphChangeSet`. |
| `GraphChangeSet` | Before and after values of every touched node, edge and map. Drives saving and undo. |
| `GraphValidator` | Finds structural issues: missing root, root with a parent, detached branch, parent loop, dangling or self-loop edge. |
| `GraphRepair` | Fixes those issues without losing a node. Used when loading. |
| `GraphEngine` | Executes commands, validates the result, keeps undo and redo history. |

## Commands

| Command | Does | Refuses |
| --- | --- | --- |
| `AddNodeCommand(.root / .child(of:at:) / .sibling(after:))` | Creates a node with a caller-chosen ID; opens a collapsed parent | A second root, a missing parent, a sibling of the root, an anchor under another parent, a duplicate ID |
| `UpdateNodeCommand` | Sets title, note, collapsed, type or metadata | A missing node. Setting the current value is a no-op. |
| `DeleteNodeCommand` | Deletes nodes with their branches and touching edges; one undo step for a multi-selection | A missing node |
| `ReparentNodeCommand` | Moves or reorders a node with its branch | Moving the root; moving under itself or its own descendant |
| `BatchCommand` | Several commands as one atomic undo step | Anything any part refuses; nothing applies |

Later phases add duplicate, merge, split, promote, connect and disconnect as more commands. Each one only describes its change.

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

Once iCloud sync is on, a remote change can touch a node that local history also holds. Phase 6 decides between clearing history on remote changes and rebasing it; until then history assumes it is the only writer.

## Traversal

`ancestors(of:)` (parent first), `descendants(of:)` (pre-order, display order), `siblings(of:)`, `depth(of:)`, `isAncestor(_:of:)`, and `visibleOutline()` (pre-order, skipping the inside of collapsed branches). All are iterative and track visited nodes, so a deep map cannot overflow the stack and a corrupt loop cannot hang the app.
