import XCTest

/// The system's open or save panel (`fileImporter`, `fileExporter`). It
/// belongs to the system, so it has no identifiers of ours.
@MainActor
extension MindMapApp {
    /// The labels of the button that closes the document picker. iOS 27 shows
    /// an ✕ (Close) where earlier versions showed Cancel.
    private static let filePanelCloseLabels = ["Cancel", "Close", "Hủy", "Huỷ", "Đóng"]

    private var filePanelCloseButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", Self.filePanelCloseLabels)).firstMatch
    }

    #if os(iOS)
    private var documentPicker: XCUIElement {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'DOC'")).firstMatch
    }

    private var documentBrowser: XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'DOC' OR identifier CONTAINS 'FullDocumentManager'")).firstMatch
    }
    #endif

    /// Fails unless the panel comes up.
    func waitForSystemFilePanel(file: StaticString = #filePath, line: UInt = #line) {
        #if os(iOS)
        let shown = [documentPicker, documentBrowser, filePanelCloseButton].contains {
            $0.waitForExistence(timeout: Self.timeout / 3)
        }
        XCTAssertTrue(shown, "no document picker", file: file, line: line)
        #else
        let shown = app.sheets.firstMatch.waitForExistence(timeout: Self.timeout / 3) || app.dialogs.firstMatch.exists
        XCTAssertTrue(shown, "no file panel", file: file, line: line)
        #endif
    }

    func dismissSystemFilePanel() {
        #if os(iOS)
        let close = filePanelCloseButton
        if close.waitForExistence(timeout: Self.timeout / 6) { close.tapOrClick() }
        #else
        app.typeKey(.escape, modifierFlags: [])
        #endif
    }

    /// Fails while the panel is still up after `dismissSystemFilePanel()`.
    func waitForSystemFilePanelToClose(file: StaticString = #filePath, line: UInt = #line) {
        #if os(iOS)
        let gone = NSPredicate(format: "exists == false")
        let expectations = [documentPicker, documentBrowser, filePanelCloseButton].map {
            XCTNSPredicateExpectation(predicate: gone, object: $0)
        }
        XCTAssertEqual(XCTWaiter.wait(for: expectations, timeout: Self.timeout / 3), .completed, "document picker still open", file: file, line: line)
        #endif
    }
}
