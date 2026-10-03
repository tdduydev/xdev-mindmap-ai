import XCTest

/// Find in the open map (MM-15): the match count, Next and Previous, Done,
/// diacritic folding, in English and Vietnamese.
final class FindUITests: XCTestCase {
    @MainActor
    private func openPlan(language: MindMapApp.Language = .english) -> EditorPage {
        MindMapApp.launch(fixture: .sample, language: language).library.show()
            .open(UITestFixture.Title.plan)
            .show(.outline)
    }

    @MainActor
    func testFindCountsAndStepsThroughMatches() {
        // "ar" is in Research and Marketing, in that reading order.
        let editor = openPlan().find("ar")
        editor.waitForFindStatus("1 of 2")
        XCTAssertTrue(editor.findNextButton.isEnabled)

        editor.findNextButton.tapOrClick()
        editor.waitForFindStatus("2 of 2")
        editor.findPreviousButton.tapOrClick()
        editor.waitForFindStatus("1 of 2")
    }

    @MainActor
    func testFindWithNoMatch() {
        let editor = openPlan().find("zzzz")
        editor.waitForFindStatus("No Results")
        XCTAssertFalse(editor.findNextButton.isEnabled)
        XCTAssertFalse(editor.findPreviousButton.isEnabled)
    }

    @MainActor
    func testFindIgnoresCaseAndDiacritics() {
        let editor = openPlan().find("DÉSIGN")
        editor.waitForFindStatus("1 of 1")
    }

    @MainActor
    func testDoneClosesTheFindBar() {
        let editor = openPlan().find("Design")
        editor.waitForFindStatus("1 of 1")
        editor.findDoneButton.tapOrClick()
        XCTAssertTrue(editor.findField.waitForNonExistence(timeout: MindMapApp.timeout))
    }

    @MainActor
    func testVietnameseFindStatus() {
        let editor = openPlan(language: .vietnamese).find("zzzz")
        editor.waitForFindStatus("Không có kết quả")
        editor.findField.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue
            + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "ar")
        editor.waitForFindStatus("1 / 2")
    }
}
