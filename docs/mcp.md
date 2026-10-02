# MCP server: AI apps read your maps

Design for MM-39, 2026-10-02. The shared query layer (MM-47) and the server core `MindMapMCP` (MM-40, [Server core](#server-core)) are built; the app does not host the server yet (M2). Decisions are in [ADR 0008](adr/0008-mcp-server.md); the in-app chat that shares the query layer is in [chat.md](chat.md). Items marked [Đề xuất] are proposals waiting for the product owner. *[Inference]* marks reasoning that no source states. Sources were read on 2026-10-02; recheck them before building, since the protocol and the clients change every few months.

## Summary

- **What:** a Model Context Protocol (MCP) server inside the Mac app, so AI apps the person already uses (Claude Desktop, Claude Code, ChatGPT desktop, Cursor, VS Code) can list, read and search their maps. Mac only: no iPad or iPhone client launches or reaches a local server *[Inference]*.
- **Transport [Đề xuất]:** first, the app itself serves Streamable HTTP on `127.0.0.1` while it runs, with a token per client. Second, a small stdio helper in the app bundle that only relays to the running app, for clients that speak stdio only (Claude Desktop). No helper reads the store, and nothing is remote: there is no backend (ADR 0001).
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

Decision [Đề xuất]: **A first, then C.** B is rejected. When the app is not running, the helper answers with an error that says "Open MindMap AI to let AI apps read your maps" rather than launching it; 2.4.5(iii) forbids processes the person did not start, and a helper that opens the app is close to that *[Inference]*.

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

*[Inference, not verified]* A sandboxed helper that another app launches is unusual in the Mac App Store; build a TestFlight build with it before relying on option C (task M4 below).

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
| Privacy manifest | No new required-reason API expected; check the helper (option C) carries its own `PrivacyInfo.xcprivacy` *[Inference]* |
| What changes in the docs | [privacy.md](privacy.md) gets an "AI apps (MCP)" row when the feature ships; the privacy policy (`docs/web/privacy-policy.md`) says that a connected AI app can read maps and is responsible for what it sends. Done in the task that ships the switch (M2) |

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
| `outline` | Pre-order from the central topic or `branch`, collapsed branches included. `depth` 0 is the start topic alone. Stops at the first topic that does not fit, so the rows are always a prefix of the tree; reports `omittedTopicCount` (cut by the limit) and `deeperTopicCount` (below `depth`). The first topic is always returned, with its note cut (`isNoteCut`) when the note alone is over the limit. Returns structured rows (ID, depth, title, note, child count): MCP writes them as Markdown with IDs, the chat with handles |
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
| `mindmap-mcp-dev` | Developer executable, not shipped: two sample maps in an in-memory store, prints the URL, token and `claude mcp add` line |

**Order of checks** (each answers and stops): path not `/mcp` → 404; any `Origin` → 403; `Host` not `127.0.0.1`, `localhost` or `[::1]` → 403 (a DNS-rebinding page names its own host); not POST → 405 `Allow: POST` (no GET stream, no sessions to DELETE); bearer token missing or unknown → 401 `WWW-Authenticate: Bearer`; over the rate → 429 `Retry-After`; not `application/json` → 415; then JSON-RPC (-32700 parse, -32600 batch or not 2.0, `id` null).

**Eras.** A request whose `_meta` has `io.modelcontextprotocol/protocolVersion` (other than a legacy version) is served as 2026-07-28: `MCP-Protocol-Version`, `Mcp-Method` and, for `tools/call`, `Mcp-Name` (base64 sentinel decoded) must match the body, else 400 -32020; an unknown version is 400 -32022 with `supported`; missing `clientCapabilities` is 400 -32602; unknown method 404 -32601; results carry `resultType: "complete"` and `serverInfo` in `_meta`; `tools/list` and `server/discover` carry `ttlMs` 3,600,000 and `cacheScope: "private"`. Anything else is legacy: `initialize` echoes 2025-11-25 or 2025-06-18 when asked, else answers 2025-11-25; later requests need one of those in `MCP-Protocol-Version` (absent means 2025-03-26, refused); `ping`; JSON-RPC errors with HTTP 200. No era mints `Mcp-Session-Id`. Notifications get 202. Replies are always one JSON object, never SSE.

**Limits** [Đề xuất values, in `MCPServer.Configuration`]: body 64 KiB (413 before reading it), headers 16 KiB (431), `Transfer-Encoding` refused (411; every recorded client sends `Content-Length`), 120 requests per client per sliding minute (any method), 20,000 Markdown characters per tool result (`get_map` sizes its outline with `TextLimit.characters`, the rest is cut with a note; `structuredContent` is never cut, so its size follows the tool's own `limit`), 16 connections, 30 s idle.

**Tool output.** Markdown text plus `structuredContent` with snake_case keys (`map_id`, `topic_id`, `topic_count`, `omitted_topic_count`…). `get_map` writes `- Title <!-- topic_id: UUID -->` per topic, two spaces per level, notes indented under it, and ends with "N more topics did not fit…" or "N topics below depth D not shown." No `outputSchema` yet, so clients do not validate the JSON against one. `instructions` tell the model that map text is data, not commands.

**Changed from the design:** errors as `isError` results (above); 2025-06-18 accepted besides 2025-11-25 (mid-2025 clients still ask for it; the four tools use nothing that differs); a `Host` check besides `Origin`; the Markdown is ours, not `MarkdownOutline.export`, because MM-47 returns rows.

**Tests** (`Tests/MindMapMCPTests`, 43): recorded requests replayed through `MCPServer` (`Fixtures/README.md`): Claude Code 2.1.283 on 2026-07-28 (it probes with `server/discover` first), the same client falling back to `initialize` 2025-11-25 when the probe gets an empty 400, and MCP Inspector CLI 2.9.0 (2025-11-25, also sends a GET for a stream). No recording from Cursor or VS Code: neither was installed on the Mac used. Also each check above, both eras, the four tools in Vietnamese and English, Recently Deleted, the limits, the HTTP parser, and a real `URLSession` round trip through `MCPListener` on a free port.

**MCP Inspector run** (2026-10-02, `npx @modelcontextprotocol/inspector --cli http://127.0.0.1:51947/mcp --transport http --header "Authorization: Bearer …"` against `mindmap-mcp-dev`): `tools/list` returned the four tools with their schemas and annotations; `tools/call` for `list_maps`, `search` (`query=thiet ke`: both Vietnamese topics, title hit first), `get_map` (the outline with topic IDs and notes) and `get_topic` (note, subtopics, the cross-link with its label) returned text and structured content, `isError` false. The Inspector CLI speaks 2025-11-25 (seen in its recorded requests). Claude Code 2.1.283 (`claude -p` with an HTTP `--mcp-config`) was also pointed at the dev server, called `list_maps`, `search` and `get_topic`, and answered with the topic's note; which era it used against this server was not logged *[Inference: 2026-07-28, since it probes with `server/discover` and the server answers it]*. curl checks: an `Origin` header gave 403, no token 401, GET 405.

Try it: `swift run --package-path Packages/MindMapCore mindmap-mcp-dev` (optional port argument; token from `MINDMAP_MCP_TOKEN` or printed).

## Proposed tasks

For the leader to create; the names are placeholders.

| | Task | Done when | Depends on |
| --- | --- | --- | --- |
| Q1 | Query layer `MindMapQuery` ✓ MM-47 | `MapQueries` and `TopicRef` as above; Vietnamese and English tests for search (diacritics, đ), outline limits, deleted maps left out, live state preferred; docs updated | MM-15, MM-31 (done) |
| M1 | MCP server core `MindMapMCP` ✓ MM-40 | JSON-RPC for 2026-07-28 and 2025-11-25; the four read tools; Streamable HTTP on loopback with token and `Origin` checks; size and rate limits; tests with recorded requests from Claude Code, Cursor and VS Code; MCP Inspector run noted | Q1 |
| M2 | MCP in the Mac app | Settings ▸ AI Apps (off by default), clients and Keychain tokens, copy snippets for Claude Code, ChatGPT desktop (Codex config), Cursor and VS Code; reading indicator; menu items; `network.server`; privacy.md, privacy policy, Review Notes; en and vi; UI test for the switch | M1 |
| M3 | Spike: helper in the Mac App Store | A sandboxed `mindmap-mcp` relay in `Contents/Helpers`, launched by Claude Desktop from a TestFlight build; answer whether App Review and signing accept it, and whether a `.mcpb` can point at it. Ship it (M4) only if yes | M2 |
| M4 | Claude Desktop through the helper | Helper relays stdio to the app, clear error when the app is closed, own privacy manifest, config snippet or `.mcpb` | M3 |
| M5 | MCP proposals | `propose_topics`, suggestions labelled with the client's name, Accept as one command with undo and redo tests, nothing edited or deleted through MCP | M2, C2 ([chat.md](chat.md)) |
