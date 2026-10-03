# ADR 0013: AI Apps through a stdio helper and an App Group socket, no network entitlement

- Status: proposed (MM-48 spike); the product owner accepts it before MM-49 builds it
- Date: 2026-10-03
- Amends: ADR 0008 (decisions 1–3 and the `network.server` consequence)
- Relates to: ADR 0001 (no backend), ADR 0006 (macOS first)

## Context

App Review rejected macOS 1.0.0 on 2026-10-03 under guideline 2.4.5. The reason was the `com.apple.security.network.server` entitlement: the automated scan found no feature that uses it, because AI Apps listens only on `127.0.0.1` and is off by default. The product owner set a goal for 1.1: AI Apps works without `network.server`. Every client the app supports (Claude Desktop, Claude Code, ChatGPT desktop/Codex, Cursor, VS Code) can start a local MCP server as a subprocess over stdio ([mcp.md](../mcp.md#clients)).

The MM-48 spike built a sandboxed helper and a sandboxed stand-in for the app, and ran them on macOS 27.0.1 with the team's development certificate. Results and sources are in [mcp.md, *Helper spike*](../mcp.md#helper-spike-mm-48).

## Decision

1. **AI Apps reaches clients only through the helper.** `Contents/Helpers/mindmap-mcp` is a bare executable with its Info.plist embedded (`CREATE_INFOPLIST_SECTION_IN_BINARY`), signing identifier `asia.xdev.mindmapai.mcp`. It is signed with `app-sandbox` and the App Group, has no `inherit` and no network entitlement. Clients start it over stdio. It copies newline-delimited JSON-RPC between stdio and the app, and does nothing else.
2. **Helper and app talk over a Unix domain socket** in the App Group container (`~/Library/Group Containers/<group>/mcp.sock`), using the stdio framing that the MCP spec recommends for custom transports. Neither process has `network.server` or `network.client`. XPC is not used: a Mach service needs a launchd job (a launch agent through `SMAppService`), which is a background item the person did not start (2.4.5(iii)).
3. **The group is the macOS-style `$(TeamIdentifierPrefix)asia.xdev.mindmapai`**, added to the Mac app next to `group.asia.xdev.mindmapai` and claimed by the helper. A bare executable cannot embed a provisioning profile, so it cannot claim the iOS-style ID. A Team-ID-prefixed ID needs no profile and no registration.
4. **No token.** Before answering, the app checks who is on the other end of the socket. It takes the peer's audit token (`LOCAL_PEERTOKEN`) and checks the code against the requirement `anchor apple generic and certificate leaf[subject.OU] = "M6C7NX9MUZ" and identifier "asia.xdev.mindmapai.mcp"`. Anything else is closed unanswered. The sandbox already keeps out sandboxed apps that lack the group. The check is needed because unsandboxed processes of the same user can still connect.
5. **Drop the HTTP loopback listener from the app** in the same release that ships the helper, and with it `ENABLE_INCOMING_NETWORK_CONNECTIONS`. All supported clients speak stdio. macOS 1.0.0 was resubmitted with the same build, so if it is approved, some people will have HTTP configs from 1.0. The first time 1.1 opens with AI Apps on, Settings ▸ AI Apps says once that the old address no longer works and shows the new snippet. `MCPServer` keeps its JSON-RPC core behind a transport-neutral entry point. The HTTP code stays only for `mindmap-mcp-dev` and the core tests.
6. **App closed:** the helper answers every request with the JSON-RPC error "Open MindMap AI to let AI apps read your maps." It never launches the app.

## Consequences

- No `network.server` and no `network.client` in the Mac app. The rejection reason goes away *[Inference: App Review cites only that entitlement]*.
- Settings ▸ AI Apps shows one copyable config per client, all pointing at `/Applications/MindMap AI.app/Contents/Helpers/mindmap-mcp`. There is no port, no token and no Revoke per client. Off is the switch. The app learns which client is connected from `clientInfo` in `initialize`, which the client reports about itself. Whether to ask on first use per client (as iMCP does) is open [Đề xuất: no prompt in 1.1, the switch is the consent].
- The helper is a second sandboxed executable with its own container (`~/Library/Containers/asia.xdev.mindmapai.mcp`). It needs its own `PrivacyInfo.xcprivacy` *[Inference]*. Changing its signer for the same identifier (development → TestFlight) makes macOS ask about the container once (seen in the spike).
- Builds signed ad hoc (`scripts/ci.sh`) cannot use the group. containermanagerd refuses it ("Group containers identifiers should be prefixed by requestor's team ID"). Tests therefore run the socket path outside the sandbox in `swift test`, and the app keeps the group behind `MINDMAP_MAC_APP_GROUP`.
- Still not verified: whether App Store Connect upload validation and App Review accept a sandboxed bare helper that another app launches. No Mac App Store precedent was found. The answer comes from the first TestFlight build with the helper (MM-49 step 1). If the bare helper is refused, the fallback is an app-like wrapper `Contents/Helpers/MindMap AI MCP.app` with its own bundle ID and profile (Apple's advice for executables that claim groups). Clients then point at `…/MindMap AI MCP.app/Contents/MacOS/mindmap-mcp`.
- A `.mcpb` must ship a file as `entry_point` (mcpb 2.1.2 validation). Its `mcp_config.command` may be an absolute path into the app bundle and still validate. Whether Claude Desktop runs it has not been tried, so 1.1 offers the `claude_desktop_config.json` snippet first.
