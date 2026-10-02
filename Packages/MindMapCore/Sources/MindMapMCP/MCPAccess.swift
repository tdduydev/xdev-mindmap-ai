import Foundation
import Security
import Synchronization

/// An AI app the person connected in Settings, named by them ("Claude Code").
public struct MCPClient: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// Who a bearer token belongs to. The app keeps one token per client in the
/// Keychain (M2); tests and the dev server use `MCPTokenList`.
public protocol MCPAccess: Sendable {
    /// Nil for an unknown or revoked token.
    func client(forToken token: String) async -> MCPClient?
}

/// Tokens held in memory. Lookups compare every stored token in constant
/// time, so response timing does not tell a local process how much of a
/// guessed token was right.
public final class MCPTokenList: MCPAccess {
    private let tokens: Mutex<[(token: Data, client: MCPClient)]>

    public init(_ entries: [String: MCPClient] = [:]) {
        tokens = Mutex(entries.map { (Data($0.key.utf8), $0.value) })
    }

    public func add(_ client: MCPClient, token: String) {
        tokens.withLock { $0.append((Data(token.utf8), client)) }
    }

    public func revoke(_ clientID: MCPClient.ID) {
        tokens.withLock { $0.removeAll { $0.client.id == clientID } }
    }

    public func client(forToken token: String) async -> MCPClient? {
        let candidate = Data(token.utf8)
        return tokens.withLock { entries in
            var found: MCPClient?
            for entry in entries where Self.constantTimeEqual(entry.token, candidate) {
                found = entry.client
            }
            return found
        }
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    /// 32 random bytes as base64url without padding: 43 header-safe characters.
    public static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Calls per client in a sliding window, so a looping agent cannot keep the
/// app busy reading maps.
final class RateLimiter: Sendable {
    let limit: Int
    let window: Duration
    private let calls = Mutex<[MCPClient.ID: [ContinuousClock.Instant]]>([:])

    init(limit: Int, window: Duration) {
        self.limit = limit
        self.window = window
    }

    /// Nil when the call may go ahead, else how long until the oldest call
    /// leaves the window.
    func admit(_ clientID: MCPClient.ID, at now: ContinuousClock.Instant) -> Duration? {
        calls.withLock { calls in
            var recent = (calls[clientID] ?? []).filter { now - $0 < window }
            defer { calls[clientID] = recent }
            guard recent.count < limit else { return window - (now - recent[0]) }
            recent.append(now)
            return nil
        }
    }
}
