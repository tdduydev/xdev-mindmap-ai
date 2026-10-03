import MindMapDomain
import SwiftUI

/// The watch's only list: Add Idea on top, then recent maps.
struct WatchRootView: View {
    @Bindable var model: WatchModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.isCapturing = true
                    } label: {
                        Label("Add Idea", systemImage: "plus.bubble")
                    }
                    .foregroundStyle(WatchStyle.accent)
                    .accessibilityIdentifier("watch.addIdea")
                }
                if model.isICloudOff {
                    Section {
                        ICloudNotice()
                    }
                }
                Section("Recent Maps") {
                    if !model.isStoreAvailable {
                        Text("Your maps can't be opened on this watch right now.")
                            .foregroundStyle(.secondary)
                    } else if model.isLoaded && model.recentMaps.isEmpty {
                        Text("No maps yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.recentMaps) { map in
                        NavigationLink(value: map.id) {
                            Text(map.title)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("MindMap AI")
            .navigationDestination(for: MapID.self) { mapID in
                WatchOutlineView(model: model, mapID: mapID, title: model.recentMaps.first { $0.id == mapID }?.title ?? "")
            }
            .sheet(isPresented: $model.isCapturing) {
                CaptureView(model: model)
            }
            .task { await model.load() }
        }
    }
}

/// FR-WCH-04: maps from other devices need iCloud on.
private struct ICloudNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WatchStyle.noticeSpacing) {
            Label("iCloud Is Off", systemImage: "icloud.slash")
                .font(.headline)
            Text("Turn on iCloud for MindMap AI on your iPhone to see your maps here. Ideas you add are kept on this watch until then.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
