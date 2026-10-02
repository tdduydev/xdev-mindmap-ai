import MindMapDomain
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Keys the canvas takes itself (FR-KBD-01). They are not menu key
/// equivalents: a bare Return or Tab in the menu bar would never reach a text
/// field, so they only act while the canvas, not a title field, has focus.
struct CanvasKeys: ViewModifier {
    let model: CanvasModel
    /// ⇧Tab arrives as the back-tab character on some keyboards.
    private static let backTab = KeyEquivalent("\u{19}")

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return, phases: .down) { press in
                // ⌘Return and ⇧⌘Return are the menu's.
                guard press.modifiers.isEmpty else { return .ignored }
                return result(model.handle(.addSibling))
            }
            .onKeyPress(keys: [.tab, Self.backTab]) { press in
                let promote = press.key == Self.backTab || press.modifiers.contains(.shift)
                return result(model.handle(promote ? .promote : .addChild))
            }
            .onKeyPress(.space, phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                return result(model.handle(.rename))
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                let direction: CanvasDirection = switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                default: .right
                }
                return result(model.handle(.move(direction, extending: press.modifiers.contains(.shift))))
            }
            .onKeyPress(.escape) { result(model.handle(.cancel)) }
            .onKeyPress(keys: Self.commandLetters) { press in
                guard press.modifiers == .command, model.editingID == nil else { return .ignored }
                return commandLetter(press.key) ? .handled : .ignored
            }
    }

    // On the Mac, Edit ▸ Copy, Cut and Paste reach the canvas through
    // `CanvasClipboard`; ⌘A is here too in case Select All does not.
    #if os(macOS)
    private static let commandLetters: Set<KeyEquivalent> = ["a"]
    #else
    private static let commandLetters: Set<KeyEquivalent> = ["a", "c", "x", "v"]
    #endif

    private func commandLetter(_ key: KeyEquivalent) -> Bool {
        let session = model.session
        switch key {
        case "a": model.selectAll()
        case "c": session.copySelection()
        case "x": session.cutSelection()
        case "v": session.paste()
        default: return false
        }
        return true
    }

    private func result(_ handled: Bool) -> KeyPress.Result {
        handled ? .handled : .ignored
    }
}

/// Edit ▸ Cut, Copy, Paste and Select All on the Mac act on topics while the
/// canvas has focus; a title field being edited takes them first, as usual.
struct CanvasClipboard: ViewModifier {
    let model: CanvasModel

    func body(content: Content) -> some View {
        #if os(macOS)
        let session = model.session
        content
            .onCopyCommand(perform: session.canCopySelection ? {
                session.selectionMarkdown.map { [NSItemProvider(object: $0 as NSString)] } ?? []
            } : nil)
            .onCutCommand(perform: session.canCutSelection ? {
                session.cutSelectionReturningText().map { [NSItemProvider(object: $0 as NSString)] } ?? []
            } : nil)
            .onPasteCommand(of: [.plainText]) { _ in session.paste() }
            .onCommand(#selector(NSText.selectAll(_:))) { model.selectAll() }
        #else
        content
        #endif
    }
}

/// What a drag shows above the topics: the selection rectangle, the drop
/// indicator (a dashed outline on the new parent or a bar where the topics
/// will go) and a copy of the dragged topic under the pointer.
struct CanvasDragLayer: View {
    let model: CanvasModel
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let marquee = model.marquee {
                Rectangle()
                    .fill(Palette.accent.opacity(CanvasMetrics.marqueeFillOpacity))
                    .overlay(Rectangle().strokeBorder(Palette.accent, lineWidth: CanvasMetrics.marqueeStrokeWidth))
                    .frame(width: marquee.width, height: marquee.height)
                    .position(x: marquee.midX, y: marquee.midY)
            }
            if let drag = model.drag {
                if let drop = drag.drop, let indicator = model.dropIndicator(for: drop) {
                    dropIndicator(indicator, level: model.scene.topic(drop.anchor)?.level ?? 0)
                }
                ghost(drag)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dropIndicator(_ indicator: (frame: CGRect, isBar: Bool), level: Int) -> some View {
        let viewport = model.viewport
        let origin = viewport.toView(indicator.frame.origin)
        let size = CGSize(width: indicator.frame.width * viewport.scale, height: indicator.frame.height * viewport.scale)
        if indicator.isBar {
            Capsule()
                .fill(Palette.accent)
                .frame(width: size.width, height: CanvasMetrics.dropInsertionBarWidth)
                .position(x: origin.x + size.width / 2, y: origin.y)
        } else {
            let outset = CanvasMetrics.selectionRingGap + CanvasMetrics.dropTargetOutlineWidth
            RoundedRectangle(cornerRadius: CanvasMetrics.box(level: level).cornerRadius * viewport.scale + outset, style: .continuous)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: CanvasMetrics.dropTargetOutlineWidth, dash: CanvasMetrics.dropTargetDash))
                .frame(width: size.width + 2 * outset, height: size.height + 2 * outset)
                .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        }
    }

    @ViewBuilder
    private func ghost(_ drag: CanvasModel.TopicDrag) -> some View {
        if let topic = model.scene.topic(drag.leadID), let spec = model.textSpec(for: topic) {
            let centre = CGPoint(x: drag.location.x - drag.grabOffset.width, y: drag.location.y - drag.grabOffset.height)
            TopicView(
                topic: topic,
                style: model.style(for: topic, colorScheme: colorScheme, contrast: contrast),
                spec: spec,
                isRoot: false,
                isSelected: false,
                isEditing: false,
                model: model,
                rotorNamespace: ghostNamespace
            )
            .dragElevation()
            .scaleEffect(model.viewport.scale)
            .position(centre)
            if drag.ids.count > 1 || drag.isRefused {
                badge(drag)
                    .position(x: drag.location.x + Spacing.lg, y: drag.location.y - Spacing.lg)
            }
        }
    }

    /// How many branches move, or a no-entry sign over a branch they cannot enter.
    @ViewBuilder
    private func badge(_ drag: CanvasModel.TopicDrag) -> some View {
        if drag.isRefused {
            Image(systemName: "nosign")
                .font(Typography.Content.badge.font)
                .foregroundStyle(Palette.danger)
                .padding(Spacing.xs)
                .background(Palette.canvasBackground, in: Circle())
        } else {
            Text(drag.ids.count, format: .number)
                .font(Typography.Content.badge.font)
                .foregroundStyle(Palette.canvasBackground)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: CanvasMetrics.collapseBadgeHeight)
                .background(Palette.accent, in: Capsule())
        }
    }

    @Namespace private var ghostNamespace
}
