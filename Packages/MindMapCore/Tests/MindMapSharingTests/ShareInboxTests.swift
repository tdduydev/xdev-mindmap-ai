import Foundation
import MindMapDomain
import MindMapSharing
import Testing

@Suite("Share inbox")
struct ShareInboxTests {
    let root: URL
    let inbox: ShareInbox

    init() throws {
        root = URL.temporaryDirectory.appending(path: "ShareInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        inbox = ShareInbox(containerURL: root)
    }

    @Test func emptyUntilSomethingIsShared() throws {
        #expect(try inbox.items().isEmpty)
    }

    @Test func copiesFilesAndListsThemOldestFirst() throws {
        let photo = try file("Ảnh.heic", contents: "image")
        let paper = try file("paper.pdf", contents: "%PDF")
        let mapID = MapID()

        let first = try inbox.add(fileAt: photo, kind: .image, targetMapID: mapID, now: Date(timeIntervalSince1970: 1))
        let second = try inbox.add(fileAt: paper, kind: .pdf, targetMapID: nil, now: Date(timeIntervalSince1970: 2))
        try FileManager.default.removeItem(at: photo)

        #expect(try inbox.items() == [first, second])
        #expect(first.targetMapID == mapID)
        #expect(try String(contentsOf: inbox.fileURL(of: first), encoding: .utf8) == "image")
    }

    @Test func removedItemIsGone() throws {
        let item = try inbox.add(fileAt: try file("a.pdf", contents: "%PDF"), kind: .pdf, targetMapID: nil)

        try inbox.remove(item)

        #expect(try inbox.items().isEmpty)
    }

    @Test func failedCopyLeavesNothingBehind() throws {
        #expect(throws: (any Error).self) {
            try inbox.add(fileAt: root.appending(path: "missing.pdf"), kind: .pdf, targetMapID: nil)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: inbox.directory.path(percentEncoded: false))
        #expect(leftovers.isEmpty)
    }

    private func file(_ name: String, contents: String) throws -> URL {
        let url = root.appending(path: "source-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
