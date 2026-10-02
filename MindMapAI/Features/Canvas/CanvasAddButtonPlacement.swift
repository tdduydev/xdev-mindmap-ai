import CoreGraphics

/// Places the two + controls beside a card in screen points. The sibling
/// control uses the parent-facing side, clear of the card below and its title.
enum CanvasAddButtonPlacement {
    static func center(for topic: CanvasTopic, viewport: CanvasViewport, sibling: Bool) -> CGPoint {
        let isRightBranch = topic.side != .left
        let isTrailing = sibling ? !isRightBranch : isRightBranch
        let cardEdge = viewport.toView(CGPoint(
            x: isTrailing ? topic.frame.maxX : topic.frame.minX,
            y: topic.frame.midY
        ))
        let badgeClearance = !sibling && topic.hiddenDescendantCount > 0
            ? CanvasMetrics.addButtonBadgeClearance * viewport.scale : 0
        let distance = Metrics.minimumHitTarget / 2 + CanvasMetrics.addButtonGap + badgeClearance
        return CGPoint(x: cardEdge.x + (isTrailing ? distance : -distance), y: cardEdge.y)
    }

    static func frame(for topic: CanvasTopic, viewport: CanvasViewport, sibling: Bool) -> CGRect {
        let point = center(for: topic, viewport: viewport, sibling: sibling)
        let size = Metrics.minimumHitTarget
        return CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
    }
}
