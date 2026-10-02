import MindMapDomain
import MindMapGraph
import SwiftUI

/// Manage Tags: rename, recolour, merge, delete, and move tags between the
/// map and the library. Map tag changes are undo steps of the map; shared tag
/// changes reach every map and are not, so Delete asks first.
struct TagManagerView: View {
    @Bindable var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var sharedCounts: [TagID: Int] = [:]
    @State private var pendingDelete: MindTag?

    var body: some View {
        NavigationStack {
            let counts = session.engine.state.tagUseCounts()
            List {
                Section {
                    if session.engine.state.mapTags.isEmpty {
                        Text("Tags you add to topics appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.engine.state.mapTags) { tag in
                        TagManagerRow(session: session, tag: tag, topicCount: counts[tag.id] ?? 0) { pendingDelete = $0 }
                    }
                } header: {
                    Text("Map Tags")
                } footer: {
                    Text("Only in this map. You can undo changes to them.")
                }
                Section {
                    if session.engine.state.sharedTags.isEmpty {
                        Text("Make a tag shared to offer it in every map.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.engine.state.sharedTags) { tag in
                        TagManagerRow(session: session, tag: tag, topicCount: counts[tag.id] ?? 0) { pendingDelete = $0 }
                    }
                } header: {
                    Text("Shared Tags")
                } footer: {
                    Text("Offered in every map. Changes reach every map and can’t be undone.")
                }
            }
            .navigationTitle(Text("Manage Tags"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { sharedCounts = await session.sharedTagMapCounts() }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { tag in
                Button("Delete Tag", role: .destructive) {
                    Task { await session.deleteTag(tag.id) }
                }
            } message: { tag in
                if tag.isShared {
                    Text("“\(tag.name)” is used in \(sharedCounts[tag.id] ?? 0) maps. Deleting it removes it from every map and can’t be undone. The topics stay.")
                } else {
                    Text("The tag is removed from its topics. The topics stay.")
                }
            }
            .alert(
                Text("Couldn’t Change the Tag"),
                isPresented: Binding(get: { session.tagFailure != nil }, set: { if !$0 { session.tagFailure = nil } }),
                presenting: session.tagFailure
            ) { _ in
                Button("OK") { session.tagFailure = nil }
            } message: { failure in
                Text(failure.message)
            }
        }
        .frame(minWidth: Metrics.tagManagerSize.width, minHeight: Metrics.tagManagerSize.height)
    }

    private var deleteTitle: Text {
        Text("Delete “\(pendingDelete?.name ?? "")”?")
    }
}

private struct TagManagerRow: View {
    let session: EditorSession
    let tag: MindTag
    let topicCount: Int
    let onDelete: (MindTag) -> Void
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(session: EditorSession, tag: MindTag, topicCount: Int, onDelete: @escaping (MindTag) -> Void) {
        self.session = session
        self.tag = tag
        self.topicCount = topicCount
        self.onDelete = onDelete
        _draft = State(initialValue: tag.name)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TagSwatch(color: tag.color)
            TextField("Tag Name", text: $draft)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: tag.name) { _, name in if !isFocused { draft = name } }
            Spacer()
            Text("\(topicCount) topics")
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
            actions
        }
    }

    private var actions: some View {
        Menu {
            Picker("Color", selection: colorBinding) {
                Text("None").tag(TopicColor?.none)
                ForEach(TopicColor.all, id: \.self) { color in
                    Label(color.title, systemImage: color.shapeSymbol).tag(TopicColor?.some(color))
                }
            }
            let survivors = session.availableTags.filter { session.canMerge(tag.id, into: $0.id) }
            Menu("Merge Into") {
                ForEach(survivors) { survivor in
                    Button(survivor.name) { Task { await session.mergeTag(tag.id, into: survivor.id) } }
                }
            }
            .disabled(survivors.isEmpty)
            if tag.isShared {
                Button("Make Map Tag") { Task { await session.makeMapTag(tag.id) } }
            } else {
                Button("Make Shared") { Task { await session.makeShared(tag.id) } }
            }
            Divider()
            Button("Delete Tag…", role: .destructive) { onDelete(tag) }
        } label: {
            Label("Tag Actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help(Text("Tag Actions"))
    }

    private var colorBinding: Binding<TopicColor?> {
        Binding(get: { tag.color }, set: { color in Task { await session.setTagColor(tag.id, to: color) } })
    }

    private func commit() {
        guard draft != tag.name else { return }
        let name = draft
        Task {
            await session.renameTag(tag.id, to: name)
            // Refused or cleaned: show what the tag is called now.
            draft = session.engine.state.tag(tag.id)?.name ?? name
        }
    }
}
