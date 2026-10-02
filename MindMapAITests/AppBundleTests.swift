import Foundation
@testable import MindMapAI
import SwiftUI
import Testing

/// Facts App Review checks in the built app. Tests run inside the app, so
/// `Bundle.main` is the shipped bundle.
@Suite("App bundle")
struct AppBundleTests {
    @Test func privacyManifestShipsAndDeclaresNoTracking() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let reasons = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])?
            .first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }?["NSPrivacyAccessedAPITypeReasons"] as? [String]
        #expect(reasons == ["CA92.1"])
    }

    @Test func declaresNoNonExemptEncryption() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool == false)
    }

    @Test func identity() {
        #expect(Bundle.main.bundleIdentifier == "asia.xdev.mindmapai")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "MindMap AI")
    }

    @Test func appearanceMapsToColorSchemes() {
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.light.colorScheme == .light)
        #expect(AppearancePreference.dark.colorScheme == .dark)
    }
}
