# Recorded MCP requests

Each `.jsonl` line is one HTTP request a real client sent: method, path, headers and body. They were recorded on 2026-10-02 with a small Python server on 127.0.0.1 that logged every request and gave minimal answers, so the client went through its whole flow (probe, handshake, list tools, one `list_maps` call).

| File | Client | How |
| --- | --- | --- |
| `claude-code-2.1.283-2026-07-28.jsonl` | Claude Code 2.1.283 | `claude -p … --mcp-config` with `"type": "http"` and an `Authorization` header; the recorder answered `server/discover`, so the client stayed on 2026-07-28 |
| `claude-code-2.1.283-2025-11-25.jsonl` | Claude Code 2.1.283 | Same, but the recorder answered the modern probe with an empty 400, so the client fell back to `initialize` (2025-11-25) |
| `mcp-inspector-cli-2.9.0-2025-11-25.jsonl` | MCP Inspector CLI 2.9.0 | `npx @modelcontextprotocol/inspector --cli <url> --transport http --header … --method tools/call --tool-name list_maps --tool-arg limit=5` |

The token in them, `test-token-0123`, was made up for the recording. Cursor and VS Code were not installed on the recording Mac, so there is no fixture from them yet; record one the same way before relying on them.
