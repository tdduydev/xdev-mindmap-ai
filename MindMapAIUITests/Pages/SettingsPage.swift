import XCTest

/// Settings: a window of panes on the Mac (⌘,), a sheet with one page per
/// pane on iPad and iPhone (docs/settings.md).
@MainActor
struct SettingsPage {
    /// `SettingsPane` raw values, in the app's order of panes.
    enum Pane: String, CaseIterable {
        case general
        case export
        case ai
        case data
        case aiApps
        case pro
        case privacy
        case about
    }

    let app: XCUIApplication

    #if os(macOS)
    /// SwiftUI names the Mac's Settings window itself.
    var window: XCUIElement { app.windows["com_apple_SwiftUI_Settings_window"].firstMatch }
    #endif

    func paneButton(_ pane: Pane) -> XCUIElement {
        #if os(macOS)
        // On macOS 27 the identifier set on a Tab never reaches its toolbar
        // button, which has only its title, so panes are found by position;
        // that works in every language. A Mac without Apple Intelligence has no AI pane.
        let buttons = window.toolbars.buttons
        var panes = Pane.allCases
        if buttons.count == panes.count - 1 { panes.removeAll { $0 == .ai } }
        // An index past the last button matches nothing, as a missing pane should.
        return buttons.element(boundBy: panes.firstIndex(of: pane) ?? Pane.allCases.count)
        #else
        app.descendants(matching: .any)[AccessibilityID.Settings.pane(pane.rawValue)].firstMatch
        #endif
    }

    /// A pop-up button on the Mac, a menu button on iOS; its value is the chosen option.
    var appearancePicker: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Settings.appearance].firstMatch
    }

    var doneButton: XCUIElement { app.buttons[AccessibilityID.Settings.done].firstMatch }

    /// Opens Settings the way a person does: ⌘, on the Mac, the sidebar's
    /// Settings button on iPad and iPhone.
    static func open(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> SettingsPage {
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        let button = app.buttons[AccessibilityID.Sidebar.settings].firstMatch
        if !button.waitForExistence(timeout: MindMapApp.timeout / 3) {
            // On iPhone the sidebar sits below the list in the stack.
            app.navigationBars.buttons.element(boundBy: 0).tapOrClick()
        }
        button.waitToExist(file: file, line: line).tapOrClick()
        #endif
        let page = SettingsPage(app: app)
        #if os(macOS)
        page.window.waitToExist(file: file, line: line)
        #endif
        page.paneButton(.general).waitToExist(file: file, line: line)
        return page
    }

    /// Shows a pane: the Mac's tab, or the iOS row that pushes its page.
    @discardableResult
    func show(_ pane: Pane, file: StaticString = #filePath, line: UInt = #line) -> SettingsPage {
        paneButton(pane).waitToExist(file: file, line: line).tapOrClick()
        return self
    }

    /// Picks an appearance by its position in the menu (System, Light, Dark),
    /// so it works in every language.
    func chooseAppearance(at index: Int, file: StaticString = #filePath, line: UInt = #line) {
        appearancePicker.waitToExist(file: file, line: line).tapOrClick()
        #if os(macOS)
        let item = appearancePicker.menuItems.element(boundBy: index)
        #else
        // The open menu is the only collection of buttons outside the form.
        let item = app.collectionViews.buttons.element(boundBy: index)
        #endif
        item.waitToExist(file: file, line: line).tapOrClick()
    }

    /// The text the picker shows for the chosen option.
    var appearanceValue: String {
        #if os(macOS)
        appearancePicker.value as? String ?? ""
        #else
        // A Form picker on iOS is a button labelled "Appearance, Dark".
        (appearancePicker.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appearancePicker.label
        #endif
    }

    func close() {
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        // Done is on the list of panes only; a pane's page goes back to it first.
        if !doneButton.exists {
            app.navigationBars.buttons.element(boundBy: 0).tapOrClick()
        }
        doneButton.waitToExist().tapOrClick()
        #endif
    }
}
