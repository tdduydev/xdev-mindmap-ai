import XCTest
final class ZZDebugUITests: XCTestCase {
    @MainActor func testDump() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-fixture", "sample"]
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 20)
        let a = XCTAttachment(string: "windows=\(app.windows.count) state=\(app.state.rawValue)\n" + app.debugDescription); a.name = "tree"; a.lifetime = .keepAlways; add(a)
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
    }
}
