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
    /// Drawn faded in place while a copy follows the pointer.
    var isDragSource = false
    let model: CanvasModel
    let rotorNamespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.box.cornerRadius, style: .continuous)
        ZStack {
            shape.fill((isHovering ? style.hoverFill : style.fill).color)
            if let stroke = style.stroke {
                shape.strokeBorder(stroke.color, lineWidth: style.strokeWidth)
            }
            if isEditing {
                TopicTitleEditor(model: model, spec: spec, color: style.textColor.color, width: textWidth)
            } else {
                title
            }
        }
        .frame(width: topic.frame.width, height: topic.frame.height)
        .overlay {
            if isSelected { selectionRing }
        }
        .animation(Motion.selection(reduceMotion: reduceMotion), value: isSelected)
        .overlay(alignment: topic.side == .left ? .leading : .trailing) {
            if topic.hiddenDescendantCount > 0 { badge }
        }
        .opacity(isDragSource ? CanvasMetrics.dragSourceOpacity : 1)
        .contentShape(.interaction, Rectangle().inset(by: -hitOutset))
        // The double tap is listed first so it can see both taps; the single tap
        // runs alongside it, so selection does not wait for the double-tap timeout.
        .onTapGesture(count: 2) { model.beginEditing(topic.id) }
        .simultaneousGesture(selectionTap)
        // While the title is a text field, a drag selects text instead.
        .gesture(moveDrag, including: isEditing ? .subviews : .all)
        .contextMenu { TopicContextMenu(topic: topic, isRoot: isRoot, model: model) }
        .onHover { isHovering = $0 }
        .modifier(TopicAccessibility(topic: topic, isRoot: isRoot, isSelected: isSelected, isEditing: isEditing, model: model))
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

    private var textWidth: CGFloat {
        max(topic.frame.width - 2 * spec.horizontalPadding, 0)
    }

    private var title: some View {
        Group {
            if topic.title.isEmpty {
                Text("Untitled Topic").foregroundStyle(style.secondaryTextColor.color)
            } else {
                Text(verbatim: topic.title).foregroundStyle(style.textColor.color)
            }
        }
        .font(.custom(spec.postScriptName, fixedSize: spec.pointSize))
        .lineSpacing(spec.lineSpacing)
        .multilineTextAlignment(.center)
        .frame(width: textWidth)
        .fixedSize(horizontal: false, vertical: true)
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
        // Alignment guides run outside the main actor; read the gap here.
        let gap = CanvasMetrics.collapseBadgeGap
        return Button {
            model.toggleCollapsed(topic.id)
        } label: {
            Text(topic.hiddenDescendantCount, format: .number)
                .font(Typography.Content.badge.font)
                .foregroundStyle(style.badgeText.color)
                .padding(.horizontal, Spacing.sm)
                .frame(minWidth: CanvasMetrics.collapseBadgeHeight, minHeight: CanvasMetrics.collapseBadgeHeight)
                .background(style.badgeFill.color, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.trailing) { $0[.leading] - gap }
        .alignmentGuide(.leading) { $0[.trailing] + gap }
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
            .accessibilityLabel(topic.title.isEmpty ? Text("Untitled Topic") : Text(verbatim: topic.title))
            .accessibilityValue(Text(verbatim: value))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(topic.id) }
            .accessibilityActions {
                if topic.childCount > 0 {
                    Button(topic.isCollapsed ? "Expand Topic" : "Collapse Topic") { model.toggleCollapsed(topic.id) }
                }
                Button("Add Child Topic") { model.addChild(of: topic.id) }
                Button("Rename Topic") { model.beginEditing(topic.id) }
                if !isRoot {
                    Button("Delete Topic") { model.delete(topic.id) }
                }
            }
    }

    /// Levels count from 1 below the central topic, as the outline reads them.
    private var value: String {
        let level = isRoot ? String(localized: "Central Topic") : String(localized: "Level \(topic.level + 1)")
        return "\(level), \(String(localized: "\(topic.childCount) subtopics"))"
    }
}
