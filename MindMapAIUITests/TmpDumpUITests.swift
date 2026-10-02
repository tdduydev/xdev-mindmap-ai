import XCTest
final class TmpDumpUITests: XCTestCase {
    @MainActor func testDump() {
        let app = MindMapApp.launch(fixture: .sample, arguments: [UITestLaunch.ai, UITestAI.ready.rawValue])
        app.library.show().open(UITestFixture.Title.plan).show(.canvas)
        let chat = ChatPage(app: app.app)
        let e = chat.entryPoint()
        print("ENTRY:", e?.debugDescription ?? "nil")
        e?.tap()
        sleep(4)
        print("DUMPSTART"); print(app.app.debugDescription); print("DUMPEND")
    }
}
