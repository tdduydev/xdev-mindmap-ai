import Foundation
import MindMapDomain
import MindMapGraph

/// Markdown read as an outline: headings and nested list items are topics,
/// everything else is a note.
///
/// - Headings nest by level; a skipped level (`#` then `###`) still nests one deep.
/// - List items nest under the heading above them and under each other by
///   indentation, as CommonMark does: an item indented to its parent's text is a child.
/// - Paragraphs, quotes, tables and code fences become the note of the nearest
///   topic: the list item they are indented under (or continue without a blank
///   line), otherwise the heading of their section. Text before the first
///   topic goes into the first topic's note.
/// - Inline markup is kept as written, so a title or note comes back unchanged.
/// - Front matter and thematic breaks are skipped, and so is the list of
///   connections an export may end with (`ExportOptions.connectionsTitle`):
///   an outline has no place for them, and they must not come back as topics.
/// - A file with no headings or lists is read as plain text, one topic per line.
public enum MarkdownOutline {
    public static func parse(_ text: String) -> OutlineDraft {
        var parser = Parser()
        for line in withoutConnections(withoutFrontMatter(TextLines.split(text))) {
            parser.read(line)
        }
        let draft = parser.builder.finish()
        return draft.isEmpty ? PlainTextOutline.parse(text) : draft
    }

    public struct ExportOptions: Hashable, Sendable {
        public var includeNotes: Bool
        /// How many levels, from the top topic down, are headings (`#`, `##`…);
        /// deeper topics are a nested list. Clamped to 0...6.
        public var headingLevels: Int

        /// Set to end the file with the map's connections under this title
        /// (the caller localises it), one item each: `- Source → Target: label`.
        /// Nil leaves them out, as copy does.
        public var connectionsTitle: String?

        public init(includeNotes: Bool = true, headingLevels: Int = 2, connectionsTitle: String? = nil) {
            self.includeNotes = includeNotes
            self.headingLevels = min(max(0, headingLevels), 6)
            self.connectionsTitle = connectionsTitle
        }
    }

    /// The map, or the branch under `branchID`, as Markdown with a trailing
    /// line break. Reading the result back gives the same topics and notes.
    public static func export(
        _ state: GraphState,
        branch branchID: NodeID? = nil,
        options: ExportOptions = ExportOptions()
    ) throws -> String {
        var writer = Writer()
        var exported: Set<NodeID> = []
        for (node, depth) in try OutlineWalk.nodes(of: state, from: branchID) {
            var title = TextLines.singleLine(node.title)
            // Only a link this build opens: anything else would not read back as one.
            let link = node.link.flatMap { $0.url == nil ? nil : $0 }
            // A title that is link markup but no link must read back as text.
            let looksLinked = link == nil && InlineLink.read(title).1 != nil
            if let link { title = InlineLink.write(text: title, link: link) }
            let note = options.includeNotes ? TextLines.noteLines(node.note) : nil
            if depth < options.headingLevels {
                writer.heading(level: depth + 1, title: title, note: note, escapingLink: looksLinked, task: node.taskState)
            } else {
                writer.listItem(indent: (depth - options.headingLevels) * 2, title: title, note: note, escapingLink: looksLinked, task: node.taskState)
            }
            exported.insert(node.id)
        }
        if let heading = options.connectionsTitle {
            let lines = connectionLines(state, among: exported)
            if !lines.isEmpty { writer.connections(title: heading, lines: lines) }
        }
        return writer.text
    }

    static let connectionArrow = " → "

    /// Connections with both ends in the export, in a stable order.
    private static func connectionLines(_ state: GraphState, among exported: Set<NodeID>) -> [String] {
        state.edges.values
            .filter { exported.contains($0.sourceNodeID) && exported.contains($0.targetNodeID) }
            .sorted { ($0.createdAt, $0.id.rawValue.uuidString) < ($1.createdAt, $1.id.rawValue.uuidString) }
            .compactMap { edge in
                guard let source = state.node(edge.sourceNodeID), let target = state.node(edge.targetNodeID) else { return nil }
                var line = TextLines.singleLine(source.title) + connectionArrow + TextLines.singleLine(target.title)
                if let label = edge.label { line += ": " + TextLines.singleLine(label) }
                return line
            }
    }

    /// Drops a trailing connections block: a thematic break, one line ending
    /// in ":", then only list items with the connection arrow.
    private static func withoutConnections(_ lines: ArraySlice<Substring>) -> ArraySlice<Substring> {
        guard let rule = lines.lastIndex(where: { $0.trimmingTrailingWhitespace() == "---" }) else { return lines }
        let rest = lines[(rule + 1)...].map { $0.trimmingTrailingWhitespace() }.filter { !$0.isEmpty }
        guard let title = rest.first, title.hasSuffix(":"), rest.count > 1,
              rest.dropFirst().allSatisfy({ $0.hasPrefix("- ") && $0.contains(connectionArrow) }) else { return lines }
        return lines[..<rule]
    }

    private static func withoutFrontMatter(_ lines: [Substring]) -> ArraySlice<Substring> {
        guard lines.first?.trimmingTrailingWhitespace() == "---" else { return lines[...] }
        let end = lines.dropFirst().firstIndex { ["---", "..."].contains($0.trimmingTrailingWhitespace()) }
        return end.map { lines[($0 + 1)...] } ?? lines[...]
    }
}

// MARK: - Reading

private struct Parser {
    struct OpenHeading {
        let level: Int
        let depth: Int
        let index: Int
    }

    struct OpenItem {
        /// Where the item's text starts; lines indented this far belong to it.
        let contentColumn: Int
        let depth: Int
        let index: Int
    }

    struct Fence {
        let marker: Character
        let length: Int
        let target: DraftBuilder.NoteTarget
        let stripColumns: Int
    }

    var builder = DraftBuilder()
    private var headings: [OpenHeading] = []
    private var items: [OpenItem] = []
    private var fence: Fence?
    private var previousBlank = false
    /// The previous line was a list item or its text, so an unindented line
    /// right after it continues that item, as in CommonMark.
    private var inListText = false

    mutating func read(_ line: Substring) {
        let (column, rest) = TextLines.indentation(of: line)
        let content = rest.trimmingTrailingWhitespace()

        if let open = fence {
            // Code is kept byte for byte, blank lines and all.
            builder.appendNote(TextLines.dropIndentation(line, columns: open.stripColumns), to: open.target, afterBlank: false)
            if Self.closes(content, open) { fence = nil }
            previousBlank = false
            return
        }

        if content.isEmpty {
            previousBlank = true
            return
        }
        defer { previousBlank = false }

        if column <= 3, let (level, boxed) = Self.heading(content) {
            let (task, title) = Self.taskBox(boxed.title, raw: boxed.raw)
            let (text, link) = Self.linkedTitle(title, raw: content)
            items.removeAll()
            inListText = false
            while let last = headings.last, last.level >= level { headings.removeLast() }
            let depth = headings.last.map { $0.depth + 1 } ?? 0
            let index = builder.add(depth: depth, title: text, link: link, taskState: task)
            headings.append(OpenHeading(level: level, depth: depth, index: index))
            return
        }

        if column <= 3, Self.isThematicBreak(content) {
            inListText = false
            return
        }

        if let (markerWidth, task, title) = Self.listItem(content) {
            // A sibling or a shallower item closes every item it does not reach into.
            while let last = items.last, column < last.contentColumn { items.removeLast() }
            let depth = items.last.map { $0.depth + 1 } ?? headings.last.map { $0.depth + 1 } ?? 0
            let (text, link) = Self.linkedTitle(title, raw: content)
            let index = builder.add(depth: depth, title: text, link: link, taskState: task)
            items.append(OpenItem(contentColumn: column + markerWidth, depth: depth, index: index))
            inListText = true
            return
        }

        let (target, stripColumns) = noteTarget(column: column)
        if let (marker, length) = Self.fenceOpening(content) {
            fence = Fence(marker: marker, length: length, target: target, stripColumns: stripColumns)
            builder.appendNote(TextLines.dropIndentation(line, columns: stripColumns), to: target, afterBlank: previousBlank)
            return
        }
        let text = Self.unescaped(TextLines.dropIndentation(line, columns: stripColumns).trimmingTrailingWhitespace())
        builder.appendNote(text, to: target, afterBlank: previousBlank)
    }

    /// Who owns a line of text, and how much indentation is the list's rather than the text's.
    private mutating func noteTarget(column: Int) -> (DraftBuilder.NoteTarget, Int) {
        if let last = items.last {
            // Unindented continuation lines drop all their indentation; lines
            // indented under the item keep whatever goes past its text.
            if inListText, !previousBlank { return (.item(last.index), min(column, last.contentColumn)) }
            while let last = items.last, column < last.contentColumn { items.removeLast() }
            if let owner = items.last {
                inListText = true
                return (.item(owner.index), owner.contentColumn)
            }
        }
        inListText = false
        if let heading = headings.last { return (.item(heading.index), 0) }
        // Unindented text after a top-level list, with no heading above it.
        if let last = builder.lastIndex { return (.item(last), 0) }
        return (.preamble, 0)
    }

    /// A title the writer escaped (`\\[a](b)`) is text, though it reads as a link once unescaped.
    static func linkedTitle(_ title: String, raw: Substring) -> (String, TopicLink?) {
        guard title.hasPrefix("["), !raw.contains("\\[" + title.dropFirst()) else { return (title, nil) }
        return InlineLink.read(title)
    }

    // MARK: Line kinds

    /// `#` to `######` followed by a space or nothing. An optional closing run
    /// of `#` is dropped, as in CommonMark.
    static func heading(_ content: Substring) -> (Int, (title: String, raw: Substring))? {
        let hashes = content.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        var title = content.dropFirst(hashes)
        guard title.isEmpty || title.first == " " || title.first == "\t" else { return nil }
        title = title.drop { $0 == " " || $0 == "\t" }

        let closing = title.reversed().prefix { $0 == "#" }.count
        if closing > 0 {
            let beforeClosing = title.dropLast(closing)
            if beforeClosing.isEmpty || beforeClosing.last == " " || beforeClosing.last == "\t" {
                title = beforeClosing.trimmingTrailingWhitespace()
            }
        }
        return (hashes, (unescaped(title, trailingHash: true), title))
    }

    /// A heading that starts with a task box (`## [ ] Title`). Read from the
    /// raw text, so an escaped box (`## \[ ] Title`) stays part of the title.
    static func taskBox(_ title: String, raw: Substring) -> (TaskState?, String) {
        guard let (state, length) = taskBoxPrefix(raw) else { return (nil, title) }
        return (state, unescaped(raw.dropFirst(length), trailingHash: true))
    }

    static func taskBoxPrefix(_ text: Substring) -> (TaskState, Int)? {
        TaskBox.prefix(text)
    }

    /// A bullet (`-`, `*`, `+`) or a number (`1.`, `1)`) followed by a space or
    /// nothing. Returns the marker's width including one space, the task box's
    /// state, and the title without the box.
    static func listItem(_ content: Substring) -> (Int, TaskState?, String)? {
        var markerLength: Int
        if let first = content.first, "-*+".contains(first) {
            markerLength = 1
        } else {
            let digits = content.prefix { $0.isASCII && $0.isNumber }.count
            guard (1...9).contains(digits) else { return nil }
            let delimiter = content.dropFirst(digits).first
            guard delimiter == "." || delimiter == ")" else { return nil }
            markerLength = digits + 1
        }
        let afterMarker = content.dropFirst(markerLength)
        guard afterMarker.isEmpty || afterMarker.first == " " || afterMarker.first == "\t" else { return nil }

        var title = afterMarker.drop { $0 == " " || $0 == "\t" }
        let task = taskBoxPrefix(title)
        if let (_, length) = task { title = title.dropFirst(length) }
        return (markerLength + 1, task?.0, unescaped(title))
    }

    /// Three or more `-`, `*` or `_`, optionally spaced.
    static func isThematicBreak(_ content: Substring) -> Bool {
        let marks = content.filter { $0 != " " && $0 != "\t" }
        guard let first = marks.first, "-*_".contains(first), marks.count >= 3 else { return false }
        return marks.allSatisfy { $0 == first }
    }

    static func fenceOpening(_ content: Substring) -> (Character, Int)? {
        guard let first = content.first, first == "`" || first == "~" else { return nil }
        let length = content.prefix { $0 == first }.count
        return length >= 3 ? (first, length) : nil
    }

    static func closes(_ content: Substring, _ fence: Fence) -> Bool {
        let trimmed = content.drop { $0 == " " || $0 == "\t" }
        return trimmed.count >= fence.length && trimmed.allSatisfy { $0 == fence.marker }
    }

    // MARK: Escapes

    /// Undoes the escapes `Writer` adds at the start of a line (and, for
    /// headings, before a trailing `#`). Other backslashes are content.
    static func unescaped(_ text: Substring, trailingHash: Bool = false) -> String {
        var text = String(text)
        if text.hasSuffix("\\#"), trailingHash {
            text.remove(at: text.index(text.endIndex, offsetBy: -2))
        }
        let leading = text.prefix { $0 == " " || $0 == "\t" }
        let body = text.dropFirst(leading.count)
        if body.count >= 2, body.first == "\\", let next = body.dropFirst().first, Writer.escapable.contains(next) {
            return String(leading + body.dropFirst())
        }
        // `12\.` is how a numbered-list lookalike is escaped.
        let digits = body.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix("\\.") || body.dropFirst(digits.count).hasPrefix("\\)") {
            return String(leading + digits + body.dropFirst(digits.count + 1))
        }
        return text
    }
}

// MARK: - Writing

private struct Writer {
    /// Characters a leading backslash protects. All are ASCII punctuation, so
    /// any Markdown viewer hides the backslash too.
    static let escapable: Set<Character> = ["\\", "#", "-", "*", "+", ">", "_", "`", "~", "["]

    private enum Block { case none, heading, headingNote, item, itemNote }

    private var lines: [String] = []
    private var last = Block.none

    var text: String { lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n" }

    mutating func heading(level: Int, title: String, note: [Substring]?, escapingLink: Bool = false, task: TaskState? = nil) {
        if last != .none { lines.append("") }
        var title = (escapingLink ? "\\" : "") + Self.escapedLine(title)
        if let task { title = TaskBox.write(task) + title }
        // A closing `#` run would be read as decoration and dropped. The reader
        // takes one backslash off before a final `#`, so a title that already
        // has one there gets another.
        if title.hasSuffix("#"),
           title.dropLast().last == "\\"
            || title.dropLast(title.reversed().prefix { $0 == "#" }.count).last.map({ $0 == " " || $0 == "\t" }) ?? true {
            title.insert("\\", at: title.index(before: title.endIndex))
        }
        lines.append(String(repeating: "#", count: level) + (title.isEmpty ? "" : " " + title))
        last = .heading
        guard let note else { return }
        lines.append("")
        lines.append(contentsOf: Self.escapedNote(note, indent: ""))
        last = .headingNote
    }

    /// After a thematic break, so no reader takes the list for more topics.
    mutating func connections(title: String, lines connections: [String]) {
        lines.append(contentsOf: ["", "---", "", title, ""])
        lines.append(contentsOf: connections.map { "- " + Self.escapedLine($0) })
        last = .item
    }

    mutating func listItem(indent: Int, title: String, note: [Substring]?, escapingLink: Bool = false, task: TaskState? = nil) {
        if last == .heading || last == .headingNote { lines.append("") }
        let padding = String(repeating: " ", count: indent)
        var title = (escapingLink ? "\\" : "") + Self.escapedTitle(title)
        // The box goes before any escape, so `- [ ] \[ ] a` reads back as a task named `[ ] a`.
        if let task { title = TaskBox.write(task) + title }
        lines.append(padding + "-" + (title.isEmpty ? "" : " " + title))
        last = .item
        guard let note else { return }
        lines.append("")
        lines.append(contentsOf: Self.escapedNote(note, indent: padding + "  "))
        last = .itemNote
    }

    private static func escapedTitle(_ title: String) -> String {
        for box in ["[ ] ", "[x] ", "[X] "] where title.hasPrefix(box) {
            return "\\" + title
        }
        return escapedLine(title)
    }

    /// Note lines that would read as structure get a backslash. Lines inside a
    /// complete code fence are left alone; an unclosed fence is escaped, or it
    /// would swallow the rest of the file.
    private static func escapedNote(_ note: [Substring], indent: String) -> [String] {
        let fenceLines = balancedFenceLines(note)
        return note.indices.map { index in
            let line = note[index].trimmingTrailingWhitespace()
            if line.isEmpty { return "" }
            return indent + (fenceLines.contains(index) ? String(line) : escapedLine(String(line)))
        }
    }

    /// Indices of lines inside, or opening and closing, a fence that closes.
    private static func balancedFenceLines(_ note: [Substring]) -> Set<Int> {
        var result: Set<Int> = []
        var index = 0
        while index < note.count {
            let content = note[index].drop { $0 == " " || $0 == "\t" }
            guard let (marker, length) = Parser.fenceOpening(content) else {
                index += 1
                continue
            }
            let fence = Parser.Fence(marker: marker, length: length, target: .preamble, stripColumns: 0)
            if let end = note[(index + 1)...].firstIndex(where: { Parser.closes($0.trimmingTrailingWhitespace(), fence) }) {
                result.formUnion(index...end)
                index = end + 1
            } else {
                index += 1
            }
        }
        return result
    }

    /// Escapes a line that starts like a heading, list item, quote, break, fence
    /// or escape, so it reads back as text.
    private static func escapedLine(_ line: String) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let body = Substring(line.dropFirst(leading.count))
        guard let first = body.first else { return line }

        let isListItem = Parser.listItem(body) != nil
        if isListItem, first.isNumber {
            // A backslash before a digit is not an escape; `12\.` is.
            let digits = body.prefix { $0.isASCII && $0.isNumber }
            return leading + digits + "\\" + body.dropFirst(digits.count)
        }

        let startsStructure = isListItem
            || Parser.heading(body) != nil
            || Parser.isThematicBreak(body)
            || Parser.fenceOpening(body) != nil
            || first == ">" || first == "\\"
            // A heading that starts with a box would read back as a task.
            || Parser.taskBoxPrefix(body) != nil
        return startsStructure && escapable.contains(first) ? leading + "\\" + body : line
    }
}

// MARK: - Links

/// A title that is one inline link, `[Title](url)` (FR-ORG-26). Brackets and
/// backslashes in the title, and parentheses in the URL, are escaped with a
/// backslash, as CommonMark reads them.
enum InlineLink {
    static func write(text: String, link: TopicLink) -> String {
        "[" + escaped(text, ["\\", "[", "]"]) + "](" + escaped(link.string, ["\\", "(", ")"]) + ")"
    }

    /// The text and link when the whole title is one link with an allowed
    /// scheme; any other title, inline links inside it included, stays text.
    static func read(_ title: String) -> (String, TopicLink?) {
        guard title.hasPrefix("["), title.hasSuffix(")"),
              let (text, rest) = scan(Substring(title.dropFirst()), until: "]"),
              rest.hasPrefix("("),
              let (destination, tail) = scan(rest.dropFirst(), until: ")"), tail.isEmpty,
              let link = TopicLink.normalized(destination), link.url != nil
        else { return (title, nil) }
        return (text, link)
    }

    /// Unescaped text up to the first unescaped `end`, and what follows it.
    /// An unescaped opening bracket or parenthesis means nested markup, which
    /// is not a plain link, so nil.
    private static func scan(_ text: Substring, until end: Character) -> (String, Substring)? {
        let opening: Character = end == "]" ? "[" : "("
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\\", let next = text.index(index, offsetBy: 1, limitedBy: text.endIndex), next < text.endIndex,
               "\\[]()".contains(text[next]) {
                result.append(text[next])
                index = text.index(after: next)
                continue
            }
            if character == end { return (result, text[text.index(after: index)...]) }
            if character == opening { return nil }
            result.append(character)
            index = text.index(after: index)
        }
        return nil
    }

    private static func escaped(_ text: String, _ characters: Set<Character>) -> String {
        var result = ""
        for character in text {
            if characters.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
