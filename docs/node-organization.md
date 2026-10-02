# Node organization

How people sort, mark and group topics beyond the tree: tags, colour and symbol, tasks, styled cross-links, boundaries, and the filter bar with Focus on Branch. This is the design for MM-31 to MM-37 (MM-30). The stored fields are in [[data-model]] (*Schema V2*); the research behind it, 14 apps compared on 2026-10-02, is the Hive page [[research-node-features]].

Status: the stored fields, domain values, commands and repair rules are built (MM-31, see [[data-model]] *Schema V2* and [[graph-engine]]); no UI exists for any of this yet, except where *What exists today* says so.

## Principles

1. **The tree stays the structure.** Tags, colours, tasks and boundaries describe topics; they never move them. Hierarchy is still `MindNode.parentID` only (ADR 0004). A boundary is a range of siblings, not a second parent.
2. **Every change is a command.** Tagging, colouring, task fields, link styles and boundaries go through `GraphCommand` and `GraphEngine` with one undo step per user action, named for the Edit menu ([[graph-engine]]). Filters and Focus are view state, never commands.
3. **Colour is never the only signal.** Each colour comes with a shape, a symbol or text (WCAG 1.4.1, [[design-guidelines]]). Priority shows as `!` marks, overdue as a symbol and a word, done as a checkmark.
4. **AI proposes, people accept.** Suggested tags, groups and boundary titles are previews with the AI style; Accept is one command with `origin = ai` and one undo step ([[ai-architecture]]).
5. **Sync can arrive in any order.** New records refer to each other by UUID and survive a missing partner; repair is deterministic, so two devices reach the same result ([[cloudkit-sync]]).

## What exists today

Checked against `main` at `8f28e35`:

| Area | Today | What this design adds |
| --- | --- | --- |
| Outline view | `OutlineEditorView` (MM-0c): one row per visible topic, inline rename, note mark, collapse, Find marks. FR-EDT-16 keeps it as the full alternative to the canvas | Checkbox, symbol, priority, tag chips, due date and boundary bar in each row; the filter applies to it too. No new outline task is needed |
| Inspector | `MapInspectorView` (MM-16): Note, Details (level, subtopics, origin, dates), Map (title, theme) for one selected topic | Tags, Style, Task, Links and Boundary sections, and multi-selection |
| Cross-links | `MindEdge.label` is already in the domain and in `EdgeRecord` (V1); `ConnectNodesCommand` takes a label; `GraphTransaction.updateEdge` exists. `EditorSession.connect`/`removeLink` exist but no menu, canvas gesture or inspector calls them. The canvas draws every link dashed 4–3, with an arrowhead for `reference`; labels are not drawn ([[canvas]], *Not done yet*). A link whose end is hidden in a collapsed branch is not drawn at all (`HorizontalTreeLayout.crossLinks`) | Making, labelling and styling links in the UI; drawing to the nearest visible ancestor |
| Colour | Branch colour from the map theme (`BranchPalette`, MM-18); no colour per topic | `colorToken` per topic, edge, tag and boundary from the same palette |
| Origin | `NodeMetadata.origin` (`user`, `ai`, `imported`), shown in the inspector | A filter by origin; `origin` on tag links and boundaries |
| Search | `MindMapSearch` folds case, Vietnamese marks and đ; Find (⌘F, ⌘G, ⇧⌘G) walks titles and notes | Find and library search also match tag names; the filter's text field reuses the same folding |
| Markdown | Import drops `[ ]`/`[x]` task boxes ([[interchange]]) | Tasks read and write them |
| AI | `SuggestionState` previews suggested topics only | Suggested tags, groups and boundary titles as new suggestion kinds |

## Colour and symbol (MM-32)

- **Colour** is a `TopicColor` token stored as a raw string: `blue`, `teal`, `amber`, `violet`, `rose`, `green` (the Standard branch colours) and `graphite`. `nil` means "follow the theme". A value this build does not know shows as `nil` and is kept in storage.
- A colour set on a topic replaces the branch colour for that topic and for its descendants that have no colour of their own, the way the level-1 branch colour already flows down. It wins over the theme, since the person chose it. Fills, strokes and badges derive from it through `BranchColors`, so the contrast tests of [[design-system]] cover it with no new values.
- **Paired shape.** Each colour has a fixed shape (`circle.fill`, `square.fill`, `triangle.fill`, `diamond.fill`, `hexagon.fill`, `seal.fill`, `capsule.fill` in the order above). The colour menu and inspector show the shape with the colour's name. With Differentiate Without Color on, a coloured topic draws its shape, 9 pt, at the leading edge of the title.
- **Symbol** is one SF Symbol from a curated `TopicSymbol` catalogue (flag, star, lightbulb, question mark, exclamation mark, person, calendar, checkmark, heart, bolt and about 30 more; names checked in the SF Symbols app when building) or one emoji. A string of only `a-z`, `0-9` and `.` is a symbol name; anything else is an emoji, and only the first grapheme is kept. A symbol name this build or OS does not have draws nothing and stays stored.
- **On the canvas** the symbol sits before the title, at the title's cap height, in the topic text colour; the topic is measured with it (`TopicMeasurer` adds its width), so the layout does not move after drawing. Below the detail zoom only the colour shows.
- **Commands.** `SetNodeStyleCommand(nodeIDs:color:symbol:)` sets either or both for one or many topics; one undo step, "Change Color" or "Change Symbol".

## Tags (MM-34)

- **Scope.** A tag belongs to one map (`MindTag.mapID` set) or to the library (`mapID` nil, a "shared tag", offered in every map). New tags are map tags; Make Shared and Make Map Tag move a tag between the two.
- **Fields.** Name, optional colour token and symbol, `sortOrder` for the tag list. A topic's tags are `MindNodeTag` links (node, tag, origin), one record each, so two devices adding different tags to one topic both keep theirs. A list of tag IDs on the node would lose one of them to last-writer-wins.
- **Names.** Trimmed, inner whitespace collapsed to one space, a leading `#` dropped, 1 to 40 characters [Đề xuất]. Two names are the same tag when their **tag key** is equal: Unicode NFC, then case folding without a locale (`folding(options: .caseInsensitive, locale: nil)`), keeping every diacritic. So "Việc", "VIỆC" and a decomposed "việc" are one tag; "việc", "viếc" and "viec" are three, and "đ" is not "d". This is deliberately stricter than search folding: tags are identities, search is forgiving.
- **Commands** (map tags): `CreateTagCommand`, `UpdateTagCommand` (rename, colour, symbol, order), `DeleteTagCommand` (the tag and every link to it), `MergeTagsCommand(into:merging:)` (links move to the survivor, duplicates dropped), `TagNodesCommand(nodeIDs:add:remove:origin:)`. Creating a tag whose key matches an existing one in the same scope uses the existing tag instead. `TagNodesCommand` takes `TagReference.existing(id)` or `.named(text, newTagID:)`, so typing a new name, or accepting AI tags, creates and links in one undo step.
- **Shared tags** are library data, like `isFavorite`: rename, recolour, merge and delete go through the repository's library actions, not a map's undo history. Delete Shared Tag asks first and says how many maps use it. Open maps pick up the change from the repository's change stream. Tagging a topic with a shared tag is still a map command.
- **Search.** Find and library search match tag names with the search folding, so "viec" finds the tag "việc". Typing `#name` in the filter's text field filters by that tag.
- **AI Suggest Tags** (see *AI*).

## Tasks (MM-35)

| Field | Values | Notes |
| --- | --- | --- |
| `taskState` | `nil` (not a task), `open`, `done` | A stored value this build does not know reads as `open`, so it stays a task |
| `priority` | `nil`, 1 high, 2 medium, 3 low | Three levels, shown as `!!!`, `!!`, `!` as in Reminders; a stored value above 3 reads as low |
| `startDate`, `dueDate` | A calendar day or `nil` | Days, not instants, so a due date does not move with the time zone; stored as ISO 8601 `YYYY-MM-DD` |

- **Progress** is computed, never stored: for any topic with task descendants, the done count over the leaf tasks of its branch (tasks with no task below them), drawn as "3/5" with a small ring. A stored progress would conflict across devices and go stale on every child edit.
- **Overdue**: `dueDate` before today in the device's calendar and not done. Drawn with `exclamationmark.circle`, the date in `danger`, and "Overdue" in the VoiceOver value: three signals, one of them colour.
- **Done**: filled checkbox (`checkmark.square.fill`) and the title in `topicTextSecondary`. No strikethrough: it hurts Vietnamese diacritics at small sizes *[Inference]*.
- **Commands.** `SetTaskCommand(nodeIDs:state:priority:start:due:)` with "leave unchanged" for each field, so one command covers Make Task, Mark as Done, a priority key and a date. Removing the task clears state and keeps priority and dates, so Make Task undoes cleanly and toggling back loses nothing.
- **Markdown.** List items export as `- [ ] Title` and `- [x] Title`; heading-level tasks as `## [ ] Title`. Import reads both into `taskState` instead of dropping the box. Plain text writes `[ ] ` and `[x] ` before the title and escapes a title that starts with `[`. Priority, dates, tags, colours, boundaries and link styles are not written to Markdown or plain text: there is no common syntax for them, and an invented one would read as noise in other apps. PNG and PDF draw everything the canvas draws.

## Cross-links (MM-33)

- **Fields.** `label` (exists in V1), `lineStyle` (`solid`, `dashed`, `dotted`), `arrowHeads` (`none`, `end`, `start`, `both`), `colorToken`. `nil` style fields keep today's look derived from `edgeType`: dashed 4–3, an arrow at the end for `reference`, none for `relationship`. Old links therefore draw exactly as before.
- **Making a link.** Topic ▸ Add Link… (⌘K) with a topic selected enters link mode: the pointer becomes a crosshair, a line follows it, and the next topic clicked becomes the target; Esc cancels. On iPad, the topic's context menu has Add Link…, then tap the target. With two topics selected, Add Link links the primary to the other without link mode. The outline and VoiceOver use Add Link… with a target picker sheet that lists topics by path.
- **Editing.** A link is selectable by clicking its line or its label (hit width `Metrics.minimumHitTarget`). Space or double-click edits the label in place; the Delete key removes the selected link. The inspector's Links section lists the selected topic's links (direction, other end, label) with Line, Arrows, Color and Remove.
- **Commands.** `UpdateEdgeCommand(edgeID:label:lineStyle:arrowHeads:color:)` on `GraphTransaction.updateEdge`; Reverse Link swaps the ends. One undo step each ("Edit Link", "Change Link Style", "Reverse Link").
- **Hidden ends.** When an end is inside a collapsed branch or hidden by a filter, the link is drawn to the nearest visible ancestor, at 60% opacity, and that ancestor gets a `link` badge with the count of such links. Today these links vanish. Both ends at the same visible ancestor: not drawn, but the badge counts it.
- **Label** is the capsule of [[design-system]] (*Edges*): on the arc's midpoint, `badge` text, `canvasBackground` fill, stroked in the link colour; it wraps at 160 pt and is measured by the layout pass, so labels do not collide with topics *[Inference]*.

## Boundaries (MM-37)

A boundary is a frame around a run of adjacent siblings and everything under them. A boundary around one branch is a run of one.

- **Fields** (`MindGroup`): `kind` (`boundary` now; `summary` and `zone` reserved), `parentNodeID`, `firstNodeID`, `lastNodeID`, optional `title`, `colorToken`, `origin`. Members are positional: every sibling from first to last in `sortOrder`, so a topic added inside the run joins it and a topic moved out leaves it. This is the model XMind uses; fixed member lists (iThoughts) go stale on every reorder.
- **Not allowed** (the command refuses): the central topic, endpoints with different parents, a run identical to an existing boundary, and a run that crosses another boundary under the same parent (A–C with B–D). Nesting is fine: a boundary inside another's run or deeper in its branch.
- **Kept valid in the same transaction.** `GraphTransaction` fixes boundaries whenever a node is deleted, reparented or reordered, so every command (delete, move, promote, demote, merge, split, drag, cut, AI accept) keeps them valid and undo restores them with the node:
  - an endpoint deleted or moved away: the endpoint moves inward to the nearest sibling that is still in the run;
  - every member gone: the boundary is deleted;
  - an endpoint reordered past the other: the run becomes the siblings now between them;
  - an endpoint reordered within its own run: the boundary keeps the same members, and the outermost of them become the ends (MM-31: without this rule, moving the first topic one place down would drop the topic it passed).
- **Duplicate Branch** copies boundaries whose parent is inside the copied branch; a boundary around the copied topic itself stays with the original.
- **On the canvas.** The frame is the union of the members' laid-out frames (topics and visible descendants) plus `CanvasMetrics.boundaryPadding`, a rounded rectangle with a solid 1.5 pt stroke in the boundary colour (2 pt with Increase Contrast) and a fill at the sub-topic fill opacity, behind edges and topics. Solid on purpose: dashed outlines already mean "AI suggestion" and "drop target". The default colour is `graphite`. The title is a capsule at the frame's top leading corner, `badge` text. The layout engine reserves the padding and title height between the run and its neighbours, so `HorizontalTreeLayout` takes the boundaries as input and returns their frames in `MapLayout.boundaries`. PNG and PDF export draw them through the same layout.
- **Collapse and filter.** A boundary whose parent is collapsed is hidden with it. Members that are collapsed keep the frame around the collapsed cards. Under a filter, the frame shrinks to the visible members and disappears when none are visible.
- **Selection.** Clicking the title capsule or the frame's stroke selects the boundary; Space or double-click renames it; Delete removes it (the topics stay). The inspector's Boundary section has title, colour and Remove Boundary.
- **Commands.** `AddGroupCommand` (caller-chosen `GroupID`, like `AddNodeCommand`), `UpdateGroupCommand`, `RemoveGroupCommand`; "Add Boundary", "Rename Boundary", "Remove Boundary".

## Filter bar and Focus on Branch (MM-36)

- **Filter bar.** View ▸ Show Filter Bar (⌥⌘L) shows a bar under the toolbar, like the Find bar, with: tags (match any or all), priority, task state (open, done, not a task), due (overdue, today, next 7 days, no date), origin (you, AI, import), and text (search folding). Each criterion is a menu button; the bar shows the number of matches.
- **Dim or hide.** Dim keeps the layout and draws non-matching topics at `CanvasMetrics.filteredOpacity` (35% [Đề xuất]). Hide lays out only the matches and their ancestors, so the tree stays connected; ancestors shown only for context use the dimmed style. Hide is a layout input, like collapse, never a change to `isCollapsed`.
- **While a filter is on**, a chip in the toolbar says "Filtered" with the count and a clear button, even when the bar is closed. Clear Filter (⌥⇧⌘L) ends it.
- **What actions reach.** Select All (⌘A) and the rectangle select only topics that are shown (in dim mode, only matches). Tag, colour, symbol and task actions apply to the selection only. Branch actions (delete, cut, copy, duplicate, move) take the whole branch, hidden topics included, exactly as they do for a collapsed branch; the undo name says the count ("Undo Delete 12 Topics"). Find walks only shown topics and says how many more matches the filter hides.
- **Focus on Branch** (⇧⌘F) draws only the selected topic's branch, laid out with that topic in the centre. A breadcrumb of its ancestors sits above the canvas; each crumb focuses there, and Exit Focus (⇧⌘F again, or the chip's clear button) returns. The filter applies inside the focused branch. If the focused topic disappears (deleted, undone, removed by sync), focus ends.
- **Never synced, never in the map.** Filter and focus live in `EditorSession` per window. MM-36 may add them to `EditorRestoration` (MM-17), which is device-local `@SceneStorage`. They are never written to SwiftData or CloudKit: a filter on the Mac must not hide topics on the iPad.
- The filter's predicates (`MapFilter`) live in `MindMapSearch`, next to Find, and return the visible and matching sets from a `GraphState`; the canvas and outline only draw them.

## Where it shows

### Canvas

| Element | Placement | Below the detail zoom |
| --- | --- | --- |
| Checkbox (task) | Before the title, tappable (toggles done) | Hidden |
| Colour shape (Differentiate Without Color) | Before the checkbox | Hidden |
| Symbol | Before the title | Hidden |
| Priority | `!` marks after the title, in the branch colour | Hidden |
| Tags | A row of chips under the title: up to 3, then "+n"; chip fill from the tag colour (badge style), name in `badge` text | Hidden |
| Due date | Caption under the title with `calendar`, `danger` and `exclamationmark.circle` when overdue | Hidden |
| Progress | "3/5" with a ring, after the title | Hidden |
| Topic colour | Fill and stroke as a branch colour | Shown |
| Link badge | `link` with a count on the visible ancestor | Hidden |
| Boundary | Frame and title | Frame only |

Every adornment has a fixed size in `CanvasMetrics` and is measured with the title, so a topic's size is known before it is drawn. Adornments are drawn in content fonts and `Palette` colours, never glass.

### Outline

Each row gets, in order: checkbox, symbol, title, priority marks, tag chips (up to 3), due date. A boundary shows as a 3 pt bar in its colour along the leading edge of its member rows, with its title as a caption above the first member's title. The filter applies to the outline as to the canvas (hide removes rows, dim uses secondary text). Focus on Branch shows the branch only, with the same breadcrumb.

### Inspector

Sections for the selected topic, in order: Note (exists), Tags (a token field with suggestions from map and shared tags, new names offered as "Create Tag"), Style (colour swatches with shapes and names, symbol picker, None), Task (Task toggle, Done, Priority picker, Start and Due date pickers with Clear, progress read-only), Links, Boundary (when the selection is a boundary or inside one), Details (exists), Map (exists). With several topics selected, Tags, Style and Task apply to all of them and show mixed values as such.

### Menus and shortcuts (Mac)

Every item is also in the iPad menu bar. Items that do not apply are disabled, not hidden. Shortcuts were checked against the current menus (`AppCommands`, `FileTransferCommands`, `InspectorCommands`), the standard list in [[design-guidelines]] and the system-wide keys (⌥⌘D Dock, ⌃⌘D Look Up, ⌃⌘Q Lock Screen, ⌃⌘Space Character Viewer). None uses ⌘G, which is Find Next. All are [Đề xuất] until the implementing task confirms them in the menu bar.

| Menu | Item | Key |
| --- | --- | --- |
| Topic | Add Link… | ⌘K |
| Topic | Add Tag… (opens the inspector's tag field) | ⇧⌘T |
| Topic | Tags ▸ the map's most used tags as toggles, Manage Tags… | — |
| Topic | Make Task / Remove Task | ⇧⌘K |
| Topic | Mark as Done / Mark as Not Done | ⌥⌘K |
| Topic | Priority ▸ High, Medium, Low, None | ⌥⌘1, ⌥⌘2, ⌥⌘3; the current priority's key again clears it |
| Topic | Set Task Dates… (opens the inspector's Task section) | ⌥⇧⌘K |
| Topic | Add Boundary / Remove Boundary | ⌥⌘B |
| Format (new, between Edit and View) | Topic Color ▸ None, Blue … Graphite | — |
| Format | Topic Symbol ▸ Choose Symbol…, Emoji & Symbols, None | — |
| Format | Link ▸ Line ▸ Solid, Dashed, Dotted; Arrows ▸ None, At End, At Start, Both Ends; Color ▸; Reverse Link | — |
| Format | Boundary Color ▸ | — |
| View | Show Filter Bar / Hide Filter Bar | ⌥⌘L |
| View | Clear Filter | ⌥⇧⌘L |
| View | Filter Mode ▸ Dim Others, Hide Others | — |
| View | Focus on Branch / Exit Focus | ⇧⌘F |
| AI | Suggest Tags | ⌃⌘T |
| AI | Suggest Groups | ⌃⌘O |
| AI | Summarize Boundary | ⌃⌘Y |

Picker submenus (colours, symbols, line styles) have no keys of their own, as Rewrite Topic ▸ and Promote/Demote do today. Each new key also goes into Help ▸ Keyboard Shortcuts (`KeyboardShortcutsView.groups`), which no test checks against the menus.

Context menus: a topic gains Tags ▸, Task ▸, Color ▸, Add Link…, Add Boundary, Focus on Branch and Suggest Tags; a link has Edit Label, Line ▸, Arrows ▸, Color ▸, Reverse Link, Remove Link; a boundary has Rename Boundary, Color ▸, Summarize Boundary, Remove Boundary.

On iPhone the filter bar is a sheet from the toolbar, the inspector is a sheet as today, and chips show up to 2 tags.

## AI

Three new requests, each a `@Generable` result turned into a proposal, previewed, and accepted as one `BatchCommand` with `origin = ai` ([[ai-architecture]]). They follow the existing rules: on-device only, hidden on ineligible devices, one line of why otherwise, cancellable with ⌘., no retries around the guardrails, and context built by `AIContextBuilder` (chunked with `chunkContexts` when a branch is too large; the chunks' results are merged before the preview, so it is still one Accept and one undo step).

| Request | Input | Output (`@Generable`) | Preview | Accept |
| --- | --- | --- | --- | --- |
| Suggest Tags | Selected topics or the selected branch; the map's and shared tag names (capped) so the model reuses them | Per topic reference: up to 3 tag names | Chips with the AI dashed outline and `sparkles` on each topic; Accept or Discard per chip, Accept All in the suggestion bar | Matching existing tags are reused by tag key; new names become map tags; links get `origin = ai`. "Add AI Tags" |
| Suggest Groups | Children of the selected topic (at least 4) | Groups of 2 or more children (by reference), each with a short title; a child in at most one group | Children shown in their proposed order with AI-dashed boundaries; the bar says how many topics would move | Moves each group's members next to each other (keeping their relative order) and adds the boundaries, `origin = ai`. "Add AI Groups" |
| Summarize Boundary | The boundary's members and their branches | A short title | The title capsule in the AI style, editable before Accept | Sets the title. "Rename Boundary" |

- Topic references in prompts are short temporary IDs (`t1`, `t2`…) mapped back to `NodeID`s by the translator, as for generated topics; an answer naming an unknown reference, repeating a child or making a group of one is dropped by the translator, as malformed proposals are today.
- Suggest Groups reorders topics, so its preview must show the new order before Accept; Discard leaves the order untouched.
- Pro or free: [Đề xuất] free, since the Pro list in [[pricing]] names generation from long descriptions, whole-map summaries and missing ideas, not organizing. Product owner to confirm.

## Accessibility

- **VoiceOver value** of a topic stays short: "Level n, m subtopics", then "task, done" or "task, not done", "priority high", "overdue" when it applies. Tags, dates, colour name, symbol name, links ("Link to Budget, label: depends on") and boundary ("In boundary Phase 1") go to accessibility custom content, read with "more content".
- **Actions** on a topic element: Mark as Done, Add Tag, Add Link, Focus on Branch, beside the existing ones.
- **Rotors**: Topics (exists), Open Tasks, Links, and Matches while a filter is on.
- **Differentiate Without Color**: the colour shape on coloured topics and in tag chips; overdue and priority already carry symbols and marks. Boundaries have titles and a stroke.
- **Increase Contrast**: IC variants of every token, 2 pt boundary and link strokes. **Reduce Motion**: dim, hide and focus changes crossfade through `Motion`.
- Each chip, checkbox and badge has a hit target of `Metrics.minimumHitTarget` on touch, without changing the drawing.
- The outline row reads the same facts in the same order, so the outline remains the full alternative (FR-EDT-16).

## Sync and repair

New records follow the CloudKit rules of [[data-model]]: optional or defaulted properties, no unique constraints, UUID references, raw-string enums with a fallback, record-by-record deletes. What can go wrong and what happens:

| Case | Outcome |
| --- | --- |
| A tag link arrives before its tag, or its tag was deleted on another device | The link is kept but ignored: no chip, no filter match. Repair deletes a link whose tag is still missing 30 days after the link's `createdAt` [Đề xuất], long enough for a late sync |
| A tag link whose node is gone | Deleted by `GraphRepair`, as an edge whose end is gone is today |
| The same tag created on two devices offline ("Việc" and "việc") | Repair merges tags of the same scope with equal tag keys into the oldest (`createdAt`, then ID): links move to it, duplicates are dropped, the other tag is deleted. Shared tags are merged by the library's repair pass on load and after a remote change |
| A map tag and a shared tag with the same key | Both kept (different scopes); the tag field offers the shared one first, and Merge is manual |
| Two links between the same node and tag | The oldest is kept |
| Boundary endpoints no longer siblings under `parentNodeID`, or in the wrong order, after a remote move | Repair shrinks the run to the endpoint still under the parent, swaps endpoints out of order, and deletes a boundary with no member left. Crossing boundaries from two devices are drawn as they are and not repaired |
| An unknown `taskState`, colour, line style or group kind from a newer version | Read with the fallback (`open`, theme colour, derived style, hidden group) and left untouched in storage |

Every rule depends only on stored values, timestamps and IDs, so two devices repair to the same graph. Repair changes are saved, as today, so they run once.

## Not in V2

Listed so later tasks can build on the same records; the fields they need are in [[data-model]] (*Not in V2*).

| When | Feature | Why not now |
| --- | --- | --- |
| V1.x | Summary topics (bracket over siblings, `MindGroup.kind = summary`) | Needs a node type for the summary and layout rules for brackets |
| V1.x | Floating topics and several main topics | Needs stored positions, which the derived layout avoids today |
| V1.x | Saved filters and smart views across maps | Filters are device-local first; a saved view is a new synced record |
| V1.x | Links to other maps and backlinks | Needs `targetMapID` and handling of maps that are deleted or not synced yet |
| V1.x | Structure per branch (logic chart, org chart, timeline) | Needs more layout engines than `HorizontalTreeLayout` |
| V1.x | Numbering (1, 1.1) and per-branch styles | Display rules, best designed with the branch structures |
| V1.x | Presentation and zen mode | View-only; Focus on Branch covers part of it |
| V1.x | Images and attachments | Large data in its own record with external storage, not in a node |
| Later | Board view, Gantt, custom properties, rule-based formatting, zones, callouts, equations and code, ratings and assignees, comments (needs CloudKit sharing) | Rare in the compared apps or depends on sharing |
