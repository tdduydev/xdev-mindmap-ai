import Foundation

/// Topics read from a file or the clipboard, before they are in any map.
///
/// Kept flat, in reading order with a depth per topic, rather than as a nested
/// tree: parsers, commands and exporters all walk it with loops, so a file
/// nested thousands of levels deep cannot overflow the stack.
public struct OutlineDraft: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        /// 0 for a top-level topic.
        public var depth: Int
        public var title: String
        public var note: String?

        public init(depth: Int, title: String, note: String? = nil) {
            self.depth = depth
            self.title = title
            self.note = note
        }
    }

    public private(set) var items: [Item]

    /// Depths are clamped so the outline is always a valid tree: the first item
    /// is top level and no item is more than one level below the one before.
    public init(items: [Item] = []) {
        var previousDepth = -1
        self.items = items.map { item in
            var item = item
            item.depth = min(max(0, item.depth), previousDepth + 1)
            previousDepth = item.depth
            return item
        }
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Items at depth 0, which become siblings when inserted.
    public var topLevelCount: Int { items.count { $0.depth == 0 } }
}
