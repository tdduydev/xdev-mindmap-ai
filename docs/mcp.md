# MCP server: AI apps read your maps

Design for MM-39, 2026-10-02. The shared query layer (MM-47), the server core `MindMapMCP` (MM-40, [Server core](#server-core)) and the Mac app's Settings ▸ AI Apps that hosts it (MM-46, [In the app](#in-the-app)) are built. Decisions are in [ADR 0008](adr/0008-mcp-server.md); the in-app chat that shares the query layer is in [chat.md](chat.md). Items marked [Đề xuất] are proposals waiting for the product owner. *[Inference]* marks reasoning that no source states. Sources were read on 2026-10-02; recheck them before building, since the protocol and the clients change every few months.

## Summary

- **What:** a Model Context Protocol (MCP) server inside the Mac app, so AI apps the person already uses (Claude Desktop, Claude Code, ChatGPT desktop, Cursor, VS Code) can list, read and search their maps. Mac only: no iPad or iPhone client launches or reaches a local server *[Inference]*.
- **Transport (decided 2026-10-02):** first, the app itself serves Streamable HTTP on `127.0.0.1` while it runs, with a token per client. Second, a small stdio helper in the app bundle that only relays to the running app, for clients that speak stdio only (Claude Desktop). No helper reads the store, and nothing is remote: there is no backend (ADR 0001).
- **Changed 2026-10-03 (proposed, [ADR 0013](adr/0013-mcp-helper-over-app-group-socket.md)):** App Review rejected macOS 1.0.0 for `network.server`. From 1.1 every client goes through the stdio helper, which reaches the app over a Unix socket in a Team-ID-prefixed App Group, with no network entitlement and no token. The HTTP listener leaves the app. See [Helper spike](#helper-spike-mm-48).
- **Read-only first.** Writing comes later and only as a proposal the person accepts in the app; Accept is one `GraphCommand`, one undo step, like every AI suggestion ([ai-architecture.md](ai-architecture.md)).
- **Off by default.** Turned on in Settings, one client at a time, each with its own token, visible last access and Revoke.
- **Privacy:** map text leaves the Mac only through the AI app the person connected, under that app's terms. xDev still receives nothing. Settings, the privacy page and the privacy policy say so before the switch is turned on.
- **No dependency.** A small JSON-RPC server in a new `MindMapMCP` target on the Network framework, not the official Swift SDK ([Dependency](#dependency)).
- **Apple has not made App Intents an MCP server for users.** WWDC26 brought MCP to Xcode for developers only, so the app builds its own.

## Where MCP stands

| Fact | Source |
| --- | --- |
| The current revision is **2026-07-28**. It made the protocol stateless: no `initialize` handshake and no sessions; every request carries its protocol version and client capabilities in `_meta`; servers must answer `server/discover`. | [Key changes 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/changelog) |
| Two standard transports: **stdio** (the client launches the server as a subprocess, newline-delimited JSON-RPC on stdin and stdout, logs on stderr only) and **Streamable HTTP** (each message is a POST to one endpoint; the reply is JSON or a request-scoped SSE stream). | [Transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports), [stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio) |
| Custom transports over a byte stream (Unix socket, TCP) should reuse the stdio framing. | [Transports: custom](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports#custom-transports) |
| A local Streamable HTTP server **must** validate `Origin` (403 when invalid) against DNS rebinding, **should** bind to 127.0.0.1 only and **should** authenticate every connection. | [Streamable HTTP: security](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#security-%26-endpoint) |
| Clients that speak both eras probe with `server/discover` and fall back to `initialize`; servers that want older clients implement the 2025-11-25 behaviour too. | [stdio: backward compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio#backward-compatibility), [Streamable HTTP: earlier revisions](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#earlier-streamable-http-revisions) |
| Roots, Sampling and Logging are deprecated. | [Key changes: deprecated](https://modelcontextprotocol.io/specification/2026-07-28/changelog#deprecated) |

*[Inference]* Clients released before August 2026 still speak 2025-11-25 (`initialize`). The server answers both eras, so it works with today's clients and with those that move to 2026-07-28.

## Apple and MCP

- WWDC26 brought MCP to **Xcode 27**: coding agents use Xcode's tools over MCP, and Xcode connects to other MCP servers ([Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/), [Inside Apple Intelligence and Xcode](https://developer.apple.com/videos/play/wwdc2026/382/)).
- App Intents in 27 reach Siri and Spotlight's semantic index through entity and intent schemas and View Annotations; the WWDC26 macOS guide does not mention MCP ([WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/)).
- The Omni Group, after WWDC26: "Apple did announce MCP integration for Xcode, but not for App Intents; Xcode's integration is only for developers, not for end users." Omni had waited for Apple and now plans its own MCP support, probably through Omni Automation or App Intents, and was looking for testers in July 2026 ([Omni Roadmap 2026, post-WWDC](https://www.omnigroup.com/blog/omni-roadmap-2026-post-wwdc-update), [MacSparky](https://www.macsparky.com/blog/2026/07/omni-group-building-toward-mcp-support/)). Omni has not published how it handles the sandbox (not verified).
- 9to5Mac found MCP code in the macOS 26.1 beta in 2025 ([9to5Mac](https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/)); by Omni's account above, nothing reached users by WWDC26.

So the app builds its own server. The MCP tools read through the same query layer as the App Intents ([system-integration.md](system-integration.md)) and the chat, so if Apple later exposes App Intents over MCP, only the transport changes *[Inference]*.

## Clients

| Client | Local stdio | Local HTTP | Where it is configured | Source |
| --- | --- | --- | --- | --- |
| Claude Desktop (Mac) | Yes: `mcpServers` in `claude_desktop_config.json`, or a `.mcpb` bundle installed by double-click | Not in that file (stdio only, third-party guide; not verified on an Anthropic page) | Settings ▸ Developer ▸ Edit Config | [Desktop Extensions](https://www.anthropic.com/engineering/desktop-extensions), [MCPB manifest](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md), [hooklayer guide](https://hooklayer.dev/guides/claude-desktop-config-json) |
| Claude Code | Yes, `claude mcp add <name> -- <command>` | Yes, `claude mcp add --transport http <name> <url>` | `~/.claude.json` or the project's `.mcp.json` | [Claude Code MCP](https://code.claude.com/docs/en/mcp) |
| ChatGPT desktop | Yes, through the configuration it shares with Codex | Yes (Streamable HTTP) | `~/.codex/config.toml` | [ChatGPT: MCP](https://learn.chatgpt.com/docs/extend/mcp) |
| ChatGPT web, developer mode | No: remote HTTPS servers only | No (localhost is not reachable from OpenAI's servers *[Inference]*) | Settings ▸ Apps & Connectors | [designrevision guide](https://designrevision.com/blog/add-mcp-server-to-chatgpt), [ResolveMesh](https://resolvemesh.com/guides/chatgpt-mcp-compatibility) (third-party) |
| Cursor | Yes | Yes (Streamable HTTP, also old SSE) | `~/.cursor/mcp.json` | [Cursor MCP](https://cursor.com/docs/context/mcp) |
| VS Code (Copilot) | Yes, `"type": "stdio"` | Yes, `"type": "http"` | `mcp.json`; asks the person to trust a server before it first starts | [VS Code MCP servers](https://code.visualstudio.com/docs/copilot/customization/mcp-servers) |

Remote connectors (claude.ai, ChatGPT web) run on the vendor's servers and cannot reach a server on the person's Mac; supporting them would need a public endpoint, which ADR 0001 rules out.

## Transport

| Option | How | For | Against |
| --- | --- | --- | --- |
| **A. In-app Streamable HTTP** | The app listens on `127.0.0.1:<port>` with `NWListener` (loopback only) while it runs | One process: the switch, tokens, client list and proposals all live in the app. Reads the same live graph the editor shows. Works with Claude Code, ChatGPT desktop, Cursor, VS Code | Needs the `com.apple.security.network.server` entitlement. Works only while the app runs. Claude Desktop's config file does not take a URL |
| **B. stdio helper that opens the store** | A CLI in the bundle, launched by the client, opens the SwiftData store in the App Group | Works when the app is closed | A second process on the store the app and (later) CloudKit write. A tool launched by another app cannot use `com.apple.security.inherit` ([Apple forums](https://developer.apple.com/forums/thread/680212), [Twocanoes](https://twocanoes.com/adding-a-command-line-tool-helper-to-a-mac-app-store-app/)), so it needs its own sandbox and App Group claim; the iOS-style ID `group.asia.xdev.mindmapai` must be authorised by a provisioning profile, which a bare executable cannot embed: Apple says to wrap it in an app-like bundle ([App Groups: macOS vs iOS](https://developer.apple.com/forums/thread/721701)). The off switch and client list are in the app, which might not be running |
| **C. stdio helper that relays** | A CLI in the bundle (`Contents/Helpers/mindmap-mcp`), launched by the client, copies newline-delimited JSON-RPC between stdio and the app's loopback port | Claude Desktop and `.mcpb`; all logic stays in the app | Same "app must run" limit as A. Still a sandboxed executable started by another app, whose acceptance by App Review is not verified |

Decision (product owner, 2026-10-02): **A first, then C.** B is rejected. When the app is not running, the helper answers with an error that says "Open MindMap AI to let AI apps read your maps" rather than launching it; 2.4.5(iii) forbids processes the person did not start, and a helper that opens the app is close to that *[Inference]*.

The two shipping examples follow the same split: iMCP (direct download, not the Mac App Store) is a sandboxed app plus a stdio CLI that talks to the app over Bonjour, and asks the person to approve each client ([iMCP](https://github.com/mattt/iMCP)); PromptsMaker (Mac App Store, in review when written, not verified) runs MCP over HTTP on 127.0.0.1 inside the sandboxed app with `network.server`, a 32-byte bearer token and an `Origin` check ([dev.to](https://dev.to/klukyanov/i-embedded-an-mcp-server-inside-my-macos-app-so-agents-could-talk-back-1fda)).

### Port and connection details [Đề xuất]

- A fixed default port in the dynamic range, `MCPListener.defaultPort` = **51947** (chosen in MM-40), shown and changeable in Settings, because every client's config holds the URL. If it is taken, Settings says so; the app does not pick another one silently.
- Endpoint `http://127.0.0.1:<port>/mcp`. `Authorization: Bearer <token>` on every request, else 401. Any request with an `Origin` header is refused with 403: no supported client sends one, and browsers always do *[Inference]*.
- The helper (option C) reads the port and token from its arguments or environment, which the client config passes (`.mcpb` `user_config` keeps the token in the Keychain, per [Desktop Extensions](https://www.anthropic.com/engineering/desktop-extensions)).

## Sandbox and App Store

| Item | Rule | Plan |
| --- | --- | --- |
| Sandbox (2.4.5(i)) | Mac App Store apps are sandboxed | Add `com.apple.security.network.server` to the Mac app only. The helper gets `app-sandbox` and `network.client`, no App Group |
| One bundle, no shared locations (2.4.5(ii)) | "self-contained, single app installation bundles and cannot install code or resources in shared locations" ([guidelines](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)) | The app never writes another app's config file or copies the helper elsewhere. Settings shows the snippet with Copy (and the full `claude mcp add` command); the person pastes it. A `.mcpb` that copies the helper into Claude's folder would put our code in a shared location *[Inference]*, so offer one only if its manifest can point at the helper inside the app bundle (not verified) |
| No processes after quit (2.4.5(iii)) | No launch at login, nothing running after quit without consent | The listener stops when the app quits. No login item, no agent |
| No downloaded code (2.4.5(iv), 2.5.2) | — | Tool definitions ship in the bundle |
| Third-party AI (5.1.2(i)) | "clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)) | Turning the switch on is the permission, after a sheet that says which data the connected app can read and that it may send it to its own AI provider |
| Review Notes (2.3.1(a)) | No hidden features | Describe the switch, the port and a one-line test with Claude Code |

*[Inference, not verified]* A sandboxed helper that another app launches is unusual in the Mac App Store; build a TestFlight build with it before relying on option C (task M4 below). Superseded on 2026-10-03 by ADR 0013 (proposed): no `network.server`; the helper and the app share a Team-ID-prefixed App Group and a Unix socket, results in [Helper spike](#helper-spike-mm-48).

## Tools and resources

Read-only tools, in a fixed order (2026-07-28 asks for deterministic `tools/list`). Each one is marked `readOnlyHint: true` and returns Markdown text plus `structuredContent`. IDs are the UUIDs the app already uses.

| Tool | Arguments | Returns |
| --- | --- | --- |
| `list_maps` | `limit` (default 50), `query` (optional, matches map titles) | Live maps, most recently edited first: ID, title, topic count, last edit. Recently Deleted is never listed |
| `get_map` | `map_id`, `topic_id` (optional: one branch), `depth` (optional), `include_notes` (default true) | The map or branch as a Markdown outline (`MarkdownOutline.export`, the same format as File ▸ Export), with each topic's ID in a trailing comment so follow-up calls can name it; cut at the output limit with "N more topics" |
| `search` | `query`, `map_id` (optional: one map, else every map), `limit` (default 20) | Matching topics, not just maps: map, topic ID, title, path from the central topic, a short excerpt. Same folding as Find (case, Vietnamese marks, đ) |
| `get_topic` | `map_id`, `topic_id` | Title, note, path, children (titles and IDs), tags, task state and dates, cross-links |

- **Output limit [Đề xuất]:** about 20,000 characters per result, so one large map does not fill the client's context; `get_map` with `topic_id` and `depth` reads the rest.
- **Resources [Đề xuất], second step:** `mindmap://map/{map_id}` as a Markdown resource for clients that attach resources. Tools first, since every client in the table calls tools *[Inference]*.
- **Prompts:** none.
- **Errors:** an unknown ID, a deleted map or a bad argument is a tool result with `isError: true` and a plain message the model can act on (changed in MM-40 from invalid-params: 2026-07-28 classes these as tool execution errors that clients pass to the model). An unknown tool name stays a JSON-RPC invalid-params error. A store error says to try again, without its description.

### Writing, later

One write tool, `propose_topics(map_id, parent_topic_id, topics)`, where `topics` is a small tree of titles and optional notes (`destructiveHint: false`):

1. The app checks it with `ProposalTranslator` (the same checks as model output) and keeps it as a suggestion with the client's name: "Suggested by Claude Code".
2. The map shows it like any AI suggestion; nothing is in the graph or the store yet. The tool answers "Waiting for the person to review it in MindMap AI", never "added".
3. Accept is one `BatchCommand` of `AddNodeCommand`s named "Add Suggested Topics", one undo step; the topics keep `metadata.origin = .ai` (no new `NodeOrigin` case, so the stored raw value stays one an older build reads).

No tool edits, moves or deletes existing topics. A tool that did would let text inside a map (prompt injection) steer the client into changing the map without the person.

## Security

- **Off by default.** Settings ▸ AI Apps (Mac only) [Đề xuất name]: the switch "Allow AI Apps to Read Maps", the port, and the list of clients.
- **One token per client.** Add App… asks for a name ("Claude Code"), makes a 32-byte random token (`SecRandomCopyBytes`), keeps it in the Keychain, and shows the snippet once. Revoke deletes it; Turn Off revokes nothing but closes the port.
- **Who is reading.** Each client row shows its last request time. While a client has read in the last minute, the editor toolbar shows a small "AI app reading" indicator that opens the list [Đề xuất]. The activity kept is the tool name and time, in memory only.
- **Loopback and Origin** as in [Port and connection details](#port-and-connection-details-đề-xuất).
- **Limits:** a cap on request size and on calls per minute per client [Đề xuất: 120], so a looping agent cannot keep the app busy.
- **Logs:** tool name and result size with `Log.mcp`; the client's name, queries and IDs with `privacy: .private`; never map content ([privacy.md](privacy.md)).
- **Prompt injection.** A map can hold text written to steer an AI app. The app cannot control the client; read-only tools and proposal-only writes keep the map itself safe. The Settings sheet says that connected apps act on what they read.

## Privacy

| Question | Answer |
| --- | --- |
| Does data leave the Mac? | Yes, when the person connects an AI app and it calls a tool: the app reads the map, and may send it to its provider (Anthropic, OpenAI…) under its own terms. iMCP's README puts it the same way ([iMCP](https://github.com/mattt/iMCP)) |
| Does xDev receive it? | No |
| App Privacy label | *[Inference, not verified]* Stays "Data Not Collected": the developer does not collect it, and it is a transfer the person sets up, as with the share sheet. Recheck with the [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) page before release |
| Privacy manifest | No new required-reason API (Keychain and Network are not on the list); check the helper (option C) carries its own `PrivacyInfo.xcprivacy` *[Inference]* |
| What changes in the docs | Done in MM-46: [privacy.md](privacy.md) has the "AI apps over MCP" row, the privacy policy (`docs/web/privacy-policy.md`) the "AI apps you connect" section, [app-store-readiness.md](app-store-readiness.md) the Review Notes text |

## Dependency

| | Own server in `MindMapMCP` | [Official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) |
| --- | --- | --- |
| Protocol | What we need: `server/discover` and stateless requests (2026-07-28), `initialize` (2025-11-25), `tools/list`, `tools/call`, later `resources/*` | Documents 2025-11-25 as its version; 2026-07-28 support not stated |
| Transport | `NWListener` for HTTP on loopback; stdio in the helper | Stdio, HTTP server transports, Network framework transport |
| Cost | A few hundred lines plus tests *[Inference]*; follows the spec ourselves | A package dependency; ADR 0001 says no outside dependency without a decision |

Decision [Đề xuất]: build our own, as ADR 0008 records. Test against the protocol with the MCP Inspector by hand (a developer tool, not shipped) and with fixtures of real client requests in `swift test`. Revisit the SDK by ADR if the protocol work grows.

## Shared query layer

Built in MM-47 (Q1). The MCP tools and the chat's tools ([chat.md](chat.md)) read maps the same way, so both go through one target, `MindMapQuery` in `MindMapCore` (Domain, Graph, Persistence for the `MapRepository` protocol, Search; no UI, no AI, no network, no logging):

```swift
public struct TopicRef: Hashable, Sendable, Codable { public var mapID: MapID; public var nodeID: NodeID }

public protocol GraphSource: Sendable {          // the open map's live state first, else the store
    func graph(for mapID: MapID) async throws -> GraphState?
    func openMapIDs() async -> Set<MapID>        // default []: maps whose live graph may be ahead of the store
}

public struct MapQueries: Sendable {
    public init(repository: any MapRepository, graphs: any GraphSource)
    public func maps(matching: String?, limit: Int) async throws -> [MapListing]
    public func outline(of mapID: MapID, branch: NodeID?, depth: Int?, includeNotes: Bool, limit: TextLimit) async throws -> OutlineExcerpt
    public func search(_ text: String, in mapID: MapID?, limit: Int) async throws -> [TopicHit]
    public func topic(_ ref: TopicRef) async throws -> TopicDetail?
}
```

| Call | Behaviour |
| --- | --- |
| `maps` | Live maps, most recently edited first; `matching` folds like Find. Topic counts come from `MapRepository.fetchTopicCounts()` (no graph loaded); an open map's title, count and edit time come from its live graph |
| `outline` | Pre-order from the central topic or `branch`, collapsed branches included. `depth` 0 is the start topic alone. Stops at the first topic that does not fit, so the rows are always a prefix of the tree; reports `omittedTopicCount` (cut by the limit) and `deeperTopicCount` (below `depth`). The first topic is always returned, with its note cut (`isNoteCut`) when the note alone is over the limit. Returns structured rows (ID, depth, title, note, child count, `isFloating`): MCP writes them as Markdown with IDs, the chat with handles. The whole map is the main tree, then each floating branch from depth 0 (MCP marks its top "(floating topic)" and `"floating": true`) |
| `search` | `LibrarySearchIndex` over the store's text picks maps, every open map is searched too (its edits may not be saved yet), then `MapFind.matches` on each graph. Title hits before note hits; within each, maps most recently edited first and topics in reading order. Each hit has the path from the central topic and, for a note hit, the note line with most query words (shortened to 160 characters around the match). `in:` a map that is not live throws `mapNotFound` |
| `topic` | Title, note, path, children, tag names, task state, priority, dates, cross-links with direction and label. Nil when the map is not live or the topic does not exist |

- `GraphSource` in the app asks `OpenMaps` first, so a client sees what the editor shows, not an older save. `RepositoryGraphSource` reads only the store (tests, or no open maps). The app's source is built in C1 or M2.
- `TextLimit(budget:perTopic:measure:)` takes the measure from the caller: `.characters(n)` for MCP, `TokenEstimator.estimate` for the chat (passed in from `MindMapAIApple`), so `MindMapQuery` does not import `MindMapAICore`. `perTopic` is the bullet, indentation and the ID or handle the caller adds.
- Recently Deleted maps are never returned. Every call checks the map against `fetchMaps()` as well as `deletedAt`, since an editor's copy of a map may not know the library moved it to Recently Deleted.
- Errors: `MapQueryError.mapNotFound` and `.topicNotFound`; M1 maps both to invalid-params.
- Changed from the design: no dependency on `MindMapInterchange` (the outline is structured rows, not `MarkdownOutline.export` text, so each caller can name topics its own way); `GraphSource.openMapIDs()` added so library search does not miss unsaved edits; `MapRepository.fetchTopicCounts()` added for `list_maps`.

## Server core

Built in MM-40 (M1), in `Packages/MindMapCore/Sources/MindMapMCP`. Protocol pages were reread on 2026-10-02: [changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog), [Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http), [versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning), [server/discover](https://modelcontextprotocol.io/specification/2026-07-28/server/discover), [tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools).

| Type | Role |
| --- | --- |
| `MCPServer` | `handle(HTTPRequest) async -> HTTPResponse`: the checks below, then JSON-RPC. No transport, so tests feed it recorded requests |
| `MCPListener` | `NWListener` bound to `127.0.0.1` with `acceptLocalOnly`; HTTP/1.1 keep-alive, requests on a connection answered in order; `states` stream (`ready(port:)`, `failed`, `stopped`). A taken port is `failed`, never another port |
| `MCPAccess`, `MCPTokenList`, `MCPClient` | Token → client. M2 backs `MCPAccess` with the Keychain; `MCPTokenList` (memory, constant-time compare) is for tests and the dev server. `makeToken()` = 32 bytes from `SecRandomCopyBytes`, base64url (43 characters) |
| `MCPServer.Activity` | Client and tool name per call, for the last-read row and reading indicator (M2). No arguments |
| `mindmap-mcp-dev` | Developer executable, not shipped: three sample maps (en, vi, ja) in an in-memory store, prints the URL, token and `claude mcp add` line |

**Order of checks** (each answers and stops): path not `/mcp` → 404; any `Origin` → 403; `Host` not `127.0.0.1`, `localhost` or `[::1]` → 403 (a DNS-rebinding page names its own host); not POST → 405 `Allow: POST` (no GET stream, no sessions to DELETE); bearer token missing or unknown → 401 `WWW-Authenticate: Bearer`; over the rate → 429 `Retry-After`; not `application/json` → 415; then JSON-RPC (-32700 parse, -32600 batch or not 2.0, `id` null).

**Eras.** A request whose `_meta` has `io.modelcontextprotocol/protocolVersion` (other than a legacy version) is served as 2026-07-28: `MCP-Protocol-Version`, `Mcp-Method` and, for `tools/call`, `Mcp-Name` (base64 sentinel decoded) must match the body, else 400 -32020; an unknown version is 400 -32022 with `supported`; missing `clientCapabilities` is 400 -32602; unknown method 404 -32601; results carry `resultType: "complete"` and `serverInfo` in `_meta`; `tools/list` and `server/discover` carry `ttlMs` 3,600,000 and `cacheScope: "private"`. Anything else is legacy: `initialize` echoes 2025-11-25 or 2025-06-18 when asked, else answers 2025-11-25; later requests need one of those in `MCP-Protocol-Version` (absent means 2025-03-26, refused); `ping`; JSON-RPC errors with HTTP 200. No era mints `Mcp-Session-Id`. Notifications get 202. Replies are always one JSON object, never SSE.

**Limits** [Đề xuất values, in `MCPServer.Configuration`]: body 64 KiB (413 before reading it), headers 16 KiB (431), `Transfer-Encoding` refused (411; every recorded client sends `Content-Length`), 120 requests per client per sliding minute (any method), 20,000 Markdown characters per tool result (`get_map` sizes its outline with `TextLimit.characters`, the rest is cut with a note; `structuredContent` is never cut, so its size follows the tool's own `limit`), 16 connections, 30 s idle.

**Tool output.** Markdown text plus `structuredContent` with snake_case keys (`map_id`, `topic_id`, `topic_count`, `omitted_topic_count`…). `get_map` writes `- Title <!-- topic_id: UUID -->` per topic, two spaces per level, notes indented under it, and ends with "N more topics did not fit…" or "N topics below depth D not shown." No `outputSchema` yet, so clients do not validate the JSON against one. `instructions` tell the model that map text is data, not commands.

**Changed from the design:** errors as `isError` results (above); 2025-06-18 accepted besides 2025-11-25 (mid-2025 clients still ask for it; the four tools use nothing that differs); a `Host` check besides `Origin`; the Markdown is ours, not `MarkdownOutline.export`, because MM-47 returns rows.

**Tests** (`Tests/MindMapMCPTests`, 43): recorded requests replayed through `MCPServer` (`Fixtures/README.md`): Claude Code 2.1.283 on 2026-07-28 (it probes with `server/discover` first), the same client falling back to `initialize` 2025-11-25 when the probe gets an empty 400, and MCP Inspector CLI 2.9.0 (2025-11-25, also sends a GET for a stream). No recording from Cursor or VS Code: neither was installed on the Mac used. Also each check above, both eras, the four tools in Vietnamese and English, Recently Deleted, the limits, the HTTP parser, and a real `URLSession` round trip through `MCPListener` on a free port.

**MCP Inspector run** (2026-10-02, `npx @modelcontextprotocol/inspector --cli http://127.0.0.1:51947/mcp --transport http --header "Authorization: Bearer …"` against `mindmap-mcp-dev`): `tools/list` returned the four tools with their schemas and annotations; `tools/call` for `list_maps`, `search` (`query=thiet ke`: both Vietnamese topics, title hit first), `get_map` (the outline with topic IDs and notes) and `get_topic` (note, subtopics, the cross-link with its label) returned text and structured content, `isError` false. The Inspector CLI speaks 2025-11-25 (seen in its recorded requests). Claude Code 2.1.283 (`claude -p` with an HTTP `--mcp-config`) was also pointed at the dev server, called `list_maps`, `search` and `get_topic`, and answered with the topic's note; which era it used against this server was not logged *[Inference: 2026-07-28, since it probes with `server/discover` and the server answers it]*. curl checks: an `Origin` header gave 403, no token 401, GET 405.

Try it: `swift run --package-path Packages/MindMapCore mindmap-mcp-dev` (optional port argument; token from `MINDMAP_MCP_TOKEN` or printed).

## Helper spike (MM-48)

Run on 2026-10-03 on the Mac mini (macOS 27.0.1, Claude Code 2.1.283) after App Review rejected macOS 1.0.0 under 2.4.5 for `network.server`. The decision that follows from it is [ADR 0013](adr/0013-mcp-helper-over-app-group-socket.md). The code is in `Prototypes/MCPHelperSpike` (not in the app or the package; `build.sh` there, README for re-running). Both binaries are bare executables with an embedded Info.plist, `app-sandbox` and one App Group, and no network entitlement. `server` stands in for the app.

### What was run

| # | Question | Result | How |
| --- | --- | --- | --- |
| 1 | Can a sandboxed helper started by another app run, with stdio? | **Yes.** `APP_SANDBOX_CONTAINER_ID` set, container `~/Library/Containers/<identifier>` created, stdin/stdout pipes usable | Started from a shell and by Claude Code |
| 2 | Can a real MCP client use it? | **Yes.** `claude -p … --mcp-config` with `"command": "<path>/helper"` (stdio) called the tool and printed the text the server sent over the socket. App not running: the client got "Open MindMap AI to let AI apps read your maps." (-32000) and reported it | Claude Code 2.1.283. Claude Desktop is not tested: its window cannot be driven on the shared Mac. *[Inference]* It spawns stdio servers the same way (subprocess, absolute path, per the MCP docs below) |
| 3 | Does the socket need `network.server`/`network.client`? | **No.** `bind`, `listen`, `accept` and `connect` on `AF_UNIX` in the group container work with neither entitlement | `server` and `helper` signed with sandbox + group only |
| 4 | Can a bare executable claim the group without a profile? | **Team-ID-prefixed group: yes** (containermanagerd: "APPROVED. Requestor's signature allows it to access a TCC-protected group container"). **Ad hoc: no** ("REJECTED … Group containers identifiers should be prefixed by requestor's team ID"); `bind` then fails with EPERM | Development certificate of team M6C7NX9MUZ vs `codesign -s -`; group `M6C7NX9MUZ.asia.xdev.mindmapai` |
| 5 | Can other processes reach the socket? | Sandboxed binary with another group: `connect` EPERM. **Unsandboxed process of the same user (python): connects**, although it cannot list the group folder | So the app must check the peer, see 6 |
| 6 | Can the app trust the peer without a token? | **Yes.** `getsockopt(LOCAL_PEERTOKEN)` → `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)` → `SecCodeCheckValidity` with `anchor apple generic and certificate leaf[subject.OU] = "M6C7NX9MUZ" and identifier "<helper id>"`: helper 0, python -67050 (`errSecCSReqFailed`), closed unanswered | In `server.swift`. *[Inference]* App Store re-signing keeps team and identifier, so the same requirement holds |
| 7 | Can a `.mcpb` point at the helper inside the app? | **Schema: yes**, `server.type` `binary` with `mcp_config.command` `/Applications/MindMap AI.app/Contents/Helpers/mindmap-mcp` passes `mcpb validate` (2.1.2); `entry_point` is required, so the bundle must carry some file. **Claude Desktop: not tried** | `npx @anthropic-ai/mcpb validate` |

Gotcha seen: a container made by one signer (ad hoc) and opened by another for the same identifier (development) makes `secinitd` ask the person ("not in ACL for container … prompting"). The process waits inside `_libsecinit_appsandbox` until someone answers. A tester going from a development build to TestFlight may see this once. Store users get one signer.

### Sources

| Claim | Source |
| --- | --- |
| A tool run by something other than the app is signed with `app-sandbox` only (no `inherit`) and needs a bundle ID, for example through "Create Info.plist Section in Binary" | Quinn, [forum 751165](https://developer.apple.com/forums/thread/751165); one tool cannot serve both ways, [forum 75436](https://developer.apple.com/forums/thread/75436) |
| Apple's helper-tool article covers only the child-process case (`app-sandbox` + `inherit`) | [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) |
| Team-ID-prefixed groups need no registration; `group.` IDs need a profile on macOS; on macOS 15+ a group container opens without a prompt when the ID starts with the Team ID, among other cases | [`com.apple.security.application-groups`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups), [App Groups: macOS vs iOS](https://developer.apple.com/forums/thread/721701) |
| A Unix domain socket path must be in the group container, within `SOCK_MAXADDRLEN`; Mach/XPC names use `<group>.<name>` | Same entitlement page; Quinn on sockets in a group container, [forum 788364](https://developer.apple.com/forums/thread/788364); `sun_path` 104 bytes, [forum 756756](https://developer.apple.com/forums/thread/756756) |
| XPC between unrelated processes needs a launchd-registered service (launch agent through `SMAppService`) | [forum 835003](https://developer.apple.com/forums/thread/835003), [forum 99602](https://developer.apple.com/forums/thread/99602) |
| Custom transports over a byte stream reuse the stdio framing | [MCP transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports#custom-transports) |
| Claude Desktop starts configured servers itself, needs absolute paths, logs each server's stderr to `~/Library/Logs/Claude/mcp-server-<name>.log` | [Connect local servers](https://modelcontextprotocol.io/docs/2026-07-28/develop/connect-local-servers) |
| MCPB `server.type` `binary`, `${__dirname}`, `platform_overrides` | [MCPB MANIFEST.md](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md) |
| Another developer's Mac app was rejected for `network.server` with no visible feature (August 2026) | [forum 841526](https://developer.apple.com/forums/thread/841526) |
| An app that tells people to put `/Applications/Muse.app/Contents/MacOS/muse-mcp` in `claude_desktop_config.json` | [Muse](https://www.theodorehq.com/muse/blog/posts/add-mcp-server-claude-desktop). It does not say whether Muse is sold in the Mac App Store |

The forum quotes reached the spike through a summarising fetch. Reread them before quoting them to App Review.

### Answers

- **Helper runs sandboxed when another app starts it:** yes, tested with Claude Code. Claude Desktop [Chưa kiểm chứng].
- **Helper–app without `network.server`/`network.client`:** yes, through a Unix socket in a Team-ID-prefixed App Group, tested.
- **App Review accepts the helper:** [Chưa kiểm chứng]. No Mac App Store app with a sandboxed helper started by other apps was found, and no rejection of one either. Upload validation was not run either, because that needs the helper in the Xcode target (MM-49).
- **HTTP loopback:** drop it from the app (ADR 0013). Every client in [Clients](#clients) speaks stdio, so nothing needs HTTP. Keeping it would keep the entitlement that caused the rejection.
- **`.mcpb`:** possible by schema, not tried in Claude Desktop. Ship the config snippet first.

### MM-49 order

1. Add the helper target (bare tool, `CREATE_INFOPLIST_SECTION_IN_BINARY`, identifier `asia.xdev.mindmapai.mcp`, own entitlements and `PrivacyInfo.xcprivacy`), copied to `Contents/Helpers` and signed. Add `$(TeamIdentifierPrefix)asia.xdev.mindmapai` to the Mac app's groups behind `MINDMAP_MAC_APP_GROUP`. Upload a TestFlight build at once, before the rest: upload validation is the first gate.
2. The product owner installs it from TestFlight, pastes the snippet into Claude Desktop, and checks that `list_maps` answers and that no container prompt appears.
3. Then: the socket listener in the app with the peer check, `MCPServer` behind a transport-neutral entry point, the listener and `ENABLE_INCOMING_NETWORK_CONNECTIONS` removed, Settings ▸ AI Apps with snippets for the helper, Review Notes rewritten.
4. If step 1 or 2 fails because of the bare executable, wrap the helper as `Contents/Helpers/MindMap AI MCP.app` (new bundle ID and profile, `LSBackgroundOnly`) and repeat.

## In the app

Built in MM-46 (M2), Mac only, in `MindMapAI/Features/AIApps`.

| Piece | What it does |
| --- | --- |
| `AIAppsHost` | `@Observable`, one per app (`AppEnvironment.aiApps`), started from `MindMapAIApp.init` on macOS only. Holds the switch (`mcp.enabled`, default off) and port (`mcp.port`, default 51947, 1024–65535; out of range reads as the default) in `AppDefaults`, the connected apps, and the `MCPListener` while the switch is on. Status: Off, Starting…, Ready, Port N Is Unavailable (never another port). Switch and port apply at once; turning off closes the port and keeps the apps |
| `KeychainAIAppClientStore` | One generic password per app (service `asia.xdev.mindmapai.mcp-client`, account = client UUID, generic = name, data = token), `AfterFirstUnlockThisDeviceOnly`, not synchronizable. Data protection keychain first; an ad-hoc local build gets `errSecMissingEntitlement` (-34018) and falls back to the file-based keychain, which returns one item's data at a time. Tokens load into an in-memory `MCPTokenList` at launch, so a request never touches the Keychain. Tests and `-uitest` use `InMemoryAIAppClientStore` |
| `OpenMapsGraphSource` | The app's `GraphSource`: an open map's live `GraphState` from `OpenMaps.liveGraph(for:)`, else the store; `openMapIDs` from `OpenMaps`. The chat (C1) can reuse it |
| `AIAppSetup` | Copy-only snippets, formats read 2026-10-02: Claude Code `claude mcp add --transport http --scope user mindmap-ai <url> --header "Authorization: Bearer …"`; ChatGPT desktop `~/.codex/config.toml` `[mcp_servers.mindmap-ai]` with `url` and `http_headers` (shared with Codex CLI and IDE, per [ChatGPT: MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)); Cursor `~/.cursor/mcp.json` `mcpServers` with `url`, `headers` ([Cursor MCP](https://cursor.com/docs/context/mcp)); VS Code `mcp.json` `servers` with `type: http`, `url`, `headers` ([VS Code MCP configuration](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration)); Other: URL and header |
| `AIAppsSettingsSection` | Switch, Port, Status, Address (while Ready); footer with the privacy text before turning on; Connected Apps with "Read 2 minutes ago" (in memory, from `MCPServer.Activity`) or "Not used since MindMap AI opened", Revoke… (confirmation, since the app's config stops working); Add App… sheet: App picker and Name, then the snippet and token once, Copy, where to paste it |

- Settings ▸ Privacy has an AI Apps row on the Mac: "Off", or "On: apps you connect can read your maps and handle them under their own terms".
- `com.apple.security.network.server` comes from `ENABLE_INCOMING_NETWORK_CONNECTIONS[sdk=macosx*] = YES` (no entitlements file change). There is no `network.client`, so the app's hosted tests send requests to `AIAppsHost.server` directly; the socket round trip stays in the core tests.
- Not built here: the "AI app reading" toolbar indicator and menu items listed for M2 above (the task note keeps the menu bar unchanged); a confirmation sheet when turning the switch on (the footer says it first, per [settings.md](settings.md)); Allow Suggestions (M5).
- Tests: `MindMapAITests/AIAppsTests` (defaults, port range, tokens per app, Revoke → 401, relaunch keeps apps without last read, activity sets last read, Keychain failure, live graph of an open map, switch and port on a real listener, taken port, Keychain round trip, snippet shapes); `MindMapAIUITests/AIAppsSettingsUITests` (Mac: off by default, Ready at once, Privacy row; iOS: no AI Apps pane).

## Proposed tasks

For the leader to create; the names are placeholders.

| | Task | Done when | Depends on |
| --- | --- | --- | --- |
| Q1 | Query layer `MindMapQuery` ✓ MM-47 | `MapQueries` and `TopicRef` as above; Vietnamese and English tests for search (diacritics, đ), outline limits, deleted maps left out, live state preferred; docs updated | MM-15, MM-31 (done) |
| M1 | MCP server core `MindMapMCP` ✓ MM-40 | JSON-RPC for 2026-07-28 and 2025-11-25; the four read tools; Streamable HTTP on loopback with token and `Origin` checks; size and rate limits; tests with recorded requests from Claude Code, Cursor and VS Code; MCP Inspector run noted | Q1 |
| M2 | MCP in the Mac app ✓ MM-46 (no indicator or menu items, see [In the app](#in-the-app)) | Settings ▸ AI Apps (off by default), clients and Keychain tokens, copy snippets for Claude Code, ChatGPT desktop (Codex config), Cursor and VS Code; reading indicator; menu items; `network.server`; privacy.md, privacy policy, Review Notes; en and vi; UI test for the switch | M1 |
| M3 | Spike: helper in the Mac App Store ✓ MM-48 (no TestFlight build, see [Helper spike](#helper-spike-mm-48)) | A sandboxed `mindmap-mcp` relay in `Contents/Helpers`, launched by Claude Desktop from a TestFlight build; answer whether App Review and signing accept it, and whether a `.mcpb` can point at it. Ship it (M4) only if yes | M2 |
| M4 | AI Apps through the helper (MM-49, ADR 0013) | Steps in [MM-49 order](#mm-49-order): TestFlight upload with the helper first, then the App Group socket with the peer check, the HTTP listener and `network.server` removed, snippets for every client, Review Notes | M3 |
| M5 | MCP proposals | `propose_topics`, suggestions labelled with the client's name, Accept as one command with undo and redo tests, nothing edited or deleted through MCP | M2, C2 ([chat.md](chat.md)) |
