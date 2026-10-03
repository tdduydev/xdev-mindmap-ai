import MindMapDomain
import MindMapSharing
import SwiftUI

/// FR-WCH-02: a map read top to bottom, read-only. Branches collapse and
/// expand here only; the map itself is not changed. watchOS has no
/// `OutlineGroup` or `DisclosureGroup`, so rows are flattened by hand.
struct WatchOutlineView: View {
    let model: WatchModel
    let mapID: MapID
    let title: String
    @State private var topics: [ReadOnlyTopic]?
    @State private var collapsed: Set<NodeID> = []
    @State private var isLoaded = false

    var body: some View {
        List {
            if let topics {
                ForEach(rows(of: topics), id: \.topic.id) { row in
                    TopicRow(topic: row.topic, depth: row.depth, isCollapsed: collapsed.contains(row.topic.id)) {
                        toggle(row.topic.id)
                    }
                }
            } else if isLoaded {
                Text("This map is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .task {
            topics = await model.outline(of: mapID)
            isLoaded = true
        }
    }

    private func toggle(_ id: NodeID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func rows(of topics: [ReadOnlyTopic]) -> [(topic: ReadOnlyTopic, depth: Int)] {
        var result: [(topic: ReadOnlyTopic, depth: Int)] = []
        var stack = topics.reversed().map { ($0, 0) }
        while let (topic, depth) = stack.popLast() {
            result.append((topic, depth))
            if let children = topic.children, !collapsed.contains(topic.id) {
                stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }
}

private struct TopicRow: View {
    let topic: ReadOnlyTopic
    let depth: Int
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        if topic.children == nil {
            label
        } else {
            Button(action: toggle) { label }
                .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
                .accessibilityHint(isCollapsed ? Text("Shows the subtopics") : Text("Hides the subtopics"))
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: WatchStyle.noticeSpacing) {
            if topic.children != nil {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(topic.title)
                .font(depth == 0 ? .headline : .body)
        }
        .padding(.leading, CGFloat(min(depth, WatchStyle.maximumIndentLevels)) * WatchStyle.indentPerLevel)
    }
}
