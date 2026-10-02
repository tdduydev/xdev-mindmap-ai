# ADR 0003: Commands with recorded change sets for undo

- Status: accepted
- Date: 2026-10-02

## Context

Every graph mutation must go through commands (approved decision ADR-008), so that undo, redo, AI changes, history and debugging share one path. The first sketch gave each command an `inverse()`. An inverse written per command has to know the state before execution (a delete must restore a whole branch, an update its old values), and it misses side effects such as renumbering siblings or opening a collapsed parent.

## Decision

- A command only describes a change: `execute(in: inout GraphTransaction)`.
- `GraphTransaction` checks each mutation and records the before and after value of every node, edge and map it touches in a `GraphChangeSet`.
- `GraphEngine` validates the resulting graph, commits it and pushes the change set onto history. Undo applies the change set reversed; redo applies it again.
- The same change set tells the repository exactly which records to write.

## Consequences

- Undo and redo are exact for every command, present and future, with no per-command inverse to keep correct.
- Saving is incremental without diffing whole maps.
- A failed command or validation leaves the graph untouched, because the transaction works on a copy.
- History stores values, not intents. Replaying intents (for collaboration) would need the commands themselves, which stay available to record later.
- With sync, a remote change can make a recorded `before` stale; Phase 6 decides how history reacts.
