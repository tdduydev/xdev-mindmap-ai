#!/usr/bin/env bash
# The check every change must pass before merging. There is no hosted CI, so
# this runs locally: core tests on the Mac, app tests on macOS, then an iOS
# Simulator build so the shared code keeps compiling for iPad and iPhone.
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

step "iOS Simulator build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

printf '\nAll checks passed.\n'
