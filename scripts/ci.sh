#!/usr/bin/env bash
# The check every change must pass before merging. There is no hosted CI, so
# this runs locally: core tests on the Mac, app tests on macOS, a universal
# macOS Release build (Apple silicon and Intel), then an iOS Simulator build.
# scripts/rosetta-tests.sh runs the tests as x86_64; it is slower and optional.
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

# Intel Macs get macOS 26 as their last release, so the shipped Mac app must
# keep an x86_64 slice (MM-21). lipo fails quietly, so say what is missing.
app_binary="$derived/Build/Products/Release/MindMap AI.app/Contents/MacOS/MindMap AI"
if ! lipo "$app_binary" -verify_arch arm64 x86_64; then
  echo "error: the Release app is not universal; it has: $(lipo -archs "$app_binary")" >&2
  exit 1
fi

step "iOS Simulator build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

printf '\nAll checks passed.\n'
