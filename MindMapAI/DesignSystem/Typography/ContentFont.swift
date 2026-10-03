import CoreText
import Foundation
import os
import SwiftUI

/// A brand face with Japanese fallback (NFR-L10N, MM-96). The brand faces
/// have Latin and Vietnamese glyphs only. Without a cascade, CoreText picks
/// the fallback from the person's languages: on a Mac set to English or
/// Vietnamese, kana falls back to Hiragino Sans but kanji and 、。「」 fall back
/// to PingFang SC, so one Japanese title mixes Chinese and Japanese glyph
/// forms. The cascade puts Hiragino Sans first, at the brand face's weight.
///
/// The canvas measures (`TopicMeasurer`) and draws (`TopicView`) with the
/// same `CTFont` from here, so a wrapped Japanese title takes the space measured.
nonisolated enum ContentFont {
    /// The font to draw and measure content with: the brand face, then
    /// Hiragino Sans, then the system's cascade for Japanese.
    static func ctFont(postScriptName: String, size: CGFloat) -> CTFont {
        let key = Key(postScriptName: postScriptName, size: size)
        if let cached = cache.withLock({ $0[key] }) { return cached.value }
        let cached = Cached(value: makeFont(postScriptName: postScriptName, size: size, languages: Locale.preferredLanguages))
        cache.withLock { $0[key] = cached }
        return cached.value
    }

    /// The SwiftUI font for `ctFont`, at a fixed size: callers pass the size
    /// with Dynamic Type already applied, as the canvas does.
    static func font(postScriptName: String, size: CGFloat) -> Font {
        Font(ctFont(postScriptName: postScriptName, size: size))
    }

    /// The Hiragino Sans weight drawn beside a brand face. iOS has W3, W6 and
    /// W7 only, so Medium takes W6 there and on the Mac alike.
    static func japaneseFace(for postScriptName: String) -> String {
        switch postScriptName {
        case BrandFont.beVietnamProRegular.rawValue: "HiraginoSans-W3"
        default: "HiraginoSans-W6"
        }
    }

    /// Builds the cascade. Someone who reads Chinese before Japanese keeps the
    /// system's cascade, which already gives their Han glyph forms.
    static func makeFont(postScriptName: String, size: CGFloat, languages: [String]) -> CTFont {
        let base = CTFontCreateWithName(postScriptName as CFString, size, nil)
        guard prefersJapaneseHan(languages) else { return base }
        let japanese = CTFontDescriptorCreateWithNameAndSize(japaneseFace(for: postScriptName) as CFString, size)
        let system = CTFontCopyDefaultCascadeListForLanguages(base, ["ja"] as CFArray) as? [CTFontDescriptor] ?? []
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: postScriptName,
            kCTFontCascadeListAttribute: [japanese] + system,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Whether Japanese comes before any Chinese language in `languages`
    /// (none of either counts as Japanese: the app's CJK language is Japanese).
    static func prefersJapaneseHan(_ languages: [String]) -> Bool {
        for language in languages {
            let code = Locale.Language(identifier: language).languageCode?.identifier
            if code == "ja" { return true }
            if code == "zh" || code == "yue" { return false }
        }
        return true
    }

    private struct Key: Hashable {
        let postScriptName: String
        let size: CGFloat
    }

    /// CoreText fonts are immutable and thread-safe.
    private struct Cached: @unchecked Sendable {
        let value: CTFont
    }

    private static let cache = OSAllocatedUnfairLock<[Key: Cached]>(initialState: [:])
}
