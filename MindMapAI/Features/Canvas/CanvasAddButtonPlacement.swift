import CoreGraphics
import MindMapLayout

/// Places the two + controls beside a card in view points, so their
/// `Metrics.minimumHitTarget` tap areas never shrink with the zoom.
enum CanvasAddButtonPlacement {
    /// Add child: outside the card on the side away from the parent, at mid-height.
    static func childFrame(for topic: CanvasTopic, viewport: CanvasViewport) -> CGRect {
        let isTrailing = topic.side != .left
        let cardEdge = viewport.toView(CGPoint(
            x: isTrailing ? topic.frame.maxX : topic.frame.minX,
            y: topic.frame.midY
        ))
        let badgeClearance = topic.hiddenDescendantCount > 0
            ? CanvasMetrics.addButtonBadgeClearance * viewport.scale : 0
        let distance = Metrics.minimumHitTarget / 2 + clearance(viewport) + badgeClearance
        return square(around: CGPoint(x: cardEdge.x + (isTrailing ? distance : -distance), y: cardEdge.y))
    }

    /// Add sibling: under the card, centred, where the new topic will appear.
    /// Not on the parent-facing side, where the circle would hide the point the
    /// edge meets the card. Nil when the whole tap area does not fit before the
    /// next topic or callout: a smaller target would break the 44 pt minimum on
    /// iOS, and one reaching into that topic would steal its taps. Return, the
    /// menu and the context menu still add a sibling there.
    static func siblingFrame(for topic: CanvasTopic, among topics: [CanvasTopic], viewport: CanvasViewport) -> CGRect? {
        let card = viewFrame(topic.frame, viewport: viewport)
        let size = Metrics.minimumHitTarget
        let frame = CGRect(x: card.midX - size / 2, y: card.maxY + clearance(viewport), width: size, height: size)
        let isBlocked = topics.contains { other in
            guard other.id != topic.id else { return false }
            if viewFrame(other.frame, viewport: viewport).intersects(frame) { return true }
            return other.calloutFrame.map { viewFrame($0, viewport: viewport).intersects(frame) } ?? false
        }
        return isBlocked ? nil : frame
    }

    static func viewFrame(_ rect: CGRect, viewport: CanvasViewport) -> CGRect {
        let origin = viewport.toView(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * viewport.scale, height: rect.height * viewport.scale)
    }

    /// The selection ring is drawn outside the card and grows with the zoom;
    /// the circle starts beyond it so the ring stays whole.
    private static func clearance(_ viewport: CanvasViewport) -> CGFloat {
        CanvasMetrics.addButtonGap
            + (CanvasMetrics.selectionRingGap + CanvasMetrics.selectionRingWidthHighContrast) * viewport.scale
    }

    private static func square(around point: CGPoint) -> CGRect {
        let size = Metrics.minimumHitTarget
        return CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
    }
}
