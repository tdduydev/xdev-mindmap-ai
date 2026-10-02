import Foundation
import MindMapMCP
import OSLog
import Security

/// An AI app the person added in Settings ▸ AI Apps, with its bearer token.
struct StoredAIApp: Equatable {
    var client: MCPClient
    var token: String
    var addedAt: Date
}

/// Where AI app tokens are kept. The app uses the Keychain; tests and the UI
/// test mode keep them in memory so they never touch the person's Keychain.
protocol AIAppClientStore: AnyObject {
    func load() throws -> [StoredAIApp]
    func save(_ app: StoredAIApp) throws
    func delete(_ id: MCPClient.ID) throws
}

final class InMemoryAIAppClientStore: AIAppClientStore {
    private var apps: [StoredAIApp] = []

    func load() throws -> [StoredAIApp] { apps }
    func save(_ app: StoredAIApp) throws { apps.append(app) }
    func delete(_ id: MCPClient.ID) throws { apps.removeAll { $0.client.id == id } }
}

/// One generic password per app: account = client ID, generic attribute = its
/// name, data = the token. Device-only and never synced, since the token
/// opens a port on this Mac only (docs/mcp.md, Security).
final class KeychainAIAppClientStore: AIAppClientStore {
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    private let service: String
    /// The data protection keychain: no access prompts when a new build of
    /// the app reads items an older one wrote. It needs a signed build with an
    /// application identifier; an ad-hoc local build gets
    /// errSecMissingEntitlement and falls back to the file-based keychain.
    private var usesDataProtection = true

    init(service: String = "asia.xdev.mindmapai.mcp-client") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: usesDataProtection,
        ]
    }

    /// Runs `operation`, once more on the file-based keychain if the data
    /// protection keychain is not available to this build.
    private func withKeychain(_ operation: () -> OSStatus) -> OSStatus {
        let status = operation()
        guard status == errSecMissingEntitlement, usesDataProtection else { return status }
        usesDataProtection = false
        Log.mcp.notice("No data protection keychain for this build; using the file-based keychain")
        return operation()
    }

    func load() throws -> [StoredAIApp] {
        var result: CFTypeRef?
        let status = withKeychain { copyAttributes(into: &result) }
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw Failure(status: status) }
        return try items.compactMap { item -> StoredAIApp? in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let id = UUID(uuidString: account),
                  let nameData = item[kSecAttrGeneric as String] as? Data,
                  let name = String(data: nameData, encoding: .utf8),
                  let token = try token(for: account) else { return nil }
            let addedAt = item[kSecAttrCreationDate as String] as? Date ?? .distantPast
            return StoredAIApp(client: MCPClient(id: id, name: name), token: token, addedAt: addedAt)
        }
        .sorted { $0.addedAt < $1.addedAt }
    }

    /// Attributes only: the file-based keychain returns data for one item at a time.
    private func copyAttributes(into result: inout CFTypeRef?) -> OSStatus {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    private func token(for account: String) throws -> String? {
        var query = baseQuery
        query[kSecAttrAccount as String] = account
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ app: StoredAIApp) throws {
        let status = withKeychain { add(app) }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    private func add(_ app: StoredAIApp) -> OSStatus {
        var item = baseQuery
        item[kSecAttrAccount as String] = app.client.id.uuidString
        item[kSecAttrGeneric as String] = Data(app.client.name.utf8)
        // What Keychain Access shows; the name is the person's own label, not map content.
        item[kSecAttrLabel as String] = "MindMap AI: \(app.client.name)"
        item[kSecValueData as String] = Data(app.token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        return SecItemAdd(item as CFDictionary, nil)
    }

    func delete(_ id: MCPClient.ID) throws {
        let status = withKeychain {
            var query = baseQuery
            query[kSecAttrAccount as String] = id.uuidString
            return SecItemDelete(query as CFDictionary)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
