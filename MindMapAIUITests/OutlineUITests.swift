import XCTest

/// The outline editor: rename, add, delete, collapse, each undone and redone
/// from the toolbar (FR-EDT, FR-UND), in English and Vietnamese.
final class OutlineUITests: XCTestCase {
    /// Product Launch: the central topic, Research (holding Interviews), Design and Marketing.
    private static let planRowCount = 5

    @MainActor
    private func openPlan(language: MindMapApp.Language = .english) -> EditorPage {
        let editor = MindMapApp.launch(fixture: .sample, language: language).library.show()
            .open(UITestFixture.Title.plan)
            .show(.outline)
        editor.outlineTopics.waitForCount(Self.planRowCount)
        return editor
    }

    @MainActor
    func testRenameTopicUndoRedo() {
        let editor = openPlan()
        editor.renameOutlineTopic(UITestFixture.Title.design, to: "Prototype")
        editor.outlineTopic(titled: "Prototype").waitToExist()

        editor.undoButton.tapOrClick()
        editor.outlineTopic(titled: UITestFixture.Title.design).waitToExist()
        editor.redoButton.tapOrClick()
        editor.outlineTopic(titled: "Prototype").waitToExist()
    }

    @MainActor
    func testAddSiblingUndoRedo() {
        let editor = openPlan()
        editor.selectOutlineTopic(UITestFixture.Title.marketing)

        editor.tap(.addSibling)
        editor.outlineTopics.waitForCount(Self.planRowCount + 1)
        editor.undoButton.tapOrClick()
        editor.outlineTopics.waitForCount(Self.planRowCount)
        editor.redoButton.tapOrClick()
        editor.outlineTopics.waitForCount(Self.planRowCount + 1)
    }

    @MainActor
    func testDeleteBranchUndoRedo() {
        let editor = openPlan()
        editor.selectOutlineTopic(UITestFixture.Title.research)

        // Research goes with Interviews below it.
        editor.tap(.delete)
        editor.outlineTopics.waitForCount(Self.planRowCount - 2)
        editor.undoButton.tapOrClick()
        editor.outlineTopics.waitForCount(Self.planRowCount)
        editor.outlineTopic(titled: UITestFixture.Title.interviews).waitToExist()
        editor.redoButton.tapOrClick()
        editor.outlineTopics.waitForCount(Self.planRowCount - 2)
    }

    @MainActor
    func testCollapseHidesChildren() {
        let editor = openPlan()
        // Disclosures show only on rows with children: the central topic, then Research.
        editor.outlineDisclosures.waitForCount(2)
        let research = editor.outlineDisclosures.element(boundBy: 1)

        research.tapOrClick()
        editor.outlineTopics.waitForCount(Self.planRowCount - 1)
        XCTAssertFalse(editor.outlineTopic(titled: UITestFixture.Title.interviews).exists)
        research.tapOrClick()
        editor.outlineTopics.waitForCount(Self.planRowCount)
        editor.outlineTopic(titled: UITestFixture.Title.interviews).waitToExist()
    }

    @MainActor
    func testVietnameseOutlineLabels() {
        let editor = openPlan(language: .vietnamese)
        let root = editor.outlineTopic(titled: UITestFixture.Title.plan).waitToExist()
        XCTAssertEqual(root.label, "Chủ đề trung tâm")
        let design = editor.outlineTopic(titled: UITestFixture.Title.design).waitToExist()
        XCTAssertEqual(design.label, "Chủ đề, cấp 2")
    }
}
