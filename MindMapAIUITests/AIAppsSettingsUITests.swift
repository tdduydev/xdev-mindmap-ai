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
        app.typeKey(",", modifierFlags: .command)

        app.descendants(matching: .any)[AccessibilityID.Settings.pane("aiApps")].waitToExist().click()
        let toggle = app.checkBoxes[AccessibilityID.Settings.aiAppsSwitch].firstMatch.exists
            ? app.checkBoxes[AccessibilityID.Settings.aiAppsSwitch].firstMatch
            : app.switches[AccessibilityID.Settings.aiAppsSwitch].firstMatch
        toggle.waitToExist()
        XCTAssertEqual(toggle.value as? Int, 0, "AI Apps must be off by default")
        let status = app.staticTexts[AccessibilityID.Settings.aiAppsStatus]
        XCTAssertEqual(status.waitToExist().label, "Off")

        toggle.click()
        XCTAssertTrue(
            app.staticTexts.matching(identifier: AccessibilityID.Settings.aiAppsStatus).matching(NSPredicate(format: "label == 'Ready'")).firstMatch
                .waitForExistence(timeout: MindMapApp.timeout),
            "the port did not open"
        )

        app.descendants(matching: .any)[AccessibilityID.Settings.pane("privacy")].click()
        let privacy = app.descendants(matching: .any)[AccessibilityID.Settings.aiAppsPrivacy].waitToExist()
        XCTAssertTrue(String(describing: privacy.value ?? privacy.label).contains("On"), "Privacy does not say AI Apps is on")

        app.descendants(matching: .any)[AccessibilityID.Settings.pane("aiApps")].click()
        toggle.click()
        XCTAssertEqual(status.waitToExist().label, "Off")
    }
    #else
    @MainActor
    func testNoAIAppsPaneOnIPadAndIPhone() {
        let mindMap = MindMapApp.launch()
        let app = mindMap.app
        let settings = app.buttons[AccessibilityID.Sidebar.settings]
        // On iPhone the library is pushed over the sidebar, which has the button.
        if !settings.waitForExistence(timeout: MindMapApp.timeout / 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        settings.waitToExist().tap()
        app.descendants(matching: .any)[AccessibilityID.Settings.pane("privacy")].waitToExist()
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.Settings.pane("aiApps")].exists)
        app.descendants(matching: .any)[AccessibilityID.Settings.pane("privacy")].tap()
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.Settings.aiAppsPrivacy].waitForExistence(timeout: 2))
    }
    #endif
}
