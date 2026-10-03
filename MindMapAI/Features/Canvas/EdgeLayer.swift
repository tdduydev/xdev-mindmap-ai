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

    /// A connection's look that changes the stroke; dimmed ones have their own.
    struct LinkStroke: Hashable {
        let color: SRGBColor
        let lineStyle: EdgeLineStyle
        let isDimmed: Bool
    }

    struct LinkFill: Hashable {
        let color: SRGBColor
        let isDimmed: Bool
    }

    struct Label {
        let text: String
        let center: CGPoint
        let color: SRGBColor
        let isDimmed: Bool
    }

    /// A boundary's frame and title, drawn under every edge and topic.
    struct Boundary {
        let frame: CGRect
        let title: String?
        let line: SRGBColor
        let fill: SRGBColor
        let strokeWidth: CGFloat
        let isSelected: Bool
        let isSuggestion: Bool
    }

    struct Badge {
        /// The top-leading corner of the topic it marks.
        let corner: CGPoint
        let count: Int
    }

    /// Outermost first.
    var boundaries: [Boundary] = []
    var edges: [Stroke: Path] = [:]
    var crossLinks: [LinkStroke: Path] = [:]
    var arrowheads: [LinkFill: Path] = [:]
    var connectionLabels: [Label] = []
    var connectionBadges: [Badge] = []
    /// Topics drawn as shapes below the detail zoom.
    var fills: [SRGBColor: Path] = [:]
    var outlines: [Stroke: Path] = [:]
    var imagePlaceholders: [SRGBColor: Path] = [:]
    var selection = Path()
    /// The selected connection, drawn over its own stroke in the selection colour.
    var selectedConnection = Path()
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
            selectedConnection: model.session.activeConnection,
            selectedBoundary: model.session.activeBoundary,
            variant: ColorVariant(colorScheme: colorScheme, contrast: contrast),
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
        selectedConnection: EdgeID? = nil,
        selectedBoundary: GroupID? = nil,
        variant: ColorVariant,
        imageFrame: (CanvasTopic) -> CGRect? = { _ in nil },
        style: (CanvasTopic) -> TopicStyle
    ) -> CanvasDrawing {
        var drawing = CanvasDrawing()

        for boundary in scene.boundaries where boundary.frame.intersects(rect) {
            let colors = BranchColors(line: (boundary.color ?? .graphite).token, variant: variant)
            drawing.boundaries.append(Boundary(
                frame: boundary.frame,
                title: boundary.title,
                line: colors.line,
                fill: colors.subFill,
                strokeWidth: variant.isHighContrast ? CanvasMetrics.boundaryStrokeWidthHighContrast : CanvasMetrics.boundaryStrokeWidth,
                isSelected: boundary.id == selectedBoundary,
                isSuggestion: boundary.isSuggestion
            ))
        }

        for (child, path) in scene.connectors(in: rect) {
            guard let topic = scene.topic(child) else { continue }
            if topic.isSuggestion {
                drawing.suggestionEdges.addCurve(path)
                continue
            }
            let style = style(topic)
            drawing.edges[Stroke(color: style.edgeColor, width: style.edgeWidth), default: Path()].addCurve(path)
        }

        // A bracket stands for the connector to its summary topic, so it takes that topic's line.
        for bracket in scene.summaryBrackets(in: rect) {
            let stroke = bracket.summaryNodeID.flatMap(scene.topic).map { topic in
                let style = style(topic)
                return Stroke(color: style.edgeColor, width: style.edgeWidth)
            } ?? Stroke(color: BranchColors(line: TopicColor.graphite.token, variant: variant).line,
                width: CanvasMetrics.boundaryStrokeWidth)
            drawing.edges[stroke, default: Path()].addSummaryBracket(bracket)
        }

        for (id, path) in scene.crossLinks(in: rect) {
            guard let look = scene.crossLinkLooks[id] else { continue }
            let color = (look.color?.token ?? Palette.Tokens.crossLink)[variant]
            drawing.crossLinks[LinkStroke(color: color, lineStyle: look.lineStyle, isDimmed: look.isRerouted), default: Path()]
                .addCurve(path)
            let fill = LinkFill(color: color, isDimmed: look.isRerouted)
            if look.hasEndArrow {
                drawing.arrowheads[fill, default: Path()].addArrowhead(at: path.end, from: path.control2)
            }
            if look.hasStartArrow {
                drawing.arrowheads[fill, default: Path()].addArrowhead(at: path.start, from: path.control1)
            }
            if id == selectedConnection { drawing.selectedConnection.addCurve(path) }
            if let label = look.label {
                drawing.connectionLabels.append(Label(text: label, center: path.midpoint, color: color, isDimmed: look.isRerouted))
            }
        }
        for (id, count) in scene.connectionBadges {
            guard let topic = scene.topic(id), topic.frame.intersects(rect) else { continue }
            drawing.connectionBadges.append(Badge(corner: topic.frame.origin, count: count))
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

            for boundary in drawing.boundaries {
                drawBoundary(boundary, in: &context)
            }

            for (stroke, path) in drawing.edges {
                context.stroke(path, with: .color(stroke.color.color), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round))
            }
            for (stroke, path) in drawing.crossLinks {
                let opacity = stroke.isDimmed ? CanvasMetrics.reroutedCrossLinkOpacity : 1
                context.stroke(path, with: .color(stroke.color.color.opacity(opacity)), style: Self.strokeStyle(stroke.lineStyle))
            }
            for (fill, path) in drawing.arrowheads {
                let opacity = fill.isDimmed ? CanvasMetrics.reroutedCrossLinkOpacity : 1
                context.fill(path, with: .color(fill.color.color.opacity(opacity)))
            }
            if !drawing.selectedConnection.isEmpty {
                context.stroke(drawing.selectedConnection, with: .color(Palette.selectionRing),
                    style: StrokeStyle(lineWidth: drawing.selectionWidth, lineCap: .round))
            }
            for label in drawing.connectionLabels {
                drawLabel(label, in: &context)
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
            for badge in drawing.connectionBadges {
                drawBadge(badge, in: &context)
            }
        }
        .accessibilityHidden(true)
    }

    static func strokeStyle(_ lineStyle: EdgeLineStyle) -> StrokeStyle {
        let width = CanvasMetrics.crossLinkWidth
        return switch lineStyle {
        case .solid: StrokeStyle(lineWidth: width, lineCap: .round)
        case .dotted: StrokeStyle(lineWidth: width, lineCap: .round, dash: CanvasMetrics.crossLinkDot)
        // A style from a newer version draws as the V1 dash.
        default: StrokeStyle(lineWidth: width, lineCap: .round, dash: CanvasMetrics.crossLinkDash)
        }
    }

    private func drawLabel(_ label: CanvasDrawing.Label, in context: inout GraphicsContext) {
        let padding = CanvasMetrics.connectionLabelPadding
        let text = context.resolve(Text(label.text)
            .font(Typography.Content.badge.font)
            .foregroundStyle(Palette.topicText))
        let size = text.measure(in: CGSize(width: CanvasMetrics.connectionLabelMaxWidth, height: .infinity))
        let box = CGRect(
            x: label.center.x - size.width / 2 - padding.width,
            y: label.center.y - size.height / 2 - padding.height,
            width: size.width + 2 * padding.width,
            height: size.height + 2 * padding.height
        )
        var context = context
        if label.isDimmed { context.opacity = CanvasMetrics.reroutedCrossLinkOpacity }
        let capsule = Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous)
        context.fill(capsule, with: .color(Palette.canvasBackground))
        context.stroke(capsule, with: .color(label.color.color), lineWidth: CanvasMetrics.crossLinkWidth)
        context.draw(text, in: box.insetBy(dx: padding.width, dy: padding.height))
    }

    private func drawBoundary(_ boundary: CanvasDrawing.Boundary, in context: inout GraphicsContext) {
        let shape = Path(roundedRect: boundary.frame, cornerRadius: CanvasMetrics.boundaryCornerRadius, style: .continuous)
        if boundary.isSuggestion {
            context.fill(shape, with: .color(Palette.canvasBackground))
            context.stroke(shape, with: .style(aiStyle),
                style: StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, dash: CanvasMetrics.suggestionDash))
        } else {
            context.fill(shape, with: .color(boundary.fill.color))
            context.stroke(shape, with: .color(boundary.line.color), lineWidth: boundary.strokeWidth)
        }
        if boundary.isSelected {
            let outset = CanvasMetrics.selectionRingGap
            let ring = Path(roundedRect: boundary.frame.insetBy(dx: -outset, dy: -outset),
                cornerRadius: CanvasMetrics.boundaryCornerRadius + outset, style: .continuous)
            context.stroke(ring, with: .color(Palette.selectionRing), lineWidth: drawing.selectionWidth)
        }
        guard let title = boundary.title else { return }
        let padding = CanvasMetrics.boundaryTitlePadding
        let text = context.resolve(Text(title)
            .font(Typography.Content.badge.font)
            .foregroundStyle(Palette.topicText))
        let size = text.measure(in: CGSize(width: CanvasMetrics.boundaryTitleMaxWidth - 2 * padding.width, height: CanvasMetrics.boundaryTitleHeight))
        let box = CGRect(
            x: boundary.frame.minX + CanvasMetrics.boundaryPadding,
            y: boundary.frame.minY + (CanvasMetrics.boundaryTitleHeight - size.height) / 2 - padding.height,
            width: size.width + 2 * padding.width,
            height: size.height + 2 * padding.height
        )
        let capsule = Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous)
        context.fill(capsule, with: .color(Palette.canvasBackground))
        if boundary.isSuggestion {
            context.stroke(capsule, with: .style(aiStyle),
                style: StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, dash: CanvasMetrics.suggestionDash))
        } else {
            context.stroke(capsule, with: .color(boundary.line.color), lineWidth: boundary.strokeWidth)
        }
        context.draw(text, in: box.insetBy(dx: padding.width, dy: padding.height))
    }

    private func drawBadge(_ badge: CanvasDrawing.Badge, in context: inout GraphicsContext) {
        let padding = CanvasMetrics.connectionBadgePadding
        let content = context.resolve(Text("\(Image(systemName: CanvasMetrics.connectionBadgeSymbol)) \(badge.count)")
            .font(Typography.Content.badge.font)
            .foregroundStyle(Palette.crossLink))
        let size = content.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
        let box = CGRect(
            x: badge.corner.x - size.width / 2 - padding.width,
            y: badge.corner.y - size.height / 2 - padding.height,
            width: size.width + 2 * padding.width,
            height: size.height + 2 * padding.height
        )
        let capsule = Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous)
        context.fill(capsule, with: .color(Palette.canvasBackground))
        context.stroke(capsule, with: .color(Palette.crossLink), lineWidth: CanvasMetrics.crossLinkWidth)
        context.draw(content, in: box.insetBy(dx: padding.width, dy: padding.height))
    }
}

extension EdgePath {
    /// The curve at t = 0.5, where a connection's label sits.
    nonisolated var midpoint: CGPoint {
        CGPoint(
            x: (start.x + 3 * control1.x + 3 * control2.x + end.x) / 8,
            y: (start.y + 3 * control1.y + 3 * control2.y + end.y) / 8
        )
    }
}

private extension Path {
    mutating func addCurve(_ edge: EdgePath) {
        move(to: edge.start)
        addCurve(to: edge.end, control1: edge.control1, control2: edge.control2)
    }

    /// A `}` filling the bracket's frame, its back on the run's side and its
    /// tip, at mid-height, toward the summary topic.
    mutating func addSummaryBracket(_ bracket: SummaryBracket) {
        let frame = bracket.frame
        let back = bracket.side == .left ? frame.maxX : frame.minX
        let tip = bracket.side == .left ? frame.minX : frame.maxX
        let spine = (back + tip) / 2
        // The curls take half the width, or less on a short run so the spine stays straight.
        let curl = min(frame.width / 2, frame.height / 4)
        let top = frame.minY
        let middle = frame.midY
        let bottom = frame.maxY
        move(to: CGPoint(x: back, y: top))
        addQuadCurve(to: CGPoint(x: spine, y: top + curl), control: CGPoint(x: spine, y: top))
        addLine(to: CGPoint(x: spine, y: middle - curl))
        addQuadCurve(to: CGPoint(x: tip, y: middle), control: CGPoint(x: spine, y: middle))
        addQuadCurve(to: CGPoint(x: spine, y: middle + curl), control: CGPoint(x: spine, y: middle))
        addLine(to: CGPoint(x: spine, y: bottom - curl))
        addQuadCurve(to: CGPoint(x: back, y: bottom), control: CGPoint(x: spine, y: bottom))
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
