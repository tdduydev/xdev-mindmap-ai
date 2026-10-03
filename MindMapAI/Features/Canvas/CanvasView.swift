import MindMapDomain
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The map on an infinite canvas: pan, zoom, select, edit in place. Edges are
/// one SwiftUI `Canvas`; topics are views, and only those in view are built.
struct CanvasView: View {
    /// The space gestures report in: the canvas's own frame, which is the
    /// camera's view space.
    static let coordinateSpace = "canvas"

    @Bindable var model: CanvasModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Namespace private var rotorNamespace
    @FocusState private var isFocused: Bool
    @State private var drag: (start: CGPoint, last: CGSize)?
    @State private var pinchStartScale: CGFloat?

    private var session: EditorSession { model.session }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            EdgeLayer(
                drawing: CanvasDrawing.make(model: model, colorScheme: colorScheme, contrast: contrast),
                viewport: model.viewport,
                aiStyle: Palette.ai(colorScheme: colorScheme, contrast: contrast, reduceTransparency: reduceTransparency)
            )
                .allowsHitTesting(false)
            if model.isDetailed {
                callouts
                topics
            } else {
                topicShapesForAccessibility
            }
            CanvasDragLayer(model: model, colorScheme: colorScheme, contrast: contrast)
                .allowsHitTesting(false)
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if session.rootID != nil {
                CanvasControls(model: model)
                    .padding(Spacing.lg)
            }
        }
        .overlay {
            if session.rootID == nil { emptyState }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.setViewSize($0) }
        .simultaneousGesture(pinch)
        #if os(macOS)
        .background(CanvasScrollInput(model: model))
        #else
        .gesture(CanvasScrollInput(model: model))
        #endif
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .modifier(CanvasKeys(model: model))
        .modifier(CanvasClipboard(model: model))
        .sensoryFeedback(.error, trigger: model.refusedDrops)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: session.map.title))
        .accessibilityIdentifier(AccessibilityID.Canvas.canvas)
        .accessibilityRotor(Text("Topics")) {
            ForEach(model.scene.topics) { topic in
                AccessibilityRotorEntry(rotorLabel(topic), id: topic.id, in: rotorNamespace) {
                    model.reveal(topic.id)
                }
            }
        }
        .focusedSceneValue(\.canvasModel, model)
        .onAppear {
            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                model.initialPlacement = .firstLevel
            } else if horizontalSizeClass == .compact {
                model.initialPlacement = .firstLevelWidth
            }
            #endif
            model.setTextSpecs(textSpecs)
            model.revealSelection()
            model.takeFocusRequest()
            model.hasKeyboardFocus = isFocused
        }
        .onChange(of: isFocused) { _, focused in model.hasKeyboardFocus = focused }
        .onChange(of: dynamicTypeSize) { model.setTextSpecs(textSpecs) }
        .onChange(of: session.calloutEditorTarget) { model.calloutEditingDidChange() }
        .onChange(of: session.focusRequest) { model.takeFocusRequest() }
        .onChange(of: session.selection) {
            if model.editingID == nil { isFocused = true }
        }
        .onChange(of: model.editingID) { _, editing in
            // Keys go back to the canvas after editing, so Return can edit again.
            if editing == nil { isFocused = true }
        }
    }

    // MARK: Layers

    private var background: some View {
        Rectangle()
            .fill(Palette.canvasBackground)
            .contentShape(Rectangle())
            #if os(macOS)
            .gesture(marqueeDrag(.command, adding: false).exclusively(before: marqueeDrag(.shift, adding: true)).exclusively(before: pan))
            #else
            .gesture(pan)
            .simultaneousGesture(holdThenMarquee)
            #endif
            // On a topic shape it edits; on empty canvas it adds a floating topic there.
            .onTapGesture(count: 2) { model.doubleTap(at: $0) }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                model.tap(at: value.location)
                isFocused = true
            })
            #if os(macOS)
            .pointerStyle(model.isPanning ? .grabActive : .grabIdle)
            // Touch keeps the hold on empty canvas for the selection rectangle;
            // it adds floating topics by double-tap and the Topic menu.
            .contextMenu {
                Button("Add Floating Topic", action: model.addFloatingTopic)
                    .disabled(!session.canAddFloatingTopic)
            }
            #endif
            .accessibilityHidden(true)
    }

    private var topics: some View {
        let selection = session.selectedIDs
        let selectedSuggestion = model.selectedSuggestionPreviewID
        let rootID = session.rootID
        let dragged = model.drag.map { Set($0.ids) } ?? []
        return ForEach(model.visibleTopics) { topic in
            if let spec = model.textSpec(for: topic) {
                let addButtons = model.addButtons(for: topic)
                TopicView(
                    topic: topic,
                    style: model.style(for: topic, colorScheme: colorScheme, contrast: contrast),
                    spec: spec,
                    chipSpec: model.chipSpec,
                    isRoot: topic.id == rootID,
                    isSelected: topic.isSuggestion ? topic.id == selectedSuggestion : selection.contains(topic.id),
                    isEditing: topic.id == model.editingID,
                    isFindMatch: session.findMatchSet.contains(topic.id),
                    isDragSource: dragged.contains(topic.id),
                    addButtons: addButtons,
                    model: model,
                    rotorNamespace: rotorNamespace
                )
                .scaleEffect(model.viewport.scale)
                .position(model.viewport.toView(CGPoint(x: topic.frame.midX, y: topic.frame.midY)))
                // The + buttons reach past the card; drawn over the neighbours they overlap.
                .zIndex(addButtons == nil ? 0 : 1)
            }
        }
    }

    /// Callout bubbles above their topics (FR-ORG-30). Their room is reserved
    /// in the layout, so they cover no topic.
    private var callouts: some View {
        let editing = session.calloutEditorTarget
        return ForEach(model.visibleTopics.filter { $0.calloutFrame != nil }) { topic in
            if let bubble = topic.calloutFrame, let spec = model.calloutSpec {
                CanvasCalloutView(topic: topic, bubble: bubble, spec: spec, isEditing: topic.id == editing, model: model)
                    .id(topic.id == editing)
                    .scaleEffect(model.viewport.scale)
                    // The view is the bubble plus its tail below it.
                    .position(model.viewport.toView(CGPoint(
                        x: bubble.midX,
                        y: bubble.midY + CanvasMetrics.calloutTailHeight / 2
                    )))
            }
        }
    }

    /// Below the detail zoom the topics are shapes in the edge layer; these
    /// empty frames keep one VoiceOver element per topic in view.
    private var topicShapesForAccessibility: some View {
        let selection = session.selectedIDs
        let rootID = session.rootID
        let viewport = model.viewport
        return ForEach(model.visibleTopics) { topic in
            Color.clear
                .frame(width: topic.frame.width * viewport.scale, height: topic.frame.height * viewport.scale)
                .modifier(TopicAccessibility(topic: topic, isRoot: topic.id == rootID, isSelected: selection.contains(topic.id), isFindMatch: session.findMatchSet.contains(topic.id), model: model))
                .accessibilityRotorEntry(id: topic.id, in: rotorNamespace)
                .position(viewport.toView(CGPoint(x: topic.frame.midX, y: topic.frame.midY)))
                .allowsHitTesting(false)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Empty Map", systemImage: "point.3.connected.trianglepath.dotted")
        } actions: {
            Button("Add Central Topic", action: session.addRoot)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.Canvas.addCentralTopic)
        }
    }

    // MARK: Gestures

    /// Drag on empty canvas pans (mouse drag on the Mac, one finger on touch).
    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                // On touch, a hold turned this drag into a selection rectangle.
                guard model.marquee == nil else { return }
                // A gesture cancelled without `onEnded` leaves an old drag behind;
                // a new start location means a new drag.
                let last = drag?.start == value.startLocation ? drag?.last ?? .zero : .zero
                model.pan(by: CGSize(width: value.translation.width - last.width, height: value.translation.height - last.height))
                drag = (value.startLocation, value.translation)
                model.setPanning(true)
            }
            .onEnded { _ in
                drag = nil
                model.setPanning(false)
            }
    }

    #if os(macOS)
    /// ⌘-drag on empty canvas selects the topics in a rectangle; ⇧-drag adds
    /// them to the selection. A plain drag still pans (FR-CNV-02, FR-CNV-03).
    private func marqueeDrag(_ modifier: EventModifiers, adding: Bool) -> some Gesture {
        DragGesture()
            .modifiers(modifier)
            .onChanged { value in
                if model.marquee == nil { model.beginMarquee(at: value.startLocation, adding: adding) }
                model.updateMarquee(from: value.startLocation, to: value.location)
            }
            .onEnded { _ in model.endMarquee() }
    }
    #else
    /// Touch has no modifier keys: hold on empty canvas, then drag, to select
    /// with a rectangle.
    private var holdThenMarquee: some Gesture {
        LongPressGesture(minimumDuration: CanvasMetrics.marqueeHoldDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if model.marquee == nil { model.beginMarquee(at: drag.startLocation, adding: false) }
                model.updateMarquee(from: drag.startLocation, to: drag.location)
            }
            .onEnded { _ in model.endMarquee() }
    }
    #endif

    /// Pinch on a trackpad or touch screen zooms around where it started.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartScale ?? model.viewport.scale
                pinchStartScale = start
                model.zoom(to: start * value.magnification, anchor: value.startLocation)
            }
            .onEnded { _ in pinchStartScale = nil }
    }

    // MARK: Helpers

    private func rotorLabel(_ topic: CanvasTopic) -> Text {
        topic.title.isEmpty ? Text("Untitled Topic") : Text(verbatim: topic.title)
    }

    /// Topic fonts at the current Dynamic Type size. Only iOS and iPadOS scale
    /// content text; the Mac has no Dynamic Type.
    private var textSpecs: TopicTextSpecs {
        #if os(iOS)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return .make { style in
            UIFontMetrics(forTextStyle: style.textStyle.uiTextStyle).scaledValue(for: style.size, compatibleWith: traits)
        }
        #else
        return .designSizes()
        #endif
    }
}
