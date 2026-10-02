#if os(iOS)
import UIKit
import XCTest

final class TopicImageUITests: XCTestCase {
    @MainActor
    func testPasteImageInspectRemoveAndUndo() {
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        UIPasteboard.general.image = bitmap
        defer { UIPasteboard.general.items = [] }

        let editor = MindMapApp.launch(fixture: .sample).library.show()
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
