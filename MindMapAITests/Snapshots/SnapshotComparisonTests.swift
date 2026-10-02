#if os(macOS)
@testable import MindMapAI
import Testing

/// The comparison itself, on small bitmaps, so it runs in `scripts/ci.sh`
/// unlike the scenes: a glyph edge one pixel off passes, a missing line or a
/// changed colour does not (docs/testing.md, Comparing).
struct SnapshotComparisonTests {
    static let size = 20
    static let white: [UInt8] = [255, 255, 255, 255]
    static let ink: [UInt8] = [20, 20, 20, 255]
    static let accent: [UInt8] = [0, 90, 255, 255]

    /// White, with `filled` columns from `rows` painted `colour`.
    static func bitmap(columns filled: ClosedRange<Int>, rows: ClosedRange<Int> = 0...(size - 1), colour: [UInt8] = ink) -> Bitmap {
        var pixels = [UInt8]()
        for y in 0..<size {
            for x in 0..<size {
                pixels += filled.contains(x) && rows.contains(y) ? colour : white
            }
        }
        return Bitmap(width: size, height: size, pixels: pixels)
    }

    @Test func sameImageMatches() {
        let image = Self.bitmap(columns: 5...8)
        #expect(!image.compared(with: image).differs)
    }

    @Test func edgeOnePixelOffMatches() {
        // A whole column moving is far above 0.2% of 400 pixels, so only the
        // neighbourhood lets it pass.
        let comparison = Self.bitmap(columns: 6...9).compared(with: Self.bitmap(columns: 5...8))
        #expect(!comparison.differs)
        #expect(comparison.summary.hasPrefix("0 pixels"))
    }

    @Test func edgeTwoPixelsOffDiffers() {
        #expect(Self.bitmap(columns: 7...10).compared(with: Self.bitmap(columns: 5...8)).differs)
    }

    @Test func missingThinLineDiffers() {
        let blank = Self.bitmap(columns: 0...0, colour: Self.white)
        #expect(blank.compared(with: Self.bitmap(columns: 10...10)).differs)
        #expect(Self.bitmap(columns: 10...10).compared(with: blank).differs)
    }

    @Test func changedColourDiffers() {
        #expect(Self.bitmap(columns: 5...8, colour: Self.accent).compared(with: Self.bitmap(columns: 5...8)).differs)
    }

    @Test func otherSizeDiffers() {
        let small = Bitmap(width: 1, height: 1, pixels: Self.white)
        #expect(small.compared(with: Self.bitmap(columns: 5...8)).differs)
    }
}
#endif
