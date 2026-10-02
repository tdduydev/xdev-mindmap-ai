# ADR 0008: An MCP server in the Mac app, read-only first

- Status: proposed (MM-39); the product owner accepts or changes the items marked [Đề xuất] in [mcp.md](../mcp.md)
- Date: 2026-10-02
- Relates to: ADR 0001 (no backend, no outside dependency without a decision), ADR 0003 (commands with recorded undo)

## Context

People asked (2026-10-02) to let the AI apps they already use, such as Claude and ChatGPT, read their maps. The Model Context Protocol is how those apps reach local data. Apple brought MCP to Xcode 27 for developers but did not expose App Intents over MCP for users ([mcp.md](../mcp.md#apple-and-mcp)), so the app has to serve MCP itself. The app is sandboxed, sold in the Mac App Store, has no backend, and promises that xDev never sees a map.

## Decision

1. **The Mac app is the server.** It serves MCP over Streamable HTTP on `127.0.0.1` only, while it runs, using the Network framework. Nothing listens on other interfaces, and nothing runs after the app quits.
2. **Clients that speak only stdio** (Claude Desktop) get a sandboxed relay helper in the app bundle, after a spike shows App Review and signing accept it. The helper never opens the store.
3. **Off by default.** Turned on in Settings; each client gets its own token, kept in the Keychain, revocable; requests carrying an `Origin` header are refused; the app shows which client read last.
4. **Read-only tools first** (`list_maps`, `get_map`, `search`, `get_topic`). A later write tool only proposes topics; the person accepts them in the app as one `GraphCommand` with one undo step. No MCP tool edits, moves or deletes existing content.
5. **One query layer.** A new `MindMapQuery` target serves the MCP tools and the in-app chat (ADR 0009).
6. **No dependency.** The JSON-RPC server is ours, in a `MindMapMCP` target, answering protocol revisions 2026-07-28 and 2025-11-25. Adopting the official Swift SDK later needs a new ADR.
7. **iPad and iPhone** build the package but never start the server.

## Consequences

- Map text can leave the Mac through an app the person connects, under that app's terms. Settings explains this before the switch turns on (guideline 5.1.2(i)); [privacy.md](../privacy.md) and the privacy policy change with the task that ships it. xDev still receives nothing, so the App Privacy label is expected to stay "Data Not Collected" (not verified).
- The Mac app gains the `com.apple.security.network.server` entitlement.
- The feature works only while the app is open; a closed app gives clients a plain error.
- The protocol is maintained by us; a new MCP revision means a task to follow it.
- Remote connectors (claude.ai, ChatGPT web) are out of reach, as ADR 0001 rules out a public endpoint.
