# Layout engine

`MindMapLayout` in `Packages/MindMapCore` turns a `GraphState` into geometry. It depends on Domain and Graph only, never on SwiftUI, and uses the `CGRect`, `CGPoint` and `CGSize` types that Foundation provides, so the canvas draws the result without converting it.

## Contract

```swift
protocol MindMapLayoutEngine: Sendable {
    func layout(_ graph: GraphState, sizes: [NodeID: CGSize], options: LayoutOptions) -> MapLayout
    func update(_ previous: MapLayout, graph: GraphState, sizes: [NodeID: CGSize],
                options: LayoutOptions, changed: Set<NodeID>) -> MapLayout
}
```

- **Sizes are input.** Only the view knows how a title wraps at the current Dynamic Type size, so the canvas measures topics and passes the sizes in. A topic without a size gets `options.defaultNodeSize`.
- **`MapLayout`** holds a `LayoutNode` per visible topic (frame, side, depth, how many topics a collapsed branch hides), a connector `EdgePath` (cubic Bézier) from each topic's parent, a path per visible cross-link, and the bounds. Coordinates are canvas points, y down, with the central topic centered on the origin.
- **`LayoutOptions`** is geometry: which sides main branches use, the gaps, the fallback size. The user's stored choice of style stays in `MindMap.layoutConfiguration`; `LayoutStyle.engine` names the engine for a style.
- Engines are values with no state, so the canvas can run them off the main actor (NFR-PERF-04).

## HorizontalTreeLayout

- The central topic sits at the origin. Main branches go right and left (`BranchSides.balanced`, the default), or all to one side (`.rightOnly`, `.leftOnly`).
- **Balance** splits the main branches in display order: a prefix goes right, the rest left, choosing the split that makes the visible topic counts closest; on a tie the right side takes the extra branch. Keeping order means a branch changes side only when the balance demands it. This default is still a proposal in the SRS (FR-LAY-02, open question Q10).
- **Reading goes clockwise:** down the right side, then up the left, so the first left branch is the lowest. Children inside a branch always read top to bottom.
- **No overlap with any sizes.** Each branch gets a horizontal band as tall as the branch; sibling bands are stacked with `verticalSpacing` between them, and a topic is centered on its children's block. Children start `horizontalSpacing` past their own parent's edge, so a wide topic pushes only its own branch outward. This is simpler and less compact than contour-based tidy-tree algorithms; it can be swapped for one behind the same protocol if maps look too sparse.
- **Collapsed branches take no space:** their topics are not in the layout, and the collapsed topic reports `hiddenDescendantCount` for the canvas badge.
- **Deterministic:** the walk follows `GraphState`'s display order (sort order, creation time, ID), never dictionary order, so the same graph, sizes and options give the same `MapLayout` on every device.
- Walks use explicit stacks, so a very deep map cannot overflow the call stack.

## Updating one branch

`update` reuses the previous layout for everything the edit did not touch. `changed` must name every topic whose content or measured size changed, plus the old and new parent of every topic that moved or was deleted; `GraphChangeSet.layoutInvalidation` gives that for a command, undo or redo, and the canvas adds topics whose size changed for other reasons (Dynamic Type).

1. The changed topics and their ancestors are measured again; every other branch keeps its measure (band height, topic count).
2. Placement runs from the root, but stops at an untouched branch whose frame, side and depth come out exactly as before, since nothing inside it can have moved.
3. Topics that stopped being visible (deleted, collapsed, moved away) are removed.

A branch that does move is placed with the same arithmetic as a full layout, never shifted by a delta, so an update is bit-for-bit equal to a full layout. Tests check that equality after every kind of edit and after long chains of edits. Changing options or the root falls back to a full layout. Cross-links are recomputed on every pass: a map has few of them, and an edge edit changes no topic.

## Performance

NFR-PERF-06 asks for 1,000 topics under 50 ms and a one-branch update faster than a full layout. `LayoutPerformanceTests` checks both with medians of 15 runs and prints the numbers.
