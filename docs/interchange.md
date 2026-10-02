# Interchange

`MindMapInterchange` in `Packages/MindMapCore` reads plain text and Markdown into topics and writes a map, or one branch, back out. It depends on Domain and Graph only: no SwiftUI, no SwiftData, no AI. That lets the Share Extension and App Intents (MM-11) import text without the app, and File ▸ Import/Export (MM-10) is a thin layer of `fileImporter`/`fileExporter` on top.

## Shape

```swift
enum InterchangeFormat { case markdown, plainText }        // init?(fileExtension:)
format.parse(_ text: String) -> OutlineDraft
format.parse(_ data: Data) async throws -> OutlineDraft    // @concurrent, decodes first
format.export(_ state: GraphState, branch: NodeID?, includeNotes: Bool) throws -> String
format.exportData(…) async throws -> Data                  // @concurrent

InsertOutlineCommand(draft, under: parentID, at: placement, origin: .imported)  // into the open map
GraphState.imported(from: draft, title: fileName)                               // a new map
```

- **`OutlineDraft`** is the parsed file: a flat list of items in reading order, each with a depth, a title and an optional note. Flat rather than nested so every walk is a loop; a file nested thousands of levels deep cannot overflow the stack. Its initializer clamps depths so the list is always a valid tree.
- **Into the open map, one undo step (FR-IO-07).** `InsertOutlineCommand` adds every topic through `AddNodeCommand` inside one command, so the engine validates once and undo removes the whole import. IDs are picked when the command is made: the caller can select `topNodeIDs` afterwards. New topics carry `metadata.origin = .imported`; a parent that was collapsed opens, as it does for any new child.
- **A new map.** One top-level topic (a Markdown file with a single `#` title) becomes the central topic and the map's name. Several become children of a central topic named after the file. An empty file throws `InterchangeError.emptyDocument`.
- **Off the main actor.** The `Data` variants are `@concurrent`; the caller awaits them from the editor. Parsing and exporting 10,000 topics takes tens of milliseconds in a release build on the development Mac (measured once, not a benchmark in the suite).
- **Decoding.** UTF-8 (with or without a byte order mark) and UTF-16 with a byte order mark. Anything else, or bytes with a NUL in them, throws `InterchangeError.unreadableText` instead of guessing: a Vietnamese legacy encoding read as Latin-1 would import garbage without a warning. MM-10 turns the error into the message of FR-IO-09.

## Plain text (FR-IO-01)

- One topic per line, nested by indentation: tabs, spaces or both, any number of spaces per level. A tab advances to the next multiple of four columns. A line indented back goes up to the nearest topic it lines up with or passes.
- A leading bullet (`-`, `*`, `+`, `•`) is dropped, so a pasted list reads well. Blank lines are skipped.
- Export: one tab per level. A note goes on `> ` lines one level below its topic, and those lines read back as the note. A title that starts with `>`, a bullet or a backslash gets a leading backslash, so it reads back unchanged.

## Markdown (FR-IO-02, FR-IO-03)

- **Topics:** ATX headings (`#` to `######`) nest by level, and a skipped level still nests only one deep. List items (`-`, `*`, `+`, `1.`, `1)`) nest under the heading above them and under each other by indentation, as in CommonMark: an item indented to its parent's text is its child. A task box (`[ ]`, `[x]`) is dropped.
- **Notes:** paragraphs, quotes, tables and code fences go to the nearest topic: the list item they are indented under or continue without a blank line, otherwise the heading of their section. Text before the first topic goes into the first topic's note, so nothing in the file is lost. This rule is still marked [Đề xuất] in the SRS.
- **Kept as written:** inline markup (`**bold**`, links) stays in the title or note. Code fences are copied line for line.
- **Skipped:** YAML front matter and thematic breaks.
- **Fallback:** a file with no headings or list items is read as plain text, one topic per line.
- **Not read:** Setext headings (`Title` over `===`) and HTML blocks. They become notes.
- **Export:** the first two levels are headings (`#`, `##`), deeper levels a nested list with two spaces per level (`ExportOptions.headingLevels`, 0 to 6; 0 writes only a list). A note follows its topic after a blank line, indented under a list item. Collapsed branches are exported too: an export is the whole map, not what is on screen. A line break inside a title becomes a space.
- **Round trip:** for any map, Markdown → map → Markdown gives the same topics, depths and notes (tests cover syntax-like titles and notes, and a file the exporter wrote coming back byte for byte). Lines that would read as structure (a title starting with `#`, `-` or `1.`, a note line starting with `>`, a title ending in `#`) get a backslash that every Markdown viewer hides. A note's code fence is left alone when it closes; an unclosed one is escaped so it cannot swallow the rest of the file.

## In the app (MM-10)

`MindMapAI/Features/Interchange`: the panels, the export sheet and PNG/PDF drawing. Parsing and writing text stay in the package.

- **Menus (FR-IO-08).** File ▸ Import… (⇧⌘I) makes a new map; Import into Map… (⌥⇧⌘I) adds the file under the selected topic of the open map, one undo step named "Import"; Export… (⇧⌘E) opens the export sheet. The library toolbar has Import… and the editor toolbar Export…, for iPhone where there is no menu bar. `FileTransfer` (one per window, in `RootView`) holds which panel is up and the import alert; `FileTransferCommands` reaches it through a focused value.
- **Reading a file.** `MapImporter.read` is `@concurrent`: it opens the security-scoped URL, picks the format by extension (`.md`, `.markdown`, `.txt`, then any other plain text as indented text) and parses. The open panel also offers other text types, such as rich text, so the user gets the FR-IO-09 message naming the formats instead of a greyed-out file. `ImportFailure` words every case: unsupported type, not UTF-8/UTF-16, no topics, unreadable, not saved.
- **Sandbox.** `ENABLE_USER_SELECTED_FILES = readwrite`. No file timestamp, size or disk-space API is read, so `PrivacyInfo.xcprivacy` needs no new reason; the "Include Notes" default is UserDefaults, already declared (CA92.1).
- **The export sheet.** Format (Markdown, Plain Text, PNG Image, PDF), then per format: whole map or the selected branch and Include Notes for text; resolution 1×/2×/3× and background for PNG; one fitted page or actual size over several pages, A4 or US Letter (by region), and background for PDF. Every option but the branch starts from Settings ▸ Export (FR-SET-07) and a change in the sheet is written back to the same key (`ExportPreferences`, [[settings]]); the sheet also reopens on the last format. The file is made before the save panel opens, so a failure shows in the sheet.
- **Pictures (FR-IO-04, FR-IO-05).** `MapPicture.make` runs a full `CanvasLayoutPass` off the main actor with `CanvasModel.layoutOptions` and design-size fonts, so a picture has the canvas's layout but not its camera, AI suggestions, selection or Dynamic Type. Collapsed branches stay collapsed with their badge, as on screen. `MapPictureView` draws edges through the canvas's `CanvasDrawing`/`EdgeLayer` and each topic with the same `TopicTitleText` and `CollapseBadgeLabel` as `TopicView`, at standard contrast (the file is for other people). `ImageRenderer` turns it into a PNG (`CGImageDestination`) or a PDF (`render` into a `CGContext` PDF), where text stays text and lines stay paths. White paper always uses the light colours.
- **Limits.** A PNG's longest side is capped at `CanvasMetrics.exportMaximumPixels` (16,384 px); a larger map is drawn at a lower scale. `PDFPageLayout` is plain geometry: a fitted page turns landscape for a wide map and never enlarges a small one; several pages tile the map at actual size inside a 36 pt margin, centred on the grid, in reading order, in the orientation that needs fewer sheets. Each page draws the whole picture clipped to its tile, so a PDF of n pages holds the map's drawing n times.
- **Pro.** PNG above 1× and PDFs over several pages ask `ProEntitlements` (`ProFeature.highResolutionImage`, `.multiPagePDF`); the sheet disables Export with one line when locked. Until MM-13's StoreKit entitlement lands everything is unlocked (`AllFeaturesUnlocked`). OPML is not built.

## Map archive: the backup format (MM-54)

Markdown keeps titles, notes and the tree only; tags, colours, symbols, tasks, connections, boundaries and the theme are lost (FR-ORG-10), so it is not a backup. `MapArchive` (`MindMapInterchange/MapArchive.swift`) is: one JSON file per map, holding every record of the map as the Codable domain values store it.

```swift
MapArchive(graph)                               // every record, sorted by ID
try await MapArchive.exportData(graph)          // @concurrent, pretty JSON, sorted keys
try await MapArchive.decode(data)               // throws MapArchiveError: notAnArchive, newerVersion(n), damaged
archive.graph                                   // the map exactly as written, same IDs
archive.importedGraph(sharedTags:)              // a new map: every ID new
```

```json
{ "format": "asia.xdev.mindmapai.map", "version": 1,
  "map": { … }, "nodes": [ … ], "edges": [ … ], "tags": [ … ], "nodeTags": [ … ], "groups": [ … ] }
```

- **Why JSON of the domain types.** No dependency, readable and diffable, and the domain values already are what SwiftData stores (`RecordMapping`), so a field added to the domain is in the file without a second mapping to keep in step. Open-ended values (`TopicColor`, `TaskState`, `GroupKind`…) are raw strings, so a value a newer build wrote survives this one.
- **Version.** `format` marks the file as ours (any other JSON is refused, not read as an empty map); `version` is 1. A new optional field does not raise it: older builds skip unknown keys, newer ones read a missing key as nil. It goes up only when a field is renamed, removed or changes meaning, and then `decode` keeps reading every older layout and converts it. A file with a version above `currentVersion` is refused with "made by a newer version". A frozen version 1 file in `MapArchiveTests` must keep opening.
- **Dates** stay seconds since 2001 as `Double` (the encoder's default). ISO 8601 would round to the millisecond, and an edit time that moves breaks newest-wins after sync.
- **Same map, same bytes.** Records are sorted by ID and keys sorted, so two backups of one map compare with `diff`.
- **What a map file holds.** The map (theme, layout, favourite), every topic with every field, connections, the map's tags and the shared tags its topics carry, tag links and boundaries. Library-only data stays out: unused shared tags, and `deletedAt` (an imported map is live).
- **Importing never overwrites.** `importedGraph` gives the map and every record a new ID, keeping every other field, edit times included, so a backup can be imported next to its original or twice. A shared tag of the file joins the library's shared tag with the same `MindTag.key` when the caller passes the library's tags; otherwise it becomes a tag of the new map. The app passes none today, so a shared tag comes back as a map tag with the same name, colour and symbol (shared tags change only through library actions). A reference to a record the file lacks gets a fresh dangling ID, so `GraphRepair` handles the file like a map that lost a record in sync.
- **When the domain grows:** add the field to `importedGraph`'s copy and set it in `ArchiveFixture.everyField`. `importingKeepsEverythingButTheIDs` compares each record's JSON minus its IDs, so a field set in the fixture but not copied fails there. MM-59 did this for `link`, `position`, `callout` and `summaryNodeID` (the summary follows its topic's new ID). `NodeType` is a struct since MM-59, so a node type this build does not know is kept. **Images are not in the file yet:** `GraphState` holds no bytes and the archive has no `images` list; MM-64 decides on base64 in the file or a folder per map, then adds the list (a new optional key, version stays 1).

**In the app.** File ▸ Export… has the format **MindMap AI Backup** (`ExportFormat.backup`, `.json`, always the whole map); File ▸ Import… reads a `.json` file as a backup and opens it as a new map (`MapImporter.readBackup`, `FileTransfer.importBackup`). Import into Map… refuses a backup with a message, since a backup is a whole map. Settings ▸ Data reuses both: Export All Maps (MM-45) writes `MapArchive.exportData` for each map into one folder, and its Import Maps… calls `FileTransfer.importFile`, so the menu and Settings share one reader and one writer. Errors (FR-IO-09): not a backup, made by a newer version, damaged.

## Not here

- OPML (FR-IO-06): not planned for V1. It would be a third `InterchangeFormat` case over the same `OutlineDraft`.
- Clipboard paste of several lines (MM-5) can reuse `PlainTextOutline.parse` and `InsertOutlineCommand`.
