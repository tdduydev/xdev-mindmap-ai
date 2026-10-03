#if os(iOS)
import XCTest

/// FR-ORG-30: Add Callout from a topic's context menu opens the bubble for
/// typing on the canvas; Return commits it as one step, and the menu then
/// offers Edit and Remove. Runs on the iOS Simulator.
final class TopicCalloutUITests: XCTestCase {
    @MainActor
    func testAddCalloutInPlaceRemoveAndUndo() {
        let editor = MindMapApp.launch(fixture: .sample).library.show()
            .open(UITestFixture.Title.plan).show(.canvas)
        let topic = editor.canvasTopics.matching(NSPredicate(format: "label == %@", UITestFixture.Title.plan)).firstMatch
            .waitToExist()

        topic.press(forDuration: 1)
        editor.app.buttons["Add Callout"].firstMatch.waitToExist().tap()
        // A vertical TextField is a text view or a text field depending on the OS.
        let field = editor.app.descendants(matching: .any)[AccessibilityID.Canvas.calloutField].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: MindMapApp.timeout))
        editor.app.typeText("Check with finance\n")
        XCTAssertFalse(editor.app.descendants(matching: .any)[AccessibilityID.Canvas.calloutField].firstMatch
            .waitForExistence(timeout: 1))

        topic.press(forDuration: 1)
        editor.app.buttons["Remove Callout"].firstMatch.waitToExist().tap()
        topic.press(forDuration: 1)
        XCTAssertTrue(editor.app.buttons["Add Callout"].firstMatch.waitForExistence(timeout: MindMapApp.timeout))
        // Dismiss the menu before undoing.
        editor.canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()

        editor.undoButton.tapOrClick()
        topic.press(forDuration: 1)
        XCTAssertTrue(editor.app.buttons["Edit Callout"].firstMatch.waitForExistence(timeout: MindMapApp.timeout))
    }
}
#endif
