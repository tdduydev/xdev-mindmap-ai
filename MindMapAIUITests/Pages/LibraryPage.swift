import XCTest

/// The sidebar and the list of maps.
@MainActor
struct LibraryPage {
    /// The sidebar rows, in `LibrarySection` order.
    enum Section: String {
        case all
        case recent
        case favorites
        case recentlyDeleted
    }

    let app: XCUIApplication

    var list: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Library.list] }
    var sidebar: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Sidebar.list] }

    /// Every row in the current section. A row's text starts with the map
    /// title: in its label on iOS, in its value on macOS, where the combined
    /// row is a static text.
    var maps: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: AccessibilityID.Library.map) }

    func map(titled title: String) -> XCUIElement {
        maps.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", title, title)).firstMatch
    }

    /// The toolbar button, or the one in the empty state; both make a map.
    var newMapButton: XCUIElement { app.buttons[AccessibilityID.Library.newMap].firstMatch }

    /// The `.searchable` field above the list ("Maps and Topics").
    var searchField: XCUIElement { app.searchFields.firstMatch }

    func sectionRow(_ section: Section) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Sidebar.section(section.rawValue)].firstMatch
    }

    /// Brings the list on screen. On iPhone the split view is a stack that
    /// starts at the sidebar, so this opens All Maps first; from an open map
    /// it goes back first.
    @discardableResult
    func show(file: StaticString = #filePath, line: UInt = #line) -> LibraryPage {
        if !list.waitForExistence(timeout: MindMapApp.timeout / 3) {
            #if os(iOS)
            if !sidebar.exists {
                // An open map on iPhone: back to the list, which is below it in the stack.
                app.navigationBars.buttons.element(boundBy: 0).tapOrClick()
            }
            #endif
            if !list.waitForExistence(timeout: MindMapApp.timeout / 3) {
                sidebar.waitToExist(file: file, line: line)
                sidebar.cells.firstMatch.tapOrClick()
            }
        }
        list.waitToExist(file: file, line: line)
        return self
    }

    /// Brings the row of `section` on screen and returns it.
    @discardableResult
    func showSectionRow(_ section: Section, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        #if os(iOS)
        // On iPhone the sidebar is the screen below the list.
        if !sectionRow(section).waitForExistence(timeout: MindMapApp.timeout / 3) {
            app.navigationBars.buttons.element(boundBy: 0).tapOrClick()
        }
        #endif
        return sectionRow(section).waitToExist(file: file, line: line)
    }

    /// Picks a section in the sidebar and waits for its list.
    @discardableResult
    func select(_ section: Section, file: StaticString = #filePath, line: UInt = #line) -> LibraryPage {
        showSectionRow(section, file: file, line: line).tapOrClick()
        list.waitToExist(file: file, line: line)
        return self
    }

    func createMap(file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        newMapButton.waitToExist(file: file, line: line).tapOrClick()
        return EditorPage(app: app).waitUntilOpen(file: file, line: line)
    }

    /// Taps Import…. On iPhone it is in the toolbar's More menu, whose items
    /// lose their identifiers, so there it is found by its symbol.
    func tapImport(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[AccessibilityID.Library.importMap].firstMatch
        #if os(iOS)
        if !button.waitForExistence(timeout: MindMapApp.timeout / 6) {
            let overflow = app.buttons.matching(identifier: "OverflowBarButtonItem")
            overflow.element(boundBy: max(overflow.count - 1, 0)).waitToExist(file: file, line: line).tapOrClick()
            app.collectionViews.buttons.containing(.image, identifier: "square.and.arrow.down").firstMatch
                .waitToExist(file: file, line: line).tapOrClick()
            return
        }
        #endif
        button.waitToExist(file: file, line: line).tapOrClick()
    }

    func open(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        let row = map(titled: title).waitToExist(file: file, line: line)
        let editor = EditorPage(app: app)
        row.tapOrClick()
        #if os(macOS)
        // The first click on a Mac sometimes only brings the window forward,
        // when a system prompt or another app held the focus at launch.
        if !editor.presentationPicker.waitForExistence(timeout: MindMapApp.timeout / 3) {
            row.tapOrClick()
        }
        #endif
        return editor.waitUntilOpen(file: file, line: line)
    }

    /// Moves a map to Recently Deleted: the swipe action on iOS, ⌘⌫ on the Mac.
    func delete(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = map(titled: title).waitToExist(file: file, line: line)
        #if os(iOS)
        row.swipeLeft()
        app.buttons[AccessibilityID.Library.delete].firstMatch.waitToExist(file: file, line: line).tapOrClick()
        #else
        row.click()
        app.typeKey(.delete, modifierFlags: .command)
        #endif
    }

    /// Restores a map shown in Recently Deleted: the leading swipe action on
    /// iOS, the row's context menu on the Mac (menu items have no identifiers,
    /// so the Mac finds it by its English title).
    func restore(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = map(titled: title).waitToExist(file: file, line: line)
        #if os(iOS)
        row.swipeRight()
        app.buttons[AccessibilityID.Library.restore].firstMatch.waitToExist(file: file, line: line).tapOrClick()
        #else
        row.rightClick()
        app.menuItems["Restore"].firstMatch.waitToExist(file: file, line: line).tapOrClick()
        #endif
    }

    /// Asks to delete a map in Recently Deleted for good and returns the
    /// dialog's Delete Permanently button, not yet pressed.
    func askToDeletePermanently(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = map(titled: title).waitToExist(file: file, line: line)
        #if os(iOS)
        row.swipeLeft()
        app.buttons[AccessibilityID.Library.delete].firstMatch.waitToExist(file: file, line: line).tapOrClick()
        #else
        row.click()
        app.typeKey(.delete, modifierFlags: [.command, .option])
        #endif
        return app.buttons[AccessibilityID.Library.confirmPermanentDeletion].firstMatch.waitToExist(file: file, line: line)
    }

    /// Types into the search field; the list then shows the matching maps.
    @discardableResult
    func search(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> LibraryPage {
        let field = searchField.waitToExist(file: file, line: line)
        field.tapOrClick()
        field.typeText(text)
        return self
    }
}
