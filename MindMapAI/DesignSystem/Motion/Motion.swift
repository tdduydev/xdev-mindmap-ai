import SwiftUI

/// Animation timing from the xDev motion tokens. All animation goes through
/// here; with Reduce Motion on, movement becomes a fast crossfade or nothing.
enum Motion {
    enum Duration {
        static let instant: Double = 0.08
        static let fast: Double = 0.12
        static let base: Double = 0.18
        static let slow: Double = 0.24
        static let slower: Double = 0.32
    }

    /// Cubic Bézier control points (x1, y1, x2, y2).
    struct Curve: Hashable, Sendable {
        let x1: Double, y1: Double, x2: Double, y2: Double

        static let standard = Curve(x1: 0.2, y1: 0, x2: 0, y2: 1)
        static let emphasized = Curve(x1: 0.3, y1: 0, x2: 0, y2: 1)
        static let enter = Curve(x1: 0, y1: 0, x2: 0.2, y2: 1)
        static let exit = Curve(x1: 0.4, y1: 0, x2: 1, y2: 1)

        func animation(duration: Double) -> Animation {
            .timingCurve(x1, y1, x2, y2, duration: duration)
        }
    }

    /// Delay between AI suggestions fading in one after another.
    static let suggestionStagger: Double = 0.04

    /// UI tests run with no animation (docs/testing.md), so a query never
    /// finds a view halfway through moving.
    private static func isStill(_ reduceMotion: Bool) -> Bool {
        reduceMotion || UITestMode.isActive
    }

    /// 180 ms with the standard curve; nil (no animation) with Reduce Motion.
    static func standard(reduceMotion: Bool) -> Animation? {
        isStill(reduceMotion) ? nil : Curve.standard.animation(duration: Duration.base)
    }

    /// A topic appearing: fade and scale in, or a quick fade with Reduce Motion.
    static func topicAdded(reduceMotion: Bool) -> Animation {
        if UITestMode.isActive { return Curve.standard.animation(duration: 0) }
        return reduceMotion ? Curve.standard.animation(duration: Duration.fast) : Curve.enter.animation(duration: Duration.base)
    }

    /// Scale a new topic starts from; 1 with Reduce Motion, so it only fades.
    static func topicAddedScale(reduceMotion: Bool) -> CGFloat {
        isStill(reduceMotion) ? 1 : 0.96
    }

    /// A topic disappearing; removed without animation with Reduce Motion.
    static func topicDeleted(reduceMotion: Bool) -> Animation? {
        isStill(reduceMotion) ? nil : Curve.exit.animation(duration: Duration.fast)
    }

    /// Topics moving to new frames after collapse, expand or relayout.
    static func relayout(reduceMotion: Bool) -> Animation? {
        isStill(reduceMotion) ? nil : Curve.standard.animation(duration: Duration.slow)
    }

    /// Camera moves: zoom to fit, jump to a search result.
    static func camera(reduceMotion: Bool) -> Animation? {
        isStill(reduceMotion) ? nil : Curve.emphasized.animation(duration: Duration.slower)
    }

    /// The AI suggestion at `index` fading in after the ones before it; all at
    /// once with Reduce Motion.
    static func suggestionArrival(index: Int, reduceMotion: Bool) -> Animation? {
        isStill(reduceMotion) ? nil : Curve.enter.animation(duration: Duration.base).delay(Double(index) * suggestionStagger)
    }

    static func selection(reduceMotion: Bool) -> Animation? {
        isStill(reduceMotion) ? nil : Curve.standard.animation(duration: Duration.instant)
    }
}
