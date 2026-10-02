# Canvas

The map on an infinite canvas (MM-3): drawing, pan, zoom, selection, editing a title in place, and culling. Code in `MindMapAI/Features/Canvas/`; visual values from [[design-system]], geometry from [[layout-engine]].

## Where it lives

In the app target, `Features/Canvas`, not yet the `MindMapUI/MindMapCanvas` package that [[module-structure]] plans. The canvas draws with the design system, which is in the app target too, and only the app uses the canvas so far. A package would force both to become `public` API now and move `DesignSystem` out of the app ahead of the Share Extension (MM-11). The canvas code keeps the boundary ready: the camera (`CanvasViewport`), the scene (`CanvasScene`) and measuring (`TopicMeasurer`) take plain values and import no app type, so they can move when PNG/PDF export (MM-10) or another target needs them. PNG/PDF export (MM-10) stays in the app target too and reuses them: it runs its own `CanvasLayoutPass` with `CanvasModel.layoutOptions`, and draws with `CanvasDrawing.make`, `EdgeLayer`, `TopicTitleText` and `CollapseBadgeLabel`, so a change to how the canvas draws a topic reaches exports ([[interchange]]).

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

While AI suggestions exist (MM-8), the pass lays out `SuggestionState.preview(in:)` instead of the map's graph and marks the suggested topics, so they take their place in the tree without being part of the map; every such pass is a full layout. See [[ai-architecture]].

A topic added from anywhere sets `EditorSession.focusRequest`; the canvas takes it, waits for the pass that lays the topic out, scrolls it into view and opens its title (FR-CNV-05).

## Measuring

Only the view knows how a title wraps, so the canvas measures. Each level has a `TopicTextSpec` copied from `Typography.Content` and `CanvasMetrics` (the design-system enums are main-actor isolated, the pass is not). Line spacing is the design's line height minus the font's real line height (ascent + descent + leading), and `TopicView` passes the same value to `lineSpacing`, so measured and drawn heights agree. A point of width slack keeps a title that just fits from wrapping in the view. On iOS and iPadOS the view scales each content size with `UIFontMetrics` for the current Dynamic Type size and the topic draws with `Font.custom(_:fixedSize:)` at that size, so text is scaled once.

## Drawing and culling

- The camera transforms each visible topic (`scaleEffect`, `position`) and the edge layer (`translateBy`, `scaleBy`), so a pan re-runs no topic's body.
- Only topics whose frame meets the visible rectangle plus a quarter of its size on each side are built, and only edges whose control-point box meets it are stroked (FR-CNV-06). The test is a linear scan; the scene works out each curve's box once when it is built, not on every frame.
- Below 30% (`CanvasMetrics.detailZoomThreshold`) titles are under 4 pt and unreadable; topics become filled shapes in the edge layer, so a zoomed-out large map draws one `Canvas`, not hundreds of views. A tap there selects the topic under it; a double tap edits it and zooms back to 100%.
- Zoom to Fit stops at 10%, so a tall map does not always fit: the 1,000-topic test map is 2,487 × 15,812 pt and shows about 680 topics in a 1000 × 700 view.

### First view (FR-CNV-01, MM-84)

- On Mac and iPad a map opens as Zoom to Fit does: the whole map in view with `CanvasMetrics.fitPadding` around it, never above 100%, so a small map opens at actual size in the middle and a large one is not cut off. Only a map that needs less than 10% still overflows (see above).
- On iPhone (compact width) the central topic and its children are fitted to the width, and at accessibility text sizes to the view (`CanvasModel.InitialPlacement`), since the whole map would be too small to read there.
- Until the camera moves (pan, zoom, reveal, editing a title) or the map is edited, the first view is placed again whenever the view size or the layout changes. The window settling at its restored size, the inspector opening or Dynamic Type remeasuring would otherwise leave a map fitted to a size the view no longer has. `viewport`'s `didSet` notices any other camera change and stops this.

### Measured (Mac M1)

`timingsForAThousandTopics` and `frameWorkForAThousandTopics` print these; they do not fail on time. The release column comes from running those two tests with `-configuration Release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO` (the hardened runtime refuses to load the test bundle into a Release app).

| Work at 1,000 topics | Debug | Release |
| --- | --- | --- |
| Measure every title and lay out the whole map | 22–24 ms | 14 ms |
| One rename: re-measure and partial layout | 5–6 ms | 1.8 ms |
| Cull topics and connectors, per frame | 0.23 ms | 0.012 ms |
| Model work per pan frame (cull and build the edge layer's paths) at 100% | 0.28 ms | 0.035 ms |
| The same at Zoom to Fit (10%, ~680 topic shapes) | 1.6 ms | 0.54 ms |

These time the model only. SwiftUI's layout and rendering are not in them, so they are not a frame rate; 60 fps at 1,000 topics (NFR-PERF-01) still has to be checked with Instruments.

## Input

| Input | Mac | iPad, iPhone |
| --- | --- | --- |
| Pan | Two-finger scroll, mouse wheel, drag on empty canvas (open and closed hand pointer) | One-finger drag on empty canvas; two-finger scroll on a trackpad |
| Zoom | Pinch, ⌘-scroll, ⌘+ ⌘− ⌘0, ⌥⌘0 Zoom to Fit, the floating controls | Pinch, the floating controls, hardware keyboard shortcuts |
| Select | Click; ⌘-click toggles, ⇧-click adds; ⌘-drag on empty canvas selects in a rectangle, ⇧-drag adds; ⌘A (Edit ▸ Select All) | Tap (44 pt target around small topics); hold then drag on empty canvas for a rectangle; Add to Selection in the context menu |
| Keyboard (no title being edited) | Return adds a sibling, Tab a child, ⇧Tab promotes, Space renames, arrows walk the map (⇧ adds), Esc keeps only the primary topic | Same with a hardware keyboard |
| Edit title | Double-click, Space, Topic ▸ Rename Topic; Return commits, Esc cancels | Double-tap, Space on a keyboard |
| Move | Drag a topic: middle of a topic drops inside it, top or bottom quarter beside it | Drag a topic |
| Copy, cut, paste | Edit ▸ Cut, Copy, Paste (⌘X ⌘C ⌘V), context menu | Context menu, ⌘X ⌘C ⌘V on a keyboard |
| Delete topic | Delete while the canvas has focus and no title is being edited (a selected suggestion is discarded instead), Topic ▸ Delete Topic | Topic ▸ Delete Topic |
| Canvas or outline | View ▸ As Canvas ⌘1, As Outline ⌘2, toolbar picker | Toolbar picker |

**+ buttons (MM-57, FR-CNV-05, FR-EDT-02).** The hovered topic and the primary selection show a round + on the side away from the parent (add child) and, except on the central topic, one on the bottom edge (add sibling, still [Đề xuất]). Pressing one runs `CanvasModel.addFromButton`, the same `EditorSession.addChild`/`addSibling` as the menu and context menu: one "Add Topic" undo step, and the new topic opens for editing. `CanvasModel.addButtons(for:)` decides which topics show them and on which side; `setHovering(_:part:_:)` takes the hover of the card and of each button apart, since the buttons sit outside the card, and clears the hover only after `Motion.hoverExitDelay` with no part hovered. The buttons are overlaid after the topic's `contentShape`, which would otherwise keep taps off anything outside the card, and the topic showing them is drawn above its neighbours (`zIndex`), as a 44 pt tap area on iOS reaches past the 10 pt sibling gap.

Collapsing a topic that holds the selection selects the collapsed topic, so Delete and Rename never act on a topic nobody sees.

The Mac's scroll events reach SwiftUI's hosting view rather than a background view, so `CanvasScrollInput` watches the window's scroll events and takes those over the canvas. Delete is a menu key equivalent, so it is switched on only while `EditorSession.deleteKeyDeletesTopic` holds: `CanvasModel` reports the canvas's focus and its title editing, the outline reports its own (MM-0i). Delete removes every selected branch as one step. Find (MM-15) selects and reveals each match on the canvas too, and every match gets the `searchMatchFill` and `searchMatchBorder` of [[design-system]] behind its title, drawn outside the measured text so the layout does not move (FR-KBD-06).

## Keys, selection, drag and clipboard (MM-5)

- **Keys the canvas takes itself.** Return, Tab, ⇧Tab, Space, the arrows and Esc are `onKeyPress` handlers on the canvas (`CanvasKeys`), not menu key equivalents: a bare key in the menu bar would never reach a text field. `CanvasModel.handle(_:)` ignores them while a title is being edited, so typing never adds topics (FR-KBD-01). Return adds a sibling as FR-KBD-01 lists; the MM-3 proposal of Return for rename (FR-CNV-04, still [Đề xuất]) moved to Space. Help ▸ Keyboard Shortcuts lists these keys, which neither the menu bar nor the iPad's ⌘ overlay can show.
- **Selection.** `EditorSession.selection` is the primary topic, which single-topic actions use; `selectedIDs` holds every selected topic and setting `selection` selects one. Delete, Duplicate, Cut, Copy and drag act on `selectedBranchRoots` (topics inside another selected branch go with it) as one `BatchCommand`, so one undo step (FR-EDT-04, FR-UND-04). ⌘A selects the visible topics; collapsing a branch moves selected topics inside it to the branch.
- **Modifier clicks are Mac only.** SwiftUI's `Gesture.modifiers` is unavailable on iOS, so on iPad and iPhone a tap selects one topic; touch adds with a hold-and-drag rectangle, ⇧-arrows on a keyboard, or Add to Selection in the context menu.
- **Arrows** follow the tree as drawn (`CanvasScene.neighbour`): away from the central topic goes to the child nearest in height, towards it to the parent, up and down to the next sibling on screen, else the nearest topic of the same level on that side.
- **Drag and drop** is a `DragGesture` on each topic in the canvas's named coordinate space, not system drag and drop, so the drop target updates on every move. The middle half of a topic drops inside it (last child), the top and bottom quarters before and after it; the central topic only takes children. A topic dragged from the selection moves the whole selection. Over the moving branches the drop is refused: a no-entry badge follows the pointer, and dropping plays error feedback and posts an announcement (FR-KBD-04). Dropping into a collapsed topic opens it in the same step, and a drop that changes nothing is no undo step. The source stays at 60% opacity; a copy with the drag shadow follows the pointer; the target gets the dashed accent outline or the 3 pt bar of [[design-system]].
- **Clipboard.** Copy writes the selected branches as a nested Markdown list (`MarkdownOutline.export` with no heading levels, one branch after another), notes as indented paragraphs; paste reads Markdown lists, headings or any indented lines with `InterchangeFormat.markdown.parse` and adds them under the selected topic with one `InsertOutlineCommand` (origin `.user`), then selects the new top-level topics (FR-EDT-14). See [[interchange]]. On the Mac the canvas answers Edit ▸ Cut, Copy, Paste and Select All (`onCopyCommand`, `onCutCommand`, `onPasteCommand`, `onCommand(selectAll:)`); SwiftUI's `copyable`/`pasteDestination` need iOS 27, so on iOS the keys come through `onKeyPress` and the context menu. The session writes through `TextClipboard` (`SystemClipboard` per platform, `MemoryClipboard` in tests), so it does not branch by platform.
- **Context menu** on each topic (FR-KBD-03): Add Child, Add Sibling, Rename, Duplicate, Cut, Copy, Paste, Collapse/Expand, Delete. Opened on a selected topic it acts on the selection, otherwise on that topic alone; Paste goes under the topic it opened on. The AI actions (MM-8) follow; a suggestion keeps its own menu (Accept, Edit, Discard), is selected alone, and is neither dragged nor a drop target.

## Floating topics (MM-62)

The rules are in [[node-organization]] *Floating topics*; the commands are MindMapGraph's (MM-61), named in `EditorSession+FloatingTopics`.

- **Add.** A double-click or double-tap on empty canvas (`CanvasModel.doubleTap`) makes an empty floating topic centred there and opens its title. Topic ▸ Add Floating Topic (⌥⌘↩) and the empty canvas's context menu (Mac only: on touch a hold on empty canvas is the selection rectangle) ask `CanvasModel.freeFloatingSpot()`, handed to the session as `floatingTopicPlacement`: the middle of the view, moved down by `CanvasMetrics.floatingTopicNudge` until a level-1 card there overlaps no topic (at most `floatingTopicNudgeLimit` steps). With no canvas laid out (outline only) it goes `floatingTopicFallbackOffset` below the central topic.
- **Move and detach.** A floating topic dragged alone and dropped on empty canvas stores its new centre ("Move Topic"); a drop over its own branch is not refused for it. Dropped on a topic it attaches there with the MM-5 drop rules. A tree branch dropped on empty canvas with ⌥ held at the drop becomes floating there ("Detach Topic"); without ⌥ the drop stays cancelled. Topic ▸ Detach Topic places it with the Add rule.
- **Attach to Topic…** (Topic menu, context menu, VoiceOver action) opens `AttachFloatingTopicSheet`, listing the outline rows the topic may move under (`canMove`), indented by depth.
- **Disabled on a floating topic:** Add Sibling Topic (adds a child, as on the central topic), Duplicate, Promote, Demote, Detach. The + button for a sibling is not shown.
- **Outline.** Floating branches come after the main tree under a "Floating Topics" section; their rows read "Floating topic" to VoiceOver.

## Accessibility

Each topic in view is one element: label the title, value "Level n, m subtopics" (levels count as the outline does; "Floating topic, m subtopics" for a floating topic), actions Collapse/Expand, Add Child Topic, Add Sibling Topic and Detach Topic (not on the central topic or a floating topic), Attach to Topic… (floating topics only), Rename Topic, Delete Topic. A Topics rotor lists every visible topic of the map, floating branches after the main tree, and scrolls to the one chosen. Adding a topic posts an announcement. Below the detail zoom, empty frames keep the same elements. At accessibility text sizes (iOS, iPadOS) the canvas opens with the central topic and its children fitted to the view (see First view). The outline stays the full alternative (FR-EDT-16).

## Not done yet

- Camera and relayout animation (`Motion.camera`, `Motion.relayout`): the edge layer is not animatable yet, so topics would move while their edges jump. Everything moves at once for now; only the selection ring animates (`Motion.selection`).
- A frame-rate measurement with Instruments on a Mac and an iPad at 1,000 topics, including the empty VoiceOver frames kept below the detail zoom.
- Per-level gaps: `LayoutOptions` takes one horizontal and one vertical gap, so the canvas uses the sub-topic gaps (40, 10) for every level.
- Cross-link labels and cross-links in each topic's accessibility custom content, and links whose end is collapsed (not drawn today): designed in [[node-organization]] for MM-33.
- Auto-scrolling while a drag nears the edge of the view, and moving topics with the keyboard (no shortcut for Move Up/Down yet).
