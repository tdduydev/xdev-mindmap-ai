#!/usr/bin/env bash
# Runs the AI evaluations (MM-105) on Foundation Models and on local MLX models
# and writes one JSONL per provider to docs/research/ai-evaluations/.
#   scripts/evaluations/run.sh [MODEL...]   default: mlx-community/Qwen3-1.7B-4bit
# Local models run in `mlx_lm.server` through uv (weights cached in
# ~/.cache/huggingface); its peak resident memory is sampled every second.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
out=docs/research/ai-evaluations
mkdir -p "$out" scripts/out
models=("$@")
[[ ${#models[@]} -eq 0 ]] && models=(mlx-community/Qwen3-1.7B-4bit)
port=8089

swift build --package-path Packages/MindMapCore --product mindmap-ai-eval -c release
tool=Packages/MindMapCore/.build/release/mindmap-ai-eval

for model in "${models[@]}"; do
  name=$(basename "$model")
  uv run --python 3.12 --with mlx-lm python -m mlx_lm server --model "$model" --port "$port" > "scripts/out/$name.server.log" 2>&1 &
  server=$!
  until curl -s "http://127.0.0.1:$port/v1/models" > /dev/null; do sleep 2; done
  # uv starts python as a child; sample the python process, not uv.
  python_pid=$(pgrep -P "$server" -f mlx_lm || echo "$server")
  ( peak=0; while kill -0 "$python_pid" 2>/dev/null; do
      rss=$(ps -o rss= -p "$python_pid" | tr -d ' '); [[ -n "$rss" && "$rss" -gt "$peak" ]] && peak=$rss && echo "$peak" > "$out/$name.peak-kb"
      sleep 1; done ) &
  sampler=$!
  "$tool" local "$out/$name.jsonl" "http://127.0.0.1:$port" "$model" | tee "$out/$name.log"
  kill "$server" "$python_pid" 2>/dev/null || true
  wait "$sampler" 2>/dev/null || true
done

"$tool" apple "$out/foundation-models.jsonl" | tee "$out/foundation-models.log"
echo "EVALUATIONS DONE"
