import MindMapDomain
import SwiftUI

struct LibraryView: View {
    let model: LibraryModel
    let section: LibrarySection
    @Binding var selection: MapID?
    @State private var pendingDeletion: MindMap?

    var body: some View {
        let maps = model.maps(in: section)
        List(selection: $selection) {
            ForEach(maps) { map in
                MapRow(map: map)
                    .accessibilityIdentifier(AccessibilityID.Library.map)
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
        .accessibilityIdentifier(AccessibilityID.Library.list)
        .overlay {
            if model.hasLoaded, maps.isEmpty {
                emptyState
            }
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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(map.title.isEmpty ? String(localized: "Untitled Map") : map.title)
                    .font(Typography.rowTitle)
                    .lineLimit(1)
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
