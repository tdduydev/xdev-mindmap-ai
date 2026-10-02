import MindMapDomain
import MindMapGraph
import SwiftUI

/// `link`, or `envelope` for an email address.
struct TopicLinkSymbol: View {
    let link: TopicLink

    var body: some View {
        Image(systemName: link.isMail ? "envelope" : "link")
    }
}

/// The link mark on the bottom-trailing corner of a topic card. On the corner,
/// as the note mark is, so adding a link never changes the measured box and
/// does not move the map. A click opens it in the browser or mail app;
/// nothing is fetched before that.
struct TopicLinkButton: View {
    let link: TopicLink
    let url: URL
    let style: TopicStyle
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            TopicLinkSymbol(link: link)
                .font(.system(size: CanvasMetrics.linkSymbolSize))
                .foregroundStyle(style.secondaryTextColor.color)
                .padding(Spacing.xxs)
                .background(Palette.canvasBackground, in: Circle())
                // Centred in the target, so the guides below still centre the mark on the corner.
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: url.absoluteString))
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
        .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
        // The topic element has Open Link and names the host.
        .accessibilityHidden(true)
    }
}

/// VoiceOver: "Link: example.com" (the host or the address, never the whole
/// URL with its query) and an Open Link action.
struct TopicLinkAccessibility: ViewModifier {
    let link: TopicLink?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        if let link, let url = link.url, let name = link.displayName {
            content
                .accessibilityCustomContent(Text("Link"), Text(verbatim: name))
                .accessibilityAction(named: Text("Open Link")) { openURL(url) }
        } else {
            content
        }
    }
}

/// Topic ▸ Add Link…: one URL field, checked as it is typed and on Add.
struct TopicLinkSheet: View {
    let session: EditorSession
    let nodeID: NodeID
    @State private var text: String
    @State private var error: TopicLinkError?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    private let hadLink: Bool

    init(session: EditorSession, nodeID: NodeID) {
        self.session = session
        self.nodeID = nodeID
        let link = session.engine.state.node(nodeID)?.link
        hadLink = link != nil
        _text = State(initialValue: link?.string ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TopicLinkTextField(text: $text, error: error, onSubmit: save)
                        .focused($isFocused)
                } footer: {
                    Text("Web addresses and email addresses. Nothing is loaded until you open the link.")
                }
                if hadLink {
                    Section {
                        Button("Remove Link", role: .destructive) {
                            session.removeLink(from: nodeID)
                            dismiss()
                        }
                        .accessibilityIdentifier(AccessibilityID.Link.remove)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(hadLink ? Text("Edit Link") : Text("Add Link"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Link.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hadLink ? "Save" : "Add", action: save)
                        .disabled(text.allSatisfy(\.isWhitespace) && !hadLink)
                        .accessibilityIdentifier(AccessibilityID.Link.save)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: Metrics.linkSheetMinWidth)
        #endif
        .onAppear { isFocused = true }
        .onChange(of: text) { _, text in error = Self.check(text) }
    }

    private func save() {
        if let refused = session.setLink(text, for: nodeID) {
            error = refused
        } else {
            dismiss()
        }
    }

    static func check(_ text: String) -> TopicLinkError? {
        do {
            _ = try TopicLink.validated(text)
            return nil
        } catch {
            return error
        }
    }
}

/// The URL field with its reason under it, shared by the sheet and the inspector.
struct TopicLinkTextField: View {
    @Binding var text: String
    let error: TopicLinkError?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Link", text: $text, prompt: Text(verbatim: "https://example.com"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(onSubmit)
                .accessibilityIdentifier(AccessibilityID.Link.field)
            if let error {
                Text(error.message)
                    .font(Typography.rowDetail)
                    .foregroundStyle(Palette.danger)
                    .accessibilityIdentifier(AccessibilityID.Link.error)
            }
        }
    }
}

/// The inspector's Link section. Typing stays a draft; Return or leaving the
/// field makes it one "Add Link" or "Edit Link" step, as the note does. A
/// refused draft stays in the field with its reason and changes nothing.
struct TopicLinkInspectorField: View {
    let session: EditorSession
    let nodeID: NodeID
    let link: TopicLink?
    @State private var draft: String
    @State private var error: TopicLinkError?
    @FocusState private var isFocused: Bool
    @Environment(\.openURL) private var openURL

    init(session: EditorSession, nodeID: NodeID, link: TopicLink?) {
        self.session = session
        self.nodeID = nodeID
        self.link = link
        _draft = State(initialValue: link?.string ?? "")
    }

    var body: some View {
        TopicLinkTextField(text: $draft, error: error, onSubmit: commit)
            .focused($isFocused)
            .onChange(of: draft) { _, text in error = TopicLinkSheet.check(text) }
            .onChange(of: link) { _, link in
                if !isFocused { draft = link?.string ?? "" }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onDisappear(perform: commit)
        if let link, let url = link.url {
            Button { openURL(url) } label: {
                Label("Open Link", systemImage: link.isMail ? "envelope" : "arrow.up.forward.square")
            }
            .accessibilityIdentifier(AccessibilityID.Link.open)
            Button("Remove Link", role: .destructive) { session.removeLink(from: nodeID) }
        }
    }

    private func commit() {
        let current = session.engine.state.node(nodeID)?.link?.string ?? ""
        guard draft != current else { return }
        error = session.setLink(draft, for: nodeID)
    }
}

/// Add Link…, or Open Link, Edit Link… and Remove Link, in a topic's context menu.
struct TopicLinkMenuItems: View {
    let topic: CanvasTopic
    let model: CanvasModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let link = topic.link, let url = link.url {
            Button("Open Link") { openURL(url) }
            Button("Edit Link…") { model.editLink(topic.id) }
            Button("Remove Link") { model.removeLink(topic.id) }
        } else {
            Button("Add Link…") { model.editLink(topic.id) }
        }
    }
}

/// The link mark after a title in the outline; a click opens it.
struct OutlineLinkButton: View {
    let link: TopicLink
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            TopicLinkSymbol(link: link)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: url.absoluteString))
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        // The row has Open Link and names the host.
        .accessibilityHidden(true)
    }
}
