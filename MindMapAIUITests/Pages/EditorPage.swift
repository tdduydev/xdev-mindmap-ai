import XCTest

/// An open map, as a canvas or an outline, with the editor toolbar.
@MainActor
struct EditorPage {
    enum Presentation: Int {
        // The segment order of the View As picker.
        case canvas = 0
        case outline = 1
    }

    let app: XCUIApplication

    var presentationPicker: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Editor.presentation].firstMatch }
    var undoButton: XCUIElement { app.buttons[AccessibilityID.Editor.undo].firstMatch }
    var redoButton: XCUIElement { app.buttons[AccessibilityID.Editor.redo].firstMatch }
    var addChildButton: XCUIElement { app.buttons[AccessibilityID.Editor.addChild].firstMatch }
    /// On a narrow iPhone the editing buttons sit in the toolbar's overflow menu: use `tap(_:)`.
    var addSiblingButton: XCUIElement { app.buttons[AccessibilityID.Editor.addSibling].firstMatch }
    var deleteButton: XCUIElement { app.buttons[AccessibilityID.Editor.delete].firstMatch }
    var findButton: XCUIElement { app.buttons[AccessibilityID.Editor.find].firstMatch }

    var findField: XCUIElement { app.textFields[AccessibilityID.Find.field].firstMatch }
    /// "No Results", "1 of 2" or "2 matches"; only there while the field holds text.
    var findStatus: XCUIElement { app.staticTexts[AccessibilityID.Find.status].firstMatch }
    var findNextButton: XCUIElement { app.buttons[AccessibilityID.Find.next].firstMatch }
    var findPreviousButton: XCUIElement { app.buttons[AccessibilityID.Find.previous].firstMatch }
    var findDoneButton: XCUIElement { app.buttons[AccessibilityID.Find.done].firstMatch }

    var canvas: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Canvas.canvas].firstMatch }
    /// Topics drawn on the canvas, in view. A topic's label is its title.
    var canvasTopics: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: AccessibilityID.Canvas.topic) }

    var outline: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Outline.list].firstMatch }
    /// One text field per visible outline row; its value is the topic title.
    var outlineTopics: XCUIElementQuery { app.textFields.matching(identifier: AccessibilityID.Outline.topic) }

    func outlineTopic(titled title: String) -> XCUIElement {
        outlineTopics.matching(NSPredicate(format: "value == %@", title)).firstMatch
    }

    /// The disclosure buttons of rows that have children, top to bottom. Leaf
    /// rows keep an invisible, disabled one, which this leaves out.
    var outlineDisclosures: XCUIElementQuery {
        app.buttons.matching(identifier: AccessibilityID.Outline.disclosure).matching(NSPredicate(format: "isEnabled == true"))
    }

    /// Selects a topic in the outline by focusing its title field.
    @discardableResult
    func selectOutlineTopic(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let field = outlineTopic(titled: title).waitToExist(file: file, line: line)
        field.tapOrClick()
        return field
    }

    /// Replaces a topic's title in the outline and commits it with Return.
    func renameOutlineTopic(_ title: String, to newTitle: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = selectOutlineTopic(title, file: file, line: line)
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(newTitle + "\r")
        #else
        let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count + 2)
        field.typeText(delete + newTitle + "\n")
        #endif
    }

    /// Editor toolbar buttons a test taps, with the symbol each shows.
    enum ToolbarAction {
        case find, addChild, addSibling, delete, inspector, voice, export

        var identifier: String {
            switch self {
            case .find: AccessibilityID.Editor.find
            case .addChild: AccessibilityID.Editor.addChild
            case .addSibling: AccessibilityID.Editor.addSibling
            case .delete: AccessibilityID.Editor.delete
            case .inspector: AccessibilityID.Editor.inspector
            case .voice: AccessibilityID.Editor.voice
            case .export: AccessibilityID.Editor.export
            }
        }

        /// The SF Symbol in MapEditorView; it is the same in every language.
        var symbol: String {
            switch self {
            case .find: "magnifyingglass"
            case .addChild: "arrow.turn.down.right"
            case .addSibling: "plus"
            case .delete: "trash"
            case .inspector: "sidebar.trailing"
            case .voice: "mic"
            case .export: "square.and.arrow.up"
            }
        }
    }

    /// Taps a toolbar button. On a narrow iPhone the toolbar moves what does
    /// not fit into its More menu, whose items lose their identifiers, so
    /// there the item is found by its symbol.
    func tap(_ action: ToolbarAction, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[action.identifier].firstMatch
        #if os(iOS)
        if !button.waitForExistence(timeout: MindMapApp.timeout / 6) {
            // UIKit's identifier for the navigation bar's More button; with the
            // keyboard up its shortcuts bar has one too, before the toolbar's.
            let overflow = app.buttons.matching(identifier: "OverflowBarButtonItem")
            overflow.element(boundBy: max(overflow.count - 1, 0)).waitToExist(file: file, line: line).tapOrClick()
            app.collectionViews.buttons.containing(.image, identifier: action.symbol).firstMatch
                .waitToExist(file: file, line: line).tapOrClick()
            return
        }
        #endif
        button.waitToExist(file: file, line: line).tapOrClick()
    }

    /// Opens the find bar from the toolbar and types `text` into its field.
    @discardableResult
    func find(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        tap(.find, file: file, line: line)
        let field = findField.waitToExist(file: file, line: line)
        field.tapOrClick()
        field.typeText(text)
        return self
    }

    /// Waits until the find status reads `text`.
    func waitForFindStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let status = findStatus.waitToExist(file: file, line: line)
        // A static text keeps its text in the label on iOS and in the value on macOS.
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ OR value == %@", text, text), object: status)
        let result = XCTWaiter().wait(for: [matches], timeout: MindMapApp.timeout)
        XCTAssertEqual(result, .completed, "find status is \"\(status.shownText)\", expected \"\(text)\"", file: file, line: line)
    }

    @discardableResult
    func waitUntilOpen(file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        presentationPicker.waitToExist(file: file, line: line)
        return self
    }

    /// Picks a segment by position, so it works in every language.
    @discardableResult
    func show(_ presentation: Presentation, file: StaticString = #filePath, line: UInt = #line) -> EditorPage {
        let picker = presentationPicker.waitToExist(file: file, line: line)
        #if os(macOS)
        let segments = picker.radioButtons
        #else
        let segments = picker.buttons
        #endif
        let segment = segments.element(boundBy: presentation.rawValue).waitToExist(file: file, line: line)
        let content = presentation == .canvas ? canvas : outline
        segment.tapOrClick()
        // A tap that lands while a busy machine is still settling the editor is
        // sometimes dropped (seen on the first test of a cold simulator); more
        // are harmless, since the segment only selects.
        for _ in 0..<2 where !content.waitForExistence(timeout: MindMapApp.timeout / 3) {
            #if os(iOS)
            // On iOS 27 the glass segment can highlight on a tap yet keep its
            // selection (MM-87, iPhone App Store capture); a short press selects.
            segment.press(forDuration: 0.2)
            #else
            segment.tapOrClick()
            #endif
        }
        content.waitToExist(file: file, line: line)
        return self
    }
}
