import Foundation
import MindMapDomain

/// Puts an image on a topic, replaces the one it has, or removes it (`image:
/// nil`): "Add Image", "Replace Image", "Remove Image" (FR-ORG-28).
///
/// The change set keeps the new image's bytes, and the old one's when the
/// engine has them in `imageData`, so undo and redo bring the picture back.
public struct SetNodeImageCommand: GraphCommand {
    public let nodeID: NodeID
    /// With its bytes (`ProcessedImage.image(…)`); its `nodeID` is set to `nodeID`.
    public let image: MindImage?

    public init(nodeID: NodeID, image: MindImage?) {
        self.nodeID = nodeID
        self.image = image
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard transaction.state.node(nodeID) != nil else { throw GraphError.nodeNotFound(nodeID) }
        if let image, image.data == nil { throw GraphError.imageHasNoData(image.id) }
        // Every image on the topic goes, sync duplicates too, so the new one is the only one.
        for old in transaction.state.images(of: nodeID) {
            try transaction.removeImage(old.id)
        }
        guard var image else { return }
        image.nodeID = nodeID
        image.altText = image.altText.flatMap(MindImage.normalizedAltText)
        image.displayWidth = MindImage.normalizedDisplayWidth(image.displayWidth)
        image.byteCount = image.data?.count ?? 0
        image.createdAt = transaction.now
        image.updatedAt = transaction.now
        try transaction.insertImage(image)
    }
}

/// Changes an image's size on the canvas or its description, never its
/// bytes: "Change Image Size", "Edit Image Description". Saving it leaves the
/// stored file alone.
public struct UpdateImageCommand: GraphCommand {
    public let imageID: ImageID
    /// Points; nil is Medium (`MindImage.defaultDisplayWidth`).
    public let displayWidth: FieldChange<Double?>
    /// Normalized with `MindImage.normalizedAltText`; blank clears it.
    public let altText: FieldChange<String?>

    public init(imageID: ImageID, displayWidth: FieldChange<Double?> = .keep, altText: FieldChange<String?> = .keep) {
        self.imageID = imageID
        self.displayWidth = displayWidth
        self.altText = altText
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let width = displayWidth.map(MindImage.normalizedDisplayWidth)
        let text = altText.map { $0.flatMap(MindImage.normalizedAltText) }
        try transaction.updateImage(imageID) { image in
            width.apply(to: &image.displayWidth)
            text.apply(to: &image.altText)
        }
    }
}

extension GraphState {
    /// The images on these topics and every topic under them: what Delete,
    /// Merge or Remove Summary of them would remove. The editor loads their
    /// bytes into `GraphEngine.imageData` first, so undo can restore them.
    public func images(inBranchesOf nodeIDs: [NodeID]) -> [MindImage] {
        guard !images.isEmpty else { return [] }
        var branch: Set<NodeID> = []
        for root in nodeIDs where branch.insert(root).inserted {
            branch.formUnion(descendants(of: root))
        }
        let result = images.values.filter { branch.contains($0.nodeID) }
        return result.sorted { $0.id < $1.id }
    }
}
