import CoreGraphics
import MindMapDomain
import MindMapLayout

/// An arrow key on the canvas.
nonisolated enum CanvasDirection: Sendable {
    case up, down, left, right
}

/// Where on a topic a dragged branch would land.
nonisolated enum CanvasDropZone: Sendable {
    /// A sibling just before or after the topic.
    case before, after
    /// The topic's last child.
    case inside
}

extension CanvasScene {
    /// The topic an arrow key goes to from `id`, by the tree as drawn: away
    /// from the central topic is the children (the one level with the topic),
    /// towards it the parent, up and down the next sibling on screen, else the
    /// nearest topic of the same level on that side.
    nonisolated func neighbour(of id: NodeID, toward direction: CanvasDirection) -> CanvasTopic? {
        guard let current = topic(id) else { return nil }
        let middle = current.frame.midY

        switch direction {
        case .left, .right:
            let outward: LayoutSide = direction == .right ? .right : .left
            let isRoot = current.parentID == nil
            guard isRoot || current.side == outward else { return current.parentID.flatMap(topic) }
            return topics
                .filter { $0.parentID == id && (!isRoot || $0.side == outward) }
                .min { abs($0.frame.midY - middle) < abs($1.frame.midY - middle) }
        case .up, .down:
            guard current.parentID != nil else { return nil }
            func ahead(_ topic: CanvasTopic) -> Bool {
                direction == .up ? topic.frame.midY < middle : topic.frame.midY > middle
            }
            let distance = { (topic: CanvasTopic) in abs(topic.frame.midY - middle) }
            let siblings = topics.filter { $0.parentID == current.parentID && $0.side == current.side && ahead($0) }
            if let sibling = siblings.min(by: { distance($0) < distance($1) }) { return sibling }
            return topics
                .filter { $0.level == current.level && $0.side == current.side && $0.id != id && ahead($0) }
                .min { (distance($0), abs($0.frame.midX - current.frame.midX)) < (distance($1), abs($1.frame.midX - current.frame.midX)) }
        }
    }

    /// The topic under a canvas point while dragging and where on it the drop
    /// would go. `slack` widens each topic up and down to cover half the gap to
    /// its neighbours, so there is no dead space between siblings. The top and
    /// bottom `edgeFraction` of a topic insert beside it, the middle inside it;
    /// the central topic has no siblings, so all of it is inside.
    nonisolated func dropZone(at point: CGPoint, slack: CGFloat, edgeFraction: CGFloat) -> (topic: CanvasTopic, zone: CanvasDropZone)? {
        guard let topic = topics.last(where: { $0.frame.insetBy(dx: 0, dy: -slack).contains(point) }) else { return nil }
        guard topic.parentID != nil else { return (topic, .inside) }
        let edge = topic.frame.height * edgeFraction
        if point.y < topic.frame.minY + edge { return (topic, .before) }
        if point.y > topic.frame.maxY - edge { return (topic, .after) }
        return (topic, .inside)
    }
}
