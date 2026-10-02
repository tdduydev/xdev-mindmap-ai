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
    var addSiblingButton: XCUIElement { app.buttons[AccessibilityID.Editor.addSibling].firstMatch }
    var deleteButton: XCUIElement { app.buttons[AccessibilityID.Editor.delete].firstMatch }

    var canvas: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Canvas.canvas] }
    /// Topics drawn on the canvas, in view. A topic's label is its title.
    var canvasTopics: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: AccessibilityID.Canvas.topic) }

    var outline: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Outline.list] }
    /// One text field per visible outline row; its value is the topic title.
    var outlineTopics: XCUIElementQuery { app.textFields.matching(identifier: AccessibilityID.Outline.topic) }

    func outlineTopic(titled title: String) -> XCUIElement {
        outlineTopics.matching(NSPredicate(format: "value == %@", title)).firstMatch
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
        segments.element(boundBy: presentation.rawValue).waitToExist(file: file, line: line).tap()
        switch presentation {
        case .canvas: canvas.waitToExist(file: file, line: line)
        case .outline: outline.waitToExist(file: file, line: line)
        }
        return self
    }
}
