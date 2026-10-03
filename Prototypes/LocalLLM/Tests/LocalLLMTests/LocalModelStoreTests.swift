import Foundation
import Testing
@testable import LocalLLM

@Suite struct LocalModelStoreTests {
    @Test func installChecksAndReportsSize() async throws {
        let (store, model) = try await installedStore(for: Data(repeating: 7, count: 10_000))
        guard case .installed(let bytes) = await store.state(of: model) else {
            Issue.record("not installed"); return
        }
        #expect(bytes >= 10_000)
        let folder = await store.folder(for: model)
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        try await store.remove(model)
        #expect(await store.state(of: model) == .notInstalled)
    }

    @Test func wrongChecksumLeavesNothingInstalled() async throws {
        let source = temporaryFolder().appending(path: "weights.bin")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: source)
        let bad = model(files: [LocalModel.File(name: "weights.bin", url: source, byteCount: 7, sha256: String(repeating: "0", count: 64))])
        let store = LocalModelStore(root: temporaryFolder(), fetch: copying, availableCapacity: { _ in nil })
        await #expect(throws: LocalModelStore.StoreError.checksumMismatch(file: "weights.bin")) { try await store.install(bad) }
        #expect(await store.state(of: bad) == .notInstalled)
    }

    @Test func notEnoughSpaceStopsBeforeDownloading() async {
        let file = LocalModel.File(name: "w", url: URL(filePath: "/nonexistent"), byteCount: 2_000, sha256: "")
        let store = LocalModelStore(root: temporaryFolder(), fetch: { _ in throw URLError(.cancelled) }, availableCapacity: { _ in 1_000 })
        await #expect(throws: LocalModelStore.StoreError.notEnoughSpace(needed: 2_000, available: 1_000)) {
            try await store.install(model(files: [file]))
        }
    }

    @Test func downloadSizeIsFormatted() {
        let m = model(files: [LocalModel.File(name: "w", url: URL(filePath: "/x"), byteCount: 1_100_000_000, sha256: "")])
        #expect(m.formattedDownloadSize == ByteCountFormatter.string(fromByteCount: 1_100_000_000, countStyle: .file))
    }
}
