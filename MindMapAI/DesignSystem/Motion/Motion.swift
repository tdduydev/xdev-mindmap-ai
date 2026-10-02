import SwiftUI

/// Animation timing from the xDev motion tokens: 180 ms with the standard
/// curve (0.2, 0, 0, 1). With Reduce Motion on, changes happen without animation.
enum Motion {
    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.18)
    }
}
