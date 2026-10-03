import CryptoKit
import Foundation

/// Downloads, checks and removes local models. Each model lives in
/// Application Support/LocalModels/<id>: not Caches, since the system may purge
/// Caches while the model is in use, and excluded from backup, since it can be
/// downloaded again (iOS Data Storage Guidelines).
public actor LocalModelStore {
    public enum State: Hashable, Sendable {
        case notInstalled
        case downloading(fraction: Double)
        case installed(byteCount: Int64)
    }

    public enum StoreError: Error, Hashable, Sendable {
        case notEnoughSpace(needed: Int64, available: Int64)
        case checksumMismatch(file: String)
        case sizeMismatch(file: String)
    }

    /// Fetches one file to a temporary location. URLSession in the app;
    /// a fake in tests. Background Assets could stand behind the same call.
    public typealias Fetch = @Sendable (URL) async throws -> URL

    private let root: URL
    private let fetch: Fetch
    private let availableCapacity: @Sendable (URL) -> Int64?
    private var progress: [String: Double] = [:]

    public init(
        root: URL = URL.applicationSupportDirectory.appending(path: "LocalModels", directoryHint: .isDirectory),
        fetch: @escaping Fetch = LocalModelStore.urlSessionFetch,
        availableCapacity: @escaping @Sendable (URL) -> Int64? = LocalModelStore.importantCapacity
    ) {
        self.root = root
        self.fetch = fetch
        self.availableCapacity = availableCapacity
    }

    public func folder(for model: LocalModel) -> URL {
        root.appending(path: model.id, directoryHint: .isDirectory)
    }

    public func state(of model: LocalModel) -> State {
        if let fraction = progress[model.id] { return .downloading(fraction: fraction) }
        let folder = folder(for: model)
        // A file only reaches the folder after its checksum passed, so presence
        // of every file means a complete, checked install.
        let complete = model.files.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0.name).path)
        }
        return complete ? .installed(byteCount: Self.byteCount(of: folder)) : .notInstalled
    }

    /// Downloads every missing file, checking size and SHA-256 before moving it
    /// into place. A cancelled task leaves only the files already checked.
    public func install(_ model: LocalModel) async throws {
        let folder = folder(for: model)
        let missing = model.files.filter {
            !FileManager.default.fileExists(atPath: folder.appending(path: $0.name).path)
        }
        let needed = missing.reduce(0) { $0 + $1.byteCount }
        if let available = availableCapacity(root.deletingLastPathComponent()), available < needed {
            throw StoreError.notEnoughSpace(needed: needed, available: available)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = folder
        try excluded.setResourceValues(values)

        progress[model.id] = 0
        defer { progress[model.id] = nil }
        var done: Int64 = 0
        for file in missing {
            try Task.checkCancellation()
            let temporary = try await fetch(file.url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
            guard size == file.byteCount else { throw StoreError.sizeMismatch(file: file.name) }
            guard try Self.sha256(of: temporary) == file.sha256 else { throw StoreError.checksumMismatch(file: file.name) }
            let destination = folder.appending(path: file.name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporary, to: destination)
            done += file.byteCount
            progress[model.id] = needed > 0 ? Double(done) / Double(needed) : 1
        }
    }

    public func remove(_ model: LocalModel) throws {
        let folder = folder(for: model)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: Helpers

    /// Streams the file so a 2 GB weight file never sits in memory.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func byteCount(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in items {
            let values = try? url.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    public static let urlSessionFetch: Fetch = { url in
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // URLSession deletes its file when this call returns; keep a copy we own.
        let owned = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: temporary, to: owned)
        return owned
    }

    public static let importantCapacity: @Sendable (URL) -> Int64? = { url in
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
}
