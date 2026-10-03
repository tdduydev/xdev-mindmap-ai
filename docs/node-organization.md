# Node organization

How people sort, mark and group topics beyond the tree: tags, colour and symbol, tasks, styled connections (cross-links), boundaries, and the filter bar with Focus on Branch (design for MM-31 to MM-37, MM-30); and the V1 node types: links, floating topics, images, summaries and callouts (design for MM-59 to MM-66, MM-58, *Node types* below). The stored fields are in [[data-model]] (*Schema V2*); the research behind it, 14 apps compared on 2026-10-02, is the Hive page [[research-node-features]].

Status: the stored fields, domain values, commands and repair rules are built (MM-31, see [[data-model]] *Schema V2* and [[graph-engine]]). Tags are built end to end (MM-34, *Tags* below says what was built and how); the other features have no UI yet, except where *What exists today* says so.

## Principles

1. **The tree stays the structure.** Tags, colours, tasks and boundaries describe topics; they never move them. Hierarchy is still `MindNode.parentID` only (ADR 0004). A boundary or a summary is a range of siblings, not a second parent. The only stored position is that of a floating topic, which has no parent to derive one from (ADR 0010).
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
| Cross-links | `MindEdge.label` is already in the domain and in `EdgeRecord` (V1); `ConnectNodesCommand` takes a label; `GraphTransaction.updateEdge` exists. Built in MM-33: Add Connection… (⌘L) with a target picker, canvas selection, in-place label, inspector Connections section, styles, drawing to the nearest visible ancestor with a badge, VoiceOver content, Format ▸ Connection, Markdown export (*Connections* below) | Canvas connect mode; Space to edit a selected connection; a connection's own context menu; Connections rotor |
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

### As built (MM-34)

- **Inspector.** A Tags section under Note (`TagField`): the selection's tags with a remove button each ("Some topics" when only part of a multi-selection has one), and a field. Typing offers matching map and shared tags by search folding, shared first, and "Create Tag “x”" when no tag has the name's key; Return adds the tag with that key or creates a map tag. Every action applies to every selected topic as one undo step: "Add Tag", "Remove Tag".
- **Menus.** Topic ▸ Add Tag… (⇧⌘T) opens the inspector with the cursor in the field; Topic ▸ Tags ▸ has the ten most used tags of the map as toggles (on when every selected topic has it), Add Tag… and Manage Tags…; Topic ▸ Manage Tags… (⌥⇧⌘T) opens the sheet. The topic context menu has Tags ▸ and the AI submenu's Suggest Tags. Both keys are in Help ▸ Keyboard Shortcuts. ⌥⌘T was avoided: it is Show/Hide Toolbar in the standard View menu.
- **Manage Tags** (`TagManagerView`) lists Map Tags and Shared Tags with a topic count each: rename in place, Color ▸ (None and the seven colours with their shapes), Merge Into ▸, Make Shared or Make Map Tag, Delete Tag…. Map tag edits are commands ("Rename Tag", "Change Tag Color", "Merge Tags", "Delete Tag"). Shared tag edits are library actions (`SharedTagActions` on the repository). A shared tag merges only into a shared tag, and becomes a map tag only when no other map uses it (otherwise an alert says how many maps do). Delete asks first; for a shared tag it says how many maps use it.
- **Library actions reach open maps** through `MapRepositoryChange.tagsChanged(LibraryTagChange)`; each editor applies it with `GraphEngine.apply(_:)` without an undo step. A rename or recolour keeps the map's undo history; anything that moves, deletes or rescopes a tag or link in that map clears it, and the window's undo manager with it, since undoing across it would replay records the library replaced. The editor saves its pending edits before a library action. `LibraryModel.load` runs `repairSharedTags()` (same-key shared tags merge into the oldest), so it runs at launch, on return to the foreground and after a change from outside.
- **Canvas.** Chips under the title, measured with it (`TopicMeasurer` sets each chip's width, `ChipFlowLayout` wraps them in the same rows): up to three tags, then "+n", then suggested tags. A tag's chip is its colour's badge (graphite without a colour) and draws nothing interactive, so a click selects the topic. Hidden below the detail zoom with the rest of the card. PNG and PDF draw the same chips. VoiceOver reads tags as custom content ("more content"), not in the value.
- **Outline.** Up to three chips after the title, then "+n", read as one "Tags: …" element.
- **Find.** A topic matches when its title, its note or one of its tag names holds every word; a word written `#name` matches only tags whose folded name starts with it (`#viec #gap`). Library search texts include the names of the tags each map uses.
- **Suggest Tags** (AI ▸ Suggest Tags, ⌃⌘T; also the topic's AI menu): the topic and its branch, or the multi-selection it is part of, up to 12 topics, with the map's and shared tag names (30, most used first). Suggested chips use the AI dashed outline and `sparkles`; clicking one opens its name to edit with Accept Tag and Discard Tag; the bar has Review… (a list by topic), Discard and Accept All. Accepting is one "Add AI Tags" step: one `TagNodesCommand` per name with `origin = ai`, so a new name becomes one map tag for every topic it was accepted on. Hidden on ineligible devices, explained in one line otherwise, as every AI action.
- **Not built yet:** chips limited to two on iPhone; the colour shape in chips with Differentiate Without Color (the name is always there, so colour is not the only signal); the inspector does not show AI suggestions; the outline has no context menu, so tagging there goes through the menu bar and the inspector; the `#name` filter belongs to the filter bar (MM-36).

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

## Connections (MM-33)

A cross-link between two topics is called **Connection** / **kết nối** in the UI (product owner, 2026-10-02), so that "Link" / "liên kết" means only a URL on a topic (*Links* below). In code and storage it stays `MindEdge` / `EdgeRecord` and "cross-link".

- **Fields.** `label` (exists in V1), `lineStyle` (`solid`, `dashed`, `dotted`), `arrowHeads` (`none`, `end`, `start`, `both`), `colorToken`. `nil` style fields keep today's look derived from `edgeType`: dashed 4–3, an arrow at the end for `reference`, none for `relationship`. Old links therefore draw exactly as before.
- **Making a connection.** Topic ▸ Add Connection… (⌘L, also in the topic's context menu, the inspector's Connections section and the topic's VoiceOver actions). With two topics selected it connects the primary to the other at once. Otherwise it opens a target picker sheet listing every other topic, collapsed ones included, with its path ("Plan ▸ Launch") and a search field; picking one adds the connection. Built in MM-33 without the canvas connect mode (crosshair, line following the pointer): the picker is the one path on every platform for now, connect mode is a follow-up. ⌘L follows MindNode's key for the same action; ⌘K is Add Link….
- **Editing.** Clicking or tapping a connection's line selects it (hit width `Metrics.minimumHitTarget` on screen, at any zoom; a topic under the point wins), drawn over in the selection colour; selecting a topic clears it. The Delete key (and Edit ▸ Delete) removes the selected connection. Double-click on the line edits the label in place: a field at the label's spot, Return or leaving it commits one "Edit Connection" step, Esc cancels. Space does not edit a connection yet. The inspector's Connections section (one topic selected) lists the topic's connections, outgoing first ("To Budget" / "From Plan"), each with Label, Line (Solid, Dashed, Dotted), Arrows (None, At End, At Start, Both Ends), Color (Default and the topic colours with their shapes), Reverse Connection and Remove Connection.
- **Commands.** `ConnectNodesCommand` ("Add Connection"), `UpdateEdgeCommand(edgeID:label:lineStyle:arrowHeads:color:)` with `FieldChange` fields on `GraphTransaction.updateEdge` (a blank label is nil), `ReverseEdgeCommand` swaps the ends and refuses when the reversed link already exists, `RemoveEdgeCommand` ("Remove Connection"). One undo step each: "Edit Connection" for the label, "Change Connection Style" for line, arrows and colour, "Reverse Connection".
- **Hidden ends.** When an end is inside a collapsed branch, the layout (`MapLayout.crossLinks`) draws the link to the nearest visible ancestor, lists it in `reroutedCrossLinks` (the canvas draws it at 60%, `CanvasMetrics.reroutedCrossLinkOpacity`) and counts it in `hiddenCrossLinkCounts`, which the canvas shows as a capsule on the ancestor's top-leading corner: `point.topleft.down.to.point.bottomright.curvepath` and the count, `badge` text, `crossLink` colour. Both ends under the same visible ancestor: not drawn, counted once. Ends hidden by a filter follow the same rule once the filter (MM-35) hides topics in the layout.
- **Label** is the capsule of [[design-system]] (*Edges*): on the curve's midpoint (t = 0.5), `badge` text, `canvasBackground` fill, stroked in the connection's colour, wrapping at 160 pt (`CanvasMetrics.connectionLabelMaxWidth`). It is drawn by the edge layer and not measured by the layout, so a long label can overlap a topic.
- **Colour.** `colorToken` nil is `crossLink`; a topic colour uses its line token (`TopicColor.token`) in the current variant, so dark and Increase Contrast come with it. A style value from a newer build draws as the V1 dash or no arrow and stays stored.
- **VoiceOver.** Each topic's custom content "Connections" reads "Connection to Budget, label: depends on; Connection from Plan", and the topic's actions include Add Connection…. The inspector rows read the same description. A Connections rotor is not built yet.
- **Export.** PNG and PDF draw what the canvas draws (styles, arrows, colours, labels, badges). Markdown file export (File ▸ Export…) ends with a thematic break, "Connections:" (localised) and one item per connection with both ends in the export, `- Launch → Budget: depends on`; copy leaves them out. Markdown import drops that trailing block (a `---`, one line ending in ":", then only items with " → "), so the connections never come back as topics. Plain text has none.

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

## Node types (MM-58)

Five additions the product owner put into V1 on 2026-10-02 (FR-ORG-26..31), after the comparison on the Hive page [[research-node-types]]. Built by MM-59 (stored fields, domain values, validator and repair, no commands) and MM-60 to MM-66 (commands and UI). Every change is a `GraphCommand` with one undo step named for the Edit menu, tested for undo and redo; every menu item is disabled, never hidden, when it does not apply; texts go into `Localizable.xcstrings` in `en` and `vi`; sizes, colours and motion come from `DesignSystem` (*Node types* in [[design-system]]). The stored fields are in [[data-model]] (*Node types (MM-59)*).

| Type | What it is | Stored as | Tasks |
| --- | --- | --- | --- |
| Link | One URL on a topic | `NodeRecord.linkURL` | MM-59, MM-60 |
| Floating topic | A topic with no parent that is not the central topic, at a stored position | `NodeRecord.positionX`, `positionY` | MM-59, MM-61, MM-62 |
| Image | One picture on a topic | A new `ImageRecord` with external storage | MM-59, MM-63, MM-64 |
| Summary | A bracket over a run of siblings and a summary topic beyond it | `GroupRecord` with `kind = summary` and `summaryNodeID` | MM-59, MM-65 |
| Callout | A short floating note attached to a topic, not a child | `NodeRecord.calloutText` | MM-59, MM-66 |

### Links (MM-60)

**Behaviour.** A topic has at most one link: a URL with the scheme `http`, `https` or `mailto`. Topic ▸ Add Link… (⌘K) opens a sheet (built in MM-60 as a sheet on every platform, not a popover: the menu has no anchor topic on screen when the outline shows) with one URL field, Cancel and Add (Save and Remove Link when the topic already has one; the item then reads Edit Link…). Topic ▸ Remove Link has no key. Add Link acts on the primary selection only, as Edit Note does. The inspector has a Link section with the same field. The URL is checked as it is typed and on Add:

1. Trim whitespace and newlines; an empty field is "no link".
2. Without a scheme, `example.com/path` becomes `https://example.com/path`, and `name@example.com` (one `@`, no `/`) becomes `mailto:name@example.com`.
3. Parse with `URL(string:encodingInvalidCharacters: true)`, so spaces and Vietnamese letters in the path are percent-encoded. The scheme and host are lowercased; an IDN host is stored as given, not as punycode *[Inference: `URL` keeps it as typed]*.
4. Refused, with the reason under the field: another scheme ("Only web and email links can be added"; covers `file:`, `javascript:`, `data:` and app schemes), `http`/`https` without a host, `mailto` without an address, more than 2,048 characters [Đề xuất] ("This link is too long").

The stored value is the normalised absolute string, so two devices compare and show the same text. A stored value this build cannot parse or whose scheme it does not allow (written by a newer build) shows no link icon, cannot be opened and stays in storage until the topic's link is really changed, as for every raw value.

**On the canvas** the link shows as `link` (`envelope` for `mailto`), 11 pt (`CanvasMetrics.linkSymbolSize`), in the note mark's colour. Built in MM-60 on the card's bottom-trailing corner, mirroring the note mark on the top-trailing one, rather than after the title: it is not measured, so adding or removing a link never resizes the topic or moves the map (same reason as the note mark). Clicking or tapping the icon (hit target `Metrics.minimumHitTarget`) opens it through `openURL` in the default browser or mail app; the pointer is a pointing hand over it and its help tag shows the URL. Topic ▸ Open Link (⇧⌘O) opens the primary selection's link. ⌘-click on the topic does **not** open it, unlike the [Đề xuất] in FR-ORG-26: ⌘-click already toggles selection on the canvas ([[canvas]]). Nothing is fetched: no preview, no favicon, no title lookup ([[privacy]]). The outline shows the same icon after the title.

**Commands.** `SetNodeLinkCommand(nodeIDs:link:)` with `TopicLink?`; the session names it "Add Link" (none before), "Edit Link" or "Remove Link". Setting the same value is a no-op. Duplicate Branch, Split (stays on the first topic) and Merge (the survivor keeps its own, else takes the other's) carry it like the note.

**Context menu.** Add Link…, or Open Link, Edit Link… and Remove Link.

**VoiceOver.** Custom content "Link: example.com" (the host, or the address for `mailto`, never the full URL with its query); action Open Link. Outline row the same.

**Export.** Markdown writes the title as a link: `- [Title](https://example.com)`, `## [Title](url)`, with a task `- [ ] [Title](url)`; brackets in the title and `)` in the URL are escaped. Import reads a heading or list item whose whole text is one inline link with an allowed scheme back into title and link; any other inline link stays text. Plain text writes `Title <https://example.com>` and reads a trailing `<…>` with an allowed scheme back (built in MM-60). A Markdown title that is link markup but has no link is written with a leading backslash (`\[a](b)`), so it reads back as text. Copy and paste go through Markdown, so they carry the link. The task box form is not written yet: Markdown export has no tasks. PNG and PDF draw the icon; the PDF also gets a link annotation over it [Đề xuất, if `ImageRenderer` cannot, drop it]. AI context and MCP: the link is not sent to the on-device model; `get_topic` returns it [Đề xuất].

**Sync and repair.** One optional field on the node record, so it merges with the rest of the node (newest record wins, as for the title). Nothing to repair.

### Floating topics (MM-61, MM-62)

**What it is.** A topic whose `parentID` is nil, that is not the map's central topic, and that has a stored position (`position` set). Its own children are ordinary: hierarchy below it is `parentID` as everywhere, laid out by the tree layout. The map still has exactly one central topic (FR-EDT-01); a floating topic is not a second root of the map, and nothing (title, Generate Map, export file name) takes it for the central topic. Only the floating topic stores a position; its descendants never do (ADR 0010).

**Position.** `position` is the floating topic's centre in canvas points relative to the central topic's centre, y down, the coordinates `MapLayout` already uses. So the map can move as a whole and a floating topic keeps its place beside the tree. It is stored as two `Double`s; a non-finite value reads as `(0, 0)`, and values are clamped to ±100,000 pt [Đề xuất].

**Behaviour.**

- **Create.** Double-click (Mac) or double-tap (iPad, iPhone) on empty canvas makes a floating topic centred at that point and opens its title for typing; an empty title on Return or Esc deletes it again, the way a new topic does. Topic ▸ Add Floating Topic (⌥⌘↩), and Add Floating Topic in the empty canvas's context menu, put it at the centre of the visible canvas, moved down in steps of `CanvasMetrics.floatingTopicNudge` (24 pt) [Đề xuất] until it overlaps no laid-out topic.
- **Move.** Dragging a floating topic moves it with its branch; dropping it on empty canvas stores the new position ("Move Topic"). The drop indicator for reparenting (MM-5) shows only when the pointer is over a topic, so a free move never reparents by accident.
- **Attach.** Dropping a floating topic on a topic makes it a child there, with the drag rules of MM-5 (not onto its own branch). Topic ▸ Attach to Topic… is the non-drag way: a picker sheet that lists topics by path, also offered to VoiceOver and the outline.
- **Detach.** Dragging a branch out of the tree onto empty canvas with ⌥ held [Đề xuất: a plain drag to empty canvas stays a cancelled drag, as today in MM-5, so nothing changes for people who drop by mistake] makes its top a floating topic at the drop point. Topic ▸ Detach Topic does it without a drag and places it with the Add Floating Topic rule. Not allowed on the central topic.
- **Edit like any topic.** Add Child Topic, rename, note, collapse, tags, colour, task, link, image, callout, connections, boundaries and summaries inside its branch, Delete (deletes the branch). Add Sibling Topic, Promote and Demote are disabled on the floating topic itself (no parent), as on the central topic; a boundary or summary cannot include it.
- **Colour.** A floating topic is drawn with the main-topic style (level 1) and takes the next branch colour after the main topics, in creation order; a `colorToken` overrides it.
- **Layout.** `HorizontalTreeLayout` lays out the main tree as today, then each floating topic's branch as its own tree around its stored position, children to the right [Đề xuất]. The layout does not push the tree and floating branches apart: they can overlap, as in XMind, and the person moves the floating topic. The order (floating topics by `createdAt`, then ID) is fixed, so layout stays deterministic. Map bounds, Zoom to Fit and export include them.
- **Find, Select All, rotors, library search, MCP and AI** include floating branches. `AIContextBuilder` treats a floating topic as a topic without ancestors; Generate Map never makes one.

**Commands** (MM-61, built): `AddFloatingTopicCommand(nodeID:title:position:)` "Add Floating Topic"; `MoveFloatingTopicCommand(nodeID:to:)` "Move Topic"; `DetachBranchCommand(nodeID:position:)` "Detach Topic"; attaching goes through `ReparentNodeCommand`, which clears the position in the same update ("Move Topic"). `DeleteNodeCommand` needs no change. Each with undo and redo tests. Also built in MM-61 without UI: the layout, Find, `MapQueries` (MCP, chat; outline rows carry `isFloating`), library search, `AIContextBuilder` (tests only: it already gave no ancestors or siblings), `visibleOutline()` and Markdown/plain-text export. The canvas, menus, outline section and VoiceOver are MM-62 (built; see [[canvas]] *Floating topics*).

**Outline.** After the main tree, a section "Floating Topics" with each floating branch as a top-level row, ordered as in the layout. Reordering rows there changes nothing stored (they have no `sortOrder` among each other).

**VoiceOver.** Value "Floating topic, m subtopics"; actions Attach to Topic, Detach Topic (on tree topics); the Topics rotor lists floating topics after the main tree.

**Export.** PNG and PDF draw them where they are. Markdown and plain text write the main tree, then each floating branch as a further top-level item (`#` heading or top-level list item) [Đề xuất]. Import keeps today's rule (several top-level items become children of a new central topic), so a round trip turns floating topics into main topics; FR-IO-03's round trip holds for maps without floating topics. Making extra top-level items floating on import would change MM-10a's rule and is left to the product owner.

**Sync and repair.** How `GraphRepair` tells a floating topic from an orphaned branch, deterministically:

| Stored node | Today | With floating topics |
| --- | --- | --- |
| `parentID` points to a node that is not there | Detached branch, moved under the central topic | Same. A missing parent means the branch belongs in the tree; a stored position on it is cleared |
| `parentID` nil, not the root, no position | Detached branch, moved under the central topic | Same: only a position makes a topic floating |
| `parentID` nil, not the root, with a position | Detached branch | Floating topic, valid, left alone |
| `parentID` set and a position | — | The tree wins (ADR 0004): the position is cleared (new issue `strayPosition`) |
| The root ID missing or pointing to nothing | `rootCandidate`: oldest parentless node, then oldest branch top, then oldest node | Parentless nodes **without** a position first; a floating topic becomes the root only if there is no other candidate, and its position is cleared |
| A floating topic inside a loop | Loop cut at its most recently edited node | Same rule, unchanged |

A move on one device and a rename on another resolve by the newest node record, as for any two edits of one topic.

### Images (MM-63, MM-64)

**Behaviour.** A topic has at most one image [Đề xuất: one per topic keeps layout and VoiceOver simple; several would be a later `sortOrder` on the same record]. Ways to add one, all ending in the same command:

- Drag an image file (or an image from Photos or Safari) onto a topic; onto empty canvas it makes a floating topic with the image and an empty title [Đề xuất].
- Paste (⌘V) with a topic selected when the pasteboard holds an image and no branch or text: a branch or text paste keeps its current meaning (MM-5).
- Topic ▸ Add Image… (⌥⌘I): on the Mac a file panel (`fileImporter`, image types); on iPad and iPhone `PhotosPicker`, which runs out of process and needs no Photos permission, plus Files on iPad.
- With an image already there, the item reads Replace Image….

**Processing** (`MindMapImages` in the core package [Đề xuất name], ImageIO and Core Graphics, no platform branch, off the main actor): decode, apply the EXIF orientation, scale so the longest side is at most 2,048 px (FR-ORG-28 [Đề xuất]), re-encode as HEIC at quality 0.8, or PNG when the image has transparency [Đề xuất: HEIC decodes on every OS 26 device; JPEG is the fallback if MM-63 finds a gap]. Re-encoding from pixels without copying the source properties drops GPS, EXIF, maker notes and the file name. An encoded result over 5 MB is refused ("This image is too large") [Đề xuất]. An unreadable file is refused with "This file isn't an image the app can read".

*As built (MM-63):* `ImageProcessor` in `MindMapImages`, `process(_:)` is `@concurrent`. The thumbnail call (`CGImageSourceCreateThumbnailAtIndex` with the transform) applies the orientation, subsamples large files and takes the first frame of an animation; the pixels are drawn into an 8-bit RGBA bitmap (Display P3 kept, other spaces to sRGB) and encoded with only the compression quality, so no source property reaches the file (tested: GPS, TIFF maker and model, EXIF capture date and comment gone). PNG only when a pixel is actually see-through: a screenshot with an opaque alpha channel becomes HEIC. JPEG where HEIC cannot be written *[Unverified on the iOS Simulator and older devices: the fallback is there, untested there]*. Files over 200 MB are refused before decoding (`tooLarge`). Errors: `ImageProcessingError.unreadable`, `.tooLarge`; `ProcessedImage.image(mapID:nodeID:…)` makes the `MindImage` for the command.

**On the canvas.** The image sits above the title inside the card, at its display width (Small 96, Medium 160, Large 240 pt [Đề xuất], default Medium, never wider than the level's maximum width), aspect ratio kept, height at most 1.5× the width (cropped to fill), corner radius `CanvasMetrics.imageCornerRadius`. It is decoded as a thumbnail at the display size (`CGImageSourceCreateThumbnailAtIndex`) and cached by image ID, so a large map does not hold full images. Size changes through Format ▸ Image Size ▸ and the inspector, not by dragging handles in V1. Below the detail zoom it is a filled placeholder of the same frame. The layout measures the topic with the image frame, known from the stored pixel size before the bytes load, so nothing jumps (MM-63: `MindImage.displaySize(maximumWidth:maximumAspect:)`, `TopicMeasurer.imageSize(of:level:)`, `TopicMeasure.imageSize` in the cache key; drawing it is MM-64).

**Inspector.** An Image section: the preview, Size, Description (a text field, up to 250 characters [Đề xuất], "Describe the image for VoiceOver"), Replace Image… and Remove Image.

**Commands.** `SetNodeImageCommand(nodeID:image:)` with a `MindImage` (new or replacing) or nil: "Add Image", "Replace Image", "Remove Image"; `UpdateImageCommand(imageID:displayWidth:altText:)` (`FieldChange`s): "Change Image Size", "Edit Image Description". The change set keeps the whole `MindImage` including its bytes, so undoing Remove Image or Delete Topic brings the image back without a file; the cost is memory in the undo stack, at most the 5 MB cap per step. Deleting a topic deletes its image in the same transaction. Duplicate Branch copies the image to a new record (same bytes, new ID); Merge keeps the survivor's image, else takes the other's; Split leaves it on the first topic.

**Context menu.** Add Image…, or Replace Image…, Image Size ▸ and Remove Image.

**VoiceOver.** The image is not a separate element; the topic's custom content says "Image: <description>" or "Image, no description". The outline row shows a `photo` symbol after the title and reads the same.

**Export.** PNG and PDF draw the image at its canvas size; `MapPicture` and `StaticTopicCard` (MM-10) must draw it like `TopicView`. Markdown and plain text leave images out [Đề xuất]; they have no file to point to. Copy of a branch puts the images in the app's own pasteboard type only.

**Privacy.** Image bytes and descriptions are map content: never logged, never sent to the model (Foundation Models is not given images in V1). `PhotosPicker`, `fileImporter`, drag and paste need no usage string and no required-reason API *[Inference: checked against the required-reason categories; MM-64 confirms when it adds the code]*. iCloud storage of images uses the person's own iCloud quota.

**Sync and repair.** The image is its own record (`ImageRecord`), so the node record stays small and an image edit does not conflict with a title edit. It refers to its node by `nodeID`. An image whose node is gone is deleted (`danglingImage`). Two images for one topic (added on two devices offline) keep the newest by `createdAt`, then ID; the others are deleted (`duplicateImage`) [Đề xuất: the rare loss of one of two pictures is accepted to keep one image per topic; the product owner may prefer keeping both]. A node whose image has not arrived yet draws without it, and grows when it arrives.

### Summaries (MM-65)

**What it is.** A bracket (`}` facing away from the parent) beyond a run of adjacent siblings, and a summary topic beyond the bracket that sums them up. The run is positional, with the same rules as a boundary (FR-ORG-13, 14): first and last sibling under one parent, members are every sibling between them, nesting allowed, crossing another summary under the same parent refused. Not allowed on the central topic or on a floating topic itself (no parent); allowed over main topics only if they are on the same side of the central topic.

**Where the summary topic lives** (keeps ADR 0004). The summary topic is an ordinary node whose `parentID` is the run's parent, so it is in the tree: reachable, deleted with the parent's branch, moved with it, found by Find, exported. The group record names it in `summaryNodeID`. What makes it a summary topic is that a live summary group names it, nothing on the node, so there is one fact in one record. A summary topic is left out of its parent's child column, out of sibling runs (it is never a member of a boundary or summary under that parent), and out of Add Sibling, Promote, Demote and reorder targets among those siblings. If its group disappears it becomes the parent's last child: nothing is lost. Its own children are ordinary, laid out outward from it.

**Behaviour.** Select a run of siblings (or one topic), Topic ▸ Add Summary (⌥⌘]): the bracket appears and the summary topic opens for typing with the placeholder "Summary". It renames, gets children, notes, tags, colour, link, image and callout like any topic. Selecting the bracket (click it, hit width `Metrics.minimumHitTarget`) and pressing Delete, or Topic ▸ Remove Summary, removes the bracket and the summary topic with its branch in one step. Deleting the summary topic removes the bracket too.

**Layout.** The bracket spans the run's laid-out frames (members and their visible descendants), placed `CanvasMetrics.summaryBracketGap` beyond the outermost edge of those frames, so it clears the widest member branch; the summary topic is centred on the bracket's tip at the main-to-sub gap beyond it. The layout reserves no extra vertical space; the summary branch takes the vertical room it needs beside the run and pushes later siblings only if it is taller than the run [Đề xuất]. `HorizontalTreeLayout` takes summaries as input, like boundaries, and returns their bracket paths in `MapLayout.summaries`.

**Kept valid** as boundaries are (MM-37, *Boundaries*): endpoints deleted or moved move inward; a run with no member left deletes the group, and the summary topic stays as an ordinary last child [Đề xuất: no topic is ever deleted by a rule the person did not trigger]; reordering follows the boundary rules; Duplicate Branch copies summaries whose parent is inside the copied branch, with a copy of the summary topic.

**Commands.** `AddSummaryCommand(groupID:nodeID:parent:first:last:title:)` adds the group and the summary topic (caller-chosen IDs, so the session can start editing it): "Add Summary". `RemoveSummaryCommand(groupID:)` removes the group and the summary topic's branch: "Remove Summary". Deleting the summary topic through `DeleteNodeCommand` removes its group in the same transaction. Renaming is `UpdateNodeCommand` ("Rename Topic").

**Context menu.** On a selected run: Add Summary. On the bracket: Remove Summary. The summary topic has the topic menu.

**VoiceOver.** The summary topic's value: "Summary of <first> to <last>, m subtopics" (one member: "Summary of <title>"); members get "In summary <title>" in custom content. The bracket is not an element; Remove Summary is an action on the summary topic. The outline shows the summary topic as a row right after the run's last member, at the members' level, with a `curlybraces` [verify name] mark and a caption "Summary of n topics".

**Export.** PNG and PDF draw bracket and topic. Markdown and plain text write the summary topic as the parent's child right after the run's last member, with no mark [Đề xuất], so its text and children survive; import does not rebuild the bracket.

**Sync and repair.** Same rules as boundaries for the run (`invalidGroup`). Added for summaries: a summary group whose `summaryNodeID` is missing is drawn as a bracket only and deleted by repair once it is older than the orphan lifetime (30 days [Đề xuất], as tag links), since the topic may still be syncing; a summary topic whose `parentID` is no longer the group's parent (moved on another device) stays where its parent says and the group is deleted (`invalidSummary`); two summary groups naming one topic keep the oldest. A summary group kind unknown to an older build is hidden and kept, as `GroupKind` already does, and the topic it names shows as a plain last child there.

### Callouts (MM-66)

**What it is.** One short text attached to a topic, shown in a bubble above it with a tail pointing to the topic. It is a property of the topic, not a child, not a node: no children, no tags, no links, no connections [Đề xuất in FR-ORG-30, kept]. Up to 280 characters [Đề xuất], one line or wrapped at the topic's maximum width.

**Why a property and not a node or record.** A callout node would sit in every tree walk (counts, Find, Markdown, AI context, outline levels) and need filtering everywhere; a separate record would need its own repair and a cascade on delete. A text field on the node is deleted with the topic, copied with it, undone with it, and needs no repair. If callouts ever need children or styling, a later schema can move them to records.

**Behaviour.** Topic ▸ Add Callout (⌥⇧⌘↩) adds an empty bubble with the text field open; an empty text on Return or Esc removes it again. Clicking the bubble selects it (selecting the callout, not the topic), Space or double-click edits it in place, Delete removes it. The inspector shows it under Note as Callout with a field and Remove Callout. Hidden when the topic is hidden (collapsed parent, filter).

**Layout.** The bubble is centred above its topic. FR-ORG-30 asked that it not take room in the tree; a bubble drawn over the tree would cover the sibling above, so this design **reserves** its height: the layout measures the topic's slot as bubble + `CanvasMetrics.calloutGap` + card, and the connector still attaches to the card's centre. The tree therefore moves when a callout is added, the same way it does when a title wraps. This is a change to FR-ORG-30 for the leader to carry into the SRS.

**Commands.** `SetCalloutCommand(nodeIDs:text:)`: "Add Callout", "Edit Callout", "Remove Callout". Trimmed; blank is none. `DeleteNodeCommand` needs nothing: the text goes with the node. Duplicate copies it; Merge keeps the survivor's, else the other's.

**As built (MM-66).** `EditorSession.calloutEditorTarget` opens the bubble on the canvas (switching from the outline if needed); while open, the layout gives the topic a bubble measured for the placeholder "Callout", so the room is there before any text exists, and closing it empty stores nothing. Return commits, Esc closes unchanged, losing focus commits. Differences from the design above: a click on the bubble selects its topic (the bubble is not selectable on its own), so Delete deletes the topic and the bubble is removed with Remove Callout (menu bar, topic or bubble context menu, or blank text); the inspector has no Callout field yet; a bubble wider than its card is pulled back to the card's parent-facing edge instead of being centred (*Layout* in [[layout-engine]]). Below the detail zoom the bubbles are not drawn. Topic ▸ Add Callout / Edit Callout ⌥⇧⌘↩ and Remove Callout (no key) are in the menu bar and Help ▸ Keyboard Shortcuts.

**Context menu.** Add Callout on a topic; Edit Callout and Remove Callout on the bubble.

**VoiceOver.** Custom content "Callout: <text>" on the topic; actions Add Callout or Edit Callout. The outline shows it as a caption line under the title, read after the title.

**Export.** PNG and PDF draw it. Markdown and plain text leave it out [Đề xuất in FR-ORG-30, kept]. The lossless format (MM-54) keeps it.

**Sync and repair.** A field on the node record, merged with the node; nothing to repair.

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
| Connection badge | Connection symbol with a count on the visible ancestor | Hidden |
| Link (URL) | `link` (or `envelope` for `mailto`) after the title and note mark | Hidden |
| Image | Above the title, inside the card | A filled placeholder of the same size |
| Callout | Bubble above the topic | Bubble outline only |
| Summary | Bracket beyond the run and the summary topic | Bracket and topic shape |
| Floating topic | At its stored position, with its branch | Shown |
| Boundary | Frame and title | Frame only |

Every adornment has a fixed size in `CanvasMetrics` and is measured with the title, so a topic's size is known before it is drawn. Adornments are drawn in content fonts and `Palette` colours, never glass.

### Outline

Each row gets, in order: checkbox, symbol, title, priority marks, tag chips (up to 3), due date. A boundary shows as a 3 pt bar in its colour along the leading edge of its member rows, with its title as a caption above the first member's title. The filter applies to the outline as to the canvas (hide removes rows, dim uses secondary text). Focus on Branch shows the branch only, with the same breadcrumb.

### Inspector

Sections for the selected topic, in order: Note (exists), Tags (a token field with suggestions from map and shared tags, new names offered as "Create Tag"), Style (colour swatches with shapes and names, symbol picker, None), Task (Task toggle, Done, Priority picker, Start and Due date pickers with Clear, progress read-only), Link, Image, Callout, Connections, Boundary (when the selection is a boundary or inside one), Details (exists), Map (exists). With several topics selected, Tags, Style, Task, Link and Callout apply to all of them and show mixed values as such; Image applies to one topic only.

### Menus and shortcuts (Mac)

Every item is also in the iPad menu bar. Items that do not apply are disabled, not hidden. Shortcuts were checked against the current menus (`AppCommands`, `FileTransferCommands`, `InspectorCommands`), the standard list in [[design-guidelines]] and the system-wide keys (⌥⌘D Dock, ⌃⌘D Look Up, ⌃⌘Q Lock Screen, ⌃⌘Space Character Viewer). None uses ⌘G, which is Find Next. All are [Đề xuất] until the implementing task confirms them in the menu bar.

| Menu | Item | Key |
| --- | --- | --- |
| Topic | Add Link… / Edit Link… (URL, MM-60) | ⌘K (product owner, 2026-10-02) |
| Topic | Open Link | ⇧⌘O |
| Topic | Remove Link | — |
| Topic | Add Connection… (MM-33) | ⌘L (product owner, 2026-10-02) |
| Topic | Add Floating Topic (MM-62) | ⌥⌘↩ |
| Topic | Detach Topic / Attach to Topic… (MM-62) | — |
| Topic | Add Image… / Replace Image… (MM-64) | ⌥⌘I |
| Topic | Remove Image | — |
| Topic | Add Summary / Remove Summary (MM-65) | ⌥⌘] |
| Topic | Add Callout / Edit Callout (MM-66) | ⌥⇧⌘↩ |
| Topic | Remove Callout | — |
| Topic | Add Tag… (opens the inspector's tag field) | ⇧⌘T (built, MM-34) |
| Topic | Tags ▸ the map's most used tags as toggles, Add Tag…, Manage Tags… | — |
| Topic | Manage Tags… | ⌥⇧⌘T (built, MM-34) |
| Topic | Make Task / Remove Task | ⇧⌘K |
| Topic | Mark as Done / Mark as Not Done | ⌥⌘K |
| Topic | Priority ▸ High, Medium, Low, None | ⌥⌘1, ⌥⌘2, ⌥⌘3; the current priority's key again clears it |
| Topic | Set Task Dates… (opens the inspector's Task section) | ⌥⇧⌘K |
| Topic | Add Boundary / Remove Boundary | ⌥⌘B |
| Format (new, between Edit and View) | Topic Color ▸ None, Blue … Graphite | — |
| Format | Topic Symbol ▸ Choose Symbol…, Emoji & Symbols, None | — |
| Format | Connection ▸ Edit Label, Line ▸ Solid, Dashed, Dotted; Arrows ▸ None, At End, At Start, Both Ends; Color ▸; Reverse Connection, Remove Connection (built in MM-33; acts on the connection selected on the canvas, disabled otherwise) | — |
| Format | Image Size ▸ Small, Medium, Large | — |
| Format | Boundary Color ▸ | — |
| View | Show Filter Bar / Hide Filter Bar | ⌥⌘L |
| View | Clear Filter | ⌥⇧⌘L |
| View | Filter Mode ▸ Dim Others, Hide Others | — |
| View | Focus on Branch / Exit Focus | ⇧⌘F |
| AI | Suggest Tags | ⌃⌘T (built, MM-34) |
| AI | Suggest Groups | ⌃⌘O |
| AI | Summarize Boundary | ⌃⌘Y |

Remove items and picker submenus (colours, symbols, line styles, image sizes) have no keys of their own: a remove is in the same sheet or popover as the add, and the Delete key removes a selected connection, boundary or callout, as Rewrite Topic ▸ and Promote/Demote do today. Each new key also goes into Help ▸ Keyboard Shortcuts (`KeyboardShortcutsView.groups`), which no test checks against the menus.

Context menus: a topic gains Tags ▸, Task ▸, Color ▸, Add Link… (or Open Link, Edit Link…, Remove Link), Add Connection…, Add Image… (or Replace Image…, Image Size ▸, Remove Image), Add Callout, Add Summary (with a run of siblings selected), Add Boundary, Detach Topic or Attach to Topic…, Focus on Branch and Suggest Tags; a connection has Edit Label, Line ▸, Arrows ▸, Color ▸, Reverse Connection, Remove Connection; a boundary has Rename Boundary, Color ▸, Summarize Boundary, Remove Boundary; a summary bracket has Remove Summary; a callout has Edit Callout and Remove Callout; empty canvas has Add Floating Topic (at the pointer).

The new keys (⌘K, ⌘L, ⇧⌘O, ⌥⌘↩, ⌥⇧⌘↩, ⌥⌘I, ⌥⌘]) were checked against `AppCommands`, `FileTransferCommands` and the View menu on `main` at `d11c11c`: ⌘↩ is Add Sibling Topic, ⇧⌘↩ Add Child Topic, ⇧⌘I Import…, ⌥⇧⌘I Import into Map…, ⌃⌘I Show Inspector, ⌥⌘O Open in New Window; none of the new ones is taken there or in the standard list of [[design-guidelines]]. ⌘] and ⌘[ are left alone because text editing uses them for indent. ⌥⌘] needs another key on some keyboard layouts; macOS remaps menu keys for those layouts *[Unverified]*, so MM-65 checks it with a German layout.

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

- **VoiceOver value** of a topic stays short: "Level n, m subtopics" ("Floating topic, m subtopics" for a floating topic, "Summary of Design to Launch, m subtopics" for a summary topic), then "task, done" or "task, not done", "priority high", "overdue" when it applies. Tags, dates, colour name, symbol name, connections ("Connection to Budget, label: depends on"), the link ("Link: example.com"), the image description ("Image: whiteboard sketch", or "Image, no description"), the callout text, boundary ("In boundary Phase 1") and summary ("In summary Q3 plan") go to accessibility custom content, read with "more content".
- **Actions** on a topic element: Mark as Done, Add Tag, Add Link or Open Link, Add Connection, Add Callout, Detach Topic or Attach to Topic, Focus on Branch, beside the existing ones. Every drag in *Node types* has one of these as its non-drag alternative.
- **Rotors**: Topics (exists; floating topics after the main tree), Open Tasks, Connections, Links, and Matches while a filter is on.
- **Differentiate Without Color**: the colour shape on coloured topics and in tag chips; overdue and priority already carry symbols and marks. Boundaries have titles and a stroke.
- **Increase Contrast**: IC variants of every token, 2 pt boundary, bracket, connection and callout strokes. **Reduce Motion**: dim, hide and focus changes crossfade through `Motion`.
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
| Links, floating topics, images, summaries, callouts | Rules in *Node types* below, each under *Sync and repair*; summarised in [[data-model]] *Node types (MM-59)* |

Every rule depends only on stored values, timestamps and IDs, so two devices repair to the same graph. Repair changes are saved, as today, so they run once.

## Not in V2

Listed so later tasks can build on the same records; the fields they need are in [[data-model]] (*Not in V2*). Summary topics, floating topics, images and callouts left this table on 2026-10-02: they are V1 now (*Node types*).

| When | Feature | Why not now |
| --- | --- | --- |
| V1.x | Saved filters and smart views across maps | Filters are device-local first; a saved view is a new synced record |
| V1.x | Links to other maps and backlinks | Needs `targetMapID` and handling of maps that are deleted or not synced yet |
| V1.x | Structure per branch (logic chart, org chart, timeline) | Needs more layout engines than `HorizontalTreeLayout` |
| V1.x | Numbering (1, 1.1) and per-branch styles | Display rules, best designed with the branch structures |
| V1.x | Presentation and zen mode | View-only; Focus on Branch covers part of it |
| V1.x | File attachments, several images per topic, audio notes | Same storage path as images (*Images*), plus Quick Look and file types |
| Later | Board view, Gantt, custom properties, rule-based formatting, zones, equations and code, ratings and assignees, comments (needs CloudKit sharing) | Rare in the compared apps or depends on sharing |
