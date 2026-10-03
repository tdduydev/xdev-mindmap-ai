import XCTest
#if os(macOS)
import AppKit
#endif

/// The app under test, launched in the UI test mode (docs/testing.md): an
/// in-memory store holding `fixture`, throwaway preferences, no animation,
/// and a fixed language, so a run never depends on the machine it runs on.
@MainActor
struct MindMapApp {
    enum Language: String {
        case english = "en"
        case vietnamese = "vi"
        case japanese = "ja"

        var locale: String {
            switch self {
            case .english: "en_US"
            case .vietnamese: "vi_VN"
            case .japanese: "ja_JP"
            }
        }
    }

    /// How long a query waits for the app before failing. Generous, because a
    /// cold simulator or a Mac running several builds can take this long.
    static let timeout: TimeInterval = 30

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
        #if os(macOS)
        // Launched by XCUITest on macOS 27 the app often opens no window at
        // all, with or without saved state; File ▸ New Window opens the same one.
        if !app.windows.firstMatch.waitForExistence(timeout: timeout / 3) {
            app.typeKey("n", modifierFlags: [.command, .option])
        }
        #endif
        return MindMapApp(app: app)
    }

    var library: LibraryPage { LibraryPage(app: app) }
    var editor: EditorPage { EditorPage(app: app) }

    func openSettings(file: StaticString = #filePath, line: UInt = #line) -> SettingsPage {
        SettingsPage.open(in: app, file: file, line: line)
    }
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

@MainActor
extension XCUIElement {
    /// Taps on iOS, clicks on macOS. On macOS 27 with Xcode 27, `tap()` is
    /// played back as a touch through a virtual HID device that WindowServer
    /// refuses to create for testmanagerd (missing the
    /// `com.apple.private.hid.client.event-dispatch` entitlement), so the tap
    /// never lands and XCTest only times out after 5 s; `click()` sends a mouse event.
    func tapOrClick() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }

    /// Types `text` into the focused field. On macOS, XCTest synthesizes
    /// typing through the current keyboard layout, and a character the layout
    /// cannot produce (Vietnamese "ế", "ữ") stalls until "Timed out while
    /// synthesizing event", so such text is pasted instead and the previous
    /// clipboard is put back, since the Mac is shared with its user.
    func enterText(_ text: String) {
        #if os(macOS)
        guard !text.allSatisfy(\.isASCII) else {
            typeText(text)
            return
        }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        typeKey("v", modifierFlags: .command)
        pasteboard.clearContents()
        if let previous { pasteboard.setString(previous, forType: .string) }
        #else
        typeText(text)
        #endif
    }

    /// The text a static text shows: its label on iOS, its value on macOS.
    var shownText: String {
        label.isEmpty ? (value as? String ?? "") : label
    }
}
