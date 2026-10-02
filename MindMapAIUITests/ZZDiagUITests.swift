import XCTest

final class ZZDiagUITests: XCTestCase {
    @MainActor
    func testDump() {
        let app = MindMapApp.launch(fixture: .sample)
        let editor = app.library.show().open(UITestFixture.Title.plan).show(.outline)
        editor.selectOutlineTopic(UITestFixture.Title.design)
        app.app.buttons["OverflowBarButtonItem"].firstMatch.tap()
        _ = editor.addChildButton.waitForExistence(timeout: 10)
        print("DIAG-3-BEGIN\n\(app.app.debugDescription)\nDIAG-3-END")
    }
}
