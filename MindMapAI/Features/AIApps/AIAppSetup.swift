import Foundation

/// The AI apps Add App… writes a setup for. The app never edits their config
/// files itself (App Review 2.4.5(ii), docs/mcp.md): the person copies the
/// snippet and pastes it where the app reads it.
enum AIAppKind: String, CaseIterable, Identifiable {
    case claudeCode
    case chatGPT
    case cursor
    case vsCode
    case other

    var id: Self { self }

    /// Product names are not translated; Other is.
    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .chatGPT: "ChatGPT"
        case .cursor: "Cursor"
        case .vsCode: "VS Code"
        case .other: String(localized: "Other")
        }
    }

    /// The name a new app gets unless the person types one.
    var suggestedName: String { self == .other ? "" : title }

    /// Where the snippet goes, in one sentence.
    var instructions: String {
        switch self {
        case .claudeCode:
            String(localized: "Run this command in Terminal.")
        case .chatGPT:
            String(localized: "Add this to ~/.codex/config.toml, which the ChatGPT app, Codex CLI and Codex IDE extension share.")
        case .cursor:
            String(localized: "Add this to ~/.cursor/mcp.json, inside “mcpServers” if the file already has servers.")
        case .vsCode:
            String(localized: "Run MCP: Open User Configuration and add this to mcp.json, inside “servers” if the file already has servers.")
        case .other:
            String(localized: "Point the app at this address with Streamable HTTP and send the token in an Authorization: Bearer header.")
        }
    }
}

/// Copy-ready configuration for one app. Formats were read on 2026-10-02:
/// Claude Code `claude mcp add --transport http … --header`, ChatGPT/Codex
/// `[mcp_servers.<name>]` with `url` and `http_headers`, Cursor `mcpServers`
/// with `url` and `headers`, VS Code `servers` with `type: http`, `url`,
/// `headers` (docs/mcp.md, Clients).
enum AIAppSetup {
    /// The server's name in every client config.
    static let serverName = "mindmap-ai"

    static func endpoint(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/mcp"
    }

    static func snippet(for kind: AIAppKind, port: UInt16, token: String) -> String {
        let url = endpoint(port: port)
        let header = "Bearer \(token)"
        switch kind {
        case .claudeCode:
            return "claude mcp add --transport http --scope user \(serverName) \(url) --header \"Authorization: \(header)\""
        case .chatGPT:
            return """
                [mcp_servers.\(serverName)]
                url = "\(url)"
                http_headers = { "Authorization" = "\(header)" }
                """
        case .cursor:
            return json(["mcpServers": [serverName: ["url": url, "headers": ["Authorization": header]]]])
        case .vsCode:
            return json(["servers": [serverName: ["type": "http", "url": url, "headers": ["Authorization": header]]]])
        case .other:
            return """
                URL: \(url)
                Authorization: \(header)
                """
        }
    }

    private static func json(_ object: [String: Any]) -> String {
        // Sorted keys keep the snippet stable; the token is base64url, so nothing needs escaping.
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
