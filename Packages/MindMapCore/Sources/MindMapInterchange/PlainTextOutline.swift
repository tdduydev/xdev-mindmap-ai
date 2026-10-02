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
            _ = builder.add(depth: depth, title: title(from: content))
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
            lines.append(indent + escapedTitle(TextLines.singleLine(node.title)))
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

    private static func escapedTitle(_ title: String) -> String {
        let needsEscape = title.hasPrefix("\\") || title.hasPrefix(">")
            || bullets.contains { title.hasPrefix($0) }
            || ["-", "*", "+", "•"].contains(title)
        return needsEscape ? "\\" + title : title
    }
}

/// Pre-order walk over a map or one branch, collapsed branches included:
/// an export carries the whole map, not just what is on screen.
enum OutlineWalk {
    static func nodes(of state: GraphState, from branchID: NodeID?) throws -> [(MindNode, Int)] {
        guard let startID = branchID ?? state.map.rootNodeID else { return [] }
        guard state.node(startID) != nil else { throw InterchangeError.topicNotFound }
        var result: [(MindNode, Int)] = []
        var visited: Set<NodeID> = []
        var stack: [(NodeID, Int)] = [(startID, 0)]
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
