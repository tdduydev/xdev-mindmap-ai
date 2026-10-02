import Foundation
import MindMapDomain
import MindMapGraph
import MindMapMCP
import MindMapPersistence
import MindMapQuery
import Observation
import OSLog

/// Lets AI apps on this Mac read the maps over MCP (docs/mcp.md, M2): the
/// switch and port of Settings ▸ AI Apps, the connected apps and their tokens,
/// and the listener on 127.0.0.1 while the switch is on. Off by default; the
/// app starts it on the Mac only, iPad and iPhone build it and never do.
@MainActor
@Observable
final class AIAppsHost {
    enum Status: Equatable {
        case off
        case starting
        case listening(port: UInt16)
        /// Taken by another app or refused; the app never picks another port,
        /// since every client's config holds the URL.
        case portUnavailable(port: UInt16)
    }

    /// An app in the Connected Apps list.
    struct ConnectedApp: Identifiable, Equatable {
        let client: MCPClient
        let addedAt: Date
        /// The last tool call, kept in memory only (docs/mcp.md, Who is reading).
        var lastRead: Date?

        var id: MCPClient.ID { client.id }
        var name: String { client.name }
    }

    static let enabledKey = "mcp.enabled"
    static let portKey = "mcp.port"
    static let defaultPort = MCPListener.defaultPort
    /// Below 1024 needs privileges the sandbox does not give.
    static let allowedPorts: ClosedRange<UInt16> = 1024...65535

    private(set) var status: Status = .off
    private(set) var apps: [ConnectedApp] = []
    private(set) var isEnabled: Bool
    private(set) var port: UInt16
    /// Set when the Keychain refused to read the tokens; the list then shows nothing.
    private(set) var keychainFailed = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: any AIAppClientStore
    @ObservationIgnored private let access = MCPTokenList()
    @ObservationIgnored private let queries: MapQueries
    @ObservationIgnored private let serverVersion: String
    @ObservationIgnored private var listener: MCPListener?
    @ObservationIgnored private var listenerStates: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(queries: MapQueries, store: any AIAppClientStore, defaults: UserDefaults = AppDefaults.store, serverVersion: String = AIAppsHost.appVersion) {
        self.queries = queries
        self.store = store
        self.defaults = defaults
        self.serverVersion = serverVersion
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        port = Self.storedPort(in: defaults)
    }

    /// The port in `defaults`, or the default when it is absent or out of range.
    static func storedPort(in defaults: UserDefaults) -> UInt16 {
        let stored = defaults.integer(forKey: portKey)
        guard let port = UInt16(exactly: stored), allowedPorts.contains(port) else { return defaultPort }
        return port
    }

    /// Reads the tokens and listens if the switch is on. Once, at launch.
    func start() {
        guard !started else { return }
        started = true
        do {
            let stored = try store.load()
            for app in stored { access.add(app.client, token: app.token) }
            apps = stored.map { ConnectedApp(client: $0.client, addedAt: $0.addedAt) }
        } catch {
            keychainFailed = true
            Log.mcp.error("Reading AI app tokens failed: \(String(describing: error), privacy: .public)")
        }
        if isEnabled { listen() }
    }

    // MARK: Settings

    /// Applies at once: on opens the port, off closes it and revokes nothing.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled { listen() } else { closePort() }
    }

    /// False for a port outside `allowedPorts`, which is not stored.
    @discardableResult
    func setPort(_ newPort: UInt16) -> Bool {
        guard Self.allowedPorts.contains(newPort) else { return false }
        guard newPort != port else {
            // Trying the same port again after it was taken.
            if case .portUnavailable = status, isEnabled { listen() }
            return true
        }
        port = newPort
        defaults.set(Int(newPort), forKey: Self.portKey)
        if isEnabled { listen() }
        return true
    }

    /// Makes a token for a new app, keeps it in the Keychain and returns it,
    /// the only time it is shown.
    func addApp(named name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = StoredAIApp(
            client: MCPClient(name: trimmed.isEmpty ? String(localized: "AI App") : trimmed),
            token: MCPTokenList.makeToken(),
            addedAt: .now
        )
        try store.save(app)
        access.add(app.client, token: app.token)
        apps.append(ConnectedApp(client: app.client, addedAt: app.addedAt))
        Log.mcp.notice("Added AI app \(app.client.name, privacy: .private)")
        return app.token
    }

    /// The app's token stops working at once, even mid-session.
    func revoke(_ id: MCPClient.ID) throws {
        access.revoke(id)
        apps.removeAll { $0.id == id }
        try store.delete(id)
    }

    // MARK: Server

    /// What the listener serves; internal so tests can send it requests
    /// without a socket (the app's sandbox has no network.client).
    @ObservationIgnored private(set) lazy var server: MCPServer = MCPServer(
        queries: queries,
        access: access,
        configuration: .init(serverVersion: serverVersion),
        onActivity: { [weak self] activity in
            Task { @MainActor in self?.record(activity) }
        }
    )

    func record(_ activity: MCPServer.Activity) {
        guard let index = apps.firstIndex(where: { $0.id == activity.client.id }) else { return }
        apps[index].lastRead = activity.date
    }

    private func listen() {
        closePort()
        let port = port
        status = .starting
        let listener: MCPListener
        do {
            listener = try MCPListener(server: server, port: port)
        } catch {
            Log.mcp.error("Listener refused: \(error.localizedDescription, privacy: .public)")
            status = .portUnavailable(port: port)
            return
        }
        self.listener = listener
        // Only this listener's states count; one closed before it may still report.
        listenerStates = Task { [weak self, weak listener] in
            guard let states = listener?.states else { return }
            for await state in states {
                guard let self, self.listener === listener else { return }
                switch state {
                case .starting: status = .starting
                case .ready(let bound): status = .listening(port: bound)
                case .failed: status = .portUnavailable(port: port)
                case .stopped: if status != .portUnavailable(port: port) { status = .off }
                }
            }
        }
        listener.start()
    }

    private func closePort() {
        listenerStates?.cancel()
        listenerStates = nil
        listener?.stop()
        listener = nil
        status = .off
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

/// Answers from the editor's live graph for open maps, so an AI app reads what
/// the window shows rather than the last save, and from the store otherwise.
nonisolated struct OpenMapsGraphSource: GraphSource {
    let openMaps: OpenMaps
    let repository: any MapRepository

    func graph(for mapID: MapID) async throws -> GraphState? {
        if let live = await openMaps.liveGraph(for: mapID) { return live }
        return try await repository.loadGraph(for: mapID)
    }

    func openMapIDs() async -> Set<MapID> {
        await openMaps.openMapIDs
    }
}
