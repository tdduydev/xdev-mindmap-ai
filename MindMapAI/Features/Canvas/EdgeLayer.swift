import MindMapDomain
import MindMapLayout
import SwiftUI

/// What the edge layer strokes and fills for one frame, in canvas points,
/// grouped by colour and width so a frame costs a handful of draw calls
/// however many edges are visible.
struct CanvasDrawing {
    struct Stroke: Hashable {
        let color: SRGBColor
        let width: CGFloat
    }

    var edges: [Stroke: Path] = [:]
    var crossLinks = Path()
    var arrowheads = Path()
    /// Topics drawn as shapes below the detail zoom.
    var fills: [SRGBColor: Path] = [:]
    var outlines: [Stroke: Path] = [:]
    var imagePlaceholders: [SRGBColor: Path] = [:]
    var selection = Path()
    var selectionWidth: CGFloat = CanvasMetrics.selectionRingWidth
    /// Edges into AI suggestions, and suggestions drawn as shapes, in the AI style.
    var suggestionEdges = Path()
    var suggestionShapes = Path()

    /// Only what meets the culling rectangle is built (FR-CNV-06).
    static func make(
        model: CanvasModel,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> CanvasDrawing {
        make(
            scene: model.scene,
            rect: model.cullingRect,
            shapes: model.isDetailed ? nil : model.visibleTopics,
            selection: model.session.selection,
            imageFrame: { topic in
                guard let image = topic.topicImage, let spec = model.textSpec(for: topic) else { return nil }
                let size = image.displaySize(
                    maximumWidth: Double(spec.maximumWidth - 2 * spec.horizontalPadding),
                    maximumAspect: CanvasMetrics.imageMaxAspect
                )
                return CGRect(x: topic.frame.midX - size.width / 2,
                    y: topic.frame.minY + spec.verticalPadding,
                    width: size.width, height: size.height)
            }
        ) { model.style(for: $0, colorScheme: colorScheme, contrast: contrast) }
    }

    /// The same drawing from plain values, which export uses for the whole map.
    ///
    /// - Parameter shapes: Topics to draw as shapes, below the detail zoom;
    ///   nil where topic views draw them.
    static func make(
        scene: CanvasScene,
        rect: CGRect,
        shapes: [CanvasTopic]?,
        selection selected: NodeID?,
        imageFrame: (CanvasTopic) -> CGRect? = { _ in nil },
        style: (CanvasTopic) -> TopicStyle
    ) -> CanvasDrawing {
        var drawing = CanvasDrawing()

        for (child, path) in scene.connectors(in: rect) {
            guard let topic = scene.topic(child) else { continue }
            if topic.isSuggestion {
                drawing.suggestionEdges.addCurve(path)
                continue
            }
            let style = style(topic)
            drawing.edges[Stroke(color: style.edgeColor, width: style.edgeWidth), default: Path()].addCurve(path)
        }

        for (id, path) in scene.crossLinks(in: rect) {
            drawing.crossLinks.addCurve(path)
            if scene.crossLinkTypes[id] == .reference {
                drawing.arrowheads.addArrowhead(at: path.end, from: path.control2)
            }
        }

        guard let shapes else { return drawing }
        for topic in shapes {
            let style = style(topic)
            let shape = Path(roundedRect: topic.frame, cornerRadius: style.box.cornerRadius, style: .continuous)
            if topic.isSuggestion {
                drawing.suggestionShapes.addPath(shape)
                continue
            }
            drawing.fills[style.fill, default: Path()].addPath(shape)
            if let frame = imageFrame(topic) {
                let placeholder = Path(roundedRect: frame,
                    cornerRadius: CanvasMetrics.imageCornerRadius, style: .continuous)
                drawing.imagePlaceholders[style.edgeColor, default: Path()].addPath(placeholder)
            }
            if let stroke = style.stroke {
                drawing.outlines[Stroke(color: stroke, width: style.strokeWidth), default: Path()].addPath(shape)
            }
            if topic.id == selected {
                let outset = CanvasMetrics.selectionRingGap + style.selectionRingWidth / 2
                drawing.selection.addPath(Path(
                    roundedRect: topic.frame.insetBy(dx: -outset, dy: -outset),
                    cornerRadius: style.box.cornerRadius + outset,
                    style: .continuous
                ))
                drawing.selectionWidth = style.selectionRingWidth
            }
        }
        return drawing
    }
}

/// Hierarchy edges and cross-links, under the topics, in one SwiftUI `Canvas`;
/// below the detail zoom it draws the topics too.
struct EdgeLayer: View {
    let drawing: CanvasDrawing
    let viewport: CanvasViewport
    /// `Palette.ai` for the current appearance.
    let aiStyle: AnyShapeStyle

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: viewport.offset.x, y: viewport.offset.y)
            context.scaleBy(x: viewport.scale, y: viewport.scale)

            for (stroke, path) in drawing.edges {
                context.stroke(path, with: .color(stroke.color.color), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round))
            }
            if !drawing.crossLinks.isEmpty {
                let dashed = StrokeStyle(lineWidth: CanvasMetrics.crossLinkWidth, lineCap: .round, dash: CanvasMetrics.crossLinkDash)
                context.stroke(drawing.crossLinks, with: .color(Palette.crossLink), style: dashed)
                context.fill(drawing.arrowheads, with: .color(Palette.crossLink))
            }
            if !drawing.suggestionEdges.isEmpty {
                let dashed = StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, lineCap: .round, dash: CanvasMetrics.suggestionDash)
                context.stroke(drawing.suggestionEdges, with: .style(aiStyle), style: dashed)
            }
            if !drawing.suggestionShapes.isEmpty {
                context.fill(drawing.suggestionShapes, with: .color(Palette.canvasBackground))
                let dashed = StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, dash: CanvasMetrics.suggestionDash)
                context.stroke(drawing.suggestionShapes, with: .style(aiStyle), style: dashed)
            }
            for (fill, path) in drawing.fills {
                context.fill(path, with: .color(fill.color))
            }
            for (color, path) in drawing.imagePlaceholders {
                context.stroke(path, with: .color(color.color.opacity(CanvasMetrics.imagePlaceholderOpacity)))
            }
            for (stroke, path) in drawing.outlines {
                context.stroke(path, with: .color(stroke.color.color), lineWidth: stroke.width)
            }
            if !drawing.selection.isEmpty {
                context.stroke(drawing.selection, with: .color(Palette.selectionRing), lineWidth: drawing.selectionWidth)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension Path {
    mutating func addCurve(_ edge: EdgePath) {
        move(to: edge.start)
        addCurve(to: edge.end, control1: edge.control1, control2: edge.control2)
    }

    /// A filled triangle pointing along the curve's last tangent.
    mutating func addArrowhead(at tip: CGPoint, from control: CGPoint) {
        let angle = atan2(tip.y - control.y, tip.x - control.x)
        let length = CanvasMetrics.crossLinkArrowLength
        let spread = CanvasMetrics.crossLinkArrowAngle
        move(to: tip)
        addLine(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        addLine(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        closeSubpath()
    }
}
