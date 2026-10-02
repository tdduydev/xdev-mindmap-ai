import MindMapDomain
import MindMapGraph
import SwiftUI

/// Topic ▸ Tags and the topic context menu's Tags: the map's most used tags
/// as toggles, then Add Tag… and Manage Tags…. Toggles have no keys of their
/// own, like the other picker submenus; Add Tag… and Manage Tags… carry
/// theirs in the menu bar (`MapCommands`), so the keys are not registered twice.
struct TagsMenu: View {
    let session: EditorSession
    /// The topics the toggles act on; the selection when nil.
    var targets: [NodeID]?
    /// Opens the tag field for the menu's topics.
    let onAddTag: () -> Void

    var body: some View {
        Menu("Tags") {
            let tags = session.mostUsedTags()
            ForEach(tags) { tag in
                Toggle(isOn: binding(for: tag.id)) {
                    Text(verbatim: tag.name)
                }
            }
            if !tags.isEmpty { Divider() }
            Button("Add Tag…", action: onAddTag)
            Button("Manage Tags…") { session.isManagingTags = true }
        }
        .disabled((targets ?? session.orderedSelection).isEmpty)
    }

    /// On when every target has the tag; a mixed selection shows off, and
    /// choosing it tags them all.
    private func binding(for tagID: TagID) -> Binding<Bool> {
        Binding(
            get: { session.coverage(of: tagID, on: targets) == .all },
            set: { _ in session.toggleTag(tagID, on: targets) }
        )
    }
}
