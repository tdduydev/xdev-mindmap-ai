import MindMapDomain
import MindMapGraph
import SwiftUI

/// Chips in rows, each at the width `TopicMeasurer` gave it, rows centred
/// under the title. Wraps the same way the measurer does, so the chips take
/// exactly the height the layout reserved.
struct ChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width += current.indices.isEmpty ? size.width : spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// One chip as the canvas and export draw it: the tag's badge colours, or
/// the AI style for a suggested tag (dashed outline and `sparkles`, as a
/// suggested topic has). Task chips (MM-35) use the graphite badge with a
/// symbol: the box, a progress ring, or `calendar`, which turns into
/// `exclamationmark.circle` with the date in `danger` when overdue.
struct TopicChipLabel: View {
    let chip: TopicChip
    let spec: TopicChipSpec
    let variant: ColorVariant
    /// The AI gradient, from the canvas; export draws no suggestions.
    var aiStyle: AnyShapeStyle?
    var secondaryText: Color = Palette.topicTextSecondary

    var body: some View {
        let colors = TopicColor.chipColors(for: chip.color, in: variant)
        HStack(spacing: 0) {
            if chip.hasSymbol {
                symbol(colors: colors)
                    .frame(width: spec.symbolWidth, alignment: chip.label.isEmpty ? .center : .leading)
                    .accessibilityHidden(true)
            }
            if !chip.label.isEmpty {
                Text(verbatim: chip.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(labelColor(colors: colors))
            }
        }
        .font(ContentFont.font(postScriptName: spec.postScriptName, size: spec.pointSize))
        .padding(.horizontal, spec.horizontalPadding)
        .frame(width: chip.width, height: spec.height)
        .background {
            if chip.isSuggestion {
                Capsule().fill(Palette.canvasBackground)
                Capsule().strokeBorder(
                    aiStyle ?? AnyShapeStyle(secondaryText),
                    style: StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, dash: CanvasMetrics.suggestionDash)
                )
            } else {
                Capsule().fill(colors.badgeFill.color)
            }
        }
    }

    private func labelColor(colors: BranchColors) -> Color {
        switch chip.kind {
        case .suggestion: secondaryText
        case .due(overdue: true): Palette.danger
        default: colors.badgeText.color
        }
    }

    @ViewBuilder
    private func symbol(colors: BranchColors) -> some View {
        switch chip.kind {
        case .suggestion:
            Image(systemName: "sparkles").foregroundStyle(aiStyle ?? AnyShapeStyle(secondaryText))
        case .checkbox(let done):
            Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(colors.badgeText.color)
        case .progress(let done, let total):
            TaskProgressRing(fraction: total == 0 ? 0 : Double(done) / Double(total), color: colors.badgeText.color)
                .frame(width: spec.pointSize, height: spec.pointSize)
        case .due(let overdue):
            Image(systemName: overdue ? "exclamationmark.circle" : "calendar")
                .foregroundStyle(overdue ? Palette.danger : colors.badgeText.color)
        case .tag, .more, .priority:
            EmptyView()
        }
    }
}

/// A small ring filled to the share of done tasks.
struct TaskProgressRing: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(CanvasMetrics.taskRingTrackOpacity), lineWidth: CanvasMetrics.taskRingWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: CanvasMetrics.taskRingWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(CanvasMetrics.taskRingWidth / 2)
    }
}

/// A topic's title with its chips under it, as `TopicMeasurer` measured them.
struct TopicTitleWithChips<Title: View, Chip: View>: View {
    let chips: [TopicChip]
    let spec: TopicChipSpec?
    @ViewBuilder let title: Title
    @ViewBuilder let chip: (TopicChip) -> Chip

    var body: some View {
        if let spec, !chips.isEmpty {
            VStack(spacing: spec.topGap) {
                title
                ChipFlowLayout(spacing: spec.spacing) {
                    ForEach(chips) { chip($0) }
                }
            }
        } else {
            title
        }
    }
}

/// The tag chips of an outline row: the first few tags, then "+n". Reads as
/// part of the row's text to VoiceOver, so they carry no element of their own.
struct OutlineTagChips: View {
    let tags: [MindTag]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let variant = ColorVariant(colorScheme: colorScheme, contrast: contrast)
        let limit = CanvasMetrics.maximumTopicTagChips
        HStack(spacing: CanvasMetrics.tagChipSpacing) {
            ForEach(tags.prefix(limit)) { tag in
                let colors = TopicColor.chipColors(for: tag.color, in: variant)
                Text(verbatim: tag.name)
                    .lineLimit(1)
                    .font(Typography.Content.badge.font)
                    .foregroundStyle(colors.badgeText.color)
                    .padding(.horizontal, CanvasMetrics.tagChipHorizontalPadding)
                    .frame(minHeight: CanvasMetrics.tagChipHeight)
                    .background(colors.badgeFill.color, in: Capsule())
            }
            if tags.count > limit {
                Text(verbatim: "+\(tags.count - limit)")
                    .font(Typography.Content.badge.font)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tags: \(tags.map(\.name).formatted(.list(type: .and)))"))
    }
}

/// Tags are read on request ("more content"), so a topic's VoiceOver value
/// stays short (docs/node-organization.md, *Accessibility*).
struct TagCustomContent: ViewModifier {
    let names: [String]

    func body(content: Content) -> some View {
        if names.isEmpty {
            content
        } else {
            content.accessibilityCustomContent(Text("Tags"), Text(verbatim: names.formatted(.list(type: .and))))
        }
    }
}

/// A chip on the canvas. A tag's chip is drawing only, so a click on it
/// still selects the topic; a suggested tag opens its review: the name to
/// edit, Accept and Discard.
struct TopicChipView: View {
    let chip: TopicChip
    let spec: TopicChipSpec
    let variant: ColorVariant
    let aiStyle: AnyShapeStyle
    let model: CanvasModel
    /// The topic the chip belongs to, for the task box.
    var topicID: NodeID?
    @State private var isReviewing = false

    var body: some View {
        let label = TopicChipLabel(chip: chip, spec: spec, variant: variant, aiStyle: aiStyle)
        if case .checkbox(let done) = chip.kind, let topicID {
            // The chip is shorter than a finger; the tap area grows to the minimum around it.
            let outset = max(0, (Metrics.minimumHitTarget - spec.height) / 2)
            Button { model.session.toggleDone(topicID) } label: { label }
                .buttonStyle(.plain)
                .contentShape(.interaction, Capsule().inset(by: -outset))
                .help(done ? Text("Mark as Not Done") : Text("Mark as Done"))
                // The topic element has Mark as Done and reads the state in its value.
                .accessibilityHidden(true)
        } else if case .suggestion(let id) = chip.kind {
            Button { isReviewing = true } label: { label }
                .buttonStyle(.plain)
                .help(Text("AI suggested tag"))
                .popover(isPresented: $isReviewing) {
                    SuggestedTagReview(name: chip.label) { name in
                        model.renameTagSuggestion(id, to: name)
                        model.acceptTagSuggestion(id)
                    } onDiscard: {
                        model.discardTagSuggestion(id)
                    }
                }
                .contextMenu {
                    Button("Accept Tag") { model.acceptTagSuggestion(id) }
                    Button("Edit Tag…") { isReviewing = true }
                    Divider()
                    Button("Discard Tag") { model.discardTagSuggestion(id) }
                }
                // The topic element offers Accept and Discard for each suggested tag.
                .accessibilityHidden(true)
        } else {
            label.allowsHitTesting(false)
        }
    }
}

/// A suggested tag's name, editable before Accept, with Accept and Discard.
struct SuggestedTagReview: View {
    let onAccept: (String) -> Void
    let onDiscard: () -> Void
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(name: String, onAccept: @escaping (String) -> Void, onDiscard: @escaping () -> Void) {
        self.onAccept = onAccept
        self.onDiscard = onDiscard
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("AI suggested tag")
            } icon: {
                AISymbol()
            }
            .font(Typography.rowDetail)
            TextField("Tag", text: $name)
                .onSubmit(accept)
            HStack {
                Button("Discard Tag", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
                Spacer()
                Button("Accept Tag", action: accept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: Metrics.suggestionListWidth)
    }

    private func accept() {
        onAccept(name)
        dismiss()
    }
}
