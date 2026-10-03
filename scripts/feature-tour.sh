#!/usr/bin/env bash
# The feature tour (MindMapAIUITests/FeatureTourUITests, MM-71): walks through
# every feature with a screenshot per step, for a person to look at. Not part
# of scripts/ui-tests.sh, where the tour skips itself; it takes several minutes.
#
#   scripts/feature-tour.sh                # iOS Simulator, English
#   scripts/feature-tour.sh ios ja         # platform: ios or macos; language: en, vi or ja
#   IOS_SIMULATOR="iPad Air 11-inch (M3)" scripts/feature-tour.sh ios en
#   TOUR_NAME=ipad DERIVED_DATA=scripts/out/DerivedData-ipad IOS_SIMULATOR=… scripts/feature-tour.sh
#
# Screenshots land in scripts/out/feature-tour/<platform>-<language>/NN-step.png,
# with a table of the steps that passed and failed. macOS takes the mouse and
# keyboard while it runs (docs/testing.md).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

platform=ios
language=en
for arg in "$@"; do
  case "$arg" in
    ios | macos) platform=$arg ;;
    en | vi | ja) language=$arg ;;
    *) echo "usage: $0 [ios|macos] [en|vi|ja]" >&2; exit 64 ;;
  esac
done

case "$platform" in
  macos) destination='platform=macOS,arch=arm64' ;;
  ios)
    name=${IOS_SIMULATOR:-iPhone 17}
    if ! xcrun simctl list devices available | grep -q "    $name ("; then
      echo "No simulator named \"$name\"; set IOS_SIMULATOR to one of:" >&2
      xcrun simctl list devices available | sed -n 's/^ *\(i[^(]*\) (.*/  \1/p' >&2
      exit 1
    fi
    destination="platform=iOS Simulator,name=$name"
    ;;
esac

# TOUR_NAME and DERIVED_DATA let two tours (iPhone and iPad) run side by side.
derived=${DERIVED_DATA:-scripts/out/DerivedData}
out="scripts/out/feature-tour/${TOUR_NAME:-$platform}-$language"
results="$out.xcresult"
rm -rf "$out" "$results"
mkdir -p "$out"

printf '==> Feature tour on %s, %s (%s)\n' "$platform" "$language" "$destination"
# xcodebuild passes TEST_RUNNER_* variables to the runner without the prefix;
# the tour skips itself without MINDMAP_FEATURE_TOUR.
status=0
# The tour buys Pro; on the Mac that changes the StoreKit store every other test
# run of the app uses (scripts/storekit-lock.sh).
lock=()
if [[ $platform == macos ]]; then lock=(scripts/storekit-lock.sh); fi
TEST_RUNNER_MINDMAP_FEATURE_TOUR=1 TEST_RUNNER_MINDMAP_FEATURE_TOUR_LANGUAGE=$language \
${lock[@]+"${lock[@]}"} xcodebuild test -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAIUITests \
  -destination "$destination" \
  -derivedDataPath "$derived" \
  -resultBundlePath "$results" \
  -only-testing:MindMapAIUITests/FeatureTourUITests \
  -collect-test-diagnostics never || status=$?

if [[ ! -d "$results" ]]; then
  echo "No result bundle: the tour did not build or start." >&2
  exit 1
fi

xcrun xcresulttool export attachments --path "$results" --output-path "$out" >/dev/null
# Attachments come out under generated names; the manifest maps them back to
# the step names: "NN-step" for the screenshot, "result.NN-step" for PASS/FAIL.
/usr/bin/python3 - "$out" <<'PY'
import json, os, re, sys
folder = sys.argv[1]
with open(os.path.join(folder, "manifest.json")) as f:
    manifest = json.load(f)
steps = {}
for test in manifest:
    for attachment in test.get("attachments", []):
        exported = os.path.join(folder, attachment["exportedFileName"])
        # Xcode appends "_<n>_<UUID>" before what it takes for the extension,
        # which for "result.NN-step" is everything after "result".
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", attachment.get("suggestedHumanReadableName", ""))
        base, extension = os.path.splitext(name)
        if name.startswith("result."):
            with open(exported) as f:
                steps.setdefault(name[len("result."):], {})["result"] = f.read().strip()
            os.remove(exported)
        elif extension in (".png", ".jpeg", ".jpg", ".heic"):
            os.replace(exported, os.path.join(folder, base + extension))
            steps.setdefault(base, {})["image"] = base + extension
        else:
            os.remove(exported)
os.remove(os.path.join(folder, "manifest.json"))
failed = 0
print("\n%-34s %s" % ("Step", "Result"))
for name in sorted(steps):
    result = steps[name].get("result", "NOT RUN")
    failed += result != "PASS"
    print("%-34s %s" % (name, result))
print("\n%d steps, %d not passed. Screenshots: %s" % (len(steps), failed, folder))
PY

if [[ $status -ne 0 ]]; then
  echo "Some steps failed; the failures are in $results (open it in Xcode)." >&2
  exit 1
fi
