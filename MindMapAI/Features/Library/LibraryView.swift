import MindMapDomain
import MindMapSearch
import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryModel
    let section: LibrarySection
    @Binding var selection: MapID?
    /// Shows a map in a window of its own (FR-LIB-10).
    var openInNewWindow: ((MapID) -> Void)?
    /// Only Delete Permanently asks first; Delete is undone with ⌘Z or Restore.
    @State private var pendingPermanentDeletion: MindMap?
    /// Recently Deleted keeps a selection of its own: picking a deleted map
    /// must not open it in the editor.
    @State private var deletedSelection: MapID?
    @Environment(FileTransfer.self) private var transfer: FileTransfer?
    @Environment(\.undoManager) private var undoManager

    private var showsDeletedMaps: Bool { section == .recentlyDeleted }

    var body: some View {
        let rows = rows
        let maps = rows.map(\.map)
        List(selection: showsDeletedMaps ? $deletedSelection : $selection) {
            ForEach(rows) { row in
                let map = row.map
                MapRow(map: map, excerpt: row.excerpt, daysLeft: model.daysLeft(for: map))
                    .accessibilityIdentifier(AccessibilityID.Library.map)
                    .contextMenu {
                        if showsDeletedMaps { deletedMenu(for: map) } else { menu(for: map) }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            if showsDeletedMaps { pendingPermanentDeletion = map } else { delete(map) }
                        } label: {
                            if showsDeletedMaps {
                                Label("Delete Permanently", systemImage: "trash.slash")
                            } else {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if showsDeletedMaps {
                            Button {
                                restore(map)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Library.list)
        // Only while the list has focus, so the menu shortcuts (⌘Delete,
        // ⌥⌘Delete) never take the key from a text field.
        .focusedValue(\.libraryMapActions, mapActions)
        .overlay {
            if model.isSearching {
                if maps.isEmpty, model.searchedQuery == SearchQuery(model.searchText) {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else if model.hasLoaded, maps.isEmpty {
                emptyState
            }
        }
        .searchable(text: $model.searchText, prompt: Text("Maps and Topics"))
        .task(id: SearchKey(text: model.searchText, generation: model.searchGeneration)) {
            await model.search()
        }
        .navigationTitle(Text(section.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // ⌘N lives in the File menu (MapCommands), which calls the same action.
                Button(action: create) {
                    Label("New Mind Map", systemImage: "plus")
                }
                .accessibilityIdentifier(AccessibilityID.Library.newMap)
            }
            if let transfer {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        transfer.beginImport(.newMap)
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .focusedSceneValue(\.newMapAction, NewMapAction(perform: create))
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .onDeleteCommand {
            if showsDeletedMaps {
                pendingPermanentDeletion = maps.first { $0.id == deletedSelection }
            } else if let map = maps.first(where: { $0.id == selection }) {
                delete(map)
            }
        }
        #endif
        .confirmationDialog(
            "Delete this map permanently?",
            isPresented: isConfirmingPermanentDeletion,
            titleVisibility: .visible,
            presenting: pendingPermanentDeletion
        ) { map in
            Button("Delete Permanently", role: .destructive) {
                deletePermanently(map)
            }
        } message: { map in
            Text("“\(map.title)” and all its topics will be deleted. This can’t be undone.")
        }
        .alert("Something Went Wrong", isPresented: isShowingFailure, presenting: model.failure) { _ in
            Button("OK") {}
        } message: { failure in
            switch failure {
            case .load: Text("Couldn’t load your maps.")
            case .save: Text("Couldn’t save the map.")
            }
        }
    }

    @ViewBuilder
    private func menu(for map: MindMap) -> some View {
        if let openInNewWindow {
            Button {
                openInNewWindow(map.id)
            } label: {
                Label("Open in New Window", systemImage: "macwindow.badge.plus")
            }
            Divider()
        }
        Button {
            Task { await model.toggleFavorite(map) }
        } label: {
            if map.isFavorite {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Add to Favorites", systemImage: "star")
            }
        }
        Divider()
        Button(role: .destructive) {
            delete(map)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func deletedMenu(for map: MindMap) -> some View {
        Button {
            restore(map)
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        Divider()
        Button(role: .destructive) {
            pendingPermanentDeletion = map
        } label: {
            Label("Delete Permanently…", systemImage: "trash.slash")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch section {
        case .all:
            // The first screen of a new install, so it carries the logo (FR-LIB-08).
            ContentUnavailableView {
                VStack(spacing: Spacing.lg) {
                    BrandMark()
                    Text("Start with one thought.")
                }
            } actions: {
                Button("New Mind Map", action: create)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.Library.newMap)
            }
        case .recent:
            ContentUnavailableView("No Recent Maps", systemImage: "clock", description: Text("Maps you edit appear here."))
        case .favorites:
            ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Mark a map as a favorite to find it here."))
        case .recentlyDeleted:
            ContentUnavailableView(
                "No Recently Deleted Maps",
                systemImage: "trash",
                description: Text("Deleted maps stay here for 30 days, then are deleted permanently.")
            )
        }
    }

    private struct Row: Identifiable {
        let map: MindMap
        let excerpt: String?
        var id: MapID { map.id }
    }

    private struct SearchKey: Equatable {
        let text: String
        let generation: Int
    }

    /// The section's maps, or while searching, the ones that match.
    private var rows: [Row] {
        guard model.isSearching else {
            return model.maps(in: section).map { Row(map: $0, excerpt: nil) }
        }
        return model.searchRows(in: section).map { row in
            switch row.match {
            case .title: Row(map: row.map, excerpt: nil)
            case .content(let excerpt): Row(map: row.map, excerpt: excerpt)
            }
        }
    }

    private var isConfirmingPermanentDeletion: Binding<Bool> {
        Binding { pendingPermanentDeletion != nil } set: { if !$0 { pendingPermanentDeletion = nil } }
    }

    /// What the menu bar's library commands act on: the selected map of this section.
    private var mapActions: LibraryMapActions {
        if showsDeletedMaps {
            guard let map = model.deletedMaps.first(where: { $0.id == deletedSelection }) else { return LibraryMapActions() }
            return LibraryMapActions(
                restore: { restore(map) },
                deletePermanently: { pendingPermanentDeletion = map }
            )
        }
        guard let map = model.maps.first(where: { $0.id == selection }) else { return LibraryMapActions() }
        return LibraryMapActions(delete: { delete(map) })
    }

    private var isShowingFailure: Binding<Bool> {
        Binding { model.failure != nil } set: { if !$0 { model.failure = nil } }
    }

    private func create() {
        Task {
            if let id = await model.createMap() {
                selection = id
            }
        }
    }

    private func delete(_ map: MindMap) {
        if selection == map.id {
            selection = nil
        }
        Task { await model.delete(map, undoManager: undoManager) }
    }

    private func restore(_ map: MindMap) {
        if deletedSelection == map.id {
            deletedSelection = nil
        }
        Task { await model.restore(map, undoManager: undoManager) }
    }

    private func deletePermanently(_ map: MindMap) {
        if deletedSelection == map.id {
            deletedSelection = nil
        }
        Task { await model.deletePermanently(map) }
    }
}

struct MapRow: View {
    let map: MindMap
    /// Topic text that matched a search, shown when the title did not match.
    var excerpt: String?
    /// Set for a map in Recently Deleted, in place of its edit time.
    var daysLeft: Int?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(map.title.isEmpty ? String(localized: "Untitled Map") : map.title)
                    .font(Typography.rowTitle)
                    .lineLimit(1)
                if let excerpt {
                    Text(excerpt)
                        .font(Typography.rowDetail)
                        .lineLimit(1)
                }
                Group {
                    if let daysLeft {
                        Text("\(daysLeft) days left")
                    } else {
                        Text("Edited \(map.updatedAt, format: .relative(presentation: .named))")
                    }
                }
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.sm)
            if map.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(Palette.favorite)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
