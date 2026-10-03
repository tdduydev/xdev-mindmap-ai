import CoreText
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import SwiftUI
import Testing

/// Japanese in the brand fonts (MM-96, NFR-L10N, FR-LAY-06): kanji, kana and
/// Japanese punctuation fall back to Hiragino Sans, not to empty boxes or to
/// Chinese glyph forms, and the canvas measures a Japanese title as it draws it.
@MainActor
@Suite("Japanese typography")
struct JapaneseTypographyTests {
    /// A Mac set to English and Vietnamese, as the shared Mac mini is.
    static let westernLanguages = ["en-VN", "vi-VN"]

    static let japanese = ["直角三角形", "ひらがな", "カタカナ", "ｶﾀｶﾅ", "、。「」・ー", "ユーザー調査"]

    private func fallback(_ font: CTFont, for text: String) -> String {
        let fallback = CTFontCreateForString(font, text as CFString, CFRange(location: 0, length: (text as NSString).length))
        return CTFontCopyPostScriptName(fallback) as String
    }

    @Test(arguments: BrandFont.allCases)
    func japaneseFallsBackToHiraginoSans(_ face: BrandFont) {
        let font = ContentFont.makeFont(postScriptName: face.postScriptName, size: 14, languages: Self.westernLanguages)

        for text in Self.japanese {
            #expect(fallback(font, for: text) == ContentFont.japaneseFace(for: face.postScriptName), "\(text)")
        }
        #expect(fallback(font, for: "Việt Nam") == face.postScriptName)
        #expect(CTFontCopyPostScriptName(font) as String == face.postScriptName)
    }

    @Test func everyJapaneseCharacterHasAGlyph() {
        let font = ContentFont.ctFont(postScriptName: BrandFont.beVietnamProSemiBold.postScriptName, size: 15)
        for text in Self.japanese + UITestFixture.japaneseTitles {
            for character in text {
                let units = Array(String(character).utf16)
                let fallback = CTFontCreateForString(font, String(character) as CFString, CFRange(location: 0, length: units.count))
                var glyphs = [CGGlyph](repeating: 0, count: units.count)
                #expect(CTFontGetGlyphsForCharacters(fallback, units, &glyphs, units.count), "\(character)")
            }
        }
    }

    @Test func chineseReadersKeepTheSystemCascade() {
        #expect(ContentFont.prefersJapaneseHan(["ja-JP", "zh-Hans"]))
        #expect(ContentFont.prefersJapaneseHan(Self.westernLanguages))
        #expect(!ContentFont.prefersJapaneseHan(["en-US", "zh-Hant-TW", "ja-JP"]))

        let font = ContentFont.makeFont(postScriptName: BrandFont.beVietnamProRegular.postScriptName, size: 14, languages: ["zh-Hans"])
        #expect(CTFontCopyAttribute(font, kCTFontCascadeListAttribute) == nil)
    }

    /// The title view, laid out at the width the box gives it, is as tall as
    /// the measure: same lines, nothing cut (FR-LAY-06).
    @Test(arguments: 0...3)
    func titlesAreDrawnAsTallAsMeasured(level: Int) {
        let specs = TopicTextSpecs.designSizes()
        let spec = specs.spec(level: level)
        let measurer = TopicMeasurer(specs: specs)
        let titles = [
            "Plan",
            "Phỏng vấn người dùng về nhu cầu chính của sản phẩm mới",
            "Interview users about the main needs of the new product and write up the results before the next sprint",
            "ユーザーインタビュー",
            "新製品の主なニーズについてユーザーにインタビューし、結果を次のスプリントまでにまとめる",
            "第1四半期のKPIとOKRを、チーム全体で見直す（3月まで）",
            "直角三角形の面積は、底辺×高さ÷2で求められる。",
        ]
        for title in titles {
            let box = measurer.size(of: title, level: level)
            let width = box.width - 2 * spec.horizontalPadding
            let drawn = fittedSize(TopicTitleText(title: title, spec: spec, color: .primary, placeholderColor: .secondary, width: width), width: width)
            let measured = box.height - 2 * spec.verticalPadding
            // The host without a window rounds each line to whole points, up
            // to a point a line; a line more or less is 16 points or more.
            let lines = max(1, (measured / spec.pointSize).rounded(.down))
            #expect(abs(drawn.height - measured) <= lines, "\(title) at level \(level): drawn \(drawn.height), measured \(measured)")
            #expect(drawn.width <= width + 1, "\(title) at level \(level)")
        }
    }

    private func fittedSize(_ view: some View, width: CGFloat) -> CGSize {
        #if os(macOS)
        let host = NSHostingController(rootView: view)
        #else
        let host = UIHostingController(rootView: view)
        #endif
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

private extension UITestFixture {
    /// Every title of the Japanese showcase map, as the screenshots draw them.
    static var japaneseTitles: [String] {
        (try? UITestFixture.showcaseJa.makeMaps().graphs.flatMap { $0.nodes.values.map(\.title) }) ?? []
    }
}
