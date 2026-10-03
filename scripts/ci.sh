#!/usr/bin/env bash
# The check every change must pass before merging. There is no hosted CI, so
# this runs locally: core tests on the Mac, app tests on macOS, a universal
# macOS Release build (Apple silicon and Intel), then an iOS Simulator build
# (which embeds the watch app) and a watchOS Simulator build.
# scripts/rosetta-tests.sh runs the tests as x86_64; it is slower and optional.
# Warnings fail the build through the project and Package.swift settings, which
# leave the remote packages (MLX, ADR 0011) to their own warning flags.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools ship no SwiftData or Swift Testing macro plugins; use Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

derived=scripts/out/DerivedData
mkdir -p "$derived"

logs=scripts/out/logs
mkdir -p "$logs"

step() { printf '\n==> %s\n' "$1"; }

# Xcode builds a package target only after the targets it declares; an import
# it does not declare can compile against a stale module from DerivedData.
fail_on_missing_dependency() {
  if grep -q "is missing a dependency on" "$1"; then
    grep "is missing a dependency on" "$1" | sort -u >&2
    echo "error: declare these in Packages/MindMapCore/Package.swift" >&2
    exit 1
  fi
}

step "Package dependencies match imports"
swift package --package-path Packages/MindMapCore dump-package > "$logs/package.json"
python3 - "$logs/package.json" <<'PY'
import json, pathlib, re, sys
package = json.load(open(sys.argv[1]))
root = pathlib.Path("Packages/MindMapCore")
own = {t["name"] for t in package["targets"]}
missing = []
for target in package["targets"]:
    kind = "Tests" if target["type"] == "test" else "Sources"
    folder = root / (target.get("path") or f"{kind}/{target['name']}")
    declared = {d["byName"][0] for d in target["dependencies"] if "byName" in d}
    imported = {
        m for f in folder.rglob("*.swift")
        for m in re.findall(r"^\s*(?:@\w+\s+)*(?:\w+\s+)?import\s+(\w+)", f.read_text(), re.M)
    }
    for module in sorted((imported & own) - declared - {target["name"]}):
        missing.append(f"'{target['name']}' imports '{module}' but does not declare it")
if missing:
    print("\n".join(missing), file=sys.stderr)
    sys.exit("error: declare these in Packages/MindMapCore/Package.swift")
PY

step "Core package tests"
swift test --package-path Packages/MindMapCore 2>&1 | tee "$logs/core-tests.log"
fail_on_missing_dependency "$logs/core-tests.log"

# Not checked for missing dependencies: Xcode 26 reports MindMapGraph,
# MindMapCapture and MindMapAICore as missing dependencies they do declare
# whenever MindMapTestSupport is built for the app tests (MM-67).
step "App tests on macOS"
app_test_options=(
  -project MindMapAI.xcodeproj -scheme MindMapAI
  -destination 'platform=macOS,arch=arm64'
  -derivedDataPath "$derived"
  -only-testing:MindMapAITests
)
build_app_tests() {
  xcodebuild build-for-testing -quiet "${app_test_options[@]}" 2>&1 | tee "$logs/app-tests-build.log"
}
if ! build_app_tests; then
  # After a merge that changes a core package's API, Xcode sometimes compiles the
  # app against the old module left in DerivedData ("has no member" for code that
  # swift test has just built). One rebuild from a clean DerivedData tells that
  # apart from a real failure; a test failure is not retried.
  echo "The app build failed; rebuilding once from a clean DerivedData" >&2
  rm -rf "$derived" && mkdir -p "$derived"
  build_app_tests
fi
# Built first and outside the lock, so the lock is only held while tests run:
# another worktree's UI test runner or app tests share this Mac's StoreKit store
# and wiped purchases made by ProEntitlementTests (MM-110).
scripts/storekit-lock.sh xcodebuild test-without-building -quiet "${app_test_options[@]}" 2>&1 | tee "$logs/app-tests.log"

step "Universal macOS Release build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" 2>&1 | tee "$logs/macos-release.log"
fail_on_missing_dependency "$logs/macos-release.log"

# Intel Macs get macOS 26 as their last release, so the shipped Mac app must
# keep an x86_64 slice (MM-21). One arch per lipo call: given two, this lipo
# takes the second for an input file. lipo fails quietly, so say
# what is missing.
app_binary="$derived/Build/Products/Release/MindMap AI.app/Contents/MacOS/MindMap AI"
for arch in arm64 x86_64; do
  if ! lipo "$app_binary" -verify_arch "$arch"; then
    echo "error: the Release app has no $arch slice; it has: $(lipo -archs "$app_binary")" >&2
    exit 1
  fi
done

step "iOS Simulator build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" 2>&1 | tee "$logs/ios-simulator.log"
fail_on_missing_dependency "$logs/ios-simulator.log"

# The watch app and its complication (MM-116), on their own so a watch-only
# error names the watch scheme. The iOS build above embeds the same app.
step "watchOS Simulator build"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath "$derived" 2>&1 | tee "$logs/watchos-simulator.log"
fail_on_missing_dependency "$logs/watchos-simulator.log"
watch_app="$derived/Build/Products/Debug-watchsimulator/MindMapWatch.app"
if [[ ! -d "$watch_app/PlugIns/MindMapWatchWidgets.appex" ]]; then
  echo "error: the watch app does not embed MindMapWatchWidgets.appex" >&2
  exit 1
fi
ios_app="$derived/Build/Products/Debug-iphonesimulator/MindMap AI.app"
if [[ ! -d "$ios_app/Watch/MindMapWatch.app" ]]; then
  echo "error: the iOS app does not embed MindMapWatch.app" >&2
  exit 1
fi

printf '\nAll checks passed.\n'
