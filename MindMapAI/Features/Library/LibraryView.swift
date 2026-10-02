import MindMapDomain
import MindMapSearch
import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryModel
    let section: LibrarySection
    @Binding var selection: MapID?
    @State private var pendingDeletion: MindMap?

    var body: some View {
        let rows = rows
        let maps = rows.map(\.map)
        List(selection: $selection) {
            ForEach(rows) { row in
                let map = row.map
                MapRow(map: map, excerpt: row.excerpt)
                    .contextMenu { menu(for: map) }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDeletion = map
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
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
            }
        }
        .focusedSceneValue(\.newMapAction, NewMapAction(perform: create))
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .onDeleteCommand {
            pendingDeletion = maps.first { $0.id == selection }
        }
        #endif
        .confirmationDialog(
            "Delete this map?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { map in
            Button("Delete", role: .destructive) {
                delete(map)
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
            pendingDeletion = map
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch section {
        case .all:
            ContentUnavailableView {
                Label("Start with one thought.", systemImage: "point.3.connected.trianglepath.dotted")
            } actions: {
                Button("New Mind Map", action: create)
                    .buttonStyle(.borderedProminent)
            }
        case .recent:
            ContentUnavailableView("No Recent Maps", systemImage: "clock", description: Text("Maps you edit appear here."))
        case .favorites:
            ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Mark a map as a favorite to find it here."))
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

    private var isConfirmingDeletion: Binding<Bool> {
        Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } }
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
        Task { await model.delete(map) }
    }
}

struct MapRow: View {
    let map: MindMap
    /// Topic text that matched a search, shown when the title did not match.
    var excerpt: String?

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
                Text("Edited \(map.updatedAt, format: .relative(presentation: .named))")
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
