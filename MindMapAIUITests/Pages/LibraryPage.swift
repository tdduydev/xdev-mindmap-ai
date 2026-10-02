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
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            #endif
            if !list.waitForExistence(timeout: MindMapApp.timeout / 3) {
                sidebar.waitToExist(file: file, line: line)
                sidebar.cells.firstMatch.tap()
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
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        #endif
        return sectionRow(section).waitToExist(file: file, line: line)
    }

    /// Picks a section in the sidebar and waits for its list.
    @discardableResult
    func select(_ section: Section, file: StaticString = #filePath, line: UInt = #line) -> LibraryPage {
        showSectionRow(section, file: file, line: line).tap()
        list.waitToExist(file: file, line: line)
        return self
    }

    func createMap(file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        newMapButton.waitToExist(file: file, line: line).tap()
        return EditorPage(app: app).waitUntilOpen(file: file, line: line)
    }

    func open(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        let row = map(titled: title).waitToExist(file: file, line: line)
        let editor = EditorPage(app: app)
        row.tap()
        #if os(macOS)
        // The first click on a Mac sometimes only brings the window forward,
        // when a system prompt or another app held the focus at launch.
        if !editor.presentationPicker.waitForExistence(timeout: MindMapApp.timeout / 3) {
            row.tap()
        }
        #endif
        return editor.waitUntilOpen(file: file, line: line)
    }

    /// Types into the search field; the list then shows the matching maps.
    @discardableResult
    func search(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> LibraryPage {
        let field = searchField.waitToExist(file: file, line: line)
        field.tap()
        field.typeText(text)
        return self
    }
}
