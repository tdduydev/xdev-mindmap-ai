import XCTest

/// The app under test, launched in the UI test mode (docs/testing.md): an
/// in-memory store holding `fixture`, throwaway preferences, no animation,
/// and a fixed language, so a run never depends on the machine it runs on.
@MainActor
struct MindMapApp {
    enum Language: String {
        case english = "en"
        case vietnamese = "vi"

        var locale: String {
            switch self {
            case .english: "en_US"
            case .vietnamese: "vi_VN"
            }
        }
    }

    /// How long a query waits for the app before failing. Generous, because a
    /// cold simulator or a busy Mac is slow to show the first window.
    static let timeout: TimeInterval = 15

    let app: XCUIApplication

    /// `arguments` go after the standard ones; pass `-key value` pairs to start
    /// with a preference set, for example `["-appearance", "dark"]`.
    @discardableResult
    static func launch(
        fixture: UITestFixture = .empty,
        language: Language = .english,
        arguments: [String] = []
    ) -> MindMapApp {
        let app = XCUIApplication()
        app.launchArguments = [
            UITestLaunch.flag,
            UITestLaunch.fixture, fixture.rawValue,
            "-AppleLanguages", "(\(language.rawValue))",
            "-AppleLocale", language.locale,
            // The Mac would otherwise reopen the windows of the previous run.
            "-ApplePersistenceIgnoreState", "YES",
        ] + arguments
        app.launch()
        return MindMapApp(app: app)
    }

    var library: LibraryPage { LibraryPage(app: app) }
    var editor: EditorPage { EditorPage(app: app) }
}

@MainActor
extension XCUIElement {
    /// Waits for the element and fails the test, at the caller's line, if it never appears.
    @discardableResult
    func waitToExist(
        timeout: TimeInterval = MindMapApp.timeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) did not appear", file: file, line: line)
        return self
    }
}

@MainActor
extension XCUIElementQuery {
    /// Waits until the query matches `count` elements.
    func waitForCount(
        _ count: Int,
        timeout: TimeInterval = MindMapApp.timeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "expected \(count) elements, found \(self.count)", file: file, line: line)
    }
}
