import XCTest

/// The sidebar and the list of maps.
@MainActor
struct LibraryPage {
    let app: XCUIApplication

    var list: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Library.list] }

    /// Every row in the current section. A row's text starts with the map
    /// title: in its label on iOS, in its value on macOS, where the combined
    /// row is a static text.
    var maps: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: AccessibilityID.Library.map) }

    func map(titled title: String) -> XCUIElement {
        maps.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", title, title)).firstMatch
    }

    /// The toolbar button, or the one in the empty state; both make a map.
    var newMapButton: XCUIElement { app.buttons[AccessibilityID.Library.newMap].firstMatch }

    /// Brings the list on screen. On iPhone the split view is a stack that
    /// starts at the sidebar, so this opens All Maps first.
    @discardableResult
    func show(file: StaticString = #filePath, line: UInt = #line) -> LibraryPage {
        if !list.waitForExistence(timeout: MindMapApp.timeout / 3) {
            let sidebar = app.descendants(matching: .any)[AccessibilityID.Sidebar.list]
            sidebar.waitToExist(file: file, line: line)
            sidebar.cells.firstMatch.tap()
        }
        list.waitToExist(file: file, line: line)
        return self
    }

    func createMap(file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        newMapButton.waitToExist(file: file, line: line).tap()
        return EditorPage(app: app).waitUntilOpen(file: file, line: line)
    }

    func open(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        map(titled: title).waitToExist(file: file, line: line).tap()
        return EditorPage(app: app).waitUntilOpen(file: file, line: line)
    }
}
