import CoreGraphics
import CoreText
import Foundation

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

/// The text settings for every level, plus the placeholder an untitled topic shows.
nonisolated struct TopicTextSpecs: Hashable, Sendable {
    /// Central, main, sub, deep: indexed by level, the last one repeating.
    let levels: [TopicTextSpec]
    let placeholder: String

    func spec(level: Int) -> TopicTextSpec {
        levels[min(max(level, 0), levels.count - 1)]
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
        let spec = specs.spec(level: level)
        let text = title.isEmpty ? specs.placeholder : title
        let measured = Self.measure(text, font: font(for: spec), lineSpacing: spec.lineSpacing, wrapWidth: spec.wrapWidth)
        let width = (measured.width + Self.widthSlack + 2 * spec.horizontalPadding).rounded(.up)
        let height = (measured.height + 2 * spec.verticalPadding).rounded(.up)
        return CGSize(
            width: min(spec.maximumWidth, max(spec.minimumWidth, width)),
            height: max(spec.minimumHeight, height)
        )
    }

    private func font(for spec: TopicTextSpec) -> CTFont {
        let key = "\(spec.postScriptName)@\(spec.pointSize)"
        if let font = fonts[key] { return font }
        let font = CTFontCreateWithName(spec.postScriptName as CFString, spec.pointSize, nil)
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
