import MindMapDomain
import SwiftUI

/// A rounded bubble with a tail on its bottom edge pointing down at the card
/// (docs/design-system.md "Node types"). The rect includes the tail's height.
nonisolated struct CalloutBubbleShape: Shape {
    /// Where the tail's tip sits, from the bubble's leading edge.
    let tailX: CGFloat

    func path(in rect: CGRect) -> Path {
        let tailHeight = CanvasMetrics.calloutTailHeight
        let halfTail = CanvasMetrics.calloutTailWidth / 2
        let radius = CanvasMetrics.calloutCornerRadius
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        // Kept off the rounded corners, so the tail always meets a straight edge.
        let tip = min(max(rect.minX + tailX, body.minX + radius + halfTail), body.maxX - radius - halfTail)
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        path.move(to: CGPoint(x: tip - halfTail, y: body.maxY))
        path.addLine(to: CGPoint(x: tip, y: rect.maxY))
        path.addLine(to: CGPoint(x: tip + halfTail, y: body.maxY))
        path.closeSubpath()
        return path
    }

    /// The tail points at the middle of the card below the bubble.
    static func tailX(bubble: CGRect, card: CGRect) -> CGFloat {
        card.midX - bubble.minX
    }
}

/// The bubble as drawn on the canvas and in pictures of the map: fill, outline
/// and wrapped text, at 100% zoom. Content, not chrome, so no glass.
struct CalloutBubble<Content: View>: View {
    let bubble: CGRect
    let card: CGRect
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = CalloutBubbleShape(tailX: CalloutBubbleShape.tailX(bubble: bubble, card: card))
        let lineWidth = contrast == .increased
            ? CanvasMetrics.calloutStrokeWidthHighContrast
            : CanvasMetrics.calloutStrokeWidth
        content
            .padding(.horizontal, CanvasMetrics.calloutHorizontalPadding)
            .padding(.vertical, CanvasMetrics.calloutVerticalPadding)
            .frame(width: bubble.width, height: bubble.height)
            .padding(.bottom, CanvasMetrics.calloutTailHeight)
            .background {
                shape.fill(Palette.calloutFill)
                shape.stroke(Palette.calloutStroke, lineWidth: lineWidth)
            }
    }
}

/// The callout text in the bubble's font.
struct CalloutText: View {
    let text: String
    let spec: TopicCalloutSpec

    var body: some View {
        Text(verbatim: text)
            .font(.custom(spec.postScriptName, fixedSize: spec.pointSize))
            .lineSpacing(spec.lineSpacing)
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.topicText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A topic's callout on the canvas: a click selects the topic, a double click
/// or Edit Callout opens the text in place.
struct CanvasCalloutView: View {
    let topic: CanvasTopic
    let bubble: CGRect
    let spec: TopicCalloutSpec
    let isEditing: Bool
    let model: CanvasModel

    var body: some View {
        CalloutBubble(bubble: bubble, card: topic.frame) {
            if isEditing {
                CalloutEditor(session: model.session, nodeID: topic.id, text: topic.callout ?? "", spec: spec)
            } else {
                CalloutText(text: topic.callout ?? "", spec: spec)
            }
        }
        .contentShape(.interaction, Rectangle())
        .onTapGesture(count: 2) { model.editCallout(topic.id) }
        .simultaneousGesture(TapGesture().onEnded { model.select(topic.id) })
        .contextMenu {
            Button("Edit Callout") { model.editCallout(topic.id) }
            Button("Remove Callout") { model.removeCallout(topic.id) }
        }
        .transition(.opacity)
        // The topic element reads the callout as custom content; the bubble
        // is not a second element, except while its field is open.
        // No identifier here: on a container it would replace the field's.
        .accessibilityHidden(!isEditing)
    }
}

/// The field in an open bubble. Return commits ("Add Callout", "Edit
/// Callout", or "Remove Callout" for blank text); Esc closes it unchanged.
struct CalloutEditor: View {
    let session: EditorSession
    let nodeID: NodeID
    let spec: TopicCalloutSpec
    @State private var draft: String
    @State private var isCancelled = false
    @FocusState private var isFocused: Bool

    init(session: EditorSession, nodeID: NodeID, text: String, spec: TopicCalloutSpec) {
        self.session = session
        self.nodeID = nodeID
        self.spec = spec
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextField("Callout", text: $draft, prompt: Text("Callout"), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.custom(spec.postScriptName, fixedSize: spec.pointSize))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.topicText)
            .focused($isFocused)
            .onChange(of: draft) { _, text in
                // A vertical field takes Return as a new line; a callout is one paragraph.
                if text.contains("\n") {
                    draft = text.replacingOccurrences(of: "\n", with: "")
                    commit()
                } else if text.count > MindNode.maximumCalloutLength {
                    draft = String(text.prefix(MindNode.maximumCalloutLength))
                }
            }
            .onSubmit(commit)
            #if os(macOS)
            .onExitCommand(perform: cancel)
            #endif
            .onKeyPress(.escape) {
                cancel()
                return .handled
            }
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused, !isCancelled { commit() }
            }
            .accessibilityIdentifier(AccessibilityID.Canvas.calloutField)
    }

    private func commit() {
        guard session.calloutEditorTarget == nodeID else { return }
        session.setCallout(draft, for: nodeID)
    }

    private func cancel() {
        isCancelled = true
        if session.calloutEditorTarget == nodeID { session.calloutEditorTarget = nil }
    }
}

/// Add Callout, or Edit Callout and Remove Callout, in a topic's context menu.
struct TopicCalloutMenuItems: View {
    let topic: CanvasTopic
    let model: CanvasModel

    var body: some View {
        if topic.callout?.isEmpty == false {
            Button("Edit Callout") { model.editCallout(topic.id) }
            Button("Remove Callout") { model.removeCallout(topic.id) }
        } else {
            Button("Add Callout") { model.editCallout(topic.id) }
        }
    }
}

/// VoiceOver reads the callout as custom content of its topic, with an
/// action to add or edit it (docs/node-organization.md "Callouts").
struct TopicCalloutAccessibility: ViewModifier {
    let topicID: NodeID
    let callout: String?
    /// An AI suggestion is not a topic yet and takes no callout.
    var isSuggestion = false
    let model: CanvasModel

    func body(content: Content) -> some View {
        if isSuggestion {
            content
        } else if let callout, !callout.isEmpty {
            content
                .accessibilityCustomContent(Text("Callout"), Text(verbatim: callout))
                .accessibilityAction(named: Text("Edit Callout")) { model.editCallout(topicID) }
        } else {
            content
                .accessibilityAction(named: Text("Add Callout")) { model.editCallout(topicID) }
        }
    }
}
