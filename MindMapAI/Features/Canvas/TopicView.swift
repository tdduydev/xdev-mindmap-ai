import MindMapDomain
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
        .overlay(alignment: topic.side == .left ? .leading : .trailing) {
            if topic.hiddenDescendantCount > 0 { badge }
        }
        .contentShape(.interaction, Rectangle().inset(by: -hitOutset))
        // The double tap is listed first so it can see both taps; the single tap
        // runs alongside it, so selection does not wait for the double-tap timeout.
        .onTapGesture(count: 2) { model.beginEditing(topic.id) }
        .simultaneousGesture(TapGesture().onEnded { model.select(topic.id) })
        .onHover { isHovering = $0 }
        .modifier(TopicAccessibility(topic: topic, isRoot: isRoot, isSelected: isSelected, isEditing: isEditing, model: model))
        .accessibilityRotorEntry(id: topic.id, in: rotorNamespace)
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
        Button {
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
        .alignmentGuide(.trailing) { $0[.leading] - CanvasMetrics.collapseBadgeGap }
        .alignmentGuide(.leading) { $0[.trailing] + CanvasMetrics.collapseBadgeGap }
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
