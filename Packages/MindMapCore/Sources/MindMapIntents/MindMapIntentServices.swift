import Foundation
import MindMapDomain
import MindMapInterchange
import MindMapPersistence
import MindMapSharing

/// What the intents do, apart from App Intents so tests can call it directly.
/// The app builds one at launch and registers it with `AppDependencyManager`;
/// every intent and query reads it through `@Dependency`.
///
/// Opening a map and reading the clipboard are closures from the app: both
/// depend on the platform and on the app's windows, which this package must
/// not know about.
public final class MindMapIntentServices: Sendable {
    public enum Failure: Error, Hashable, Sendable, CustomLocalizedStringResourceConvertible {
        case emptyClipboard
        case noMaps
        case mapNotFound
        case emptyIdea

        public var localizedStringResource: LocalizedStringResource {
            switch self {
            case .emptyClipboard: "The clipboard has no text to make a map from."
            case .noMaps: "There are no maps yet."
            case .mapNotFound: "That map no longer exists."
            case .emptyIdea: "Type an idea to add."
            }
        }
    }

    private let capture: QuickCapture
    private let untitledTitle: @Sendable () -> String
    private let openMap: @MainActor @Sendable (MapID) -> Void
    private let readClipboard: @MainActor @Sendable () -> String?
    private let index: any MapSearchIndex

    public init(
        repository: any MapRepository,
        index: any MapSearchIndex,
        untitledTitle: @escaping @Sendable () -> String,
        openMap: @escaping @MainActor @Sendable (MapID) -> Void,
        readClipboard: @escaping @MainActor @Sendable () -> String?,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        capture = QuickCapture(repository: repository, clock: clock)
        self.index = index
        self.untitledTitle = untitledTitle
        self.openMap = openMap
        self.readClipboard = readClipboard
    }

    // MARK: Intents

    /// An empty map, opened in the app.
    public func newMap(title: String?) async throws -> MindMap {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let map = try await capture.createMap(from: OutlineDraft(), title: trimmed.isEmpty ? untitledTitle() : trimmed)
        await index.update(map)
        await openMap(map.id)
        return map
    }

    /// The clipboard's text read as Markdown (plain lines work too), opened in the app.
    public func mapFromClipboard() async throws -> MindMap {
        let text = await readClipboard() ?? ""
        let draft = InterchangeFormat.markdown.parse(text)
        guard !draft.isEmpty else { throw Failure.emptyClipboard }
        let map = try await capture.createMap(from: draft, title: untitledTitle())
        await index.update(map)
        await openMap(map.id)
        return map
    }

    /// Runs without opening the app, so an idea can be captured from anywhere.
    public func addIdea(_ idea: String, to mapID: MapID?) async throws -> MindMap {
        do {
            let map = try await capture.addIdea(idea, to: mapID)
            await index.update(map)
            return map
        } catch QuickCapture.Failure.nothingToAdd {
            throw Failure.emptyIdea
        } catch QuickCapture.Failure.mapNotFound {
            throw Failure.mapNotFound
        }
    }

    public func openRecent() async throws -> MindMap {
        guard let map = try await capture.recentMaps(limit: 1).first else { throw Failure.noMaps }
        await openMap(map.id)
        return map
    }

    public func open(_ mapID: MapID) async throws {
        guard try await capture.map(mapID) != nil else { throw Failure.mapNotFound }
        await openMap(mapID)
    }

    // MARK: Queries

    /// Most recently edited first, as Shortcuts lists them.
    public func recentMaps(limit: Int = 20) async throws -> [MindMap] {
        try await capture.recentMaps(limit: limit)
    }

    /// In the order asked for; IDs of deleted maps are left out.
    public func maps(withIDs ids: [MapID]) async throws -> [MindMap] {
        let maps = try await capture.recentMaps(limit: .max)
        let byID = Dictionary(uniqueKeysWithValues: maps.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Ignores case and Vietnamese diacritics, so "ke hoach" finds "Kế hoạch".
    public func maps(matching text: String) async throws -> [MindMap] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maps = try await capture.recentMaps(limit: .max)
        guard !query.isEmpty else { return maps }
        return maps.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
