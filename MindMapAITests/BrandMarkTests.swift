import Foundation
@testable import MindMapAI
import SwiftUI
import Testing

/// The logo shown in the library's empty state, Settings ▸ About and the
/// storage recovery screen. Which screens show it is checked by the UI tests
/// (MM-23); these check the parts the screens are built from.
@Suite("Brand mark")
struct BrandMarkTests {
    #if os(macOS)
    /// The @2x and @3x files sit in the image set; the compiled catalog hides
    /// its scales, so only the size in points can be checked from here.
    @Test func artworkShipsAtTheRegularSize() throws {
        let image = try #require(NSImage(named: "BrandMark"))
        #expect(image.size == CGSize(width: BrandMarkMetrics.regularIcon, height: BrandMarkMetrics.regularIcon))
    }
    #endif

    /// VoiceOver reads the mark once, by name, in every language.
    @Test func readsAsTheProductName() {
        #expect(String(localized: BrandMark.accessibilityName) == "MindMap AI by xDev")
        var vietnamese = BrandMark.accessibilityName
        vietnamese.locale = Locale(identifier: "vi")
        #expect(String(localized: vietnamese) == "MindMap AI by xDev")
    }
}
