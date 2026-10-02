# AI architecture

Status: the foundation (MM-7) is in `MindMapAICore`, `MindMapAIApple` and `MindMapTestSupport`: provider protocol, capabilities, context builder, proposal translator, Foundation Models provider, prompt catalog and mock. The AI tasks (MM-8) add streaming, `SuggestionState` and the app side in `MindMapAI/Features/AI` (see [In the app](#in-the-app)). What the platform offers, per OS and device, is in [on-device-ai.md](on-device-ai.md).

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
    func capabilities() async -> AICapabilities
    func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal
    func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal
    func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal
    func rewrite(_ request: RewriteRequest) async throws -> AIRewrite
    func summarize(_ request: SummarizeRequest) async throws -> AISummary
    func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal
    func streamSuggestions(_ request: SuggestionRequest) -> AsyncThrowingStream<ProposalSnapshot, any Error>
}
```

`streamSuggestions` covers the four requests that return topics (`SuggestionRequest`: generate, expand, brainstorm, missing topics). It yields partial proposals as the model writes them and ends with one complete snapshot that passed the translator's checks and the request's limit; partial ones are for display only. A protocol extension gives every provider a default that runs the one-shot method and yields once; the Apple provider streams with `streamResponse(to:generating:)`, turning each `PartiallyGenerated` value into a proposal (a topic shows once its title has started; a tree topic's IDs come first in the schema, so they are complete by then). Cancelling the consuming task cancels the request; a cancelled stream ends rather than throwing.

- `AppleFoundationModelProvider` is the first and only implementation: on-device, private, no token, no xDev billing. It lives in `MindMapAIApple`; the protocol and value types live in `MindMapAICore`, which never imports FoundationModels ([module-structure.md](module-structure.md)).
- Private Cloud Compute is not used: it runs on Apple's servers, which the privacy promise rules out.
- Requests throw `AIError` (or `CancellationError` when their task is cancelled): `unavailable(AIAvailability)`, `guardrailViolation`, `refusal`, `contextSizeExceeded`, `unsupportedLanguage`, `rateLimited`, `invalidResponse(ProposalError)`, `generationFailed`. Logs carry the feature and `AIError.logName` only, never prompts or answers.
- Each request opens its own `LanguageModelSession`, so nothing loads before first use and one request never fills the next one's context window. Rewrite and summarize use `.permissiveContentTransformations` guardrails, since they transform the person's own text; the others keep the default guardrails.
- `MockAIProvider` (in `MindMapTestSupport`) drives tests: answers queued per feature (proposals, rewrites, summaries, `AIError`s), capability checks like the real provider, and a record of every request.
- Cloud providers (OpenAI, Anthropic, Gemini) are not built unless requested. If one is ever added, the request shows which provider processes it.

## Structured output

Generated types use `@Generable` so the model returns typed values instead of Markdown to parse:

```swift
@Generable struct GeneratedMindMap { var title: String; var topics: [GeneratedTreeTopic] }
@Generable struct GeneratedTreeTopic { var temporaryID: String; var parentTemporaryID: String; var title: String }
@Generable struct GeneratedTopicList { var topics: [GeneratedTopic] }   // expand, brainstorm, missing topics
@Generable struct GeneratedRewrites { var titles: [String] }
```

A generated map is a flat list with parent IDs (an empty parent means a main topic); suggestions for one topic are a flat list. Arrays are capped with `@Guide(.maximumCount)` at the values of `AIProposalLimits` (30 topics for a map, 12 suggestions, 3 rewrites). MM-8 kept those caps and asks for fewer per request (`AIRequestDefaults`: 20 topics for a map, 6 subtopics, 8 ideas, 5 missing topics) [Đề xuất], so the first topics stream in quickly on the 4,096-token model; retune after measuring NFR-PERF-07 on a device. Summaries are plain text.

`ProposalTranslator` checks a proposal before anything else sees it: temporary IDs not empty and unique, titles not empty, parents present, no loops (a topic not reachable from the top level is on a loop). It then orders topics parents first, builds one `BatchCommand` of `AddNodeCommand`s with `metadata.origin = .ai`, and runs it on a copy of the `GraphEngine` (a value type) so the editor's graph and undo history are untouched until the person accepts. Accepting some topics also takes their proposed parents. A rewrite becomes an `UpdateNodeCommand` for the title; a summary is appended to the note (after a blank line, keeping what the person wrote) only when the person chooses it. The provider runs the same checks before returning, so a malformed answer arrives as `AIError.invalidResponse`, and keeps no more topics than the request asked for (`ProposalTranslator.limited`, level by level, so main topics go before details).

## Capability

`AICapabilities` holds the model state (`ready`, `deviceNotEligible`, `appleIntelligenceOff`, `modelDownloading`, `unknown`), the supported languages and `contextSize`. `availability(for:in:)` answers per feature and language, adding `languageUnsupported`. `showsAIEntryPoints` is false only for `deviceNotEligible`: the UI hides AI there and explains the other states in one line. The rest of the app does not depend on it. The app asks again when it becomes active; the model loads on first use, never at launch.

An x86_64 build reports `.notEligible` without asking the framework, so an Intel Mac, or the Intel slice under Rosetta, never shows AI (MM-21). `contextSize` is read on 26.4 and later; before that the provider assumes 4,096. Vietnamese dictation, translation and OCR are not part of `AICapabilities` yet: they come with the tasks that use them (MM-20 and later).

## Context and language

`AIContextBuilder` builds the context on purpose and bounded, never the whole map: map title, focus topic (with its note), ancestors (root first; a long path keeps the root and the nearest levels), children, siblings, deeper descendants up to a depth limit, and cross-linked topics, in that priority. The descendant walk stops at the first topic that does not fit, so what is sent is always a prefix of the branch by level, and `omittedDescendantCount` says how much was left out. Titles and notes become one trimmed line with a length cap.

The budget comes from `contextSize`: the topic text gets 40% of the window [Đề xuất], the rest is for instructions, schema and answer. The on-device model has about 4,096 tokens, and Vietnamese costs roughly one token per character, so `TokenEstimator` counts any text with a non-ASCII character at one token per character and plain ASCII at three characters per token, both on the high side *[Inference]*. A branch too large for one request is split by `chunkContexts` into contexts that each fit; MM-8 summarizes each chunk and combines the parts with `SummarizeRequest.partialSummaries`.

Instructions are in English, fixed per feature, name the user's locale and end with "You MUST respond in Vietnamese." (or English); they keep mixed-language content as written ("Thiết kế backend architecture cho HIS sử dụng .NET"). The person's text only goes in the prompt, never in the instructions. `PromptCatalog` holds every instruction and prompt, versioned by `PromptVersion` (26.0, 26.4, 27.0, picked from the running OS); all three share one text until an evaluation shows a generation needs its own.

## Suggestion state

Suggested nodes live in a separate `SuggestionState` (`MindMapAICore`), not in `GraphState`, so nothing the model writes reaches the map, its undo history or the store before Accept. It:

- follows the stream (`update(with:)`), keeping only topics reached from the top level, so a partial answer whose parent is not written yet, a repeated ID or a loop waits or drops out; each suggestion keeps a stable preview `NodeID` while it streams;
- keeps the person's edits: renamed titles and removed topics (with their suggested subtopics) survive later snapshots;
- draws: `preview(in:)` adds every suggestion to a copy of the engine as `AddNodeCommand`s (origin `.ai`) and returns the copy's state, leaving out suggestions whose anchor was deleted or un-done;
- accepts: `accept(_:in:)` goes through `ProposalTranslator.accept` per anchor and joins the commands into one `BatchCommand`, dry-run on a copy. Accepting part of a generated tree re-anchors the remaining children under the real topic their parent became (`didAccept`).

Accepting is one command named "Add AI Topics", so it is one undo step; the resulting nodes keep `metadata.origin = .ai`.

## In the app

`MindMapAI/Features/AI`:

| Type | Role |
| --- | --- |
| `AIService` | One per app (environment), shared by windows and Settings. Makes the provider on first use, holds `AICapabilities`, asks again when the app becomes active and every 30 s while the model downloads. `showsEntryPoints` is false until the first check, so an Intel Mac never flashes AI. |
| `AIAssistant` | One per open map, next to `EditorSession` and `CanvasModel`. Builds the context, runs one request at a time in a `Task` (cancel with ⌘. or the bar's Cancel; the map stays editable), owns the `SuggestionState`, and applies accepted work through `EditorSession.perform` with a name: "Add AI Topics", "Rewrite Topic", "Add Summary to Note". A generated map that lands in a map with only its central topic also renames the map and the central topic in the same batch. |
| `AIFailure` | Maps `AIError` to one message with a way forward (FR-AI-14). A refused Generate Map or Brainstorm offers Edit Request…, reopening the sheet with the text typed; the app never rewrites a request itself. |
| `ProEntitlements` | The hook for Pro features (long map descriptions over 280 characters [Đề xuất], summarizing from the central topic, find missing topics). `ProEntitlement` (StoreKit 2, MM-13) conforms and is passed in by the app; the cases come from the one `ProFeature` list. |

Entry points: the toolbar `sparkles` menu, the AI button in the floating canvas controls, the AI menu in the menu bar (with shortcuts, hidden on ineligible devices, one line of why otherwise), the topic context menu on the canvas, and New Map with AI…, which makes a map and opens it on the Generate Map sheet. Rewrite and Summary results open in a sheet; the summary goes into the note only with Add to Note. The first request shows a one-time notice that AI runs on the device and nothing goes to xDev (FR-AI-19); Settings has an AI section with the model state and a Privacy row.

The canvas draws suggestions by laying out the preview graph instead of the map's graph (a full layout while suggestions exist), with `CanvasTopic.isSuggestion` picking the suggestion style. Selecting a suggestion sets `AIAssistant.selectedSuggestion`, not the map's selection; editing its title in place renames the suggestion. The first suggestion's arrival time is logged (`Log.ai`, no content) for NFR-PERF-07.
