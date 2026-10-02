import MindMapDomain
import MindMapLayout
import SwiftUI

/// One topic card at 100% zoom; the canvas scales and places it. Takes plain
/// values and the model (compared by identity), so panning re-renders no topic
/// whose content stayed the same.
struct TopicView: View {
    let topic: CanvasTopic
    let style: TopicStyle
    let spec: TopicTextSpec
    let isRoot: Bool
    let isSelected: Bool
    let isEditing: Bool
    let model: CanvasModel
    let rotorNamespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.box.cornerRadius, style: .continuous)
        ZStack {
            if topic.isSuggestion {
                // A suggestion is drawn apart from real topics without looking
                // like an error: canvas-coloured card, dashed AI outline.
                shape.fill(Palette.canvasBackground)
                shape.strokeBorder(aiStyle, style: StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, dash: CanvasMetrics.suggestionDash))
            } else {
                shape.fill((isHovering ? style.hoverFill : style.fill).color)
                if let stroke = style.stroke {
                    shape.strokeBorder(stroke.color, lineWidth: style.strokeWidth)
                }
            }
            if isEditing {
                TopicTitleEditor(model: model, spec: spec, color: textColor, width: textWidth)
            } else {
                title
            }
        }
        .frame(width: topic.frame.width, height: topic.frame.height)
        .overlay(alignment: .topLeading) {
            if topic.isSuggestion { suggestionBadge }
        }
        .overlay {
            if isSelected { selectionRing }
        }
        .overlay(alignment: .bottom) {
            if topic.isSuggestion, isSelected || isHovering, !isEditing { suggestionActions }
        }
        .animation(Motion.selection(reduceMotion: reduceMotion), value: isSelected)
        .overlay(alignment: topic.side == .left ? .leading : .trailing) {
            if topic.hiddenDescendantCount > 0 { badge }
        }
        .contentShape(.interaction, Rectangle().inset(by: -hitOutset))
        // The double tap is listed first so it can see both taps; the single tap
        // runs alongside it, so selection does not wait for the double-tap timeout.
        .onTapGesture(count: 2) { model.beginEditing(topic.id) }
        .simultaneousGesture(TapGesture().onEnded { model.select(topic.id) })
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        .modifier(TopicAccessibility(topic: topic, isRoot: isRoot, isSelected: isSelected, isEditing: isEditing, model: model))
        .accessibilityRotorEntry(id: topic.id, in: rotorNamespace)
    }

    /// Suggestions use the secondary text colour, so they read as not yet part of the map.
    private var textColor: Color {
        (topic.isSuggestion ? style.secondaryTextColor : style.textColor).color
    }

    private var aiStyle: AnyShapeStyle {
        Palette.ai(colorScheme: colorScheme, contrast: contrast, reduceTransparency: reduceTransparency)
    }

    /// The AI mark on the corner, so a suggestion is not told apart by colour
    /// alone (NFR-A11Y-07); outside the title, so it does not change the measure.
    private var suggestionBadge: some View {
        AISymbol()
            .font(Typography.Content.badge.font)
            .padding(Spacing.xxs)
            .background(Palette.canvasBackground, in: Circle())
            .alignmentGuide(.top) { $0[VerticalAlignment.center] }
            .alignmentGuide(.leading) { $0[HorizontalAlignment.center] }
            .accessibilityHidden(true)
    }

    /// Accept and Discard under a hovered or selected suggestion.
    private var suggestionActions: some View {
        let gap = CanvasMetrics.collapseBadgeGap
        return HStack(spacing: Spacing.xs) {
            Button { model.acceptSuggestion(topic.id) } label: {
                Label("Accept Suggestion", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(aiStyle)
            }
            .disabled(model.assistant?.canAcceptSuggestions != true)
            Button { model.discardSuggestion(topic.id) } label: {
                Label("Discard Suggestion", systemImage: "xmark.circle")
                    .foregroundStyle(style.secondaryTextColor.color)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(Typography.Content.badge.font)
        .frame(minHeight: Metrics.minimumHitTarget)
        .padding(.horizontal, Spacing.xs)
        .background(Palette.canvasBackground, in: Capsule())
        .onHover { if $0 { isHovering = true } }
        .alignmentGuide(.bottom) { $0[.top] - gap }
        // The topic element already offers Accept and Discard.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var contextMenu: some View {
        if topic.isSuggestion {
            Button("Accept Suggestion") { model.acceptSuggestion(topic.id) }
                .disabled(model.assistant?.canAcceptSuggestions != true)
            Button("Edit Suggestion") { model.beginEditing(topic.id) }
            Divider()
            Button("Discard Suggestion") { model.discardSuggestion(topic.id) }
        } else if let assistant = model.assistant, assistant.service.showsEntryPoints {
            AIActionsMenu(assistant: assistant, nodeID: topic.id)
        }
    }

    private var textWidth: CGFloat {
        max(topic.frame.width - 2 * spec.horizontalPadding, 0)
    }

    private var title: some View {
        TopicTitleText(title: topic.title, spec: spec, color: textColor, placeholderColor: style.secondaryTextColor.color, width: textWidth)
    }

    /// A ring outside the box with a gap, so it reads on any fill (NFR-A11Y-07:
    /// selection is a shape, not only a colour).
    private var selectionRing: some View {
        let outset = CanvasMetrics.selectionRingGap + style.selectionRingWidth / 2
        return RoundedRectangle(cornerRadius: style.box.cornerRadius + outset, style: .continuous)
            .stroke(Palette.selectionRing, lineWidth: style.selectionRingWidth)
            .padding(-outset)
            .allowsHitTesting(false)
    }

    /// The count of hidden topics, on the side away from the parent; a click expands.
    private var badge: some View {
        Button {
            model.toggleCollapsed(topic.id)
        } label: {
            CollapseBadgeLabel(count: topic.hiddenDescendantCount, style: style)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(CollapseBadgePlacement())
        // The topic element already offers Expand Topic.
        .accessibilityHidden(true)
    }

    /// Touch needs a 44 pt target around small topics; a pointer uses the box.
    private var hitOutset: CGFloat {
        #if os(iOS)
        max(0, (Metrics.minimumHitTarget - min(topic.frame.width, topic.frame.height)) / 2)
        #else
        0
        #endif
    }
}

/// A topic's title as the card draws it, with the font, wrap width and line
/// spacing `TopicMeasurer` measured; shared by the canvas and export.
struct TopicTitleText: View {
    let title: String
    let spec: TopicTextSpec
    let color: Color
    let placeholderColor: Color
    let width: CGFloat

    var body: some View {
        Group {
            if title.isEmpty {
                Text("Untitled Topic").foregroundStyle(placeholderColor)
            } else {
                Text(verbatim: title).foregroundStyle(color)
            }
        }
        .font(.custom(spec.postScriptName, fixedSize: spec.pointSize))
        .lineSpacing(spec.lineSpacing)
        .multilineTextAlignment(.center)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The count of topics a collapsed branch hides.
struct CollapseBadgeLabel: View {
    let count: Int
    let style: TopicStyle

    var body: some View {
        Text(count, format: .number)
            .font(Typography.Content.badge.font)
            .foregroundStyle(style.badgeText.color)
            .padding(.horizontal, Spacing.sm)
            .frame(minWidth: CanvasMetrics.collapseBadgeHeight, minHeight: CanvasMetrics.collapseBadgeHeight)
            .background(style.badgeFill.color, in: Capsule())
    }
}

/// Puts the badge just outside the card, on the side away from the parent,
/// when used in an overlay aligned to that side.
struct CollapseBadgePlacement: ViewModifier {
    func body(content: Content) -> some View {
        // Alignment guides run outside the main actor; read the gap here.
        let gap = CanvasMetrics.collapseBadgeGap
        return content
            .alignmentGuide(.trailing) { $0[.leading] - gap }
            .alignmentGuide(.leading) { $0[.trailing] + gap }
    }
}

/// The title field shown in place of the title: same font, size and position,
/// so nothing moves when editing starts.
struct TopicTitleEditor: View {
    @Bindable var model: CanvasModel
    let spec: TopicTextSpec
    let color: Color
    let width: CGFloat
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Topic", text: $model.editingDraft, prompt: Text("Untitled Topic"))
            .textFieldStyle(.plain)
            .font(.custom(spec.postScriptName, fixedSize: spec.pointSize))
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
            .frame(width: width)
            .focused($isFocused)
            .onSubmit(model.commitEditing)
            #if os(macOS)
            .onExitCommand(perform: model.cancelEditing)
            #endif
            .onKeyPress(.escape) {
                model.cancelEditing()
                return .handled
            }
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused { model.commitEditing() }
            }
    }
}

/// FR-CNV-07: each topic is one VoiceOver element, "title, level n, m
/// subtopics", with the topic actions. Shared by topic views and the plain
/// shapes drawn below the detail zoom.
struct TopicAccessibility: ViewModifier {
    let topic: CanvasTopic
    let isRoot: Bool
    let isSelected: Bool
    var isEditing = false
    let model: CanvasModel

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: isEditing ? .contain : .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(Text(verbatim: value))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(topic.id) }
            .accessibilityActions {
                if topic.isSuggestion {
                    Button("Accept Suggestion") { model.acceptSuggestion(topic.id) }
                    Button("Edit Suggestion") { model.beginEditing(topic.id) }
                    Button("Discard Suggestion") { model.discardSuggestion(topic.id) }
                } else {
                    topicActions
                }
            }
    }

    private var label: Text {
        if topic.isSuggestion { return Text("AI suggestion, \(topic.title)") }
        return topic.title.isEmpty ? Text("Untitled Topic") : Text(verbatim: topic.title)
    }

    @ViewBuilder
    private var topicActions: some View {
        if topic.childCount > 0 {
            Button(topic.isCollapsed ? "Expand Topic" : "Collapse Topic") { model.toggleCollapsed(topic.id) }
        }
        Button("Add Child Topic") { model.addChild(of: topic.id) }
        Button("Rename Topic") { model.beginEditing(topic.id) }
        if !isRoot {
            Button("Delete Topic") { model.delete(topic.id) }
        }
    }

    /// Levels count from 1 below the central topic, as the outline reads them.
    private var value: String {
        let level = isRoot ? String(localized: "Central Topic") : String(localized: "Level \(topic.level + 1)")
        return "\(level), \(String(localized: "\(topic.childCount) subtopics"))"
    }
}
