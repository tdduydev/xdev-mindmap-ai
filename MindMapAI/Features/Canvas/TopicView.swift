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
    /// Nil until the canvas has its text settings; chips need them.
    var chipSpec: TopicChipSpec?
    let isRoot: Bool
    let isSelected: Bool
    let isEditing: Bool
    /// A result of Find (FR-KBD-06), marked as in the outline.
    var isFindMatch = false
    /// Drawn faded in place while a copy follows the pointer.
    var isDragSource = false
    /// The + buttons to show, on a hovered or selected topic (MM-57).
    var addButtons: CanvasModel.AddButtons?
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
            TopicTitleWithChips(chips: topic.chips, spec: chipSpec) {
                if isEditing {
                    TopicTitleEditor(model: model, spec: spec, color: textColor, width: textWidth)
                } else {
                    title
                }
            } chip: { chip in
                if let chipSpec {
                    TopicChipView(chip: chip, spec: chipSpec, variant: variant, aiStyle: aiStyle, model: model)
                }
            }
        }
        .frame(width: topic.frame.width, height: topic.frame.height)
        .overlay(alignment: .topLeading) {
            if topic.isSuggestion { suggestionBadge }
        }
        .overlay(alignment: .topTrailing) {
            if topic.hasNote, !topic.isSuggestion { noteMark }
        }
        .overlay {
            if isSelected { selectionRing }
        }
        .overlay(alignment: .bottom) {
            if topic.isSuggestion, isSelected || isHovering, !isEditing { suggestionActions }
        }
        .animation(Motion.selection(reduceMotion: reduceMotion), value: isSelected)
        .opacity(isDragSource ? CanvasMetrics.dragSourceOpacity : 1)
        .contentShape(.interaction, Rectangle().inset(by: -hitOutset))
        // After the content shape, which would otherwise keep taps off the
        // badge and buttons outside the card.
        .overlay(alignment: outerEdge == .leading ? .leading : .trailing) { outerControls }
        .overlay(alignment: .bottom) { addSiblingButton }
        // The double tap is listed first so it can see both taps; the single tap
        // runs alongside it, so selection does not wait for the double-tap timeout.
        .onTapGesture(count: 2) { model.beginEditing(topic.id) }
        .simultaneousGesture(selectionTap)
        // While the title is a text field, a drag selects text instead.
        .gesture(moveDrag, including: isEditing ? .subviews : .all)
        .onHover { hovering in
            isHovering = hovering
            model.setHovering(topic.id, part: .card, hovering)
        }
        .contextMenu { contextMenu }
        .modifier(TopicAccessibility(topic: topic, isRoot: isRoot, isSelected: isSelected, isEditing: isEditing, isFindMatch: isFindMatch, model: model))
        .accessibilityRotorEntry(id: topic.id, in: rotorNamespace)
    }

    #if os(macOS)
    /// ⌘-click toggles, ⇧-click adds, a plain click selects the topic alone
    /// (FR-CNV-03). A modifier tap fails without its key, so the next one runs.
    private var selectionTap: some Gesture {
        TapGesture().modifiers(.command).onEnded { model.click(topic.id, .toggle) }
            .exclusively(before: TapGesture().modifiers(.shift).onEnded { model.click(topic.id, .add) })
            .exclusively(before: TapGesture().onEnded { model.click(topic.id, .replace) })
    }
    #else
    /// SwiftUI gestures read no modifier keys on iOS; touch adds topics with
    /// the context menu, a hold-and-drag rectangle or ⇧-arrows instead.
    private var selectionTap: some Gesture {
        TapGesture().onEnded { model.click(topic.id, .replace) }
    }
    #endif

    /// Dragging a topic moves its branch, or the whole selection (FR-KBD-04).
    /// Locations are in the canvas's space, as the camera's view points.
    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: CanvasMetrics.dragStartDistance, coordinateSpace: .named(CanvasView.coordinateSpace))
            .onChanged { value in
                model.beginDrag(topic.id, at: value.startLocation)
                model.updateDrag(to: value.location)
            }
            .onEnded { _ in model.endDrag() }
    }

    /// Suggestions use the secondary text colour, so they read as not yet part of the map.
    private var textColor: Color {
        (topic.isSuggestion ? style.secondaryTextColor : style.textColor).color
    }

    private var variant: ColorVariant {
        ColorVariant(colorScheme: colorScheme, contrast: contrast)
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

    /// The note mark on the top-trailing corner. On the corner rather than after
    /// the title, as the AI mark is, so a note never changes the measured box
    /// and adding one does not move the map.
    private var noteMark: some View {
        Image(systemName: "note.text")
            .font(.system(size: CanvasMetrics.noteSymbolSize))
            .foregroundStyle(style.secondaryTextColor.color)
            .padding(Spacing.xxs)
            .background(Palette.canvasBackground, in: Circle())
            .alignmentGuide(.top) { $0[VerticalAlignment.center] }
            .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
            .allowsHitTesting(false)
            // The topic element says "has note" in its value.
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
        } else {
            TopicContextMenu(topic: topic, isRoot: isRoot, model: model)
            if let assistant = model.assistant, assistant.service.showsControls {
                Divider()
                AIActionsMenu(assistant: assistant, nodeID: topic.id)
            }
        }
    }

    private var textWidth: CGFloat {
        max(topic.frame.width - 2 * spec.horizontalPadding, 0)
    }

    private var title: some View {
        TopicTitleText(title: topic.title, spec: spec, color: textColor, placeholderColor: style.secondaryTextColor.color, width: textWidth)
            .background {
                // Outside the text's frame, so marking a match never changes the measure.
                if isFindMatch {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Palette.searchMatchFill)
                        .strokeBorder(Palette.searchMatchBorder)
                        .padding(-Spacing.xxs)
                }
            }
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

    /// The side away from the parent, where the badge and the add-child button go.
    private var outerEdge: HorizontalEdge {
        addButtons?.childEdge ?? (topic.side == .left ? .leading : .trailing)
    }

    /// The collapse badge, and the add-child button beyond it, so the button
    /// never covers the count.
    private var outerControls: some View {
        HStack(spacing: CanvasMetrics.collapseBadgeGap) {
            if outerEdge == .leading, addButtons != nil { addChildButton }
            if topic.hiddenDescendantCount > 0 { badge }
            if outerEdge == .trailing, addButtons != nil { addChildButton }
        }
        .animation(Motion.addButtons(reduceMotion: reduceMotion), value: addButtons)
        .modifier(CollapseBadgePlacement())
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
        .opacity(isDragSource ? CanvasMetrics.dragSourceOpacity : 1)
        // The topic element already offers Expand Topic.
        .accessibilityHidden(true)
    }

    private var addChildButton: some View {
        TopicAddButton(label: "Add Child Topic") {
            model.addFromButton(topic.id, sibling: false)
        }
        .onHover { model.setHovering(topic.id, part: .addChild, $0) }
        .transition(.opacity)
    }

    /// On the middle of the bottom edge, half over the card: the gap to the
    /// next sibling is too small for a whole button below it.
    private var addSiblingButton: some View {
        Group {
            if addButtons?.showsSibling == true {
                TopicAddButton(label: "Add Sibling Topic") {
                    model.addFromButton(topic.id, sibling: true)
                }
                .onHover { model.setHovering(topic.id, part: .addSibling, $0) }
                .offset(y: CanvasMetrics.addButtonDiameter / 2)
                .transition(.opacity)
            }
        }
        .animation(Motion.addButtons(reduceMotion: reduceMotion), value: addButtons)
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

/// Right-click or a long press on a topic (FR-KBD-03). Acts on the selection
/// when the topic is in it, else on the topic alone.
struct TopicContextMenu: View {
    let topic: CanvasTopic
    let isRoot: Bool
    let model: CanvasModel

    var body: some View {
        Button("Add Child Topic") { perform { $0.addChild() } }
        Button("Add Sibling Topic") { perform { $0.addSibling() } }
            .disabled(isRoot)
        Button("Rename Topic") { model.beginEditing(topic.id) }
        Button("Edit Note") { model.editNote(topic.id) }
        TagsMenu(session: model.session, targets: model.contextTargets(for: topic.id), onAddTag: { model.addTag(to: topic.id) })
        #if os(iOS)
        // Touch has no ⌘-click.
        Button(model.session.isSelected(topic.id) ? "Remove from Selection" : "Add to Selection") {
            model.click(topic.id, .toggle)
        }
        #endif
        Button("Duplicate Topic") { perform { $0.duplicateSelection() } }
            .disabled(isRoot)
        Divider()
        Button("Cut") { perform { $0.cutSelection() } }
            .disabled(isRoot)
        Button("Copy") { perform { $0.copySelection() } }
        // Paste goes under the topic the menu opened on, even in a multi-selection.
        Button("Paste") { perform { $0.selection = topic.id; $0.paste() } }
            .disabled(!model.session.clipboard.hasText)
        Divider()
        Button(topic.isCollapsed ? "Expand Topic" : "Collapse Topic") { model.toggleCollapsed(topic.id) }
            .disabled(topic.childCount == 0)
        Divider()
        Button("Delete Topic", role: .destructive) { perform { $0.deleteSelection() } }
            .disabled(isRoot)
    }

    private func perform(_ action: (EditorSession) -> Void) {
        model.performFromContextMenu(on: topic.id, action)
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

/// A round accent + on a hovered or selected topic (MM-57). Content, not a
/// control layer, so solid colours rather than glass. Hidden from VoiceOver:
/// the topic element already has Add Child Topic and Add Sibling Topic.
struct TopicAddButton: View {
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        let diameter = CanvasMetrics.addButtonDiameter
        let outset = max(0, (Metrics.minimumHitTarget - diameter) / 2)
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: CanvasMetrics.addButtonSymbolSize, weight: .bold))
                .foregroundStyle(Palette.canvasBackground)
                .frame(width: diameter, height: diameter)
                .background(Palette.accent, in: Circle())
                // Keeps the circle apart from a card or edge of the same hue.
                .overlay(Circle().strokeBorder(Palette.canvasBackground, lineWidth: CanvasMetrics.addButtonRingWidth))
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, Circle().inset(by: -outset))
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityHidden(true)
    }
}

/// Puts the badge just outside the card, on the side away from the parent,
/// when used in an overlay aligned to that side.
struct CollapseBadgePlacement: ViewModifier {
    func body(content: Content) -> some View {
        // Alignment guides run outside the main actor; read the gap here.
        let gap = CanvasMetrics.collapseBadgeGap
        return content
            // From the size, not `$0[.trailing]`: once the first guide is set,
            // reading the other edge returns that explicit guide instead.
            .alignmentGuide(.trailing) { _ in -gap }
            .alignmentGuide(.leading) { $0.width + gap }
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
    var isFindMatch = false
    let model: CanvasModel

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: isEditing ? .contain : .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(Text(verbatim: value))
            .accessibilityIdentifier(AccessibilityID.Canvas.topic)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(topic.id) }
            .accessibilityActions {
                if topic.isSuggestion {
                    Button("Accept Suggestion") { model.acceptSuggestion(topic.id) }
                    Button("Edit Suggestion") { model.beginEditing(topic.id) }
                    Button("Discard Suggestion") { model.discardSuggestion(topic.id) }
                } else {
                    topicActions
                    suggestedTagActions
                }
            }
            .modifier(TagCustomContent(names: topic.tagNames))
    }

    /// Accept and Discard for each suggested tag, as the chips offer them.
    @ViewBuilder
    private var suggestedTagActions: some View {
        ForEach(topic.chips.filter(\.isSuggestion)) { chip in
            if case .suggestion(let id) = chip.kind {
                Button("Accept Tag \(chip.label)") { model.acceptTagSuggestion(id) }
                Button("Discard Tag \(chip.label)") { model.discardTagSuggestion(id) }
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
        if !isRoot {
            Button("Add Sibling Topic") { model.addSibling(of: topic.id) }
        }
        Button("Rename Topic") { model.beginEditing(topic.id) }
        Button("Edit Note") { model.editNote(topic.id) }
        Button("Add Tag…") { model.addTag(to: topic.id) }
        if !isRoot {
            Button("Delete Topic") { model.delete(topic.id) }
        }
    }

    /// Levels count from 1 below the central topic, as the outline reads them.
    private var value: String {
        let level = isRoot ? String(localized: "Central Topic") : String(localized: "Level \(topic.level + 1)")
        let subtopics = String(localized: "\(topic.childCount) subtopics")
        var parts = [level, subtopics]
        if topic.hasNote { parts.append(String(localized: "has note")) }
        if isFindMatch { parts.append(String(localized: "Find Match")) }
        return parts.joined(separator: ", ")
    }
}
