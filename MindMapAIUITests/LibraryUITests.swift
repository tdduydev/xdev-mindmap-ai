import XCTest

/// The library: sections, making a map, and search by title and topic text
/// (FR-LIB, MM-15), in English and Vietnamese.
final class LibraryUITests: XCTestCase {
    @MainActor
    func testNewMapOpensAndJoinsAllMaps() {
        let app = MindMapApp.launch(fixture: .sample)
        let library = app.library.show()
        library.maps.waitForCount(2)

        _ = library.createMap()
        library.show().maps.waitForCount(3)
    }

    @MainActor
    func testFavoritesListsOnlyFavoriteMaps() {
        let library = MindMapApp.launch(fixture: .sample).library.show()
            .select(.favorites)
        library.maps.waitForCount(1)
        library.map(titled: UITestFixture.Title.favorite).waitToExist()
    }

    @MainActor
    func testRecentlyDeletedStartsEmpty() {
        let library = MindMapApp.launch(fixture: .sample).library.show()
            .select(.recentlyDeleted)
        library.maps.waitForCount(0)
    }

    @MainActor
    func testSearchFindsAMapByTopicText() {
        // "Interviews" is a topic of Product Launch, not a map title.
        let library = MindMapApp.launch(fixture: .sample).library.show()
            .search(UITestFixture.Title.interviews.lowercased())
        library.maps.waitForCount(1)
        library.map(titled: UITestFixture.Title.plan).waitToExist()
    }

    @MainActor
    func testSearchIgnoresDiacritics() {
        // NFR-L10N-04: a Vietnamese query with marks matches text without them.
        let library = MindMapApp.launch(fixture: .sample).library.show()
            .search("Rêading")
        library.maps.waitForCount(1)
        library.map(titled: UITestFixture.Title.favorite).waitToExist()
    }

    @MainActor
    func testSearchWithNoMatchShowsNoMaps() {
        let library = MindMapApp.launch(fixture: .sample).library.show()
            .search("zzzz")
        library.maps.waitForCount(0)
    }

    @MainActor
    func testVietnameseSidebarAndSearch() {
        let library = MindMapApp.launch(fixture: .sample, language: .vietnamese).library
        // The sidebar is the first screen on iPhone and beside the list elsewhere.
        let allMaps = library.sectionRow(.all).waitToExist()
        XCTAssertTrue(allMaps.label.hasPrefix("Tất cả sơ đồ"), "sidebar row reads \(allMaps.label)")

        library.select(.favorites).maps.waitForCount(1)
        library.select(.all).maps.waitForCount(2)
        XCTAssertEqual(library.searchField.placeholderValue, "Sơ đồ và chủ đề")
        library.search("reading").maps.waitForCount(1)
    }
}
