#!/usr/bin/env bash
# The check every change must pass before merging. There is no hosted CI, so
# this runs locally: core tests on the Mac, app tests on macOS, a universal
# macOS Release build, then an iOS Simulator build.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools ship no SwiftData or Swift Testing macro plugins; use Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

derived=scripts/out/DerivedData
mkdir -p "$derived"

step() { printf '\n==> %s\n' "$1"; }

step "Core package tests"
swift test --package-path Packages/MindMapCore

step "App tests on macOS"
xcodebuild test -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived" \
  -only-testing:MindMapAITests \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

step "Universal macOS Release build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

app_binary="$derived/Build/Products/Release/MindMap AI.app/Contents/MacOS/MindMap AI"
lipo -verify_arch arm64 x86_64 "$app_binary"

step "iOS Simulator build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

printf '\nAll checks passed.\n'
