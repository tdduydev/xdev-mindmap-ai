#!/usr/bin/env bash
# Runs the core and app tests as x86_64 under Rosetta, the closest an Apple
# silicon Mac gets to an Intel Mac (MM-21). Optional and not part of ci.sh: it
# builds everything again for x86_64. It does not replace a run on a real Intel
# Mac; docs/architecture.md (Platforms) says what it does and does not cover.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools ship no SwiftData or Swift Testing macro plugins; use Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "error: Rosetta is not installed: softwareupdate --install-rosetta --agree-to-license" >&2
  exit 1
fi

# Separate from ci.sh's derived data, whose arm64 Debug products would
# otherwise be relinked for x86_64 on every run, and one per workspace.
derived="$PWD/scripts/out/Rosetta"
mkdir -p "$derived"

step() { printf '\n==> %s\n' "$1"; }

# Not `swift test --arch x86_64`: it builds x86_64 bundles, then loads them in
# an arm64 test helper and crashes. xcodebuild runs them under Rosetta.
step "Core package tests under Rosetta"
(cd Packages/MindMapCore && xcodebuild test -quiet \
  -scheme MindMapCore-Package \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$derived/Core" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)

step "App tests on macOS under Rosetta"
# Same app, same StoreKit store as every other test run (scripts/storekit-lock.sh).
scripts/storekit-lock.sh xcodebuild test -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$derived/App" \
  -only-testing:MindMapAITests

printf '\nRosetta checks passed.\n'
