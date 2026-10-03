#if os(iOS)
import XCTest

/// FR-ORG-29: Add Summary from a topic's context menu brackets it and opens
/// the summary topic for typing; Remove Summary on the summary topic takes the
/// bracket and the topic in one step, and Undo brings them back. Runs on the
/// iOS Simulator.
final class TopicSummaryUITests: XCTestCase {
    @MainActor
    func testAddSummaryTypeRemoveAndUndo() {
        let editor = MindMapApp.launch(fixture: .sample).library.show()
            .open(UITestFixture.Title.plan).show(.canvas)
        let design = editor.canvasTopics.matching(NSPredicate(format: "label == %@", UITestFixture.Title.design)).firstMatch
            .waitToExist()

        design.press(forDuration: 1)
        editor.app.buttons["Add Summary"].firstMatch.waitToExist().tap()
        editor.app.typeText("Wrap-up\n")

        let summary = editor.canvasTopics.matching(NSPredicate(format: "label == %@", "Wrap-up")).firstMatch
            .waitToExist()
        XCTAssertTrue((summary.value as? String)?.hasPrefix("Summary of \(UITestFixture.Title.design)") == true)

        summary.press(forDuration: 1)
        editor.app.buttons["Remove Summary"].firstMatch.waitToExist().tap()
        XCTAssertFalse(summary.waitForExistence(timeout: 1))

        editor.undoButton.tapOrClick()
        XCTAssertTrue(summary.waitForExistence(timeout: MindMapApp.timeout))
    }
}
#endif
