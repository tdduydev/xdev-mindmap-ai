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
        XCTAssertTrue(settings.proStatus.waitToExist().shownText.hasSuffix(Status.locked), settings.proStatus.shownText)

        // Already on the Pro pane: on iPhone the sidebar's Settings button is behind it.
        settings.showPaywall.waitToExist().tapOrClick()
        let paywall = app.paywall
        paywall.close.waitToExist()
        // Every Pro feature is listed before the button; AI tools only on a device that can run them.
        // Counted before scrolling, while the first rows are still on screen.
        XCTAssertGreaterThanOrEqual(paywall.features.count, ProFeatureCount.withoutAI)
        XCTAssertTrue(paywall.reveal(paywall.purchase), "no purchase button")
        XCTAssertTrue(paywall.purchase.label.contains(Self.price), paywall.purchase.label)
        XCTAssertTrue(paywall.reveal(paywall.restore), "no Restore Purchases on the paywall")
    }

    // MARK: Free core

    @MainActor
    func testOpeningAMapNeedsNoPro() {
        let app = MindMapApp.launch(fixture: .sample)
        app.library.show().open(UITestFixture.Title.plan).canvas.waitToExist()
        XCTAssertFalse(app.paywall.purchase.exists, "opening a map showed the paywall")
    }

    @MainActor
    func testCreatingAMapNeedsNoPro() {
        let app = MindMapApp.launch(fixture: .empty)
        app.library.show().createMap().canvas.waitToExist()
        XCTAssertFalse(app.paywall.purchase.exists, "a new map showed the paywall")
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
        XCTAssertTrue(pro.proStatus.waitToExist().shownText.hasSuffix(Status.unlocked), pro.proStatus.shownText)
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

        let alert = app.alert.waitToExist()
        XCTAssertEqual(alert.title, "Purchases Restored")
        alert.element.buttons.firstMatch.tapOrClick()
        XCTAssertTrue(pro.proStatus.shownText.hasSuffix(Status.unlocked), pro.proStatus.shownText)
    }

    @MainActor
    func testRestorePurchasesWithNothingBought() {
        let app = MindMapApp.launch(fixture: .sample)
        let pro = app.openSettings().show(.pro)

        pro.restorePurchases.waitToExist().tapOrClick()

        let alert = app.alert.waitToExist()
        XCTAssertEqual(alert.title, "Nothing to Restore")
        alert.element.buttons.firstMatch.tapOrClick()
        XCTAssertTrue(pro.proStatus.shownText.hasSuffix(Status.locked), pro.proStatus.shownText)
    }
}

/// The end of the Pro pane's Status row: iOS reads the row as "Status, Unlocked",
/// the Mac reads the status text alone, "Unlocked". Case keeps the two apart.
private enum Status {
    static let unlocked = "Unlocked"
    static let locked = "Not unlocked"
}

/// An alert the app shows. iOS presents it as an alert labelled with its title;
/// on the Mac SwiftUI attaches it to the window as a sheet labelled "alert",
/// whose first text is the title.
@MainActor
struct AlertPage {
    let element: XCUIElement

    var title: String {
        #if os(macOS)
        element.staticTexts.firstMatch.shownText
        #else
        element.label
        #endif
    }

    @discardableResult
    func waitToExist(file: StaticString = #filePath, line: UInt = #line) -> AlertPage {
        element.waitToExist(file: file, line: line)
        return self
    }
}

/// `ProFeature` lives in the app: the paywall lists 5 features without AI, 9 with it.
private enum ProFeatureCount {
    static let withoutAI = 5
}

/// The paywall sheet, from Settings or from a Pro feature.
@MainActor
struct PaywallPage {
    let app: XCUIApplication

    var purchase: XCUIElement { app.buttons[AccessibilityID.Paywall.purchase].firstMatch }
    var close: XCUIElement { app.buttons[AccessibilityID.Paywall.close].firstMatch }
    var restore: XCUIElement { app.buttons[AccessibilityID.Paywall.restore].firstMatch }
    var unlocked: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Paywall.unlocked].firstMatch }
    var purchaseStatus: XCUIElement { app.staticTexts[AccessibilityID.Paywall.purchaseStatus].firstMatch }
    var features: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: AccessibilityID.Paywall.feature) }

    /// Scrolls the paywall until `element` appears. The form is a lazy list, so
    /// on an iPhone a row below the fold (the purchase button, under the Pro
    /// list) does not exist until scrolled to; the price may also still be loading.
    @discardableResult
    func reveal(_ element: XCUIElement) -> Bool {
        for _ in 0..<Self.scrollAttempts {
            if element.waitForExistence(timeout: MindMapApp.timeout / 6) { return true }
            #if os(iOS)
            app.swipeUp()
            #endif
        }
        return element.waitForExistence(timeout: MindMapApp.timeout)
    }

    private static let scrollAttempts = 4
}

@MainActor
extension SettingsPage {
    var proStatus: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Settings.proStatus].firstMatch }
    var restorePurchases: XCUIElement { app.buttons[AccessibilityID.Settings.restorePurchases].firstMatch }
    var showPaywall: XCUIElement { app.buttons[AccessibilityID.Settings.showPaywall].firstMatch }
}

@MainActor
extension MindMapApp {
    var paywall: PaywallPage { PaywallPage(app: app) }

    var alert: AlertPage {
        #if os(macOS)
        AlertPage(element: app.sheets.firstMatch)
        #else
        AlertPage(element: app.alerts.firstMatch)
        #endif
    }

    /// Settings ▸ MindMap AI Pro ▸ See What’s in Pro…, waiting for the price.
    func openPaywallFromSettings(file: StaticString = #filePath, line: UInt = #line) -> PaywallPage {
        openPaywall(from: openSettings(file: file, line: line).show(.pro, file: file, line: line), file: file, line: line)
    }

    /// See What’s in Pro… on a Settings page already showing the Pro pane.
    func openPaywall(from settings: SettingsPage, file: StaticString = #filePath, line: UInt = #line) -> PaywallPage {
        settings.showPaywall.waitToExist(file: file, line: line).tapOrClick()
        paywall.close.waitToExist(file: file, line: line)
        XCTAssertTrue(paywall.reveal(paywall.purchase), "no purchase button", file: file, line: line)
        return paywall
    }
}
