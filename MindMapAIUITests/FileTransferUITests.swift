import XCTest

/// Import and export with `-uitest-files`, which stands in for the system's
/// open and save panels (docs/testing.md): the panels are another process,
/// differ by OS version and cannot reach a fixture file. ImportUITests checks
/// that the real panels open.
final class FileTransferUITests: XCTestCase {
    /// AT-06: a Markdown file imported as a new map and exported again keeps
    /// its topics and their levels.
    @MainActor
    func testMarkdownImportedThenExportedKeepsItsStructure() {
        let mindMap = MindMapApp.launch(arguments: [UITestLaunch.files])
        mindMap.library.show().tapImport()
        // The file's one top-level heading names the new map, which opens on the canvas.
        let editor = mindMap.editor.waitUntilOpen()
        editor.canvasTopics.matching(NSPredicate(format: "label == %@", UITestFile.mapTitle)).firstMatch.waitToExist()

        editor.export(.markdown)
        let text = mindMap.exportedFileSummary(named: UITestFile.mapTitle + ".md")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines, UITestFile.exportedLines)
    }

    @MainActor
    func testPNGAndPDFExportsAreNotEmpty() {
        let mindMap = MindMapApp.launch(fixture: .sample, arguments: [UITestLaunch.files])
        let editor = mindMap.library.show().open(UITestFixture.Title.plan)

        editor.export(.png)
        assertPicture("png", summary: mindMap.exportedFileSummary(named: UITestFixture.Title.plan + ".png"))
        editor.export(.pdf)
        assertPicture("pdf", summary: mindMap.exportedFileSummary(named: UITestFixture.Title.plan + ".pdf"))
    }

    /// The summary is "<kind by the file's signature> <bytes>".
    private func assertPicture(_ kind: String, summary: String, file: StaticString = #filePath, line: UInt = #line) {
        let parts = summary.split(separator: " ")
        XCTAssertEqual(parts.first.map(String.init), kind, "not a \(kind) file: \(summary.prefix(40))", file: file, line: line)
        XCTAssertGreaterThan(parts.last.flatMap { Int($0) } ?? 0, 0, "empty \(kind) file", file: file, line: line)
    }
}
