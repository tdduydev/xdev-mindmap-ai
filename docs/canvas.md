# Canvas

The map on an infinite canvas (MM-3): drawing, pan, zoom, selection, editing a title in place, and culling. Code in `MindMapAI/Features/Canvas/`; visual values from [[design-system]], geometry from [[layout-engine]].

## Where it lives

In the app target, `Features/Canvas`, not yet the `MindMapUI/MindMapCanvas` package that [[module-structure]] plans. The canvas draws with the design system, which is in the app target too, and only the app uses the canvas so far. A package would force both to become `public` API now and move `DesignSystem` out of the app ahead of the Share Extension (MM-11). The canvas code keeps the boundary ready: the camera (`CanvasViewport`), the scene (`CanvasScene`) and measuring (`TopicMeasurer`) take plain values and import no app type, so they can move when PNG/PDF export (MM-10) or another target needs them.

## Parts

| Type | Job |
| --- | --- |
| `CanvasModel` | One per open map, next to `EditorSession`. Holds the scene, the camera and the inline edit; turns gestures into session intents. Never edits the graph itself. |
| `CanvasLayoutPass` | Measures topics and runs the layout engine, off the main actor (`@concurrent`), as plain `Sendable` values. |
| `TopicMeasurer` | CoreText measuring with the font, wrap width and line spacing the topic view draws with. |
| `CanvasScene` | The layout plus the visible topics in reading order; answers culling queries. |
| `CanvasViewport` | The camera: `view = canvas × scale + offset`; pan, zoom about a point, fit, reveal, zoom steps. |
| `CanvasView` | Background (pan, taps), `EdgeLayer`, topic views, floating `CanvasControls`, gestures, rotor. |
| `EdgeLayer` | One SwiftUI `Canvas` for hierarchy edges and cross-links, grouped by colour and width. Below the detail zoom it draws the topics as shapes too. |
| `TopicView` | One card at 100%; the canvas scales and positions it. |
| `MapEditorView` | Canvas or outline for one session, with the shared toolbar, undo wiring and menu focus. |

## Layout in step with the graph

`EditorSession` calls `onGraphChange` with every change set (command, undo, redo). The canvas collects `layoutInvalidation` and runs one pass at a time; edits made while a pass runs go into the next one, so a burst of commands costs one extra pass. A pass:

1. walks `visibleOutline()`, re-measuring a topic only when its title or level changed since it was last measured (a move changes the level of a whole branch, and the level picks the font, so those topics are added to `changed` even though the change set does not name them);
2. calls `engine.update` with the previous layout, or `engine.layout` the first time and when Dynamic Type changes;
3. builds the scene and hands it back to the main actor.

A topic added from anywhere sets `EditorSession.focusRequest`; the canvas takes it, waits for the pass that lays the topic out, scrolls it into view and opens its title (FR-CNV-05).

## Measuring

Only the view knows how a title wraps, so the canvas measures. Each level has a `TopicTextSpec` copied from `Typography.Content` and `CanvasMetrics` (the design-system enums are main-actor isolated, the pass is not). Line spacing is the design's line height minus the font's real line height (ascent + descent + leading), and `TopicView` passes the same value to `lineSpacing`, so measured and drawn heights agree. A point of width slack keeps a title that just fits from wrapping in the view. On iOS and iPadOS the view scales each content size with `UIFontMetrics` for the current Dynamic Type size and the topic draws with `Font.custom(_:fixedSize:)` at that size, so text is scaled once.

## Drawing and culling

- The camera transforms each visible topic (`scaleEffect`, `position`) and the edge layer (`translateBy`, `scaleBy`), so a pan re-runs no topic's body.
- Only topics whose frame meets the visible rectangle plus a quarter of its size on each side are built, and only edges whose control-point box meets it are stroked (FR-CNV-06). The test is a linear scan: 1,000 rectangle tests take microseconds.
- Below 30% (`CanvasMetrics.detailZoomThreshold`) titles are under 4 pt and unreadable; topics become filled shapes in the edge layer, so Zoom to Fit on a 1,000-topic map draws one `Canvas`, not 1,000 views. A tap there selects the topic under it; a double tap edits it and zooms back to 100%.

## Input

| Input | Mac | iPad, iPhone |
| --- | --- | --- |
| Pan | Two-finger scroll, mouse wheel, drag on empty canvas (open and closed hand pointer) | One-finger drag on empty canvas; two-finger scroll on a trackpad |
| Zoom | Pinch, ⌘-scroll, ⌘+ ⌘− ⌘0, ⌥⌘0 Zoom to Fit, the floating controls | Pinch, the floating controls, hardware keyboard shortcuts |
| Select | Click | Tap (44 pt target around small topics) |
| Edit title | Double-click, Return, Topic ▸ Rename Topic; Return commits, Esc cancels | Double-tap, Return on a keyboard |
| Canvas or outline | View ▸ As Canvas ⌘1, As Outline ⌘2, toolbar picker | Toolbar picker |

The Mac's scroll events reach SwiftUI's hosting view rather than a background view, so `CanvasScrollInput` watches the window's scroll events and takes those over the canvas. Return opens the title from the canvas's key handler, not as a menu key equivalent: a bare Return in the menu would never reach text fields.

## Accessibility

Each topic in view is one element: label the title, value "Level n, m subtopics" (levels count as the outline does), actions Collapse/Expand, Add Child Topic, Rename Topic, Delete Topic. A Topics rotor lists every visible topic of the map and scrolls to the one chosen. Adding a topic posts an announcement. Below the detail zoom, empty frames keep the same elements. The outline stays the full alternative (FR-EDT-16).

## Not done yet

- Camera and relayout animation (`Motion.camera`, `Motion.relayout`): the edge layer is not animatable yet, so topics would move while their edges jump. Everything moves at once for now.
- Per-level gaps: `LayoutOptions` takes one horizontal and one vertical gap, so the canvas uses the sub-topic gaps (40, 10) for every level.
- Cross-link labels and cross-links in each topic's accessibility custom content.
- Multi-selection, drag and drop, context menus, arrow-key navigation (MM-5).
