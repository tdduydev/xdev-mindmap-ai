import Foundation
import MindMapDomain
import MindMapGraph
import MindMapImages
import MindMapPersistence
import OSLog

extension EditorSession {
    private enum ImageLoadError: Error { case missing }
    var selectedImage: MindImage? { selection.flatMap { engine.state.image(of: $0) } }
    var canEditSelectionImage: Bool { selectedIDs.count == 1 && selectedNode != nil }

    /// Populate the engine before a destructive command: its inverse needs the
    /// stored bytes because GraphState intentionally holds metadata only.
    func loadImageBytes(_ images: [MindImage]) async throws {
        for image in images where engine.imageData[image.id] == nil {
            guard let data = try await repository.imageData(for: image.id) else { throw ImageLoadError.missing }
            cacheImageData(data, for: image.id)
        }
    }

    func imageBytes(for image: MindImage) async -> Data? {
        do {
            try await loadImageBytes([image])
            return engine.imageData[image.id]
        } catch {
            Log.persistence.error("Loading topic image failed: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    func addImage(_ data: Data, to nodeID: NodeID) async {
        guard engine.state.node(nodeID) != nil else { return }
        do {
            let processed = try await ImageProcessor.standard.process(data)
            let old = engine.state.images.values.filter { $0.nodeID == nodeID }
            try await loadImageBytes(old)
            guard engine.state.node(nodeID) != nil else { return }
            let image = processed.image(mapID: map.id, nodeID: nodeID,
                displayWidth: old.first?.displayWidth, altText: old.first?.altText)
            let name = old.isEmpty ? String(localized: "Add Image") : String(localized: "Replace Image")
            perform(SetNodeImageCommand(nodeID: nodeID, image: image), named: name)
        } catch ImageProcessingError.tooLarge {
            imageFailure = String(localized: "This image is too large")
        } catch {
            imageFailure = String(localized: "This file isn't an image the app can read")
        }
    }

    func removeImage(from nodeID: NodeID) async {
        let old = engine.state.images.values.filter { $0.nodeID == nodeID }
        guard !old.isEmpty else { return }
        do {
            try await loadImageBytes(old)
            perform(SetNodeImageCommand(nodeID: nodeID, image: nil), named: String(localized: "Remove Image"))
        } catch {
            imageFailure = String(localized: "Couldn’t load the image")
        }
    }

    func setImageSize(_ width: Double, for imageID: ImageID) {
        perform(UpdateImageCommand(imageID: imageID, displayWidth: .set(width)), named: String(localized: "Change Image Size"))
    }

    func setImageDescription(_ description: String, for imageID: ImageID) {
        perform(UpdateImageCommand(imageID: imageID, altText: .set(description)), named: String(localized: "Edit Image Description"))
    }
}
