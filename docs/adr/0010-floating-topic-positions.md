# ADR 0010: Floating topics store their position

- Status: accepted (product owner put floating topics into V1 on 2026-10-02; this records how)
- Date: 2026-10-02
- Amends: the last consequence of ADR 0004

## Context

Until now every canvas position was derived: `HorizontalTreeLayout` places each topic from the tree (`parentID`, `sortOrder`) and measured sizes, and nothing about position is stored (ADR 0004). That keeps sync small and conflict-free: moving a topic rewrites one record, and two devices always draw the same map from the same data.

A floating topic (FR-ORG-27) has no parent, so there is nothing to derive its place from. The person puts it somewhere and expects it to stay there on every device. ADR 0004 expected free-form positions to need "their own per-map layout record, kept apart from the semantic graph".

## Decision

- A floating topic is a node with `parentID == nil` that is not the map's root and has a stored position (`NodeRecord.positionX`, `positionY`). The position is what makes it floating; there is no separate node type.
- Only floating topics store a position. Their descendants, and every topic in the main tree, stay derived. The tree layout lays out each floating branch around its stored point.
- The position is on the node record, not in a per-map layout record. It is the floating topic's centre in canvas points relative to the central topic's centre.
- `GraphRepair` treats a parentless non-root node **with** a position as valid and one **without** a position as a detached branch, as before. A node with both a parent and a position keeps the parent and loses the position.

## Consequences

- One fact still lives in one place: whether a topic is floating is only `parentID == nil` plus a position. There is no flag that can disagree with `parentID` after a merge.
- Moving a floating topic rewrites one node record, as any other edit does. A move on one device and a rename on another resolve by the newest node record, as two edits of one topic always have.
- A per-map layout record would have been one record shared by every floating topic, so moving two of them on two devices would have conflicted, and it could sync before or after the nodes it describes. Keeping the position on the node avoids both.
- The layout is still deterministic and still needs no stored state for the tree. Floating branches can overlap the tree; the layout does not push them apart.
- Positions relative to the central topic survive a change of layout options, but not a change of layout direction (a future left-to-right or org-chart layout may need to transform them). Recorded for whoever adds a second layout engine.
- Full free-form layout (dragging any tree topic anywhere) is still not allowed. If it comes, it needs its own decision; this ADR covers only topics without a parent.
