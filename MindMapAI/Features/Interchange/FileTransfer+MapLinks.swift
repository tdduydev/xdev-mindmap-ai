import Foundation
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import OSLog

/// Share Link… for one open map.
struct ShareLinkRequest: Identifiable {
    let id = UUID()
    let session: EditorSession
}

/// Why a map link did not open, worded for the alert (FR-IO-09).
enum MapLinkFailure: Error, Equatable, Identifiable {
    case unreadable
    case newerVersion
    case tooLarge
    case couldNotSave

    init(_ error: MapLinkError) {
        switch error {
        case .notAMapLink, .damaged: self = .unreadable
        case .newerVersion: self = .newerVersion
        case .tooLarge: self = .tooLarge
        }
    }

    var id: Self { self }

    var title: String {
        String(localized: "Can’t Open Map Link")
    }

    var message: String {
        switch self {
        case .unreadable:
            String(localized: "This link can’t be opened. It may be incomplete.")
        case .newerVersion:
            String(localized: "This link needs a newer version of MindMap AI. Update the app, then try again.")
        case .tooLarge:
            String(localized: "This map is too big to open from a link.")
        case .couldNotSave:
            String(localized: "The map couldn’t be saved. Try again.")
        }
    }
}

/// Map links (FR-CLP-01, FR-CLP-02, ADR 0012): Share Link… writes the open map
/// into a link, and a link opened from anywhere becomes a new map.
extension FileTransfer {
    /// Within this time the same link is the system delivering it twice
    /// (as a URL and as a browsing activity), not the person opening it again.
    static let repeatedLinkInterval: TimeInterval = 2

    func beginShareLink(_ session: EditorSession) {
        shareLinkRequest = ShareLinkRequest(session: session)
    }

    /// Whether the URL is for this feature at all. Other URLs are left alone,
    /// so a link the app does not handle never shows an error.
    static func isMapLink(_ url: URL) -> Bool {
        MapLinkCodec.isMapLink(url)
    }

    /// A pasted link. Text that is not a URL gets the same message as a broken link.
    func openMapLink(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), Self.isMapLink(url) else {
            mapLinkFailure = .unreadable
            return
        }
        await openMapLink(url)
    }

    /// Always a new map, even for a link opened before: nothing in the library
    /// changes except the map added (docs/app-clip.md, *Opening links*).
    func openMapLink(_ url: URL, now: Date = .now) async {
        if let last = lastOpenedLink, last.url == url, now.timeIntervalSince(last.date) < Self.repeatedLinkInterval {
            return
        }
        lastOpenedLink = (url, now)
        let graph: GraphState
        do {
            graph = try await MapLinkCodec.map(from: url, now: now)
        } catch {
            // Only the kind of failure: the link holds the map's content (docs/privacy.md).
            Log.interchange.error("A map link did not open: \(String(describing: error), privacy: .public)")
            mapLinkFailure = MapLinkFailure(error)
            return
        }
        guard let id = await createMap(graph, [:]) else {
            mapLinkFailure = .couldNotSave
            return
        }
        isOpeningMapLink = false
        openMap(id)
        Log.interchange.info("Opened a map link of \(graph.nodes.count, privacy: .public) topics")
    }
}

/// What the Share Link sheet offers: the link, or what to do when it is too long.
@Observable
final class ShareLinkModel {
    enum Scope: Hashable {
        case map
        case branch(NodeID)
    }

    enum Status: Equatable {
        case preparing
        /// `withoutNotes` when the person chose Share Without Notes.
        case ready(URL, withoutNotes: Bool)
        case tooLong(canShareWithoutNotes: Bool)
    }

    let session: EditorSession
    /// The selected topic, when it is not the central topic: sharing it is a branch.
    let branchID: NodeID?
    var scope: Scope = .map
    private(set) var status: Status = .preparing
    @ObservationIgnored private var withoutNotes: URL?

    init(session: EditorSession) {
        self.session = session
        let selection = session.selection
        branchID = selection == session.map.rootNodeID ? nil : selection
    }

    /// The title the share sheet shows as the subject.
    var title: String {
        if case .branch(let id) = scope, let node = session.engine.state.node(id) { return node.title }
        return session.map.title
    }

    /// Encodes before anything is shown; the work runs off the main actor in `MapLinkCodec`.
    func prepare() async {
        status = .preparing
        let branch: NodeID? = if case .branch(let id) = scope { id } else { nil }
        switch await MapLinkCodec.share(session.engine.state, branch: branch) {
        case .link(let url):
            withoutNotes = nil
            status = .ready(url, withoutNotes: false)
        case .tooLong(let url):
            withoutNotes = url
            status = .tooLong(canShareWithoutNotes: url != nil)
        }
    }

    func shareWithoutNotes() {
        guard let withoutNotes else { return }
        status = .ready(withoutNotes, withoutNotes: true)
    }

    /// Nil when no topic other than the central one is selected, or the branch is already what is shared.
    var branchToOffer: NodeID? {
        guard let branchID, scope != .branch(branchID) else { return nil }
        return branchID
    }
}
