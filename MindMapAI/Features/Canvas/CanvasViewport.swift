import CoreGraphics

/// The camera over the infinite canvas: which canvas point sits where in the
/// view, and at what zoom. A point maps as `view = canvas × scale + offset`.
///
/// A plain value, so pan, zoom, fit and culling are tested without a window.
struct CanvasViewport: Equatable {
    var scale: CGFloat = 1
    /// Where the canvas origin (the central topic's centre) lands in the view.
    var offset: CGPoint = .zero
    var size: CGSize = .zero

    // MARK: Mapping

    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
    }

    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    /// The part of the canvas the view shows.
    var visibleRect: CGRect {
        let origin = toCanvas(.zero)
        return CGRect(x: origin.x, y: origin.y, width: size.width / scale, height: size.height / scale)
    }

    /// The visible rectangle grown by `fraction` of its size on every side, so
    /// topics just outside are already there when a pan brings them in.
    func cullingRect(margin fraction: CGFloat) -> CGRect {
        let visible = visibleRect
        return visible.insetBy(dx: -visible.width * fraction, dy: -visible.height * fraction)
    }

    // MARK: Moving

    mutating func pan(by delta: CGSize) {
        offset.x += delta.width
        offset.y += delta.height
    }

    /// Changes the zoom so the canvas point under `anchor` (a view point) stays put.
    mutating func zoom(to newScale: CGFloat, anchor: CGPoint, limits: ClosedRange<CGFloat>) {
        let clamped = min(max(newScale, limits.lowerBound), limits.upperBound)
        guard clamped != scale else { return }
        let ratio = clamped / scale
        offset.x = anchor.x - (anchor.x - offset.x) * ratio
        offset.y = anchor.y - (anchor.y - offset.y) * ratio
        scale = clamped
    }

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    /// Puts `point` (canvas) in the middle of the view without changing the zoom.
    mutating func center(on point: CGPoint) {
        offset = CGPoint(x: size.width / 2 - point.x * scale, y: size.height / 2 - point.y * scale)
    }

    /// Keeps the canvas point at the view's centre when the view is resized.
    mutating func resize(to newSize: CGSize) {
        guard newSize != size else { return }
        offset.x += (newSize.width - size.width) / 2
        offset.y += (newSize.height - size.height) / 2
        size = newSize
    }

    /// Zooms and centres so `rect` fits inside the view with `padding` around it.
    mutating func fit(_ rect: CGRect, padding: CGFloat, limits: ClosedRange<CGFloat>) {
        guard !rect.isNull, size.width > 0, size.height > 0 else { return }
        let available = CGSize(width: max(size.width - 2 * padding, 1), height: max(size.height - 2 * padding, 1))
        let fitting = min(available.width / max(rect.width, 1), available.height / max(rect.height, 1))
        scale = min(max(fitting, limits.lowerBound), limits.upperBound)
        center(on: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Fits only the width of `rect`, keeping its vertical centre; for the
    /// iPhone's first view of a map.
    mutating func fitWidth(_ rect: CGRect, padding: CGFloat, limits: ClosedRange<CGFloat>) {
        guard !rect.isNull, size.width > 0 else { return }
        let fitting = max(size.width - 2 * padding, 1) / max(rect.width, 1)
        scale = min(max(fitting, limits.lowerBound), limits.upperBound)
        center(on: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Pans the least distance that brings `rect` (canvas) fully into view with
    /// `margin` view points to spare; a rectangle larger than the view gets its
    /// top leading corner shown.
    mutating func reveal(_ rect: CGRect, margin: CGFloat) {
        let frame = CGRect(origin: toView(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        guard bounds.width > 0, bounds.height > 0 else { return }
        offset.x += Self.shift(frame.minX, frame.maxX, into: bounds.minX, bounds.maxX)
        offset.y += Self.shift(frame.minY, frame.maxY, into: bounds.minY, bounds.maxY)
    }

    private static func shift(_ low: CGFloat, _ high: CGFloat, into lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        if high - low > upper - lower || low < lower { return lower - low }
        if high > upper { return upper - high }
        return 0
    }

    // MARK: Zoom steps

    /// The next step above (or below) the current zoom, for ⌘+ and ⌘−; a zoom
    /// between steps (after a pinch) goes to the nearest step in that direction.
    func zoomStep(up: Bool, steps: [CGFloat]) -> CGFloat {
        // A small tolerance so 99.99% after a pinch does not count as below 100%.
        let tolerance: CGFloat = 0.001
        if up {
            return steps.first { $0 > scale + tolerance } ?? steps.last ?? scale
        }
        return steps.last { $0 < scale - tolerance } ?? steps.first ?? scale
    }
}
