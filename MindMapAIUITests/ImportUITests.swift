import XCTest

/// File ▸ Import… and Import into Map… open the system's file picker
/// (FR-IO-08, MM-91), from the library and from an open map.
final class ImportUITests: XCTestCase {
    @MainActor
    func testImportFromLibraryOpensFilePicker() {
        let app = MindMapApp.launch(fixture: .sample)
        app.library.show().tapImport()
        app.waitForSystemFilePanel()
        app.dismissSystemFilePanel()
        app.waitForSystemFilePanelToClose()
    }

    @MainActor
    func testImportIntoMapOpensFilePicker() {
        let app = MindMapApp.launch(fixture: .sample)
        let editor = app.library.show().open(UITestFixture.Title.plan)
        #if os(iOS)
        // An iPhone has no menu bar: the editor's toolbar has the command.
        editor.tap(.importIntoMap)
        #else
        _ = editor
        app.app.typeKey("i", modifierFlags: [.command, .shift, .option])
        #endif
        app.waitForSystemFilePanel()
        app.dismissSystemFilePanel()
        app.waitForSystemFilePanelToClose()
    }
}
