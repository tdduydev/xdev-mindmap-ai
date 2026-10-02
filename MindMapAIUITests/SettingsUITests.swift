import XCTest

/// Settings (docs/settings.md): opened the platform's way, panes, and the
/// Appearance preference kept across a reopen, in English and Vietnamese.
final class SettingsUITests: XCTestCase {
    @MainActor
    func testSettingsOpensWithItsPanes() {
        let settings = MindMapApp.launch().openSettings()
        for pane in [SettingsPage.Pane.general, .export, .pro, .privacy, .about] {
            settings.paneButton(pane).waitToExist()
        }
        settings.show(.general).appearancePicker.waitToExist()
    }

    @MainActor
    func testAppearanceChoiceIsKept() {
        let app = MindMapApp.launch()
        let settings = app.openSettings().show(.general)
        XCTAssertTrue(settings.appearanceValue.contains("System"), settings.appearanceValue)

        settings.chooseAppearance(at: 2)
        settings.close()

        let reopened = app.openSettings().show(.general)
        let value = reopened.appearanceValue
        XCTAssertTrue(value.contains("Dark"), "Appearance reads \(value) after reopening")
    }

    @MainActor
    func testStoredAppearanceIsShown() {
        // Launch arguments go into the test's defaults suite, as a stored choice would.
        let settings = MindMapApp.launch(arguments: ["-appearance", "light"]).openSettings().show(.general)
        XCTAssertTrue(settings.appearanceValue.contains("Light"), settings.appearanceValue)
    }

    @MainActor
    func testVietnameseSettings() {
        let settings = MindMapApp.launch(language: .vietnamese, arguments: ["-appearance", "dark"])
            .openSettings()
        XCTAssertTrue(settings.paneButton(.general).label.contains("Chung"), settings.paneButton(.general).label)
        settings.show(.general)
        XCTAssertTrue(settings.appearanceValue.contains("Tối"), settings.appearanceValue)
    }
}
