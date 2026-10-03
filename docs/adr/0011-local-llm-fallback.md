# ADR 0011: A downloadable open model where Apple Intelligence is missing

- Status: draft (MM-77). The product owner accepts, changes or rejects it; until then nothing here reaches the app or `Packages/MindMapCore`
- Date: 2026-10-03
- Relates to: ADR 0001 (no backend, Foundation Models first, no dependency without a decision), ADR 0005 (OS 26 minimum), ADR 0006 (macOS first)
- Research: [local-llm.md](../research/local-llm.md)

## Context

Every AI feature runs on Foundation Models. People without it get no AI: iPhones before the 15 Pro, Apple Intelligence turned off or still downloading, and regions or languages where it is not offered. On 2026-10-03 the product owner asked for a fallback, as research first, not blocking 1.0.

ADR 0001 says Foundation Models is the first provider, and the project rules forbid external dependencies without a decision. A local model needs both: a third-party runtime and weights downloaded after install.

## Decision [Đề xuất]

1. **Fallback only.** Foundation Models stays the provider wherever it is ready. The open model is offered only when the capability check reports `deviceNotEligible`, `appleIntelligenceOff` or `languageUnsupported` and the device has enough memory, and only after the person downloads it in Settings ▸ AI. It never replaces a working Foundation Models.
2. **Runtime: MLX Swift (`mlx-swift-lm`, MIT)**, the first external dependency, pinned to an exact version and linked only into the app target behind `LocalInferenceEngine`. `MindMapAICore` stays free of it. On 27 and later, the `LanguageModel` protocol (`MLXLanguageModel`) may replace the direct engine, reusing the `@Generable` types.
3. **Models: Qwen3 1.7B 4-bit (default, 0.98 GB) and Qwen3 4B 4-bit (8 GB devices and Macs, 2.3 GB), Apache-2.0.** Not Gemma (use-policy terms), Llama 3.2 or Phi-4-mini (no Vietnamese).
4. **Delivery: Apple-hosted Background Assets packs**, with SHA-256 checks kept for any other source. Stored in Application Support, excluded from backup, removable in Settings, with the size shown before downloading.
5. **Same pipeline.** Same `PromptCatalog`, constrained JSON (MLX guided generation), the same `ProposalTranslator` checks, AI labels, Accept as one command. Answers show which model wrote them [Đề xuất].
6. **Intel Macs and the Simulator** get no local model (MLX needs Apple silicon). That matches today's behaviour.

## Amends ADR 0001

Item 7 gains: "An open model on the device may stand in where Foundation Models is unavailable (ADR 0011)." The no-backend, no-account and on-device promises are unchanged. AI on servers, including Private Cloud Compute, stays out.

## Consequences

- App Review: weights are data read by code in the binary (2.5.2). Downloading after install is accepted for existing apps, but App Review itself has not confirmed it [Chưa kiểm chứng]. The first build with it says so in the review notes, and the App Store text mentions the optional download (4.2.3, 2.3.1).
- Privacy: content stays on the device, so the label stays "Data Not Collected". The policy names where the model is downloaded from.
- Size and memory: the app binary grows by the MLX libraries (not measured). A 1–2.3 GB download, and 1.3–2.7 GB of memory while generating, so iPhones under the memory threshold are not offered the model. The threshold is set from device measurements, not yet made.
- Build: MLX's Metal shaders need xcodebuild. `swift test` for `MindMapCore` is unaffected. The Simulator build links MLX, but tests use a fake engine.
- Quality: smaller than Foundation Models in Vietnamese facts (1.7B invents details). Evaluations must cover both providers, and the AI label already tells people to review before Accept.
- Licenses: MIT and Apache-2.0 notices go in Acknowledgements.
- Maintenance: one more model to evaluate per prompt change, and weights to update.

## Alternatives

- **llama.cpp (MIT):** runs on Intel Macs and in the Simulator, but has no JSON-Schema converter in the XCFramework (hand-written GBNF) and needs our own streaming loop. Second choice.
- **Core ML + swift-transformers:** needs a conversion pipeline per model and has no constrained decoding.
- **No fallback:** simplest, but leaves most iPhones and every non-Apple-Intelligence language without AI.
- **Cloud AI:** against ADR 0001 and the privacy promise.
