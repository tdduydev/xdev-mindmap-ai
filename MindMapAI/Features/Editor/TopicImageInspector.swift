import MindMapDomain
import SwiftUI

struct TopicImageInspector: View {
    let session: EditorSession
    let image: MindImage
    @State private var data: Data?
    @State private var description: String
    @FocusState private var descriptionFocused: Bool

    init(session: EditorSession, image: MindImage) {
        self.session = session
        self.image = image
        _description = State(initialValue: image.altText ?? "")
    }

    var body: some View {
        TopicImageView(image: image, level: 1, spec: TopicTextSpecs.designSizes().spec(level: 1), data: data)
            .task(id: image.id) { data = await session.imageBytes(for: image) }
        Picker("Image Size", selection: Binding(
            get: { image.displayWidth ?? CanvasMetrics.imageWidthMedium },
            set: { session.setImageSize($0, for: image.id) }
        )) {
            Text("Small").tag(CanvasMetrics.imageWidthSmall)
            Text("Medium").tag(CanvasMetrics.imageWidthMedium)
            Text("Large").tag(CanvasMetrics.imageWidthLarge)
        }
        TextField("Describe the image for VoiceOver", text: $description)
            .focused($descriptionFocused)
            .onSubmit(saveDescription)
            .onChange(of: descriptionFocused) { _, focused in if !focused { saveDescription() } }
        Button("Replace Image…") { session.imagePickerTarget = image.nodeID }
        Button("Remove Image", role: .destructive) {
            Task { await session.removeImage(from: image.nodeID) }
        }
    }

    private func saveDescription() {
        let normalized = MindImage.normalizedAltText(description)
        if normalized != image.altText { session.setImageDescription(description, for: image.id) }
    }
}
