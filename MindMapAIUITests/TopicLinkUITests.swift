import XCTest

/// FR-ORG-26: a URL typed into the inspector's Link field becomes the topic's
/// link, and a refused one shows why. Runs on the iOS
/// Simulator; nothing is opened, so no browser starts.
final class TopicLinkUITests: XCTestCase {
    @MainActor
    private func openPlanInspector() -> (EditorPage, XCUIElement) {
        let editor = MindMapApp.launch(fixture: .sample).library.show()
            .open(UITestFixture.Title.plan)
            .show(.outline)
        editor.selectOutlineTopic(UITestFixture.Title.design)
        editor.tap(.inspector)
        let field = editor.app.textFields[AccessibilityID.Link.field].firstMatch.waitToExist()
        return (editor, field)
    }

    @MainActor
    func testAddLinkFromTheInspector() {
        let (editor, field) = openPlanInspector()
        field.tapOrClick()
        field.typeText("example.com/design\n")

        let open = editor.app.buttons[AccessibilityID.Link.open].firstMatch.waitToExist()
        XCTAssertTrue(open.exists)
        XCTAssertEqual(field.value as? String, "https://example.com/design")
    }

    @MainActor
    func testARefusedLinkSaysWhy() {
        let (editor, field) = openPlanInspector()
        field.tapOrClick()
        field.typeText("javascript:alert(1)")

        editor.app.staticTexts[AccessibilityID.Link.error].firstMatch.waitToExist()
        XCTAssertFalse(editor.app.buttons[AccessibilityID.Link.open].firstMatch.exists)
    }
}
