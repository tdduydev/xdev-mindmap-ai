# Chat: ask about your maps, on the device

Design for MM-39, 2026-10-02. Ask in a map (C1) is built in MM-41; [What C1 built](#what-c1-built) lists the types and where it differs from this design. Decisions are in [ADR 0009](adr/0009-local-chat.md). The chat reads maps through the same query layer as the MCP server ([mcp.md](mcp.md#shared-query-layer)). [Đề xuất] marks proposals waiting for the product owner; *[Inference]* marks reasoning no source states. API names from WWDC26 come from the session pages and are not yet checked with the compiler.

## Summary

- **Model:** Foundation Models on the device (`SystemLanguageModel.default`) only. No Private Cloud Compute, no third-party model, as for every AI feature (ADR 0001, [ai-architecture.md](ai-architecture.md)).
- **Small context, so tools:** the model gets 4,096 tokens on the development Mac ([on-device-ai.md](on-device-ai.md)), so it never sees the whole map. It calls tools that search and read topics, and answers from what they return.
- **Two scopes:** Ask in one map (from the editor, free) and Ask across the library (from the library, Pro; decided 2026-10-02).
- **Citations:** each answer names the topics it used; clicking one opens the map at that topic.
- **Edits are suggestions:** in a map, the chat can suggest topics; they appear as AI suggestions on the canvas and Accept is one command, one undo step.
- **Saved per map (decided 2026-10-02, MM-55):** each map keeps its conversation in the store, deleted with the map and when the person clears it; it is map content, so it is never logged and syncs only with the map. The first chat release (MM-41) may keep it in memory until MM-55 lands.
- **Hidden where AI is hidden:** same `AICapabilities` as the other AI features, so an Intel Mac or an ineligible device never shows it (MM-21).

## Model and context

| Fact | Source |
| --- | --- |
| The development Mac's on-device model has a 4,096-token context; a WWDC26 sample prints 8,192. Read `contextSize`, never hard-code it | [on-device-ai.md](on-device-ai.md), [What's new in Foundation Models (WWDC26 241)](https://developer.apple.com/videos/play/wwdc2026/241/) |
| 27 adds `tokenCount(for:)` and per-response usage (`response.usage`) | [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/) |
| `PrivateCloudComputeLanguageModel` has a 32K context, and Anthropic and Google ship Swift packages for the same session API | [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/) |
| A `LanguageModelSession` keeps its transcript between calls: one session per conversation | [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) |
| Tools conform to `Tool` with `@Generable` arguments and `call(arguments:)`; Apple advises 3–5 tools per request | [WWDC26 242](https://developer.apple.com/videos/play/wwdc2026/242/), [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels) |
| On 27, `historyTransform` filters what each request sends (for example, old tool output) and `onResponse` can trim the transcript; a fresh session is the third way | [Build agentic app experiences (WWDC26 242)](https://developer.apple.com/videos/play/wwdc2026/242/) |

PCC and the third-party packages would give a larger window, but send the map to a server, which the privacy promise rules out; ADR 0009 keeps them out.

### Budget [Đề xuất]

On a 4,096-token window, with Vietnamese at about one token per character ([ai-architecture.md](ai-architecture.md#context-and-language)):

| Part | Budget |
| --- | --- |
| Instructions and the tool schemas | about 700 tokens; measure with `tokenCount(for:)` on 27 and keep a test that fails if they grow |
| Tool output per call | 600 tokens (`TextLimit` in `MindMapQuery`), with "N more topics" when cut |
| Earlier turns | what is left after the next answer's reserve; oldest tool output goes first, then oldest turns |
| Answer | 600 tokens reserved |

On `exceededContextWindowSize` the chat starts a new session with the instructions and the last question and answer, and says "Earlier messages were left out to make room" once. It never retries with a rewritten question.

## Tools

Four tools per scope, in `MindMapAIApple` (they implement `Tool`, which needs FoundationModels) over `MapQueries` ([mcp.md](mcp.md#shared-query-layer)):

| Tool | Scope | Does |
| --- | --- | --- |
| `searchTopics(query)` | map or library | Topic hits: handle, title, path, a short excerpt |
| `readTopic(handle)` | map or library | Title, note, children, tags, task state |
| `readBranch(handle, depth)` | map or library | A bounded outline of a branch |
| `suggestTopics(parent, titles)` | map only | Records a suggestion; changes nothing ([Editing](#editing)) |
| `listMaps(query)` | library only | Map titles and handles, in place of `suggestTopics` |

- **Handles, not UUIDs.** Tool output names topics `T1`, `T2`… (maps `M1`…), each mapped to a `TopicRef` in the chat's citation table. A 36-character UUID costs many tokens; a handle costs one or two *[Inference]*.
- The map scope searches the open map's live graph; the library scope searches every live map, never Recently Deleted.
- Tool output is the person's own text, so it goes into the prompt, never into the instructions, as for the other AI features.

## Citations

- Instructions ask the model to put the handles it used in brackets, for example "[T3]". The chat keeps only handles that a tool returned in this conversation and drops the rest, so a made-up handle never becomes a link.
- A cited topic shows as a chip with its title. Clicking it opens the map (in its window, per [architecture.md](architecture.md#windows)) and selects the topic; a topic inside a collapsed branch is revealed with `RevealNodeCommand` ("Reveal Topic", one undo step), the same as Find.
- A cited topic deleted since shows "Topic no longer exists".
- Guided generation of `{ text, citations }` is the fallback if bracket handles prove unreliable in the evaluations [Đề xuất]; it costs schema tokens and delays streaming.

## Editing

In a map, a question like "add three risks under Launch" makes the model call `suggestTopics`:

1. The tool turns the call into an `AIProposal` (feature `.chat`, anchor the parent topic) and checks it with `ProposalTranslator`.
2. The proposal goes into the map's `SuggestionState`, so it is drawn on the canvas as suggestions, editable before Accept, exactly like Expand or Brainstorm.
3. Accept is one `BatchCommand` named "Add AI Topics", one undo step; topics keep `metadata.origin = .ai`.
4. The chat answer says "Suggested 3 topics under Launch. Review them on the map" and never claims they were added.

The chat cannot rename, move or delete topics. Rewrite and Summary stay the existing commands in the AI menu. The library scope has no edit tool.

## Saving the conversation

[Đề xuất] Not saved in the first version:

- No schema change (a saved chat needs `SchemaV3` and a migration, [data-model.md](data-model.md)), nothing extra to sync, nothing extra to delete.
- The small window drops older turns anyway, so a saved conversation could not be continued as the model saw it *[Inference]*.
- The chat stays while the map's window is open (with `OpenMap`, so a second window on the same map sees the same chat) and is gone when the map closes. Clear Chat empties it.
- Copy an answer, or Add Answer to Note on a topic (one command), keeps what matters.

Saving, if wanted later, is a separate decision.

## Availability

| `AICapabilities` state | Chat |
| --- | --- |
| `ready` | Shown |
| `deviceNotEligible` (also every x86_64 build, MM-21) | Hidden: no menu item, no button, no panel |
| `appleIntelligenceOff`, `modelDownloading`, `unknown` | Menu item and panel shown; the panel says why in one line, as the other AI features do |
| Language unsupported | The panel says the question's language is not supported |

## Free or Pro (decided 2026-10-02: Ask in a map free, Ask across the library Pro)

Following [pricing.md](pricing.md), where single-topic AI is free and whole-map AI is Pro:

- **Ask in a map: free.** It reads a few topics at a time, like Expand or Brainstorm.
- **Ask across the library: Pro.** A new `ProFeature.askLibrary`; the menu item stays visible and opens the paywall, as other Pro features do.

The product owner decides; the split lives in `ProFeature` only.

## Languages

- Instructions in English, fixed, versioned in `PromptCatalog`, ending with the answer language. The answer follows the language of the question (`NLLanguageRecognizer`), else the app's language, so a Vietnamese question gets a Vietnamese answer even in a map written in English.
- The search tools fold case and Vietnamese marks, so a model that drops diacritics ("ke hoach") still finds "Kế hoạch".
- Every string in the panel goes into `Localizable.xcstrings` in en and vi.

## Guardrails and acceptable use

- Default guardrails; no `.permissiveContentTransformations`, since the chat writes new text rather than transforming the person's own.
- `guardrailViolation` and `refusal` show one calm line; the app never rewords a question to get past them ([acceptable use](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/), [app-store-readiness.md](app-store-readiness.md#foundation-models-acceptable-use)).
- The instructions keep the assistant to the person's maps: no persona, no companionship, which the acceptable use list ("interactions that build harmful dependency") points away from.
- When the tools find nothing, the answer says so instead of inventing an answer. Each answer carries the AI label and "Check the cited topics" ([HIG: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)).

## Interface

- **Mac:** a trailing panel in the editor window (like the topic inspector, MM-16) and in the library window. The panel is content: no Liquid Glass inside it, only on its toolbar button ([design-guidelines.md](design-guidelines.md)).
- **iPad:** the same panel as an inspector; **iPhone:** a sheet.
- **Menu bar** [Đề xuất], in the AI menu, all disabled (not hidden) when they do not apply:

| Item | Shortcut |
| --- | --- |
| Ask About This Map… (editor) / Ask About Library… (library) | ⌃⌘A |
| Clear Chat | none |
| Stop | ⌘. (the existing AI cancel) |

  ⌃⌘A is free in the app today (the AI menu uses ⌃⌘G, E, B, U, M, Return and Delete) and is not a standard macOS shortcut *[Inference]*; check again against the system list before shipping.
- **In the panel:** Return sends, Shift-Return adds a line, Escape moves focus back to the canvas. Answers stream; VoiceOver announces when an answer is complete, not each word.
- Hit targets from `Metrics.minimumHitTarget`, motion from `Motion`, colours from `Palette` ([design-system.md](design-system.md)).
- First use shows the existing one-time notice that AI runs on the device (FR-AI-19).

## App Review

| Item | Finding |
| --- | --- |
| 4.7 (chatbots) | Covers chatbots and other software "not embedded in the binary" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). The chat is in the binary and runs on the device, so 4.7 does not apply *[Inference]* |
| Age rating | Apple asks to count "all app features, including AI assistants and chatbot functionality" when answering how often sensitive content appears ([news](https://developer.apple.com/news/?id=ks775ehf)). *[Inference]* 4+ still fits: the chat answers from the person's own maps with Apple's guardrails. Re-answer the questionnaire in the release that ships it |
| 2.3.1(a) Review Notes | Say the chat needs Apple Intelligence on an eligible Mac and is hidden otherwise; give a sample map and question |
| 5.1.2(i) | Does not apply: nothing leaves the device ([app-store-readiness.md](app-store-readiness.md#privacy-51)) |

## Architecture

| Type | Where | Role |
| --- | --- | --- |
| `MapQueries`, `TopicRef` | `MindMapQuery` | Reads for both chat and MCP |
| `ChatScope`, `ChatTurn`, `ChatCitation`, `CitationTable` | `MindMapAICore` | Plain values; handle mapping and the check that drops unknown handles |
| `ChatProvider` protocol | `MindMapAICore` | `send(_:in:) -> AsyncThrowingStream<ChatUpdate, Error>`, beside `AIProvider` so neither grows for the other |
| `AppleChatProvider`, the four tools | `MindMapAIApple` | One `LanguageModelSession` per conversation, budget, trimming |
| `MockChatProvider` | `MindMapTestSupport` | Scripted tool calls and answers for tests |
| `ChatModel` | `MindMapAI/Features/Chat` | One per `OpenMap` (map scope) and one per library window; sends, cancels, opens citations, hands suggestions to `AIAssistant` |

Errors map through `AIFailure`. Logs carry the scope, tool names, token counts and time to first token (`Log.ai`), never questions, answers or tool output.

## What C1 built

MM-41, 2026-10-02. Ask in a map, read-only; suggestions (C2, MM-51), the library scope (C3, MM-52) and saving (MM-55) are not built.

| Type | Where | Role |
| --- | --- | --- |
| `ChatScope` (`.map` only), `ChatTurn`, `ChatCitation`, `ChatMessage`, `ChatUpdate` | `MindMapAICore/Chat.swift` | Plain values. `ChatTurn` is `Codable` and keeps the answer with its handles, for MM-55 |
| `ChatProvider`, `ChatConversation` | `MindMapAICore/Chat.swift` | `conversation(in:history:)` then `send(_:) -> AsyncThrowingStream<ChatUpdate, Error>`. `history` is how MM-55 hands a saved conversation back: its citations keep resolving and the latest turns that fit go back to the model |
| `CitationTable` | `MindMapAICore` | Handles `T1`, `T2`… per conversation; `citations(in:)` keeps only handles a tool returned; `displayText` strips `[T3]` and a half-written handle |
| `ChatBudget` | `MindMapAICore` | 700 instructions, 600 answer, two tool results of `min(600, contextSize / 7)` (at least 150), the rest for earlier turns [Đề xuất] |
| `AppleChatProvider`, `AppleChatConversation` | `MindMapAIApple` | `SystemLanguageModel.default`, default guardrails, one `LanguageModelSession` per conversation. When the turns so far no longer fit, the session is rebuilt from a `Transcript` of the latest turns as plain text (tool output goes first); on `exceededContextWindowSize` it is rebuilt once from the last turn and the same question is asked again. A stopped answer drops the session, so the next question starts from the finished turns |
| `searchTopics`, `readTopic`, `readBranch` | `MindMapAIApple/ChatTools.swift` over `ChatMapReader` | Three tools. `ChatMapReader` writes the plain text and holds no FoundationModels, so tests read it without a model |
| `PromptCatalog.chatInstructions`, `chatPrompt` | `MindMapAIApple` | Instructions fixed and English; the prompt carries the map title, the question and "You MUST respond in …" for the question's language |
| `MockChatProvider` | `MindMapTestSupport` | Scripted answers, failures and a hang |
| `MapChat` | `MindMapAI/Features/Chat` | One per `OpenMap`, so every window on the map shares it. Asks after the AI privacy notice, stops, clears, opens citations through `EditorSession.showTopic` (Reveal Topic as in Find) |
| `ChatPanel` | `MindMapAI/Features/Chat` | Shares the editor's `.inspector` with the topic inspector (one or the other); on iPhone `.inspector` is a sheet, which closes when a citation is opened |
| `AppEnvironment.mapQueries` | `MindMapAI/Features/Chat/AppEnvironment+Chat.swift` | The chat's `MapQueries` over the AI apps' `OpenMapsGraphSource` (`AIAppsHost.swift`, MM-46): open maps read from the editor's live graph, the rest from the store |

Differences from the design above:

- **Not a new `AIFeature`.** Availability is `AICapabilities.chatAvailability(in:)`, the same rule as `availability(for:in:)`. MM-51 adds a feature case if suggestions need one.
- **Errors** map to `ChatFailure` (its own messages: no "suggestions" wording), not `AIFailure`. `LanguageModelError` (27) is read beside `GenerationError`.
- **Menu:** AI ▸ Ask About This Map… (⌃⌘A, approved 2026-10-02) and Clear Chat; Cancel AI Request (⌘.) stops a chat answer too, so the chat has no Stop item of its own. Toolbar: Ask About This Map, beside the AI menu.
- **Use AI Features** (MM-44) does not exist yet; the chat is hidden exactly where the other AI entry points are (`AIService.showsEntryPoints`), and when the app has no store.
- **UI test mode:** `-uitest-ai ready|ineligible` puts a scripted model in place of Apple Intelligence (Debug only, `UITestAIService.swift`): the chat cites the first topic whose title matches a word of the question.

## Testing

- `MindMapAICoreTests`: citation table (unknown handles dropped, deleted topics), budget cutting, scope rules (no edit tool in the library).
- App tests with `MockChatProvider`: a suggestion reaches `SuggestionState`, Accept is one undo step and redo works, a citation opens and reveals the topic.
- `MindMapAIAppleTests`, only where the model is ready: tools are called for a fixture map in en and vi; Evaluations for answer quality and citation accuracy.
- UI tests with the mock (as MM-25): open the panel by menu and shortcut, ask, click a citation, unavailable states, Vietnamese.
- Measure time to first token and per-tool latency on the M1 Mac for a 1,000-topic map.

## Proposed tasks

Q1 (the query layer) is in [mcp.md](mcp.md#proposed-tasks).

| | Task | Done when | Depends on |
| --- | --- | --- | --- |
| C1 | Ask in a map | `ChatProvider`, Apple provider with the read tools, citations that open topics, the panel on Mac, iPad and iPhone, AI menu items and ⌃⌘A, availability states, en and vi, unit, app and UI tests | Q1, MM-8 (done) |
| C2 | Suggestions from the chat | `suggestTopics` into `SuggestionState`, Accept as one command with undo and redo tests, honest answer text | C1 |
| C3 | Ask across the library | Library window panel, `listMaps`, Pro gate if the product owner agrees, tests | C1, MM-13 (done) |
| C4 | Chat evaluations | Evaluations suite of en and vi questions on fixture maps (answer found, citations correct, says "not found"), run on 26.4 and 27 prompts | C1 |
