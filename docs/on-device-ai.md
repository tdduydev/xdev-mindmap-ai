# On-device AI on Apple platforms

Research for MM-0e, 2026-10-02. Sources are Apple documentation unless noted. "Probe" means a Swift script run on the development Mac (M1, 16 GB, macOS 27.0.1, Xcode 27.0); a probe result holds for that machine only. Statements marked *[Inference]* are reasoned, not documented. Recheck before relying on them.

## Summary

- **First provider: Foundation Models (`SystemLanguageModel.default`)** for every text feature, in English and Vietnamese. Vietnamese has been an Apple Intelligence language since 26.1 (November 2025), and the probe lists `vi-Latn-VN` as supported. Prompts, instructions and output may use different languages.
- **Plan for a 4,096-token context.** Read `contextSize` instead of hard-coding it: a WWDC26 sample prints 8,192 and says to adapt to the hardware. Vietnamese costs roughly one token per character, about three times English *[Inference]*.
- **No AI on Apple's servers.** Private Cloud Compute (`PrivateCloudComputeLanguageModel`, 27.0) and Image Playground use Apple servers, so both stay off (privacy promise, ADR 0001).
- **Non-LLM features work on every device:** OCR, Vietnamese dictation, translation and keyword search.

## Capabilities

| Capability | API | Min OS (macOS / iOS) | Vietnamese | Use in MindMap AI | Limits | Source |
| --- | --- | --- | --- | --- | --- | --- |
| On-device LLM | `SystemLanguageModel`, `LanguageModelSession` | 26.0 / 26.0 | Yes, since 26.1 (probe: supported) | Generate, expand, brainstorm, rewrite, summarize, missing topics | Apple Intelligence must be on; eligible devices only (Mac and iPad M1 or later, iPad mini A17 Pro, iPhone 15 Pro and later). Context 4,096 tokens (probe). The model changed at 26.4 and 27.0 | [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [devices](https://support.apple.com/en-us/121115), [languages](https://www.apple.com/hk/en/newsroom/2025/11/apple-intelligence-expands-to-new-languages-including-traditional-chinese/) |
| Guided generation and streaming | `@Generable`, `@Guide(.maximumCount)`, `streamResponse(to:generating:)` | 26.0 / 26.0 | as above | Typed `GeneratedMindMap`; suggestions stream into the preview | Schemas and guides cost tokens | [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) |
| Tool calling | `Tool`, `GenerationOptions.ToolCallingMode` (27) | 26.0 / 26.0 | as above | Let the model fetch a branch or its siblings on demand | Apple advises 3–5 tools per request | [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels) |
| Content tagging | `SystemLanguageModel(useCase: .contentTagging)` | 26.0 / 26.0 | Not verified | Automatic node tags, search facets | Always answers with tags | [contentTagging](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase/contenttagging) |
| Image input | `Attachment` in prompts; `OCRTool` | 27.0 / 27.0 | Not verified | Photo or whiteboard to map | `OCRTool` does not run in the Simulator | [multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting) |
| Safety | `SystemLanguageModel.Guardrails` (`.default`, `.permissiveContentTransformations`) | 26.0 / 26.0 | Supported languages only | Permissive mode when rewriting the user's own text | Errors `guardrailViolation`, `refusal`, `rateLimited` (on 26, only in the background) | [safety](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output) |
| Custom adapters | Adapter training toolkit | 26.x only | — | Not planned | The last toolkit release is not compatible with 27 | [adapters](https://developer.apple.com/apple-intelligence/foundation-models-adapter/) |
| Own local model | `LanguageModel` protocol with `MLXLanguageModel` or `CoreAILanguageModel` | 27.0 / 27.0 | Depends on the model | Optional fallback when Apple Intelligence is off | Download size and memory; App Review stance on downloaded weights not verified | [Core AI model in a session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session), [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) |
| Language ID | `NLLanguageRecognizer` | 10.14 / 12 | Yes | Pick the output language per node | Mixed text yields one dominant language; use `languageHypotheses` | [NaturalLanguage](https://developer.apple.com/documentation/naturallanguage/nllanguage/vietnamese) |
| Word tokens | `NLTokenizer(.word)` | 10.14 / 12 | Yes (probe) | Keyword search index | Lexical class tagging is not available for Vietnamese (probe) | [NaturalLanguage](https://developer.apple.com/documentation/naturallanguage) |
| Embeddings | `NLContextualEmbedding` (Latin script model) | 14 / 17 | Yes (probe: 512 dimensions, 256 tokens) | Semantic search vectors | Assets download on request; `NLEmbedding.sentenceEmbedding` has no Vietnamese (probe) | [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding) |
| OCR | `RecognizeTextRequest`, `RecognizeDocumentsRequest` (26) | 15 / 18; 26 / 26 | Yes in `.accurate` (probe) | Image or scanned PDF to an outline | Handwriting not verified | [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) |
| Ink recognition | `PKStrokeRecognizer` | 27.0 / 27.0 | Yes (probe) | Pencil strokes to node text (MM-9) | Store `recognitionVersion` and refresh when it changes | [PKStrokeRecognizer](https://developer.apple.com/documentation/pencilkit/pkstrokerecognizer) |
| Speech, English | `SpeechAnalyzer` + `SpeechTranscriber` | 26.0 / 26.0 | No (probe) | English voice to map | Assets via `AssetInventory` | [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) |
| Speech, Japanese | `SpeechAnalyzer` + `SpeechTranscriber`, else `DictationTranscriber` | 26.0 / 26.0 | — | Japanese voice to map (MM-94) | Probe 2026-10-03: both `SpeechTranscriber` and `DictationTranscriber` list `ja_JP`; falls back to `DictationTranscriber` where `SpeechTranscriber` has none. Recognition quality not checked | [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) |
| Speech, Vietnamese | `SpeechAnalyzer` + `DictationTranscriber` | 26.0 / 26.0 | Yes, `vi-VN` downloadable (probe) | Vietnamese voice to map | Not `SFSpeechRecognizer`: it sends Vietnamese to a server (probe) | [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber) |
| Translation | `TranslationSession` | 15 / 18 | Yes, vi→en installed (probe) | Translate a branch between Vietnamese and English | Does not run in the iOS Simulator | [TranslationSession](https://developer.apple.com/documentation/translation/translationsession) |
| Writing Tools | automatic in `TextEditor`; `writingToolsBehavior(_:)` | 15 / 18 | Yes | Node notes | System UI only, no structured output | [writingToolsBehavior](https://developer.apple.com/documentation/swiftui/view/writingtoolsbehavior(_:)) |
| Prompt evaluation | Evaluations framework | 27.0 / 27.0 | — | Score each prompt version per model | Does not replace unit tests | [Evaluations](https://developer.apple.com/documentation/evaluations) |

## Runtime detection

The research probe compiled and ran this under Swift 6 on the development Mac. MM-7 turns it into `AICapabilities`:

```swift
let vi = Locale(identifier: "vi-VN")
let model = SystemLanguageModel.default
let llm: LLMStatus = switch model.availability {
    case .available: model.supportsLocale(vi) ? .ready : .languageUnsupported
    case .unavailable(.deviceNotEligible): .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled): .turnedOff
    case .unavailable(.modelNotReady): .downloading
    case .unavailable: .unknown
}
let contextTokens = llm == .ready ? model.contextSize : nil
let dictationVI = await DictationTranscriber.supportedLocale(equivalentTo: vi) != nil
let translation = await LanguageAvailability().status(from: .init(identifier: "vi"), to: .init(identifier: "en"))
```

Check again each time the app becomes active, since people can turn Apple Intelligence on or off *[Inference]*. Every request also handles `unsupportedLanguageOrLocale`, `contextSizeExceeded`, `guardrailViolation`, `refusal` and `rateLimited`.

## Behaviour by availability

| State | What the user sees |
| --- | --- |
| Ready | AI actions in the toolbar and node menus |
| `modelNotReady` | AI actions show "Getting ready" and retry later |
| `appleIntelligenceNotEnabled` | One line explaining how to turn on Apple Intelligence |
| `deviceNotEligible` | AI entry points and the AI tools on the paywall hidden; everything else unchanged. Every x86_64 build (Intel Mac, or Rosetta) reports this without asking the framework (MM-21) |
| Language other than Vietnamese or English | *[Inference, untested]* translate to English with `TranslationSession`, generate, translate back |

## Prompting rules

- Write instructions in English and add the user's locale plus "You MUST respond in Vietnamese." (or English), as Apple's [language guide](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) recommends.
- Keep requests small: bounded context (`AIContextBuilder`), arrays capped with `@Guide(.maximumCount)`, long branches summarized in chunks.
- Version prompts per model generation (26.0–26.3, 26.4, 27.0) in a prompts string catalog, as Apple's [prompt update guide](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions) suggests.

## Local model fallback (1.1)

ADR 0011 (accepted 2026-10-03) adds a downloadable open model where Apple Intelligence cannot run: Qwen3 1.7B by default and Qwen3 4B on 8 GB devices, both Apache-2.0, running on MLX Swift. It applies on iPhone 15 and later, recognised by model identifier, and on Apple silicon iPad and Mac with 8 GB [Đề xuất]. Foundation Models stays first wherever it is ready. Without a download the app behaves as described above.

- Provider, choice, device rules, JSON repair: [ai-architecture.md](ai-architecture.md#local-model-fallback) (MM-105).
- Evaluations in en, vi and ja against Foundation Models: [research/ai-evaluations.md](research/ai-evaluations.md) (MM-105).
- Download in Settings ▸ AI: MM-106. Measurements on iPhone and iPad: MM-107.
- Background: [research/local-llm.md](research/local-llm.md) (MM-77).
