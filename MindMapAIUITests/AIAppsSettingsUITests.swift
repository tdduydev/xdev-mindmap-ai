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

    /// The identified element itself must say the current status: VoiceOver
    /// reads it, not a text inside it (MM-89).
    @MainActor
    private func waitForStatus(
        _ text: String,
        of status: XCUIElement,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let shown = NSPredicate { _, _ in status.exists && status.shownText == text }
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
