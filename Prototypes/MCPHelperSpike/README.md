# MCP helper spike (MM-48)

Throwaway code for [ADR 0013](../../docs/adr/0013-mcp-helper-over-app-group-socket.md). It is not part of the app, the package or `scripts/ci.sh`. Results are in [docs/mcp.md, *Helper spike*](../../docs/mcp.md#helper-spike-mm-48).

- `helper.swift` is the `mindmap-mcp` relay. It copies stdio to the socket in the App Group container, and answers with "Open MindMap AI…" when no app is listening.
- `server.swift` stands in for the app. It listens on that socket, checks the peer's code signature, and answers MCP 2025-11-25 with one stub tool.
- `build.sh` builds both into `out/` with `app-sandbox`, one App Group, an embedded Info.plist and no network entitlement.

```bash
# Team-signed: the group works. Ad hoc (IDENTITY unset): containermanagerd refuses the group.
security unlock-keychain -p "$(cat ~/.appstoreconnect/signing/keychain.pass)" ~/Library/Keychains/mindmap-build.keychain-db
SPIKE_PREFIX=spike2 IDENTITY="Apple Development: Created via API (9HJU7NZ93L)" ./build.sh
./out/server &                       # stand-in app
mkdir -p logs && echo '{"mcpServers":{"mindmap":{"command":"'$PWD'/out/helper"}}}' > logs/cfg.json
claude -p "Call list_maps on the mindmap server" --mcp-config logs/cfg.json --strict-mcp-config \
  --allowedTools mcp__mindmap__list_maps --model haiku < /dev/null
```

Use a new `SPIKE_PREFIX` whenever you change `IDENTITY`. A container created under one signer and opened by another makes macOS show a prompt and hold the process until someone answers it.
