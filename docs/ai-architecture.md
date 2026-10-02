# AI architecture

Status: planned for Phases 7 and 8. Nothing here is implemented yet; this is the design those phases follow. What the platform offers, per OS and device, is in [on-device-ai.md](on-device-ai.md).

## Flow

```
User request on a selection
  ─▶ AIContextBuilder        selected node, ancestors, bounded descendants, nearby edges, map title, language
  ─▶ AIProvider              structured output (Foundation Models guided generation)
  ─▶ AIProposal              temporary IDs, never persisted
  ─▶ ProposalTranslator      → [GraphCommand]
  ─▶ GraphEngine dry run     validation on a copy
  ─▶ Preview                 suggested nodes on the canvas: Accept all, accept one, reject
  ─▶ GraphEngine.execute     one BatchCommand per accepted set, one undo step
```

The model never mutates the graph or storage. A proposal that fails validation is dropped with a calm message.

## Provider abstraction

```swift
protocol AIProvider: Sendable {
    var availability: AIAvailability { get }
    func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal
    func expandNode(_ request: ExpandNodeRequest) async throws -> AIProposal
    func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal
    func rewrite(_ request: RewriteRequest) async throws -> AIRewrite
    func summarize(_ request: SummarizeRequest) async throws -> AISummary
    func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal
}
```

- `AppleFoundationModelProvider` is the first and only implementation: on-device, private, no token, no xDev billing. It lives in `MindMapAIApple`; the protocol and value types live in `MindMapAICore`, which never imports FoundationModels ([module-structure.md](module-structure.md)).
- Private Cloud Compute is not used: it runs on Apple's servers, which the privacy promise rules out.
- `MockAIProvider` drives tests: structured responses, invalid responses, validation failures.
- Cloud providers (OpenAI, Anthropic, Gemini) are not built unless requested. If one is ever added, the request shows which provider processes it.

## Structured output

Generated types use `@Generable` so the model returns typed values instead of Markdown to parse:

```swift
@Generable struct GeneratedMindMap { var title: String; var nodes: [GeneratedNode] }
@Generable struct GeneratedNode { var temporaryID: String; var title: String; var parentTemporaryID: String? }
```

The translator checks temporary IDs (unique, parents exist, no loops) before producing commands.

## Capability

`AICapabilities` reports, per feature: model ready, language unsupported, device not eligible, Apple Intelligence off, or model downloading; plus the context size, Vietnamese dictation, translation and OCR. The UI hides or disables AI entry points with one line of explanation. The rest of the app does not depend on it. Capabilities are checked again when the app becomes active; models load on first use, never at launch.

## Context and language

Context is built on purpose and bounded (depth and node limits), never the whole map. The on-device model has about 4,096 tokens (read `contextSize`), and Vietnamese costs roughly one token per character, so the budget is tight. Instructions are in English, name the user's locale and the output language, and keep mixed-language content as written ("Thiết kế backend architecture cho HIS sử dụng .NET"). Prompts are versioned per model generation.

## Suggestion state

Suggested nodes live in a separate `SuggestionState`, not in `GraphState`. Accepting turns them into commands; the resulting nodes keep `metadata.origin = .ai`.
