#!/usr/bin/env bash
# Runs the chat evaluations (MM-53) on this Mac's on-device model, for the
# 26.4 and 27 chat prompts, and saves one JSON report per prompt generation
# in scripts/out/evaluations. Slow and model-dependent, so ci.sh skips it; run
# it after any change to the chat prompts, tools or budget (ADR 0009).
# Needs macOS 27 with Apple Intelligence on; skipped otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

out="$PWD/scripts/out/evaluations"
mkdir -p "$out"
MINDMAP_CHAT_EVALUATIONS="$out" swift test --package-path Packages/MindMapCore \
  --filter "ChatEvaluationRun" 2>&1 | tee "$out/run.log"
echo "Reports: $out/chat-26.4.json, $out/chat-27.0.json"
