import XCTest

/// Add Topics by Voice with the UI test mode's transcriber, which hears
/// `UITestVoice.heard` (MM-20): the topics heard go
/// under the selected topic in one step, and one undo takes them all away.
final class VoiceInputUITests: XCTestCase {
    @MainActor
    func testSpokenTopicsAreAddedAndUndoneInOneStep() {
        // Voice input is a Pro feature.
        let mindMap = MindMapApp.launch(fixture: .sample, arguments: [UITestLaunch.pro])
        let app = mindMap.app
        let editor = mindMap.library.show().open(UITestFixture.Title.plan).show(.outline)
        editor.selectOutlineTopic(UITestFixture.Title.marketing)
        let topicCount = editor.outlineTopics.count
        editor.tap(.voice)

        // The sheet lists what it heard as editable fields before anything is added.
        let listen = app.buttons[AccessibilityID.Voice.listen].firstMatch
        let heard = app.textFields.matching(NSPredicate(format: "value == %@", UITestVoice.topics[0])).firstMatch
        if !heard.waitForExistence(timeout: MindMapApp.timeout / 3), listen.exists { listen.tapOrClick() }
        heard.waitToExist()
        app.buttons[AccessibilityID.Voice.addTopics].firstMatch.waitToExist().tapOrClick()

        for topic in UITestVoice.topics { editor.outlineTopic(titled: topic).waitToExist() }
        editor.outlineTopics.waitForCount(topicCount + UITestVoice.topics.count)

        editor.undoButton.waitToExist().tapOrClick()
        for topic in UITestVoice.topics { XCTAssertTrue(editor.outlineTopic(titled: topic).waitForNonExistence(timeout: MindMapApp.timeout), "\(topic) is still there") }
        editor.outlineTopics.waitForCount(topicCount)

        editor.redoButton.waitToExist().tapOrClick()
        for topic in UITestVoice.topics { editor.outlineTopic(titled: topic).waitToExist() }
    }
}
