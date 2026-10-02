#!/usr/bin/env bash
# UI tests (XCUITest) on macOS and the iOS Simulator. Slower than scripts/ci.sh,
# which does not run them; run this before merging a change to the interface.
#
#   scripts/ui-tests.sh            # macOS, then the iOS Simulator
#   scripts/ui-tests.sh macos      # one platform: macos or ios
#   scripts/ui-tests.sh ios -only-testing:MindMapAIUITests/FoundationUITests
#
# IOS_SIMULATOR picks the simulator by name (default: the first available
# iPhone). macOS needs automation mode allowed once; see docs/testing.md.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools ship no SwiftData or Swift Testing macro plugins; use Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

platforms=all
if [[ $# -gt 0 && "$1" != -* ]]; then
  platforms=$1
  shift
fi
case "$platforms" in
  all) platforms="macos ios" ;;
  macos | ios) ;;
  *) echo "usage: $0 [all|macos|ios] [xcodebuild options]" >&2; exit 64 ;;
esac

derived=scripts/out/DerivedData
results=scripts/out/UITestResults
mkdir -p "$derived" "$results"

step() { printf '\n==> %s\n' "$1"; }

ios_destination() {
  local name=${IOS_SIMULATOR:-}
  if [[ -z "$name" ]]; then
    name=$(xcrun simctl list devices available | sed -n 's/^ *\(iPhone[^(]*\) (.*/\1/p' | head -n 1 | sed 's/ *$//')
  fi
  if [[ -z "$name" ]]; then
    echo "No iPhone simulator is available; create one in Xcode or set IOS_SIMULATOR." >&2
    exit 1
  fi
  echo "platform=iOS Simulator,name=$name"
}

run() {
  local label=$1 destination=$2
  shift 2
  step "UI tests on $label ($destination)"
  rm -rf "$results/$label.xcresult"
  xcodebuild test \
    -project MindMapAI.xcodeproj -scheme MindMapAIUITests \
    -destination "$destination" \
    -derivedDataPath "$derived" \
    -resultBundlePath "$results/$label.xcresult" \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    "$@"
}

for platform in $platforms; do
  case "$platform" in
    macos) run macOS 'platform=macOS,arch=arm64' "$@" ;;
    ios) run iOS "$(ios_destination)" "$@" ;;
  esac
done

printf '\nUI tests passed. Results: %s\n' "$results"
