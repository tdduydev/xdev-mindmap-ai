import Foundation
import MindMapDomain
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct TopicImagePicker: ViewModifier {
    let session: EditorSession
    @State private var showingPicker = false
    @State private var pendingTarget: NodeID?
    #if os(iOS)
    @State private var picked: PhotosPickerItem?
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .fileImporter(isPresented: isPresented, allowedContentTypes: [.image]) { result in
                guard let target = pendingTarget else { return }
                pendingTarget = nil
                session.imagePickerTarget = nil
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        Task { await session.addImage(data, to: target) }
                    } catch {
                        session.imageFailure = String(localized: "Couldn’t load the image")
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError {
                        session.imageFailure = String(localized: "Couldn’t load the image")
                    }
                }
            }
            .onChange(of: session.imagePickerTarget) { _, target in
                if let target { pendingTarget = target; showingPicker = true }
            }
            .modifier(TopicImageFailureAlert(session: session))
        #else
        content
            .photosPicker(isPresented: isPresented, selection: $picked, matching: .images)
            .onChange(of: picked) { _, item in
                guard let item, let target = pendingTarget else { return }
                pendingTarget = nil
                session.imagePickerTarget = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await session.addImage(data, to: target)
                    } else {
                        session.imageFailure = String(localized: "Couldn’t load the image")
                    }
                    picked = nil
                }
            }
            .onChange(of: session.imagePickerTarget) { _, target in
                if let target { pendingTarget = target; showingPicker = true }
            }
            .modifier(TopicImageFailureAlert(session: session))
        #endif
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { showingPicker }, set: {
            showingPicker = $0
            if !$0 { session.imagePickerTarget = nil }
        })
    }
}

private struct TopicImageFailureAlert: ViewModifier {
    let session: EditorSession

    func body(content: Content) -> some View {
        content.alert(session.imageFailure ?? "", isPresented: Binding(
            get: { session.imageFailure != nil },
            set: { if !$0 { session.imageFailure = nil } }
        )) {
            Button("OK") { session.imageFailure = nil }
        }
    }
}
