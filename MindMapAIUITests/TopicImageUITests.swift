#if os(iOS)
import XCTest

final class TopicImageUITests: XCTestCase {
    @MainActor
    func testPasteImageInspectRemoveAndUndo() {
        let editor = MindMapApp.launch(fixture: .sample,
            arguments: [UITestLaunch.imageClipboard]).library.show()
            .open(UITestFixture.Title.plan).show(.canvas)
        let topic = editor.canvasTopics.matching(NSPredicate(format: "label == %@", UITestFixture.Title.plan)).firstMatch
            .waitToExist()
        topic.press(forDuration: 1)
        editor.app.buttons["Paste"].firstMatch.waitToExist().tap()

        editor.tap(.inspector)
        let remove = editor.app.buttons["Remove Image"].firstMatch.waitToExist()
        XCTAssertTrue(editor.app.buttons["Replace Image…"].firstMatch.exists)
        remove.tap()
        XCTAssertTrue(editor.app.buttons["Add Image…"].firstMatch.waitForExistence(timeout: MindMapApp.timeout))
        editor.undoButton.tapOrClick()
        XCTAssertTrue(editor.app.buttons["Remove Image"].firstMatch.waitForExistence(timeout: MindMapApp.timeout))
    }
}
#endif
