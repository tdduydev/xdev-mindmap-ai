import Foundation
import Observation
import SwiftUI

/// The open and save panels in the UI test mode with `-uitest-files`
/// (docs/testing.md). The system's panels belong to another process, look
/// different on each OS version and cannot reach a fixture file, so a test
/// of what import and export do (AT-06) goes around them: Import… reads
/// `UITestFile.markdown`, Export… writes into the app's temporary folder and
/// reports what it wrote on screen, where the test reads it. The code before
/// and after the panel is the shipping code. Nil whenever the mode is off.
@MainActor
@Observable
final class UITestFiles {
    /// What the last export wrote, read back from the disk.
    struct Report: Equatable {
        let fileName: String
        /// The text of a text file; "png 1234" or "pdf 1234" (kind by signature, byte count) otherwise.
        let summary: String
    }

    static let shared: UITestFiles? = UITestMode.current?.files == true ? UITestFiles() : nil

    private(set) var lastExport: Report?

    private var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "UITestFiles", directoryHint: .isDirectory)
    }

    /// Writes the fixture where the open panel would have found it.
    func fixtureURL() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: UITestFile.name)
        try Data(UITestFile.markdown.utf8).write(to: url)
        return url
    }

    /// Saves an export as the save panel would, then reads the file back, so
    /// the report says what reached the disk.
    func save(_ data: Data, fileName: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try data.write(to: url)
        let written = try Data(contentsOf: url)
        let summary: String
        if written.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            summary = "png \(written.count)"
        } else if written.starts(with: Array("%PDF".utf8)) {
            summary = "pdf \(written.count)"
        } else {
            summary = String(decoding: written, as: UTF8.self)
        }
        lastExport = Report(fileName: fileName, summary: summary)
    }
}

/// The last export's report, at the bottom of the window. Only in the mode.
struct UITestExportReport: View {
    let files: UITestFiles

    var body: some View {
        if let report = files.lastExport {
            Text(verbatim: report.fileName)
                .font(.caption2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: report.fileName))
                .accessibilityValue(Text(verbatim: report.summary))
                .accessibilityIdentifier(AccessibilityID.UITest.exportedFile)
        }
    }
}
