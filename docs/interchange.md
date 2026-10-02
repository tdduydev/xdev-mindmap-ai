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

## Not here

- File ▸ Import/Export, file types, the export-notes setting and error messages: MM-10.
- OPML (FR-IO-06): not planned for V1. It would be a third `InterchangeFormat` case over the same `OutlineDraft`.
- Clipboard paste of several lines (MM-5) can reuse `PlainTextOutline.parse` and `InsertOutlineCommand`.
