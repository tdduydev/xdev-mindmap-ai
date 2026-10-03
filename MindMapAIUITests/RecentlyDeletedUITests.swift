import XCTest

/// Delete moves a map to Recently Deleted, Restore brings it back, and
/// Delete Permanently asks first (FR-LIB-04, MM-19).
final class RecentlyDeletedUITests: XCTestCase {
    @MainActor
    func testDeleteRestoreThenDeletePermanently() {
        let library = MindMapApp.launch(fixture: .sample).library.show()
        let title = UITestFixture.Title.favorite

        library.delete(title)
        library.maps.waitForCount(1)
        library.select(.recentlyDeleted).maps.waitForCount(1)

        library.restore(title)
        library.maps.waitForCount(0)
        library.select(.all).maps.waitForCount(2)
        library.map(titled: title).waitToExist()

        library.delete(title)
        library.maps.waitForCount(1)
        library.select(.recentlyDeleted).maps.waitForCount(1)
        let confirm = library.askToDeletePermanently(title)
        // Nothing is gone until the dialog is answered.
        XCTAssertTrue(library.map(titled: title).exists, "deleted before the confirmation")
        confirm.tapOrClick()
        library.maps.waitForCount(0)
        library.select(.all).maps.waitForCount(1)
    }
}
