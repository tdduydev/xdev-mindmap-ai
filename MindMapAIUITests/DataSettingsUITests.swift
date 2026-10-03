import XCTest

/// Settings ▸ Data and ▸ AI Apps present their dialogs and pickers once and
/// keep Settings open (MM-92): attached to a Section, each row presented its
/// own copy on one binding, which on iOS 27 closed Settings instead (MM-90).
final class DataSettingsUITests: XCTestCase {
    #if os(iOS)
    @MainActor
    func testEmptyRecentlyDeletedAsksFirst() {
        let mindMap = MindMapApp.launch(fixture: .sample)
        let app = mindMap.app
        let row = mindMap.library.show().map(titled: UITestFixture.Title.favorite).waitToExist()
        row.swipeLeft()
        app.buttons[AccessibilityID.Library.delete].firstMatch.waitToExist().tapOrClick()

        mindMap.openSettings().show(.data)
        let empty = app.buttons[AccessibilityID.Settings.emptyRecentlyDeleted].firstMatch.waitToExist()
        waitUntil("Empty Recently Deleted is enabled") { empty.isEnabled }
        empty.tapOrClick()

        // The dialog's button, not the swipe action: the library is behind Settings.
        let confirm = app.buttons["Delete Permanently"].firstMatch
        confirm.waitToExist()
        confirm.tapOrClick()
        waitUntil("Recently Deleted is emptied with Settings still open") { empty.exists && !empty.isEnabled }
    }

    @MainActor
    func testExportAllMapsOpensThePicker() {
        let mindMap = MindMapApp.launch(fixture: .sample)
        let app = mindMap.app
        mindMap.openSettings().show(.data)
        app.buttons[AccessibilityID.Settings.exportAllMaps].firstMatch.waitToExist().tapOrClick()

        // The system's folder picker; Save carries the same identifier in every language.
        let save = app.buttons["DOCPicker.actionButton"].firstMatch
        save.waitToExist()
        XCTAssertEqual(app.buttons.matching(identifier: "DOCPicker.actionButton").count, 1, "more than one picker")
        app.descendants(matching: .any)["Cancel"].firstMatch.waitToExist().tapOrClick()
        waitUntil("the picker closes and Settings stays open") {
            !save.exists && app.buttons[AccessibilityID.Settings.exportAllMaps].exists
        }
    }
    #endif

    #if os(macOS)
    @MainActor
    func testAddAppOpensItsSheet() {
        let mindMap = MindMapApp.launch(arguments: ["-mcp.port", "52481"])
        let app = mindMap.app
        let settings = mindMap.openSettings().show(.aiApps)
        app.buttons[AccessibilityID.Settings.aiAppsAdd].firstMatch.waitToExist().tapOrClick()

        let sheet = settings.window.sheets.firstMatch.waitToExist()
        XCTAssertEqual(app.sheets.count, 1, "Add App opened more than one sheet")
        sheet.buttons["Cancel"].firstMatch.waitToExist().tapOrClick()
        waitUntil("the sheet closes") { !sheet.exists }
    }
    #endif

    @MainActor
    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) {
        let met = NSPredicate { _, _ in condition() }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: met, object: nil)], timeout: MindMapApp.timeout)
        XCTAssertEqual(result, .completed, message, file: file, line: line)
    }
}
