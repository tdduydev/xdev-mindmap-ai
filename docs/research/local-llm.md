# Local open models as a fallback for Apple Intelligence

Research for MM-77, 2026-10-03. The product owner asked on 2026-10-03 for AI where Apple Intelligence is missing: devices not yet eligible, Apple Intelligence still downloading on iPhone, older Macs and iPads, and Vietnamese where the system model is weak. This is research and a prototype only. It does not block 1.0, and nothing here ships until [ADR 0011](../adr/0011-local-llm-fallback.md) is accepted.

Labels: **[Đề xuất]** is a proposal that still needs the product owner's decision. **[Chưa kiểm chứng]** is not verified on a device or in a primary source. Facts from a web page link to it (fetched 2026-10-03). Numbers marked "measured" come from the development Mac only: Mac mini M1, 16 GB, macOS 27.0.1, Xcode 27.0.

## Summary

- **Recommended runtime [Đề xuất]: MLX Swift (`mlx-swift-lm`).** It is MIT-licensed. Its `MLXGuidedGeneration` constrains output to a JSON Schema, which is the closest thing to `@Generable`. It streams, it can be cancelled, and on the 27 SDK it can stand behind `LanguageModelSession`. The costs: Apple silicon only (Intel Macs keep AI hidden, as today), no iOS Simulator, and builds need Xcode, not `swift build`.
- **Recommended model [Đề xuất]: Qwen3 1.7B 4-bit** (0.98 GB download, 1.3 GB peak memory, about 45 tok/s on M1). Offer **Qwen3 4B 4-bit** (2.3 GB, 2.7 GB peak, about 22 tok/s) as "higher quality" on devices with 8 GB or more. Both are Apache-2.0 and list Vietnamese among their languages. Gemma 3 has restrictive terms and is the slowest. Llama 3.2 and Phi-4-mini do not support Vietnamese officially.
- **Quality:** with the app's own prompts, Qwen3 4B is close to Foundation Models in English and better in Vietnamese on Rewrite and Summarize. Qwen3 1.7B is usable, but it repeats existing topics ("Fixed bedtime"), and in Vietnamese it sometimes invents dishes and repeats an existing topic. Foundation Models was the fastest on Generate Map on the M1 (16–19 s against 12–37 s), and it is the only one with no download.
- **App Review:** weights are data read by code already in the binary, and an Apple DTS engineer has said updating ML models after install does not conflict with the guidelines. Several model-downloading apps are on the Store. Guideline 4.2.3(ii) requires showing the download size and asking first. This is still **[Chưa kiểm chứng]** with App Review itself: ask in the review notes of the first build that has it.
- **Privacy:** inference stays on the device, so the "Data Not Collected" label stays. The one new network call downloads the weights from a host we name. The privacy policy must say so.

## Runtimes

| | MLX Swift (`mlx-swift-lm`) | llama.cpp (XCFramework) | Core ML + `swift-transformers` |
| --- | --- | --- | --- |
| License | MIT ([mlx-swift](https://github.com/ml-explore/mlx-swift), [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)) | MIT ([llama.cpp](https://github.com/ggml-org/llama.cpp)) | Apache-2.0 ([swift-transformers](https://github.com/huggingface/swift-transformers)) |
| Minimum OS | iOS 17, macOS 14 ([Package.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Package.swift)), so 26 is fine | iOS 16.4, macOS 13.3 ([build-xcframework.sh](https://github.com/ggml-org/llama.cpp/blob/master/build-xcframework.sh)) | iOS 16, macOS 13; a stateful KV cache needs iOS 18 / macOS 15 ([MLState](https://developer.apple.com/documentation/coreml/mlstate)) |
| Apple silicon / Intel Mac | Apple silicon only: "MLX requires Apple silicon" ([running on iOS](https://github.com/ml-explore/mlx-swift/blob/main/Source/MLX/Documentation.docc/Articles/running-on-ios.md)) | Both. The macOS slice is `arm64 x86_64`, and x86 runs on the CPU (AVX). Metal on Intel GPUs is [Chưa kiểm chứng] | Both, by Core ML [Chưa kiểm chứng for LLM-sized models on Intel] |
| iOS Simulator | No: the simulator lacks the Metal GPU family MLX needs (same doc). Tests use a fake engine; device checks run on the Mac ("Designed for iPad") or a device | Yes, there is a simulator slice (CPU) | Yes (CPU) [Chưa kiểm chứng] |
| Added app size | Not published [Chưa kiểm chứng]. Measure after an Xcode archive | The all-platform release zip is 61.7 MB with debug info ([b11368](https://github.com/ggml-org/llama.cpp/releases/tag/b11368)). One platform slice is smaller [Chưa kiểm chứng] | Small library. The model is a `.mlpackage`/`.mlmodelc` download |
| Structured output in place of `@Generable` | **Yes:** `MLXGuidedGeneration` masks logits to a JSON Schema, an EBNF grammar or an XGrammar structural tag, on iOS 17 / macOS 14 and later ([README](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXGuidedGeneration/README.md)). On 27, `MLXLanguageModel` backs a `LanguageModelSession`, so the app's `@Generable` types would work unchanged ([WWDC26 session 339](https://developer.apple.com/videos/play/wwdc2026/339/)) | GBNF grammar in the C API (`llama_sampler_init_grammar`, [llama.h](https://github.com/ggml-org/llama.cpp/blob/master/include/llama.h)). JSON Schema → GBNF is C++ in `common/`, which the XCFramework leaves out (`LLAMA_BUILD_COMMON=OFF`). Write grammars by hand, or generate them at build time with the Python script ([grammars](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)) | None found in swift-transformers [Chưa kiểm chứng]. We would parse and validate JSON ourselves |
| Streaming | `generate(...) -> AsyncStream<Generation>` ([Evaluate.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLMCommon/Evaluate.swift)) | Token loop we write over `llama_decode` | Token loop we write |
| Cancellation | The token loop checks `Task.isCancelled` and stops with `.cancelled` (same file) | `llama_set_abort_callback` | Ours |
| Memory on 6–8 GB iPhones | `MLX.Memory.cacheLimit` and the [Increased Memory Limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit) entitlement are documented. Apple publishes no jetsam limits per device: read `os_proc_available_memory()` before loading | Memory-mapped GGUF weights count less against the limit [Chưa kiểm chứng] | Core ML manages it. Apple's Llama 3.1 8B example is Mac-only ([Core ML Llama](https://machinelearning.apple.com/research/core-ml-on-device-llama)) |
| Model source | `mlx-community` safetensors on Hugging Face, or our own conversion | GGUF (Hugging Face) | We convert each model with coremltools |
| Build | SwiftPM on the command line cannot build the Metal shaders; Xcode must (mlx-swift README). `scripts/ci.sh` already uses xcodebuild for the app | Binary target, no build step | Plain SwiftPM |

**Why MLX [Đề xuất].** It is the only option with JSON-Schema-constrained decoding as a Swift library today. It is the runtime Apple chose for the 27 `LanguageModel` protocol, so on 27 the fallback could reuse every `@Generable` type and `PromptCatalog` unchanged, by swapping the model under `LanguageModelSession`. Measured speed on M1 is good (below). llama.cpp is the backup if Intel Macs or the Simulator matter more: it runs on both, but it needs hand-written GBNF for each shape and our own streaming loop. Core ML costs a per-model conversion pipeline and has no constrained decoding, so it is not recommended.

**Foundation Models 27 `LanguageModel`.** WWDC26 introduced a `LanguageModel` protocol that lets a `LanguageModelSession` run on a non-Apple model, with `MLXLanguageModel` and `CoreAILanguageModel` as the implementations ([session 241](https://developer.apple.com/videos/play/wwdc2026/241/), [session 339](https://developer.apple.com/videos/play/wwdc2026/339/)). It needs the 27 runtime, and the app supports 26 (ADR 0005). Two paths are possible [Đề xuất]:

1. **On 26:** `LocalLLMProvider` (prototype below) runs MLX directly and parses JSON constrained by `MLXGuidedGeneration`.
2. **On 27:** `AppleFoundationModelProvider` gains a `LanguageModel` parameter, so the fallback is the same provider with a different model. Choose this if 27 becomes the minimum before the fallback ships.

## Models

Licenses and languages come from the official model cards.

| Model | License | Vietnamese | Download (4-bit MLX) | Note |
| --- | --- | --- | --- | --- |
| **Qwen3 1.7B** | Apache-2.0 ([card](https://huggingface.co/Qwen/Qwen3-4B), [blog](https://qwenlm.github.io/blog/qwen3/)) | Yes, among its 119 languages | 0.98 GB | Thinking mode: turn it off with `enable_thinking=False` for short JSON |
| **Qwen3 4B** | Apache-2.0 | Yes | 2.28 GB | 32K native context |
| Gemma 3 4B | Gemma Terms of Use: prohibited-use policy, terms passed on to users, a NOTICE file, and Google may restrict use "remotely or otherwise" ([terms](https://ai.google.dev/gemma/terms)) | "140+ languages" | 3.44 GB | Multimodal weights, so a larger download |
| Gemma 3 1B | as above | **English only** ([Gemma 3 blog](https://huggingface.co/blog/gemma3)) | 0.77 GB | Measured for speed only |
| Llama 3.2 3B | Llama 3.2 Community License (gated) | **No.** 8 supported languages; others are "out of scope" ([model card](https://github.com/meta-llama/llama-models/blob/main/models/llama3_2/MODEL_CARD.md)) | 1.82 GB | Measured as a reference |
| Phi-4-mini | MIT | **No.** 23 languages, no Vietnamese ([card](https://huggingface.co/microsoft/Phi-4-mini-instruct)) | — | Not measured: no Vietnamese and 3.8B |
| Qwen2.5 3B | Qwen Research License, non-commercial ([license](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/blob/main/LICENSE)) | Yes | — | Cannot ship. Qwen2.5 1.5B and 7B are Apache-2.0 |

## Measurements

How: `scripts/research/local-llm-bench.py` (MLX through `mlx-lm` 0.x in Python, the same Metal kernels as MLX Swift; Swift overhead is [Chưa kiểm chứng]) and `scripts/research/foundation-models-bench.swift` (the app's `@Generable` shapes). Both use ten real app prompts: Generate Map, Expand (Suggest Subtopics), Brainstorm, Rewrite and Summarize, each in English and Vietnamese, with `PromptCatalog`'s instructions. The open models get a JSON shape line instead of `@Generable` and **no constrained decoding**, so the JSON results are a lower bound. Temperature 0.3, one run per prompt. Raw output is in [local-llm-results/](local-llm-results/).

Generate Map was rerun with a 1,600-token budget (`bench-map.jsonl`), because pretty-printed JSON for 20 topics overflowed the first run's 700. Vietnamese costs about 1.45× the tokens of English for the same map (740 against 510, Qwen3).

### Speed and memory (measured, M1 16 GB)

| Model | Generation tok/s (median) | Prompt tok/s | Peak memory | Expand / Rewrite / Summarize | Generate Map en / vi | JSON parses / matches the shape (of 10) |
| --- | --- | --- | --- | --- | --- | --- |
| Apple Foundation Models | — (no token count) | — | system process | 2.6–3.0 s / 1.5–2.1 s / 2.0 s | 19.4 s / 16.4 s | 10 / 10 (guided) |
| Qwen3 1.7B 4-bit | 45 | 350 | 1.31 GB | 2.1–2.3 s / 0.9–1.1 s / 1.8–2.1 s | 12.5 s / 16.2 s | 10 / 9 |
| Qwen3 4B 4-bit | 23 | 150 | 2.68 GB | 3.3–5.9 s / 2.3–2.4 s / 3.3–4.5 s | 26.4 s / 37.4 s | 10 / 8 |
| Gemma 3 4B 4-bit | 17 | 144 | 2.90 GB | 8.0–9.3 s / 3.5–4.9 s / 6.1–6.6 s | 40.8 s / fail | 9 / 9, always in Markdown fences |
| Llama 3.2 3B 4-bit | 20 | 249 | 2.21 GB | 3.8 s, vi garbled / 1.9–2.5 s / 3.7–3.8 s | 20.3 s / 39.4 s | 9 / 7 |
| Gemma 3 1B 4-bit | 69 | 796 | 0.95 GB | runs on to the token limit | fail | 4 / 4 |

"Matches the shape" means the keys and types the app decodes. The misses were Brainstorm answered as a list of strings instead of `{"title"}` objects (Qwen3, Llama), and a translated key (Llama, `"tóm tắt"`). The prototype accepts both forms of a topic list. Constrained decoding would rule both out.

Peak memory is MLX's own peak for weights, KV cache and activations, not the whole process. The time to load each model is not in the table, because the first load included the download. Expect a few seconds from SSD [Chưa kiểm chứng].

**iPhone and iPad:** not measured. MLX does not run in the Simulator, and no device was attached. [Chưa kiểm chứng, inference from bandwidth]: an A17 Pro/A18 iPhone has about half the M1's memory bandwidth, so expect roughly 20 tok/s for 1.7B and 10 tok/s for 4B. A 6 GB iPhone can probably hold 1.7B but not 4B next to the app. Measure on a device before setting `minimumPhysicalMemory`.

### Quality (read by hand, en + vi)

| Prompt | Foundation Models | Qwen3 1.7B | Qwen3 4B | Gemma 3 4B | Llama 3.2 3B |
| --- | --- | --- | --- | --- | --- |
| Generate Map en | Good tree, but some chains run too deep (each topic under the previous one) | Good, balanced | Good, specific | Good, wordy titles ("X - Y") | Good |
| Generate Map vi | Good Vietnamese, deep chains | Fair: generic ("Tổng quan") | Fair | Good wording, invalid JSON | Repeats the subject in every title |
| Expand vi (Đà Nẵng food) | Good: real dishes | Poor: invents dishes ("Súp Đỏ", "Bánh Gạc"), repeats Mì Quảng | Fair: plausible dishes, few specific to Đà Nẵng | Fair: repeats the focus topic | **Garbled characters** |
| Brainstorm en / vi | Good / good | Good / good | Good / good | Good / good | Good / fair |
| Rewrite vi (mixed vi/en) | Good, keeps "backend architecture" | **Poor:** one title, a full sentence | **Good**, keeps the English terms | Good, translates the English terms | Good |
| Summarize en / vi | Markdown list instead of sentences / good | Good / good | **Good / best** | Good / good | Good / translated the JSON key ("tóm tắt") |

**Reading [Đề xuất]:** Qwen3 4B ≈ Foundation Models in English, and slightly better on Vietnamese rewrite and summary. Qwen3 1.7B is fast and small but weaker in Vietnamese. With constrained decoding and the validation the providers already run (`ProposalTranslator`), its JSON failures go away, but the invented facts stay. Ten prompts are too few to decide. The Evaluations suite should score the chosen models before release (NFR quality targets apply).

## Prototype

`Prototypes/LocalLLM` is a separate Swift package. It depends on `Packages/MindMapCore` by path, and nothing in the app or in `MindMapCore` depends on it. It has **no external dependency**: the runtime sits behind `LocalInferenceEngine`, and its MLX adapter is below rather than in main.

| Type | What it does |
| --- | --- |
| `LocalModel` | One downloadable model: files with URL, size and SHA-256, license, languages, context size, `minimumPhysicalMemory`, `formattedDownloadSize` for the button |
| `LocalModelStore` (actor) | Downloads to `Application Support/LocalModels/<id>/`. Not Caches, because the system may purge it while the model is in use. The folder is excluded from backup. Before downloading, it checks free space (`volumeAvailableCapacityForImportantUsage`). It moves each file into place only after its size and SHA-256 (CryptoKit, streamed in 4 MB chunks) match. It reports `notInstalled` / `downloading(fraction)` / `installed(byteCount)`, and can remove a model. `Fetch` is injected: URLSession now, Background Assets later |
| `LocalInferenceEngine` | `generate(instructions:prompt:shape:maximumTokens:) -> AsyncThrowingStream<String>`. `LocalOutputShape` carries a JSON Schema for engines that constrain output (MLX guided generation, llama.cpp GBNF) and the instruction line for engines that do not |
| `LocalLLMProvider: AIProvider` | Same `PromptCatalog` instructions and prompts as the Apple provider, plus the JSON line. Strips `<think>` blocks and Markdown fences, decodes, then validates with `ProposalTranslator.validate`/`limited`, the same checks as every other provider. Errors map to `AIError`. An x86_64 build, or one with too little memory, reports `.notEligible`. A model that is not installed reports `.unknown` |

Tests: `swift test --package-path Prototypes/LocalLLM` (13 tests). They cover the download checks (checksum, size, space, backup exclusion, remove), parsing (fences, thinking, braces inside strings), limits, loops in a generated tree, and rewrite dedup. They use a scripted engine with no model. The prototype has no graph commands, so there is no undo/redo test: accepted proposals go through the existing `ProposalTranslator` commands.

Not built in the prototype: streaming partial suggestions (it uses the default single snapshot), tags, groups and boundary titles (they throw `generationFailed`), the UI, Background Assets, and the real MLX engine.

### MLX engine adapter (sketch, [Chưa kiểm chứng], not compiled)

```swift
import MLXLLM
import MLXLMCommon

/// Lives in the app target once ADR 0011 is accepted; main must not resolve mlx-swift-lm before then.
struct MLXEngine: LocalInferenceEngine {
    let container: ModelContainer   // loadModelContainer(directory: store.folder(for: model))

    func generate(instructions: String, prompt: String, shape: LocalOutputShape, maximumTokens: Int) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await container.perform { context in
                        let input = try await context.processor.prepare(input: UserInput(chat: [.system(instructions), .user(prompt)],
                                                                                         additionalContext: ["enable_thinking": false]))
                        // Constrain to shape.jsonSchema with MLXGuidedGeneration here.
                        for await piece in try MLXLMCommon.generate(input: input, parameters: GenerateParameters(maxTokens: maximumTokens, temperature: 0.3), context: context) {
                            if let text = piece.chunk { continuation.yield(text) }
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

### Download: URLSession or Background Assets

| | URLSession (prototype) | Background Assets, Apple-hosted packs |
| --- | --- | --- |
| OS | any | `AssetPackManager`, OS 26 ([docs](https://developer.apple.com/documentation/backgroundassets/assetpackmanager)) |
| Hosting | Hugging Face (`mlx-community`, may change or vanish) or our own CDN | App Store Connect: 200 GB per app and 200 packs, no per-pack limit stated ([limits](https://developer.apple.com/help/app-store-connect/reference/app-uploads/apple-hosted-asset-pack-size-limits/)) |
| Integrity | Our SHA-256 list in the binary | Apple signs and delivers |
| Privacy | A request to a third-party host (IP address) | Apple only, like the app download |
| Cost | Ours if we host | Included |

**[Đề xuất] Background Assets with Apple-hosted packs:** no third-party host, nothing to pay for, and pack updates ship with app versions. `LocalModelStore.Fetch` keeps URLSession for development. Whether a 1–2.3 GB pack downloads in the background on cellular is [Chưa kiểm chứng].

## App Review and privacy

- **2.5.2:** apps "may not download, install, or execute code which introduces or changes features or functionality" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Weights are data. The inference code ships in the binary and the features exist without the download. An Apple DTS engineer wrote that updating ML models after install is not "in conflict with App Store guidelines" and that existing apps depend on it, while advising to confirm with App Review ([forum](https://developer.apple.com/forums/thread/793131)). Precedents on the Store: [PocketPal AI](https://apps.apple.com/us/app/pocketpal-ai/id6502579498), [Private LLM](https://apps.apple.com/us/app/private-llm-local-ai-chat/id6448106860), [Locally AI](https://apps.apple.com/us/app/locally-ai-by-lm-studio/id6741426692). Status: **[Chưa kiểm chứng] with App Review.** Say it in the review notes.
- **4.2.3(ii):** "disclose the size of the download and prompt users before doing so". The download is optional, so this is the minimum. Settings ▸ AI shows the model, its license, the size (`formattedDownloadSize`) and a Download button, and it never downloads by itself [Đề xuất].
- **2.3.1:** describe the optional model in the App Store text and the review notes. It is not a hidden feature.
- **Privacy:** prompts and map content never leave the device, so the App Privacy label stays "Data Not Collected". Downloading the model is a network request. With Apple-hosted packs it goes to Apple only. With our own host, the privacy policy names it, and no identifier is sent. No `PrivacyInfo.xcprivacy` change: no required-reason API is added (file timestamps are not read) [Chưa kiểm chứng: recheck when the real engine lands].
- **Licenses:** Apache-2.0 (Qwen3) needs the license text and notices in Settings ▸ About ▸ Acknowledgements. The MIT runtimes need the same. Gemma would add use-policy obligations, so it is not recommended.

## Next steps [Đề xuất]

1. The product owner decides ADR 0011 (runtime, models, Background Assets).
2. Measure Qwen3 1.7B and 4B on a 6 GB and an 8 GB iPhone and on an M1 iPad (tok/s, `os_proc_available_memory`, thermal state), with the MLX Swift engine in a throwaway app.
3. Add `AIAvailability.modelNotInstalled` with its one-line message, plus a Settings ▸ AI section to download or remove the model.
4. Move to constrained decoding (`MLXGuidedGeneration`) and stream partial suggestions.
5. Score both models with the Evaluations suite against Foundation Models in en, vi and ja (Japanese was not measured here).
