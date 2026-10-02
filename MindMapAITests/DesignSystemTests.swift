import Foundation
@testable import MindMapAI
import MindMapDomain
import SwiftUI
import Testing

#if os(macOS)
import AppKit
#endif

private typealias Tokens = Palette.Tokens

/// WCAG minimums from docs/design-system.md: text 4.5:1, graphics 3:1, in
/// all four colour variants.
private enum Minimum {
    static let text = 4.5
    static let graphic = 3.0
}

/// Approximate system backgrounds behind chrome colours (favourite star,
/// danger and success text): white in light mode, the dark window colour in
/// dark mode. Chrome surfaces are system colours, so these stand in for them.
private func systemBackground(_ variant: ColorVariant) -> RGBColor {
    variant.isDark ? RGBColor(hex: 0x1E1E1E) : RGBColor(hex: 0xFFFFFF)
}

private func expectContrast(
    _ foreground: RGBColor,
    on background: RGBColor,
    atLeast minimum: Double,
    _ pair: String,
    _ variant: ColorVariant,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let ratio = foreground.contrast(with: background)
    #expect(ratio >= minimum, "\(pair) in \(variant): \(ratio) < \(minimum)", sourceLocation: sourceLocation)
}

@Suite("Design system: contrast")
struct DesignSystemContrastTests {
    @Test func contrastMatchesTheDocumentedFigure() {
        #expect(abs(RGBColor(hex: 0xFFFFFF).contrast(with: RGBColor(hex: 0x000000)) - 21) < 0.001)
        // topicText on the light canvas is documented as 12.3:1.
        #expect(abs(Tokens.topicText.light.contrast(with: Tokens.canvasBackground.light) - 12.3) < 0.05)
    }

    @Test func canvasTextIsReadable() {
        for variant in ColorVariant.allCases {
            let canvas = Tokens.canvasBackground[variant]
            expectContrast(Tokens.topicText[variant], on: canvas, atLeast: Minimum.text, "topicText / canvas", variant)
            expectContrast(Tokens.topicTextSecondary[variant], on: canvas, atLeast: Minimum.text, "topicTextSecondary / canvas", variant)
            expectContrast(Tokens.centralText[variant], on: Tokens.centralFill[variant], atLeast: Minimum.text, "centralText / centralFill", variant)
            expectContrast(Tokens.topicText[variant], on: Tokens.searchMatchFill[variant], atLeast: Minimum.text, "topicText / searchMatchFill", variant)
        }
    }

    @Test func canvasGraphicsAreVisible() {
        for variant in ColorVariant.allCases {
            let canvas = Tokens.canvasBackground[variant]
            expectContrast(Tokens.centralFill[variant], on: canvas, atLeast: Minimum.graphic, "centralFill / canvas", variant)
            expectContrast(Tokens.accent[variant], on: canvas, atLeast: Minimum.graphic, "selectionRing / canvas", variant)
            expectContrast(Tokens.crossLink[variant], on: canvas, atLeast: Minimum.graphic, "crossLink / canvas", variant)
            expectContrast(Tokens.aiSolid[variant], on: canvas, atLeast: Minimum.graphic, "AI solid / canvas", variant)
            let gradient = variant.isDark ? Tokens.aiGradientDark : Tokens.aiGradientLight
            for stop in gradient {
                expectContrast(stop, on: canvas, atLeast: Minimum.graphic, "AI gradient / canvas", variant)
            }
        }
    }

    /// The search-match border reaches 3:1 only with Increase Contrast; in
    /// standard contrast the match is carried by the fill and the border
    /// together (see the task note of MM-0k).
    @Test func searchMatchBorderIsVisibleWithIncreaseContrast() {
        for variant in [ColorVariant.lightHighContrast, .darkHighContrast] {
            expectContrast(Tokens.searchMatchBorder[variant], on: Tokens.canvasBackground[variant], atLeast: Minimum.graphic, "searchMatchBorder / canvas", variant)
        }
    }

    @Test func chromeColoursAreReadable() {
        for variant in ColorVariant.allCases {
            let background = systemBackground(variant)
            expectContrast(Tokens.warningText[variant], on: Tokens.warningFill[variant], atLeast: Minimum.text, "warningText / warningFill", variant)
            expectContrast(Tokens.danger[variant], on: background, atLeast: Minimum.text, "danger / system background", variant)
            expectContrast(Tokens.success[variant], on: background, atLeast: Minimum.text, "success / system background", variant)
            expectContrast(Tokens.favorite[variant], on: background, atLeast: Minimum.graphic, "favorite / system background", variant)
        }
    }

    @Test func everyBranchIsReadableAndVisible() {
        let theme = MapTheme.standard
        for variant in ColorVariant.allCases {
            let canvas = Tokens.canvasBackground[variant]
            for index in theme.branches.colors.indices {
                let colors = theme.branch(index, in: variant)
                let pair = "branch \(index)"
                expectContrast(colors.line, on: canvas, atLeast: Minimum.graphic, "\(pair) line / canvas", variant)
                expectContrast(Tokens.topicText[variant], on: colors.mainFill, atLeast: Minimum.text, "topicText / \(pair) mainFill", variant)
                expectContrast(Tokens.topicText[variant], on: colors.subFill, atLeast: Minimum.text, "topicText / \(pair) subFill", variant)
                // The note symbol after a title is a graphic in the secondary colour.
                expectContrast(Tokens.topicTextSecondary[variant], on: colors.mainFill, atLeast: Minimum.graphic, "topicTextSecondary / \(pair) mainFill", variant)
                expectContrast(Tokens.topicTextSecondary[variant], on: colors.subFill, atLeast: Minimum.graphic, "topicTextSecondary / \(pair) subFill", variant)
                expectContrast(colors.badgeText, on: colors.badgeFill, atLeast: Minimum.text, "badgeText / \(pair) badgeFill", variant)
            }
        }
    }

    @Test func hoverKeepsTopicTextReadable() {
        for variant in ColorVariant.allCases {
            let (scheme, contrast) = variant.environment
            for level in 0...3 {
                let style = TopicStyle.resolve(level: level, branch: 2, theme: .standard, colorScheme: scheme, contrast: contrast)
                expectContrast(style.textColor, on: style.hoverFill, atLeast: Minimum.text, "text / hover fill, level \(level)", variant)
            }
        }
    }
}

#if os(macOS)
@Suite("Design system: asset catalog")
struct DesignSystemAssetTests {
    /// The colour sets are what views draw with; the tokens are what the tests
    /// and the derived fills compute with. They must not drift apart.
    @Test func everyColorSetMatchesItsToken() throws {
        let appearances: [(NSAppearance.Name, ColorVariant)] = [
            (.aqua, .light),
            (.darkAqua, .dark),
            (.accessibilityHighContrastAqua, .lightHighContrast),
            (.accessibilityHighContrastDarkAqua, .darkHighContrast),
        ]
        let tolerance = 0.5 / 255
        for (name, token) in Tokens.colorSets.sorted(by: { $0.key < $1.key }) {
            let color = try #require(NSColor(named: name, bundle: .main), "missing colour set \(name)")
            for (appearanceName, variant) in appearances {
                let appearance = try #require(NSAppearance(named: appearanceName))
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance {
                    resolved = color.usingColorSpace(.sRGB)
                }
                let actual = try #require(resolved)
                let expected = token[variant]
                #expect(abs(Double(actual.redComponent) - expected.red) < tolerance, "\(name) \(variant) red")
                #expect(abs(Double(actual.greenComponent) - expected.green) < tolerance, "\(name) \(variant) green")
                #expect(abs(Double(actual.blueComponent) - expected.blue) < tolerance, "\(name) \(variant) blue")
            }
        }
    }
}
#endif

@Suite("Design system: topic style")
struct TopicStyleTests {
    private func style(level: Int, branch: Int = 0, _ variant: ColorVariant = .light) -> TopicStyle {
        let (scheme, contrast) = variant.environment
        return TopicStyle.resolve(level: level, branch: branch, theme: .standard, colorScheme: scheme, contrast: contrast)
    }

    @Test func centralTopicIsAFilledNavyCard() {
        let central = style(level: 0, branch: 3)
        #expect(central.kind == .central)
        #expect(central.fill == Tokens.centralFill.light)
        #expect(central.textColor == Tokens.centralText.light)
        #expect(central.stroke == nil)
        #expect(central.edgeWidth == 0)
        #expect(central.text == Typography.Content.central)
        #expect(central.box == CanvasMetrics.central)
    }

    @Test func mainTopicIsATintedCardWithABranchStroke() {
        let blue = BranchPalette.standard.colors[0]
        let main = style(level: 1)
        #expect(main.kind == .main)
        #expect(main.fill == blue.light.composited(over: Tokens.canvasBackground.light, opacity: 0.12))
        #expect(main.stroke == blue.light)
        #expect(main.strokeWidth == CanvasMetrics.mainStrokeWidth)
        #expect(main.edgeColor == blue.light)
        #expect(main.edgeWidth == 3)
        #expect(main.textColor == Tokens.topicText.light)
        #expect(main.text == Typography.Content.main)
        #expect(main.box == CanvasMetrics.main)
    }

    @Test func subtopicsAreLightlyTintedWithoutStroke() {
        let blue = BranchPalette.standard.colors[0]
        let sub = style(level: 2)
        #expect(sub.kind == .sub)
        #expect(sub.fill == blue.light.composited(over: Tokens.canvasBackground.light, opacity: 0.07))
        #expect(sub.stroke == nil)
        #expect(sub.edgeWidth == 2)
        #expect(sub.text == Typography.Content.sub)

        let deep = style(level: 3)
        #expect(deep.text == Typography.Content.deep)
        #expect(deep.edgeWidth == 1.5)
        #expect(deep.box == CanvasMetrics.sub)
        #expect(style(level: 9) == deep)
    }

    @Test func branchesTakeTheNextColourAndCycle() {
        let fills = (0..<6).map { style(level: 1, branch: $0).fill }
        #expect(Set(fills).count == 6)
        #expect(style(level: 1, branch: 6) == style(level: 1, branch: 0))
        #expect(style(level: 2, branch: 13) == style(level: 2, branch: 1))
    }

    @Test func darkModeUsesDarkLinesAndDenserFills() {
        let blue = BranchPalette.standard.colors[0]
        let main = style(level: 1, .dark)
        #expect(main.stroke == blue.dark)
        #expect(main.fill == blue.dark.composited(over: Tokens.canvasBackground.dark, opacity: 0.20))
        #expect(style(level: 0, .dark).fill == Tokens.centralFill.dark)
    }

    @Test func increaseContrastThickensStrokesAndRing() {
        let blue = BranchPalette.standard.colors[0]
        let main = style(level: 1, .lightHighContrast)
        #expect(main.stroke == blue.lightHighContrast)
        #expect(main.strokeWidth == CanvasMetrics.mainStrokeWidthHighContrast)
        #expect(main.selectionRingWidth == CanvasMetrics.selectionRingWidthHighContrast)
        #expect(main.fill == blue.lightHighContrast.composited(over: Tokens.canvasBackground.lightHighContrast, opacity: 0.18))
        #expect(style(level: 1).selectionRingWidth == CanvasMetrics.selectionRingWidth)
        #expect(style(level: 2, .darkHighContrast).fill
            == blue.darkHighContrast.composited(over: Tokens.canvasBackground.darkHighContrast, opacity: 0.20))
    }

    @Test func storedThemeMapsToTheStandardPalette() {
        #expect(MapTheme(MindMapTheme.standard) == .standard)
        #expect(MapTheme.standard.branches.colors.count == 6)
    }

    @Test func variantFollowsSchemeAndContrast() {
        #expect(ColorVariant(colorScheme: .light, contrast: .standard) == .light)
        #expect(ColorVariant(colorScheme: .dark, contrast: .standard) == .dark)
        #expect(ColorVariant(colorScheme: .light, contrast: .increased) == .lightHighContrast)
        #expect(ColorVariant(colorScheme: .dark, contrast: .increased) == .darkHighContrast)
    }
}

@Suite("Design system: motion")
struct MotionTests {
    @Test func reduceMotionRemovesMovement() {
        #expect(Motion.standard(reduceMotion: true) == nil)
        #expect(Motion.relayout(reduceMotion: true) == nil)
        #expect(Motion.camera(reduceMotion: true) == nil)
        #expect(Motion.topicDeleted(reduceMotion: true) == nil)
        #expect(Motion.suggestionArrival(index: 3, reduceMotion: true) == nil)
        #expect(Motion.topicAddedScale(reduceMotion: true) == 1)
        #expect(Motion.standard(reduceMotion: false) != nil)
    }
}

@Suite("Design system: fonts")
struct BrandFontTests {
    @Test func brandFontsShipAndLoadByPostScriptName() {
        withKnownIssue("Font files are not in the bundle yet: the MM-0k session could not download them from google/fonts") {
            #expect(Bundle.main.url(forResource: "OFL", withExtension: "txt") != nil, "OFL.txt")
            for font in BrandFont.allCases {
                #expect(font.url != nil, "\(font.rawValue).ttf in the bundle")
                #expect(BrandFont.registered.contains(font), "\(font.rawValue) registered")
                #expect(font.isInstalled, "\(font.rawValue) resolves by PostScript name")
            }
        }
    }

    @Test func registeringTwiceIsHarmless() {
        BrandFont.registerAll()
        BrandFont.registerAll()
        #expect(BrandFont.registered.isSubset(of: Set(BrandFont.allCases)))
    }
}

private extension ColorVariant {
    var environment: (ColorScheme, ColorSchemeContrast) {
        switch self {
        case .light: (.light, .standard)
        case .dark: (.dark, .standard)
        case .lightHighContrast: (.light, .increased)
        case .darkHighContrast: (.dark, .increased)
        }
    }
}
