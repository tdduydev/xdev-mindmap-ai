import XCTest

/// Settings ▸ AI Apps (MM-46): off at first, the switch opens the port at once
/// and the Privacy pane follows it; iPad and iPhone have no such pane.
final class AIAppsSettingsUITests: XCTestCase {
    #if os(macOS)
    @MainActor
    func testSwitchStartsOffAndAppliesAtOnce() {
        // A port of its own, so a MindMap AI running on this Mac does not hold it.
        let mindMap = MindMapApp.launch(arguments: ["-mcp.port", "52480"])
        let app = mindMap.app
        let settings = mindMap.openSettings().show(.aiApps)
        let toggle = app.checkBoxes[AccessibilityID.Settings.aiAppsSwitch].firstMatch.exists
            ? app.checkBoxes[AccessibilityID.Settings.aiAppsSwitch].firstMatch
            : app.switches[AccessibilityID.Settings.aiAppsSwitch].firstMatch
        toggle.waitToExist()
        XCTAssertEqual(toggle.value as? Int, 0, "AI Apps must be off by default")
        let status = app.staticTexts[AccessibilityID.Settings.aiAppsStatus].firstMatch
        status.waitToExist()
        waitForStatus("Off", of: status)

        toggle.click()
        waitForStatus("Ready", of: status, "the port did not open")

        settings.show(.privacy)
        let privacy = app.descendants(matching: .any)[AccessibilityID.Settings.aiAppsPrivacy].waitToExist()
        XCTAssertTrue(String(describing: privacy.value ?? privacy.label).contains("On"), "Privacy does not say AI Apps is on")

        settings.show(.aiApps)
        toggle.click()
        waitForStatus("Off", of: status, "the port did not close")
    }

    /// On macOS 27, once the status changes, the element with the identifier
    /// keeps its first value and the new text is a static text inside it, so
    /// the innermost text is what the window shows.
    @MainActor
    private func waitForStatus(
        _ text: String,
        of status: XCUIElement,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let shown = NSPredicate { _, _ in
            let inner = status.staticTexts.firstMatch
            return (inner.exists ? inner.shownText : status.shownText) == text
        }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: MindMapApp.timeout)
        XCTAssertEqual(result, .completed, "status is not \(text). \(message)", file: file, line: line)
    }
    #else
    @MainActor
    func testNoAIAppsPaneOnIPadAndIPhone() {
        let mindMap = MindMapApp.launch()
        let app = mindMap.app
        let settings = app.buttons[AccessibilityID.Sidebar.settings]
        // On iPhone the library is pushed over the sidebar, which has the button.
        if !settings.waitForExistence(timeout: MindMapApp.timeout / 3) {
            app.navigationBars.buttons.firstMatch.tapOrClick()
        }
        settings.waitToExist().tapOrClick()
        app.descendants(matching: .any)[AccessibilityID.Settings.pane("privacy")].waitToExist()
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.Settings.pane("aiApps")].exists)
        app.descendants(matching: .any)[AccessibilityID.Settings.pane("privacy")].tapOrClick()
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.Settings.aiAppsPrivacy].waitForExistence(timeout: 2))
    }
    #endif
}
