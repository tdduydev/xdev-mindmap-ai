# AI evaluations: Foundation Models and local models in en, vi and ja (MM-105)

The same 30 cases run on every provider: 10 features (the 9 AI features and the chat) in English, Vietnamese and Japanese. The cases live in `MindMapAIEvaluation` (`AIEvaluationSuite`). They are graded by string checks in `AIEvaluationRunner`, not by a model judge:

- the answer must decode and pass the same checks the app runs (`ProposalTranslator`, `AITagSuggestions.checked`, …);
- lists need a minimum count;
- suggestions must not repeat a topic already in the map;
- summaries must contain a fact from the map (a number);
- chat answers must cite the topic that holds the answer;
- the answer must be in the requested language.

`swift test` checks the cases and the grading on every run (`AIEvaluationTests`). Running the models is opt-in:

```sh
scripts/evaluations/run.sh mlx-community/Qwen3-1.7B-4bit mlx-community/Qwen3-4B-4bit
python3 scripts/evaluations/summarize.py docs/research/ai-evaluations/*.jsonl
```

`run.sh` builds `mindmap-ai-eval`. It serves each MLX model with `mlx_lm.server` through `uv`, and the weights go to `~/.cache/huggingface`. The tool sends the app's own prompts (`PromptCatalog`, `LocalOutputShape`) through `LocalLLMProvider`. Then it runs the same cases on Foundation Models. Raw answers are in `docs/research/ai-evaluations/<provider>.jsonl`.

## Results (2026-10-03, Mac mini M1 16 GB, macOS 27.0.1)

| Provider | en | vi | ja | All | Median s/case | Tokens/s (end to end) | Peak memory |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Foundation Models | 10/10 | 10/10 | 10/10 | 30/30 | 2.6 | — | — |
| Qwen3 1.7B 4-bit | 8/10 | 10/10 | 9/10 | 27/30 | 2.4 | 29.5 | 1.28 GB |
| Qwen3 4B 4-bit | 10/10 | 9/10 | 9/10 | 28/30 | 5.0 | 12.7 | 1.90 GB |

| Feature | Foundation Models | Qwen3 1.7B | Qwen3 4B |
| --- | --- | --- | --- |
| generateMap | 3/3 | 3/3 | 3/3 |
| expandTopic | 3/3 | 3/3 | 3/3 |
| brainstorm | 3/3 | 3/3 | 3/3 |
| findMissingTopics | 3/3 | 3/3 | 3/3 |
| rewrite | 3/3 | 3/3 | 3/3 |
| summarize | 3/3 | 3/3 | 3/3 |
| suggestTags | 3/3 | 1/3 (en, ja: nothing valid) | 3/3 |
| suggestGroups | 3/3 | 2/3 (en: nothing valid) | 2/3 (vi: nothing valid) |
| summarizeBoundary | 3/3 | 3/3 | 3/3 |
| chat | 3/3 | 3/3 | 2/3 (ja: no citation) |

"Nothing valid" means every suggestion the model returned failed the app's checks, after the one retry (`invalidResponse(.empty)`). The person would see "no suggestions", never a wrong edit.

## How to read these numbers

- **One run per case.** Each cell is one sample, so a single flip changes a row by one. An earlier Foundation Models run on the same day failed `suggestGroups.en`, and this run passed it. Treat a difference of one or two cases as noise.
- **Qwen3 1.7B before and after the repeat filter.** The first 1.7B run scored 18/30: it repeated a topic already in the map in all 9 suggestion cases. `LocalLLMProvider` now drops suggestions that repeat a topic in the context, and the table above is the run after that change. The 4B run used the binary from before the filter; `summarize.py` scores it with the same rule, and it repeated nothing.
- **Speed.** Mac M1 numbers through an HTTP server. They are not iPhone numbers; MM-107 measures on the device. Generating a whole map takes about 20 s (1.7B) and 30–50 s (4B), against about 15 s on Foundation Models. A run that shared the machine with a build measured 17 tok/s for 1.7B.
- **Memory** is the peak resident size of the `mlx_lm.server` process, sampled each second. [Unverified] Whether RSS counts every Metal buffer on unified memory has not been checked; MM-77 measured 1.3 GB and 2.7 GB peaks with `mlx_lm` directly.
- **Chat.** The local cases give the outline in the prompt, because the local engine has no tool calling. The app's chat on the local model is not built (see [ai-architecture.md](../ai-architecture.md#local-model-fallback)).
- **Japanese** answers are checked by script and language detection only. A Japanese speaker has not read them.

## Conclusions

- Qwen3 4B is close to Foundation Models in all three languages, at about half its speed on M1. It is the right model for 8 GB devices, as ADR 0011 decided.
- Qwen3 1.7B is usable for map generation, topic suggestions, rewrite and summaries in all three languages. Tags and groups are its weak spot (English and Japanese). The app shows "no suggestions" there, so it is a quality gap, not a safety one.
- Each local failure was caught by the checks the app already runs. No answer would have reached the map in a wrong shape.

## Not covered

- The MLX Swift engine inside the app (`LocalModelEngines.makeEngine`): these runs use `mlx_lm` in Python with the same prompts and the same provider. Building MLX Swift with `xcodebuild` needs the Metal Toolchain, which this machine does not have (`xcodebuild -downloadComponent MetalToolchain`).
- Constrained decoding: `mlx_lm.server` does not apply the JSON schema, so these runs measure the weaker case (shape in the instructions only). MLX Swift's `MLXGuidedGeneration` should only improve the parse rate. [Inference]
- iPhone and iPad (MM-107), and more than one run per case.
