import CoreGraphics
import CoreText
import Foundation
import MindMapDomain

/// How a topic at one level sets its title: a plain copy of the design-system
/// values with Dynamic Type already applied, so measuring can run off the main
/// actor (the design-system enums are main-actor isolated).
nonisolated struct TopicTextSpec: Hashable, Sendable {
    let postScriptName: String
    /// The point size the title is drawn at, after Dynamic Type.
    let pointSize: CGFloat
    /// Extra space between lines so a line takes the design's line height;
    /// the topic view passes the same value to `lineSpacing`.
    let lineSpacing: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    let minimumHeight: CGFloat

    /// The width a title wraps at inside the box.
    var wrapWidth: CGFloat { maximumWidth - 2 * horizontalPadding - TopicMeasurer.widthSlack }
}

/// How tag chips under a title are set (MM-34), with Dynamic Type applied.
nonisolated struct TopicChipSpec: Hashable, Sendable {
    let postScriptName: String
    let pointSize: CGFloat
    let horizontalPadding: CGFloat
    let height: CGFloat
    /// Between chips in a row, and between rows.
    let spacing: CGFloat
    /// Between the title and the chips.
    let topGap: CGFloat
    /// The AI mark before a suggested tag's name.
    let symbolWidth: CGFloat
}

/// How a picture above the title is sized (MM-63).
nonisolated struct TopicImageSpec: Hashable, Sendable {
    /// Height ÷ width at most.
    let maximumAspect: Double
    /// Between the picture and the title.
    let gap: CGFloat
}

/// How the colour shape and symbol before a title are sized (MM-32).
nonisolated struct TopicMarkSpec: Hashable, Sendable {
    /// The colour's shape, drawn only with Differentiate Without Color.
    let shapeSize: CGFloat
    /// After each mark, before the next mark or the title.
    let gap: CGFloat
    /// A symbol's box is this many title point sizes wide, whatever the
    /// glyph, so the measure needs no font lookup for SF Symbols or emoji.
    let symbolWidthFactor: CGFloat
    /// Differentiate Without Color is on (or the picture is an export).
    let showsColorShapes: Bool

    /// Width of the marks with their gaps, before a title of this point size.
    func width(of marks: TopicMark, pointSize: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        if marks.shape != nil { width += shapeSize + gap }
        if marks.symbol != nil { width += symbolWidth(pointSize: pointSize) + gap }
        return width
    }

    func symbolWidth(pointSize: CGFloat) -> CGFloat {
        (pointSize * symbolWidthFactor).rounded(.up)
    }
}

/// The text settings for every level, plus the placeholder an untitled topic shows.
nonisolated struct TopicTextSpecs: Hashable, Sendable {
    /// Central, main, sub, deep: indexed by level, the last one repeating.
    let levels: [TopicTextSpec]
    let placeholder: String
    let chip: TopicChipSpec
    let image: TopicImageSpec
    let mark: TopicMarkSpec

    func spec(level: Int) -> TopicTextSpec {
        levels[min(max(level, 0), levels.count - 1)]
    }

    /// The marks a topic draws: its own colour's shape only when the setting
    /// asks for it, so turning the setting on or off measures every topic again.
    func mark(color: TopicColor?, symbol: String?) -> TopicMark {
        TopicMark(shape: mark.showsColorShapes ? color : nil, symbol: TopicSymbolCatalog.drawable(symbol))
    }

    func markWidth(_ marks: TopicMark, level: Int) -> CGFloat {
        mark.width(of: marks, pointSize: spec(level: level).pointSize)
    }
}

/// Measures topic boxes with CoreText, the engine SwiftUI's `Text` draws with,
/// using the same font, wrap width and line spacing as `TopicView`, so the
/// layout reserves exactly the space the title takes.
///
/// Not `Sendable` (it caches CoreText fonts); make one per layout pass.
nonisolated final class TopicMeasurer {
    /// Added to the measured text width before it becomes the box width.
    /// CoreText and SwiftUI can round a line's width differently by a fraction
    /// of a point; without slack a title that just fits could wrap in the view.
    static let widthSlack: CGFloat = 1

    private let specs: TopicTextSpecs
    private var fonts: [String: CTFont] = [:]

    init(specs: TopicTextSpecs) {
        self.specs = specs
    }

    func size(of title: String, level: Int) -> CGSize {
        var chips: [TopicChip] = []
        return size(of: title, level: level, chips: &chips)
    }

    /// The box for a title with tag chips under it. Sets each chip's width,
    /// which the view draws it at, so chips wrap into the same rows here and
    /// on screen: rows that fit the widest wrap also fit any narrower box
    /// that is at least as wide as the widest row.
    func size(of title: String, level: Int, chips: inout [TopicChip], image: CGSize? = nil, marks: TopicMark = .none) -> CGSize {
        let spec = specs.spec(level: level)
        let text = title.isEmpty ? specs.placeholder : title
        // The marks sit beside the title, so the title wraps in what is left.
        let markWidth = specs.markWidth(marks, level: level)
        let measured = Self.measure(text, font: font(postScriptName: spec.postScriptName, size: spec.pointSize), lineSpacing: spec.lineSpacing, wrapWidth: spec.wrapWidth - markWidth)
        var contentWidth = markWidth + measured.width + Self.widthSlack
        var contentHeight = measured.height
        if !chips.isEmpty {
            let rows = layOutChips(&chips, wrapWidth: spec.wrapWidth + Self.widthSlack)
            contentWidth = max(contentWidth, rows.width)
            contentHeight += specs.chip.topGap + rows.height
        }
        if let image {
            contentWidth = max(contentWidth, image.width)
            contentHeight += image.height + specs.image.gap
        }
        let width = (contentWidth + 2 * spec.horizontalPadding).rounded(.up)
        let height = (contentHeight + 2 * spec.verticalPadding).rounded(.up)
        return CGSize(
            width: min(spec.maximumWidth, max(spec.minimumWidth, width)),
            height: max(spec.minimumHeight, height)
        )
    }

    /// The frame of a topic's picture at this level: never wider than the
    /// box's content, so a Large picture on a sub-topic shrinks to fit.
    func imageSize(of image: MindImage, level: Int) -> CGSize {
        let spec = specs.spec(level: level)
        let size = image.displaySize(
            maximumWidth: Double(spec.maximumWidth - 2 * spec.horizontalPadding),
            maximumAspect: specs.image.maximumAspect
        )
        return CGSize(width: size.width, height: size.height)
    }

    /// Greedy rows, as `ChipFlowLayout` places them.
    private func layOutChips(_ chips: inout [TopicChip], wrapWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let chip = specs.chip
        let font = font(postScriptName: chip.postScriptName, size: chip.pointSize)
        var rowWidth: CGFloat = 0
        var widest: CGFloat = 0
        var rows = 1
        for index in chips.indices {
            let label = Self.measure(chips[index].label, font: font, lineSpacing: 0, wrapWidth: .greatestFiniteMagnitude / 4).width
            let symbol = chips[index].isSuggestion ? chip.symbolWidth : 0
            let width = min(wrapWidth, (label + Self.widthSlack + symbol + 2 * chip.horizontalPadding).rounded(.up))
            chips[index].width = width
            if rowWidth > 0, rowWidth + chip.spacing + width > wrapWidth {
                rows += 1
                rowWidth = width
            } else {
                rowWidth += rowWidth > 0 ? chip.spacing + width : width
            }
            widest = max(widest, rowWidth)
        }
        let height = CGFloat(rows) * chip.height + CGFloat(rows - 1) * chip.spacing
        return (widest, height)
    }

    private func font(postScriptName: String, size: CGFloat) -> CTFont {
        let key = "\(postScriptName)@\(size)"
        if let font = fonts[key] { return font }
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        fonts[key] = font
        return font
    }

    /// The natural line height SwiftUI gives a line of this font.
    static func naturalLineHeight(postScriptName: String, size: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// Width of the longest line and height of all lines once wrapped.
    private static func measure(_ text: String, font: CTFont, lineSpacing: CGFloat, wrapWidth: CGFloat) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let string = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: wrapWidth, height: .greatestFiniteMagnitude / 4), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        // CoreText documents this array as holding CTLine values only.
        let lines = CTFrameGetLines(frame) as! [CTLine]

        var width: CGFloat = 0
        var height: CGFloat = 0
        for line in lines {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            width = max(width, lineWidth - CGFloat(CTLineGetTrailingWhitespaceWidth(line)))
            height += ascent + descent + leading
        }
        height += lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }
}
