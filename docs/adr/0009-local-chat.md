# ADR 0009: Chat on the device, through tools

- Status: proposed (MM-39); the product owner accepts or changes the items marked [Đề xuất] in [chat.md](../chat.md)
- Date: 2026-10-02
- Relates to: ADR 0001 (Foundation Models on the device), ADR 0003 (commands with recorded undo), ADR 0008 (shared query layer)

## Context

People asked (2026-10-02) for a chat inside the app that answers questions about their maps. The only model the app uses is Foundation Models on the device, with a context of about 4,096 tokens on current hardware ([on-device-ai.md](../on-device-ai.md)). A map often holds more text than that, and Private Cloud Compute or third-party models, which have larger windows, send the content to a server.

## Decision

1. **On-device only.** The chat uses `SystemLanguageModel.default`, the same capability checks as the other AI features, and is hidden where they are hidden (ineligible devices, every x86_64 build).
2. **Tools, not the whole map.** The model searches and reads topics through a few `Tool`s over `MindMapQuery`; tool output and older turns are cut to a token budget read from `contextSize`.
3. **Citations are checked.** Answers cite short topic handles; only handles a tool returned become links, and a link opens the map at the topic.
4. **Edits are suggestions.** In a map, the chat can suggest topics into the existing `SuggestionState`; Accept is one command with one undo step. The chat never renames, moves or deletes.
5. **Not saved [Đề xuất].** The conversation lives with the open map or library window and is never written to the store.
6. **Scopes [Đề xuất].** Ask in a map is free; Ask across the library is Pro.

## Consequences

- Answers are limited to what fits in a few tool results; questions that need the whole library at once ("compare all my maps") get partial answers and say so.
- No schema change; saving conversations later would need SchemaV3 and its own decision.
- Prompt and tool changes need the Evaluations suite, since answer quality cannot be unit tested.
- Nothing leaves the device, so the privacy label and policy do not change for the chat.
