import Foundation

/// The App Group the app shares with its Share Extension: the store and the
/// share inbox live in its container, so both processes see the same maps.
public enum AppGroup {
    public static let identifier = "group.asia.xdev.mindmapai"

    /// Nil when the process has no App Group entitlement, as in `swift test`;
    /// the app then keeps its store in its own container.
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static func storeURL(in containerURL: URL) -> URL {
        containerURL.appending(path: "Library/Application Support/MindMapAI.store", directoryHint: .notDirectory)
    }

    /// True once the app has opened the shared store at least once. The Share
    /// Extension never creates the store itself: an older build may still have
    /// the user's maps in its own container, and an empty shared store made
    /// first would stop the app from moving them over.
    public static func hasStore(in containerURL: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: storeURL(in: containerURL).path(percentEncoded: false))
    }
}

/// Moves a SQLite store, with its write-ahead log and shared-memory files,
/// before anything opens it.
enum StoreRelocation {
    enum Outcome: Equatable {
        case moved
        case nothingToMove
        /// Both stores exist. Nothing is merged or deleted; the old one stays
        /// where it is so no map is ever lost by a move.
        case destinationExists
    }

    @discardableResult
    static func move(from source: URL, to destination: URL, fileManager: FileManager = .default) throws -> Outcome {
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return .nothingToMove }
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { return .destinationExists }

        // "MindMapAI.store", "MindMapAI.store-wal", "MindMapAI.store-shm", and
        // SwiftData's ".MindMapAI_SUPPORT" folder when it exists.
        let name = source.deletingPathExtension().lastPathComponent
        let directory = source.deletingLastPathComponent()
        let files = try fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(source.lastPathComponent) || $0 == ".\(name)_SUPPORT"
        }
        let destinationDirectory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var moved: [(from: URL, to: URL)] = []
        do {
            for file in files {
                let renamed = file.replacing(source.lastPathComponent, with: destination.lastPathComponent, maxReplacements: 1)
                    .replacing(".\(name)_SUPPORT", with: ".\(destination.deletingPathExtension().lastPathComponent)_SUPPORT")
                let pair = (from: directory.appending(path: file), to: destinationDirectory.appending(path: renamed))
                try fileManager.moveItem(at: pair.from, to: pair.to)
                moved.append(pair)
            }
        } catch {
            // A half-moved store (the database without its log) would lose the
            // edits still in the log, so put back what already moved.
            for pair in moved.reversed() {
                try? fileManager.moveItem(at: pair.to, to: pair.from)
            }
            throw error
        }
        return .moved
    }
}
