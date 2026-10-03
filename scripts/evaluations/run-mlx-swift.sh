#!/usr/bin/env bash
# Runs the AI evaluations (MM-105) through the app's own MLX engine with guided
# decoding (MM-119), to compare with run.sh's mlx_lm.server results. Writes
# docs/research/ai-evaluations/mlx-swift-<model>.jsonl.
#   scripts/evaluations/run-mlx-swift.sh [MODEL...]   default: mlx-community/Qwen3-1.7B-4bit
# Weights come from ~/.cache/huggingface, where run.sh (or `hf download`) put them.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
out=docs/research/ai-evaluations
mkdir -p "$out" scripts/out
models=("$@")
[[ ${#models[@]} -eq 0 ]] && models=(mlx-community/Qwen3-1.7B-4bit)

for model in "${models[@]}"; do
  name=$(basename "$model")
  folder=$(ls -d "$HOME/.cache/huggingface/hub/models--${model//\//--}/snapshots/"*/ | head -1)
  # xcodebuild passes TEST_RUNNER_-prefixed variables to the tests without the prefix.
  TEST_RUNNER_MINDMAP_MLX_MODEL="$folder" \
  TEST_RUNNER_MINDMAP_MLX_MODEL_NAME="$name" \
  xcodebuild test -quiet \
    -project MindMapAI.xcodeproj -scheme MindMapAI \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath scripts/out/DerivedData \
    -only-testing:MindMapAITests/MLXEvaluationRun 2>&1 | tee "scripts/out/mlx-swift-$name.log" || true
  # The sandboxed test host cannot write here, so the JSONL is a test attachment.
  result=$(ls -td scripts/out/DerivedData/Logs/Test/*.xcresult | head -1)
  rm -rf scripts/out/mlx-swift-attachments
  xcrun xcresulttool export attachments --path "$result" --output-path scripts/out/mlx-swift-attachments > /dev/null
  exported=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["attachments"][0]["exportedFileName"])' scripts/out/mlx-swift-attachments/manifest.json)
  cp "scripts/out/mlx-swift-attachments/$exported" "$out/mlx-swift-$name.jsonl"
  echo "$(grep -c '"passed":true' "$out/mlx-swift-$name.jsonl")/$(wc -l < "$out/mlx-swift-$name.jsonl" | tr -d ' ') passed"
done
echo "MLX SWIFT EVALUATIONS DONE"
