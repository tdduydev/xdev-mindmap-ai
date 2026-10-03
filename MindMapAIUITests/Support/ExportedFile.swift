import XCTest

@MainActor
extension MindMapApp {
    /// What the stand-in for the save panel (`-uitest-files`) wrote last.
    var exportedFile: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.UITest.exportedFile].firstMatch
    }

    /// Waits for the report of an export named `fileName` and returns what
    /// the file holds: its text, or "png <bytes>" / "pdf <bytes>".
    func exportedFileSummary(named fileName: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let report = exportedFile
        let named = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", fileName), object: report)
        let result = XCTWaiter().wait(for: [named], timeout: Self.timeout)
        XCTAssertEqual(result, .completed, "no export named \(fileName); last: \(report.exists ? report.label : "none")", file: file, line: line)
        return report.value as? String ?? ""
    }
}
