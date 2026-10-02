# ADR 0004: Hierarchy lives in parentID, edges are cross-links

- Status: accepted
- Date: 2026-10-02

## Context

The semantic graph is independent of visual layout (approved decision ADR-009), and edges must not all mean parent-child, so the model can grow toward a knowledge graph. The first sketch had both `MindNode.parentID` and an edge type `hierarchy`.

## Decision

- The tree is `MindNode.parentID` with a fractional `sortOrder`. That is the only record of hierarchy.
- `MindEdge` carries cross-links only: `relationship` and `reference`. More types can be added.
- Canvas positions are never stored on nodes; layout derives them.

## Consequences

- One fact, one record: a sync merge cannot leave the tree and a hierarchy edge disagreeing.
- Moving a node rewrites one record, which keeps CloudKit traffic and conflicts small.
- Rendering code that wants "all lines" combines parent links (derived) and edges (stored).
- Free-form layouts with user positions will need their own per-map layout record, kept apart from the semantic graph.
