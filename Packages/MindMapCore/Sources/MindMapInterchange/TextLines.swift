import Foundation
import MindMapDomain

/// Line handling shared by the parsers and exporters.
enum TextLines {
    static let tabWidth = 4

    /// Lines without their terminators, whatever the file's line endings.
    static func split(_ text: String) -> [Substring] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // "\r\n" is a single Character in Swift, so splitting on all three
        // separators never leaves an empty line between \r and \n.
        return text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }
    }

    /// The column where content starts, with tabs advancing to the next tab
    /// stop, and the content after the leading whitespace.
    static func indentation(of line: Substring) -> (column: Int, rest: Substring) {
        var column = 0
        var index = line.startIndex
        while index < line.endIndex {
            switch line[index] {
            case " ": column += 1
            case "\t": column += tabWidth - column % tabWidth
            default: return (column, line[index...])
            }
            index = line.index(after: index)
        }
        return (column, line[index...])
    }

    /// Removes up to `columns` columns of leading whitespace.
    static func dropIndentation(_ line: Substring, columns: Int) -> Substring {
        var column = 0
        var index = line.startIndex
        while index < line.endIndex, column < columns {
            switch line[index] {
            case " ": column += 1
            case "\t": column += tabWidth - column % tabWidth
            default: return line[index...]
            }
            index = line.index(after: index)
        }
        return line[index...]
    }

    /// Titles are one line in every format, so line breaks inside one become spaces.
    static func singleLine(_ title: String) -> String {
        title.split(omittingEmptySubsequences: true) { $0.isNewline }.joined(separator: " ")
    }

    /// Note lines, or nil for a note that is empty or only whitespace.
    static func noteLines(_ note: String?) -> [Substring]? {
        guard let note, !note.allSatisfy(\.isWhitespace) else { return nil }
        return split(note)
    }
}

/// Collects topics and their note lines while a parser reads a file.
struct DraftBuilder {
    enum NoteTarget: Equatable {
        /// Text before the first topic.
        case preamble
        case item(Int)
    }

    private(set) var items: [OutlineDraft.Item] = []
    private var notes: [[String]] = []
    private var preamble: [String] = []

    var lastIndex: Int? { items.indices.last }

    mutating func add(depth: Int, title: String, link: TopicLink? = nil, taskState: TaskState? = nil) -> Int {
        items.append(OutlineDraft.Item(depth: depth, title: title, link: link, taskState: taskState))
        notes.append([])
        return items.count - 1
    }

    /// Adds a note line. `afterBlank` keeps paragraph breaks inside a note
    /// without collecting the blank lines that separate blocks.
    mutating func appendNote(_ line: some StringProtocol, to target: NoteTarget, afterBlank: Bool) {
        switch target {
        case .preamble:
            if afterBlank, !preamble.isEmpty { preamble.append("") }
            preamble.append(String(line))
        case .item(let index):
            if afterBlank, !notes[index].isEmpty { notes[index].append("") }
            notes[index].append(String(line))
        }
    }

    /// The draft, with text found before the first topic added to that
    /// topic's note so nothing in the file is dropped.
    func finish() -> OutlineDraft {
        var notes = notes
        if !preamble.isEmpty, !notes.isEmpty {
            notes[0] = notes[0].isEmpty ? preamble : preamble + [""] + notes[0]
        }
        var items = items
        for index in items.indices {
            items[index].note = Self.joined(notes[index])
        }
        return OutlineDraft(items: items)
    }

    private static func joined(_ lines: [String]) -> String? {
        var lines = lines[...]
        while let first = lines.first, first.allSatisfy(\.isWhitespace) { lines.removeFirst() }
        while let last = lines.last, last.allSatisfy(\.isWhitespace) { lines.removeLast() }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// A task box at the start of a title (MM-35), shared by Markdown and plain text.
enum TaskBox {
    /// `[ ] ` is open, `[x] ` or `[X] ` done, as GitHub writes task lists; a
    /// box alone is a task with an empty title. Returns the state and the
    /// length to drop.
    static func prefix(_ text: Substring) -> (TaskState, Int)? {
        if text.hasPrefix("[ ] ") || text == "[ ]" { return (.open, min(4, text.count)) }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") || text == "[x]" || text == "[X]" { return (.done, min(4, text.count)) }
        return nil
    }

    /// Anything but done is written open, as `TaskState.isDone` reads it.
    static func write(_ state: TaskState) -> String {
        state.isDone ? "[x] " : "[ ] "
    }
}
