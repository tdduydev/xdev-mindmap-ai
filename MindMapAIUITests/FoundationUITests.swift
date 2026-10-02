import XCTest

/// Checks that the UI test mode itself works: fixtures load, the store starts
/// empty each launch, identifiers resolve and the language is fixed. Feature
/// suites (MM-23 onwards) build on the same launcher and pages.
final class FoundationUITests: XCTestCase {
    @MainActor
    func testEmptyFixtureStartsWithNoMaps() {
        let library = MindMapApp.launch(fixture: .empty).library.show()
        library.newMapButton.waitToExist()
        XCTAssertEqual(library.maps.count, 0)
    }

    @MainActor
    func testSampleFixtureListsItsMaps() {
        let library = MindMapApp.launch(fixture: .sample).library.show()
        library.maps.waitForCount(2)
        library.map(titled: UITestFixture.Title.plan).waitToExist()
        library.map(titled: UITestFixture.Title.favorite).waitToExist()
    }

    @MainActor
    func testEachLaunchStartsFromTheFixture() {
        let library = MindMapApp.launch(fixture: .empty).library.show()
        _ = library.createMap()

        let relaunched = MindMapApp.launch(fixture: .empty).library.show()
        relaunched.newMapButton.waitToExist()
        XCTAssertEqual(relaunched.maps.count, 0, "a map from the previous launch survived")
    }

    @MainActor
    func testOutlineAddChildUndoRedo() {
        let editor = MindMapApp.launch(fixture: .sample).library.show()
            .open(UITestFixture.Title.plan)
            .show(.outline)
        // Product Launch with Research (holding Interviews), Design and Marketing.
        editor.outlineTopics.waitForCount(5)
        editor.outlineTopic(titled: UITestFixture.Title.design).waitToExist().tap()

        editor.addChildButton.tap()
        editor.outlineTopics.waitForCount(6)
        editor.undoButton.tap()
        editor.outlineTopics.waitForCount(5)
        editor.redoButton.tap()
        editor.outlineTopics.waitForCount(6)
    }

    @MainActor
    func testCanvasShowsTopicsByTitle() {
        let editor = MindMapApp.launch(fixture: .sample).library.show()
            .open(UITestFixture.Title.plan)
            .show(.canvas)
        editor.canvasTopics.matching(NSPredicate(format: "label == %@", UITestFixture.Title.research)).firstMatch.waitToExist()
    }

    @MainActor
    func testLargeFixtureOpens() {
        let editor = MindMapApp.launch(fixture: .large).library.show()
            .open(UITestFixture.Title.large)
            .show(.canvas)
        editor.canvasTopics.firstMatch.waitToExist()
    }

    @MainActor
    func testVietnameseLaunchShowsVietnamese() {
        let app = MindMapApp.launch(fixture: .empty, language: .vietnamese)
        let button = app.library.show().newMapButton.waitToExist()
        XCTAssertEqual(button.label, "Sơ đồ mới")
    }
}
