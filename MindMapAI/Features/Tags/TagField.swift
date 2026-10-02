import MindMapDomain
import MindMapGraph
import SwiftUI

/// The inspector's Tags section: the selected topics' tags as chips with a
/// remove button, and a field that offers the map's and the library's tags
/// as you type, or Create Tag for a new name. With several topics selected,
/// every action applies to all of them, and a tag only some carry says so.
struct TagField: View {
    let session: EditorSession
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var targets: [NodeID] { session.orderedSelection }

    var body: some View {
        let tags = session.tags(on: targets)
        if !tags.isEmpty {
            ForEach(tags) { tag in
                AppliedTagRow(tag: tag, coverage: session.coverage(of: tag.id, on: targets)) {
                    session.removeTag(tag.id, from: targets)
                }
            }
        }
        TextField("Add Tag", text: $text, prompt: Text("Add a tag"))
            .focused($isFocused)
            .onSubmit(submit)
            .onChange(of: session.tagFieldFocusRequest, initial: true) { _, request in
                guard request else { return }
                isFocused = true
                session.tagFieldFocusRequest = false
            }
            .accessibilityHint(Text("Type a tag name, then press Return"))
            .accessibilityIdentifier(AccessibilityID.Inspector.tagField)
        // Only while typing: a list that came and went with focus would
        // vanish under the click that picks from it.
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            ForEach(session.tagMatches(for: text, on: targets).prefix(Self.maximumOffers)) { tag in
                Button {
                    session.addTag(tag.id, to: targets)
                    text = ""
                } label: {
                    TagOfferLabel(tag: tag)
                }
                .buttonStyle(.borderless)
            }
            if session.wouldCreateTag(named: text), let name = MindTag.normalizedName(text) {
                Button {
                    submit()
                } label: {
                    Label("Create Tag “\(name)”", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Enough to choose from without pushing the rest of the inspector away.
    static let maximumOffers = 6

    /// Return adds the tag with that name, or creates it.
    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if session.addTag(named: text, to: targets) { text = "" }
    }
}

/// A tag on the selection, with its colour, and a remove button.
private struct AppliedTagRow: View {
    let tag: MindTag
    let coverage: TagCoverage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TagSwatch(color: tag.color)
            Text(verbatim: tag.name)
            if coverage == .some {
                // Text, not a dimmed chip, so a mixed state is not told by colour.
                Text("Some topics")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRemove) {
                Label("Remove Tag", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(Text("Remove Tag"))
            .accessibilityLabel(Text("Remove Tag \(tag.name)"))
        }
    }
}

/// A tag offered in the field, marked Shared when it belongs to the library.
struct TagOfferLabel: View {
    let tag: MindTag

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TagSwatch(color: tag.color)
            Text(verbatim: tag.name)
            if tag.isShared {
                Text("Shared")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A tag's colour as its paired shape, so it reads without colour too.
struct TagSwatch: View {
    let color: TopicColor?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let variant = ColorVariant(colorScheme: colorScheme, contrast: contrast)
        Image(systemName: color?.shapeSymbol ?? "tag")
            .foregroundStyle(TopicColor.chipColors(for: color, in: variant).line.color)
            .accessibilityHidden(true)
    }
}
