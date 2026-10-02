import XCTest

#if os(macOS)
/// The Mac menu bar and its shortcuts (FR-KBD, AGENTS.md): every editor
/// action is a menu item with a shortcut, disabled rather than hidden when it
/// does not apply. Shortcuts as approved in MM-12.
///
/// Menu items are found by their English titles on purpose: SwiftUI gives
/// command items no accessibility identifier, and these tests run in English.
final class MenuShortcutUITests: XCTestCase {
    @MainActor
    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.menuBars.menuItems[title].firstMatch
    }

    @MainActor
    func testTopicCommandsAreDisabledWithoutAMap() {
        let app = MindMapApp.launch(fixture: .sample)
        app.library.show()
        app.app.menuBars.menuBarItems["Topic"].firstMatch.waitToExist().click()
        let addChild = menuItem("Add Child Topic", in: app.app).waitToExist()
        XCTAssertFalse(addChild.isEnabled)
        XCTAssertFalse(menuItem("Delete Topic", in: app.app).isEnabled)
        app.app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testCommandNMakesAMap() {
        let app = MindMapApp.launch(fixture: .sample)
        let library = app.library.show()
        library.maps.waitForCount(2)

        app.app.typeKey("n", modifierFlags: .command)
        app.editor.waitUntilOpen()
        library.maps.waitForCount(3)
    }

    @MainActor
    func testCommandOneAndTwoSwitchPresentation() {
        let app = MindMapApp.launch(fixture: .sample)
        let editor = app.library.show().open(UITestFixture.Title.plan)

        app.app.typeKey("2", modifierFlags: .command)
        editor.outline.waitToExist()
        app.app.typeKey("1", modifierFlags: .command)
        editor.canvas.waitToExist()
    }

    @MainActor
    func testChildShortcutUndoAndRedo() {
        let app = MindMapApp.launch(fixture: .sample)
        let editor = app.library.show().open(UITestFixture.Title.plan).show(.outline)
        editor.outlineTopics.waitForCount(5)
        editor.selectOutlineTopic(UITestFixture.Title.design)
        // Commit the field so the shortcut goes to the editor, not the text.
        app.app.typeKey(.return, modifierFlags: [])

        app.app.typeKey(.return, modifierFlags: [.command, .shift])
        editor.outlineTopics.waitForCount(6)
        // The new topic's title field has focus, and ⌘Z in a field undoes its
        // typing; the canvas holds no field, so undo there and look in the outline.
        app.app.typeKey("1", modifierFlags: .command)
        editor.canvas.waitToExist()
        app.app.typeKey("z", modifierFlags: .command)
        app.app.typeKey("2", modifierFlags: .command)
        editor.outlineTopics.waitForCount(5)
        app.app.typeKey("1", modifierFlags: .command)
        editor.canvas.waitToExist()
        app.app.typeKey("z", modifierFlags: [.command, .shift])
        app.app.typeKey("2", modifierFlags: .command)
        editor.outlineTopics.waitForCount(6)
    }

    @MainActor
    func testFindShortcuts() {
        let app = MindMapApp.launch(fixture: .sample)
        let editor = app.library.show().open(UITestFixture.Title.plan).show(.outline)

        app.app.typeKey("f", modifierFlags: .command)
        editor.findField.waitToExist().typeText("ar")
        editor.waitForFindStatus("1 of 2")
        app.app.typeKey("g", modifierFlags: .command)
        editor.waitForFindStatus("2 of 2")
        app.app.typeKey("g", modifierFlags: [.command, .shift])
        editor.waitForFindStatus("1 of 2")
        app.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.findField.waitForNonExistence(timeout: MindMapApp.timeout))
    }

    @MainActor
    func testCommandCommaOpensSettings() {
        let settings = MindMapApp.launch().openSettings()
        settings.show(.general).appearancePicker.waitToExist()
        settings.close()
        XCTAssertTrue(settings.appearancePicker.waitForNonExistence(timeout: MindMapApp.timeout))
    }

    @MainActor
    func testAppMenuOpensSettings() {
        let app = MindMapApp.launch()
        app.app.menuBars.menuBarItems["MindMap AI"].firstMatch.waitToExist().click()
        menuItem("Settings…", in: app.app).waitToExist().click()
        let settings = SettingsPage(app: app.app)
        settings.window.waitToExist()
        settings.paneButton(.general).waitToExist()
    }

    @MainActor
    func testSidebarButtonOpensSettings() {
        let app = MindMapApp.launch()
        app.app.buttons[AccessibilityID.Sidebar.settings].firstMatch.waitToExist().click()
        let settings = SettingsPage(app: app.app)
        settings.window.waitToExist()
        settings.paneButton(.general).waitToExist()
    }
}
#endif
