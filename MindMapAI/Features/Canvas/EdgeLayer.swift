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
    var selection = Path()
    var selectionWidth: CGFloat = CanvasMetrics.selectionRingWidth

    /// Only what meets the culling rectangle is built (FR-CNV-06).
    static func make(
        model: CanvasModel,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> CanvasDrawing {
        var drawing = CanvasDrawing()
        let scene = model.scene
        let rect = model.cullingRect

        for (child, path) in scene.connectors(in: rect) {
            guard let topic = scene.topic(child) else { continue }
            let style = model.style(for: topic, colorScheme: colorScheme, contrast: contrast)
            drawing.edges[Stroke(color: style.edgeColor, width: style.edgeWidth), default: Path()].addCurve(path)
        }

        for (id, path) in scene.crossLinks(in: rect) {
            drawing.crossLinks.addCurve(path)
            if scene.crossLinkTypes[id] == .reference {
                drawing.arrowheads.addArrowhead(at: path.end, from: path.control2)
            }
        }

        guard !model.isDetailed else { return drawing }
        let selected = model.session.selection
        for topic in model.visibleTopics {
            let style = model.style(for: topic, colorScheme: colorScheme, contrast: contrast)
            let shape = Path(roundedRect: topic.frame, cornerRadius: style.box.cornerRadius, style: .continuous)
            drawing.fills[style.fill, default: Path()].addPath(shape)
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
            for (fill, path) in drawing.fills {
                context.fill(path, with: .color(fill.color))
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
