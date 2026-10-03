import Foundation
import MindMapDomain
import MindMapGraph

/// Indented plain text: one topic per line, nested by indentation.
///
/// Reading accepts tabs, spaces or a mix, with any number of spaces per level:
/// a line indented further than the one before is its child, and a line
/// indented back goes up to the nearest topic it lines up with or passes. A
/// leading bullet (`-`, `*`, `+`, `•`) is dropped, so pasted lists read well.
/// Lines starting with `>` are a note for the topic before them, which is how
/// notes are written out. A backslash at the start of a line keeps the rest
/// exactly as written, so titles starting with `>`, a bullet or a backslash
/// survive a round trip.
public enum PlainTextOutline {
    public static func parse(_ text: String) -> OutlineDraft {
        var builder = DraftBuilder()
        // Indentation column and depth of each open topic, outermost first.
        var open: [(column: Int, depth: Int)] = []

        for line in TextLines.split(text) {
            let (column, rest) = TextLines.indentation(of: line)
            let content = rest.trimmingTrailingWhitespace()
            if content.isEmpty { continue }

            if let note = noteText(content) {
                builder.appendNote(note, to: builder.lastIndex.map { .item($0) } ?? .preamble, afterBlank: false)
                continue
            }

            while let last = open.last, last.column >= column { open.removeLast() }
            let depth = open.last.map { $0.depth + 1 } ?? 0
            let (task, boxed) = taskBox(content)
            let (text, link) = trailingLink(boxed)
            _ = builder.add(depth: depth, title: text, link: link, taskState: task)
            open.append((column, depth))
        }
        return builder.finish()
    }

    /// The map, or the branch under `branchID`, as tab-indented text with a
    /// trailing line break. Notes go on `>` lines one level below their topic.
    public static func export(
        _ state: GraphState,
        branch branchID: NodeID? = nil,
        includeNotes: Bool = true
    ) throws -> String {
        var lines: [String] = []
        for (node, depth) in try OutlineWalk.nodes(of: state, from: branchID) {
            let indent = String(repeating: "\t", count: depth)
            var title = escapedTitle(TextLines.exportTitle(of: node))
            // The box goes before any escape, so `[ ] \\[ ] a` reads back as a task named `[ ] a`.
            if let task = node.taskState { title = TaskBox.write(task) + title }
            if let link = node.link, link.url != nil {
                title += title.isEmpty ? "<\(link.string)>" : " <\(link.string)>"
            }
            lines.append(indent + title)
            guard includeNotes, let noteLines = TextLines.noteLines(node.note) else { continue }
            for noteLine in noteLines {
                let text = noteLine.trimmingTrailingWhitespace()
                lines.append(indent + "\t" + (text.isEmpty ? ">" : "> " + text))
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    // MARK: Lines

    private static let bullets: [String] = ["- ", "* ", "+ ", "• "]

    private static func noteText(_ content: Substring) -> Substring? {
        if content == ">" { return "" }
        if content.hasPrefix("> ") { return content.dropFirst(2) }
        return nil
    }

    private static func title(from content: Substring) -> String {
        if content.hasPrefix("\\") { return String(content.dropFirst()) }
        for bullet in bullets where content.hasPrefix(bullet) {
            return String(content.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
        }
        if ["-", "*", "+", "•"].contains(content) { return "" }
        return String(content)
    }

    /// `[ ] Title` or `[x] Title` after any bullet (MM-35). The title after a
    /// box may itself be escaped, as `escapedTitle` writes it.
    private static func taskBox(_ content: Substring) -> (TaskState?, String) {
        let title = title(from: content)
        guard !content.hasPrefix("\\"), let (state, length) = TaskBox.prefix(Substring(title)) else { return (nil, title) }
        let rest = title.dropFirst(length)
        return (state, String(rest.hasPrefix("\\") ? rest.dropFirst() : rest))
    }

    /// `Title <https://example.com>`: a trailing `<…>` with an allowed scheme
    /// is the topic's link. Any other `<…>` stays in the title.
    private static func trailingLink(_ title: String) -> (String, TopicLink?) {
        guard title.hasSuffix(">"), let open = title.lastIndex(of: "<") else { return (title, nil) }
        let inner = title[title.index(after: open)..<title.index(before: title.endIndex)]
        guard inner.contains(":"), !inner.contains(where: \.isWhitespace),
              let link = TopicLink.normalized(String(inner))
        else { return (title, nil) }
        return (String(title[..<open].trimmingTrailingWhitespace()), link)
    }

    private static func escapedTitle(_ title: String) -> String {
        let needsEscape = title.hasPrefix("\\") || title.hasPrefix(">")
            || TaskBox.prefix(Substring(title)) != nil
            || bullets.contains { title.hasPrefix($0) }
            || ["-", "*", "+", "•"].contains(title)
        return needsEscape ? "\\" + title : title
    }
}

/// Pre-order walk over a map or one branch, collapsed branches included:
/// an export carries the whole map, not just what is on screen.
///
/// A whole map is the main tree, then each floating branch as a further
/// top-level item (FR-ORG-27). Reading it back makes them main topics, by the
/// import rule for several top-level items.
enum OutlineWalk {
    static func nodes(of state: GraphState, from branchID: NodeID?) throws -> [(MindNode, Int)] {
        let starts: [NodeID]
        if let branchID {
            starts = [branchID]
        } else {
            guard state.map.rootNodeID != nil else { return [] }
            starts = state.topLevelIDs
        }
        guard let first = starts.first, state.node(first) != nil else { throw InterchangeError.topicNotFound }
        var result: [(MindNode, Int)] = []
        var visited: Set<NodeID> = []
        var stack: [(NodeID, Int)] = starts.reversed().map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            guard let node = state.node(id), visited.insert(id).inserted else { continue }
            result.append((node, depth))
            stack.append(contentsOf: state.childIDs(of: id).reversed().map { ($0, depth + 1) })
        }
        return result
    }
}

extension Substring {
    func trimmingTrailingWhitespace() -> Substring {
        var end = endIndex
        while end > startIndex, self[index(before: end)].isWhitespace { end = index(before: end) }
        return self[startIndex..<end]
    }
}

extension String {
    func trimmingTrailingWhitespace() -> Substring {
        self[...].trimmingTrailingWhitespace()
    }
}
