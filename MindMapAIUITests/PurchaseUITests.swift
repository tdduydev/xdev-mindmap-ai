import StoreKitTest
import XCTest

/// Buying and restoring MindMap AI Pro through StoreKit Testing with
/// `MindMapAITests/MindMapAI.storekit` (NFR-TEST-02, FR-STO-02..04): the
/// paywall's price and list, a purchase that unlocks Pro, Restore
/// Purchases, and core mind mapping without Pro. A cancelled or failed purchase
/// is covered by `ProEntitlementTests`: an error set with `setSimulatedError`
/// here did not reach the app's purchase (docs/testing.md).
///
/// The session runs in the test runner and drives the simulator's StoreKit
/// Testing store, which the app launched by the `MindMapAIUITests` scheme
/// uses. Dialogs are off, so a purchase completes without the system sheet,
/// which on a fresh iOS 27 simulator asks for an Apple Account and stops there.
/// Every test starts and ends with no transactions, so the other suites find
/// Pro locked, as on a new device.
final class PurchaseUITests: XCTestCase {
    private var session: SKTestSession!

    /// The English price in the StoreKit configuration.
    private static let price = "$14.99"

    override func setUp() async throws {
        continueAfterFailure = false
        // Read from the repo: the simulator shares the Mac's file system, and
        // the file stays in one place for the app tests, the scheme and this suite.
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "MindMapAITests/MindMapAI.storekit")
        session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
    }

    // MARK: Paywall

    @MainActor
    func testPaywallShowsPriceAndWhatProIncludes() throws {
        let app = MindMapApp.launch(fixture: .sample)
        let settings = app.openSettings().show(.pro)
        XCTAssertTrue(settings.proStatus.waitToExist().label.hasSuffix(Status.locked), settings.proStatus.label)

        let paywall = app.openPaywallFromSettings()
        XCTAssertTrue(paywall.purchase.label.contains(Self.price), paywall.purchase.label)
        // Every Pro feature is listed before the button; AI tools only on a device that can run them.
        XCTAssertGreaterThanOrEqual(paywall.features.count, ProFeatureCount.withoutAI)
        XCTAssertTrue(paywall.restore.exists)
    }

    // MARK: Free core

    @MainActor
    func testCoreMindMappingNeedsNoPro() {
        let app = MindMapApp.launch(fixture: .sample)
        // Open a map and make a new one: neither asks for Pro.
        app.library.show().open(UITestFixture.Title.plan).canvas.waitToExist()
        XCTAssertFalse(app.paywall.purchase.exists, "opening a map showed the paywall")
        let fresh = MindMapApp.launch(fixture: .empty)
        fresh.library.show().createMap().canvas.waitToExist()
        XCTAssertFalse(fresh.paywall.purchase.exists, "a new map showed the paywall")
    }

    // MARK: Purchase

    @MainActor
    func testPurchaseUnlocksPro() {
        var app = MindMapApp.launch(fixture: .sample)
        let paywall = app.openPaywallFromSettings()

        paywall.purchase.tapOrClick()

        // The thank-you replaces the button while the paywall is still open.
        paywall.unlocked.waitToExist()
        XCTAssertFalse(paywall.purchase.exists)

        // Pro holds across a launch: the app reads it back from StoreKit.
        app = MindMapApp.launch(fixture: .sample)
        let pro = app.openSettings().show(.pro)
        XCTAssertTrue(pro.proStatus.waitToExist().label.hasSuffix(Status.unlocked), pro.proStatus.label)
        XCTAssertFalse(app.app.buttons[AccessibilityID.Settings.showPaywall].exists)
    }

    // MARK: Restore

    @MainActor
    func testRestorePurchasesFindsAnEarlierPurchase() async throws {
        // Bought before, on this device or another one with the same Apple Account.
        _ = try await session.buyProduct(identifier: "asia.xdev.mindmapai.pro")
        let app = MindMapApp.launch(fixture: .sample)
        let pro = app.openSettings().show(.pro)

        pro.restorePurchases.waitToExist().tapOrClick()

        let alert = app.app.alerts.firstMatch.waitToExist()
        XCTAssertEqual(alert.label, "Purchases Restored")
        alert.buttons.firstMatch.tapOrClick()
        XCTAssertTrue(pro.proStatus.label.hasSuffix(Status.unlocked), pro.proStatus.label)
    }

    @MainActor
    func testRestorePurchasesWithNothingBought() {
        let app = MindMapApp.launch(fixture: .sample)
        let pro = app.openSettings().show(.pro)

        pro.restorePurchases.waitToExist().tapOrClick()

        let alert = app.app.alerts.firstMatch.waitToExist()
        XCTAssertEqual(alert.label, "Nothing to Restore")
        alert.buttons.firstMatch.tapOrClick()
        XCTAssertTrue(pro.proStatus.label.hasSuffix(Status.locked), pro.proStatus.label)
    }
}

/// The end of the Pro pane's Status row, read as "Status, Unlocked".
private enum Status {
    static let unlocked = ", Unlocked"
    static let locked = ", Not unlocked"
}

/// `ProFeature` lives in the app: the paywall lists 4 features without AI, 7 with it.
private enum ProFeatureCount {
    static let withoutAI = 4
}

/// The paywall sheet, from Settings or from a Pro feature.
@MainActor
struct PaywallPage {
    let app: XCUIApplication

    var purchase: XCUIElement { app.buttons[AccessibilityID.Paywall.purchase].firstMatch }
    var restore: XCUIElement { app.buttons[AccessibilityID.Paywall.restore].firstMatch }
    var unlocked: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Paywall.unlocked].firstMatch }
    var purchaseStatus: XCUIElement { app.staticTexts[AccessibilityID.Paywall.purchaseStatus].firstMatch }
    var features: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: AccessibilityID.Paywall.feature) }
}

@MainActor
extension SettingsPage {
    var proStatus: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Settings.proStatus].firstMatch }
    var restorePurchases: XCUIElement { app.buttons[AccessibilityID.Settings.restorePurchases].firstMatch }
}

@MainActor
extension MindMapApp {
    var paywall: PaywallPage { PaywallPage(app: app) }

    /// Settings ▸ MindMap AI Pro ▸ See What’s in Pro…, waiting for the price.
    func openPaywallFromSettings(file: StaticString = #filePath, line: UInt = #line) -> PaywallPage {
        openSettings(file: file, line: line).show(.pro, file: file, line: line)
        app.buttons[AccessibilityID.Settings.showPaywall].firstMatch.waitToExist(file: file, line: line).tapOrClick()
        paywall.purchase.waitToExist(file: file, line: line)
        return paywall
    }
}
