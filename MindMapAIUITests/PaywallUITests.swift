import XCTest

/// The paywall from Settings ▸ MindMap AI Pro shows its purchase button with
/// the price from MindMapAITests/MindMapAI.storekit, in English and Vietnamese
/// (FR-STO-04). StoreKit Testing keeps a purchase on the simulator, so a run
/// after one finds Pro unlocked and has nothing to check.
final class PaywallUITests: XCTestCase {
    @MainActor
    func testPurchaseButtonInEnglish() throws {
        try checkPurchaseButton(language: .english)
    }

    @MainActor
    func testPurchaseButtonInVietnamese() throws {
        try checkPurchaseButton(language: .vietnamese)
    }

    @MainActor
    private func checkPurchaseButton(language: MindMapApp.Language) throws {
        let app = MindMapApp.launch(fixture: .sample, language: language)
        app.openSettings().show(.pro)
        let showPaywall = app.app.buttons[AccessibilityID.Settings.showPaywall].firstMatch
        try XCTSkipUnless(showPaywall.waitForExistence(timeout: MindMapApp.timeout / 3), "Pro is already unlocked on this device")
        showPaywall.tapOrClick()

        let purchase = app.app.buttons[AccessibilityID.Paywall.purchase].firstMatch
        let found = purchase.waitForExistence(timeout: MindMapApp.timeout)
        if !found {
            // What the screen showed instead: the price loading, the retry, or no paywall at all.
            let tree = XCTAttachment(string: app.app.debugDescription)
            tree.name = "paywall-\(language.rawValue)"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(found, "No purchase button in \(language.rawValue)")
        if found, language == .vietnamese {
            XCTAssertTrue(purchase.label.contains("Mở khoá Pro"), purchase.label)
        }
    }
}
