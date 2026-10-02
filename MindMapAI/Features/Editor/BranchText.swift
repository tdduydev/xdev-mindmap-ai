import Foundation
import MindMapDomain
import MindMapGraph

/// Branches as text on the clipboard (FR-EDT-14): copy writes a Markdown list,
/// paste reads a list or any indented lines back into topics.
///
/// This is the seam for `MindMapInterchange` (MM-10a). Until that package is on
/// `main`, a small list writer and reader live here; when it lands, `markdown`
/// becomes `MarkdownOutline.export`, `outline` becomes
/// `InterchangeFormat.markdown.parse`, and `EditorSession.paste` inserts with
/// `InsertOutlineCommand`. Callers only see `Item`, which has the shape of
/// `OutlineDraft.Item`.
enum BranchText {
    struct Item: Hashable, Sendable {
        /// 0 for a top-level topic.
        var depth: Int
        var title: String
        var note: String?
    }

    // MARK: Writing

    /// The branches under `roots`, in order, as a nested Markdown list with two
    /// spaces per level. A note follows its topic as `>` lines one level in.
    /// Collapsed branches are copied whole: a copy is the branch, not the screen.
    static func markdown(for roots: [NodeID], in state: GraphState) -> String {
        var lines: [String] = []
        for root in roots {
            // Pre-order with an explicit stack, so a very deep branch cannot
            // overflow the call stack.
            var stack: [(id: NodeID, depth: Int)] = [(root, 0)]
            while let (id, depth) = stack.popLast() {
                guard let node = state.node(id) else { continue }
                let indent = String(repeating: "  ", count: depth)
                lines.append("\(indent)- \(escaped(singleLine(node.title)))")
                if let note = node.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    let noteIndent = String(repeating: "  ", count: depth + 1)
                    for line in note.components(separatedBy: .newlines) {
                        lines.append(line.isEmpty ? "\(noteIndent)>" : "\(noteIndent)> \(line)")
                    }
                }
                for child in state.childIDs(of: id).reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// A title is one line on the canvas only by wrapping; a hard break would
    /// split it into two topics on the way back.
    private static func singleLine(_ title: String) -> String {
        title.components(separatedBy: .newlines).joined(separator: " ")
    }

    /// A title that starts like a bullet, a heading, a quote, a task box or a number would
    /// read back as structure; a leading backslash keeps it a title.
    private static func escaped(_ title: String) -> String {
        guard let first = title.first else { return title }
        if "-*+•#>[\\".contains(first) || orderedMarkerLength(in: Substring(title)) != nil {
            return "\\" + title
        }
        return title
    }

    // MARK: Reading

    /// Topics from text: list items (`-`, `*`, `+`, `•`, `1.`, `1)`) and plain
    /// lines nest by indentation, `#` headings nest by level with the lines
    /// under them below, `>` lines are the note of the topic above. Blank lines
    /// are skipped. Depths are clamped so the result is always a valid tree.
    static func outline(from text: String) -> [Item] {
        var items: [Item] = []
        var headingDepth = -1
        // Indent columns of the open list levels under the current heading.
        var indents: [Int] = []
        var noteLines: [String] = []

        func flushNote() {
            guard !noteLines.isEmpty, !items.isEmpty else { return noteLines.removeAll() }
            let note = noteLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !note.isEmpty {
                items[items.count - 1].note = [items[items.count - 1].note, note].compactMap { $0 }.joined(separator: "\n")
            }
            noteLines.removeAll()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let column = indentColumn(of: rawLine)
            var line = rawLine.drop { $0 == " " || $0 == "\t" }
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            if line.first == ">" {
                line = line.dropFirst()
                if line.first == " " { line = line.dropFirst() }
                noteLines.append(String(line))
                continue
            }
            flushNote()

            if let level = headingLevel(of: line) {
                let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                headingDepth = min(level - 1, headingDepth + 1)
                indents = []
                items.append(Item(depth: headingDepth, title: unescaped(title)))
                continue
            }

            while let last = indents.last, column < last { indents.removeLast() }
            if indents.last != column { indents.append(column) }
            let depth = headingDepth + indents.count
            items.append(Item(depth: depth, title: unescaped(withoutMarker(line))))
        }
        flushNote()
        return clamped(items)
    }

    /// Tabs advance to the next multiple of four columns.
    private static func indentColumn(of line: String) -> Int {
        var column = 0
        for character in line {
            switch character {
            case " ": column += 1
            case "\t": column += 4 - column % 4
            default: return column
            }
        }
        return column
    }

    private static func headingLevel(of line: Substring) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " ? hashes : nil
    }

    private static func withoutMarker(_ line: Substring) -> String {
        var text = line
        if let first = text.first, "-*+•".contains(first), text.dropFirst().first == " " {
            text = text.dropFirst(2)
        } else if let length = orderedMarkerLength(in: text) {
            text = text.dropFirst(length)
        }
        // A task box is checklist decoration, not part of the title.
        for box in ["[ ] ", "[x] ", "[X] "] where text.hasPrefix(box) {
            text = text.dropFirst(box.count)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The length of `12. ` or `3) ` at the start of a line, with its space.
    private static func orderedMarkerLength(in text: Substring) -> Int? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }.count
        guard digits > 0, digits <= 9 else { return nil }
        let rest = text.dropFirst(digits)
        guard let marker = rest.first, marker == "." || marker == ")", rest.dropFirst().first == " " else { return nil }
        return digits + 2
    }

    private static func unescaped(_ title: String) -> String {
        title.hasPrefix("\\") ? String(title.dropFirst()) : title
    }

    /// The first item is top level and none is more than one level below the one before.
    private static func clamped(_ items: [Item]) -> [Item] {
        var previous = -1
        return items.map { item in
            var item = item
            item.depth = min(max(0, item.depth), previous + 1)
            previous = item.depth
            return item
        }
    }
}
