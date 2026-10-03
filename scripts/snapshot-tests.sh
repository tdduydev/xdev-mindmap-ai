#!/usr/bin/env bash
# Snapshot tests of the Mac interface (MindMapAITests/Snapshots): each scene is
# drawn in an off-screen window and compared with its reference PNG, in English
# Vietnamese and Japanese. Unlike the macOS UI tests, this runs while the Mac is locked.
#
#   scripts/snapshot-tests.sh            # compare with the references
#   scripts/snapshot-tests.sh --record   # write new references, on purpose
#   scripts/snapshot-tests.sh ja         # one language: en, vi or ja
#   SNAPSHOT_TEST='paywall()' scripts/snapshot-tests.sh --record   # one scene
#
# A failed comparison leaves the image drawn and a diff (differing pixels in
# red) in scripts/out/snapshots/<language>/. See docs/testing.md.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

mode=compare
languages="en vi ja"
for arg in "$@"; do
  case "$arg" in
    --record) mode=record ;;
    en | vi | ja) languages=$arg ;;
    *) echo "usage: $0 [--record] [en|vi|ja]" >&2; exit 64 ;;
  esac
done

derived=scripts/out/DerivedData
out=scripts/out/snapshots
references=MindMapAITests/Snapshots/References
mkdir -p "$out" "$references"

# Recorded with each run, since running while locked is the point (docs/testing.md).
locked=$(ioreg -n Root -d1 | sed -n 's/.*"IOConsoleLocked" = \(.*\)/\1/p')
printf 'Screen locked: %s\n' "${locked:-unknown}"

failed=0
for language in $languages; do
  printf '\n==> Mac snapshots, %s (%s)\n' "$language" "$mode"
  results="$out/$language.xcresult"
  # Japanese with its own region, so dates read as a person in Japan sees them.
  region=US
  if [[ $language == ja ]]; then region=JP; fi
  attachments="$out/$language"
  rm -rf "$results" "$attachments"
  mkdir -p "$attachments"
  # The test runs in the sandboxed app, so it cannot write into the repo: it
  # records images as attachments and the result bundle carries them out.
  # xcodebuild passes TEST_RUNNER_* variables on without the prefix; TZ fixes
  # the inspector's dates.
  status=0
  TEST_RUNNER_MINDMAP_SNAPSHOTS=$mode TEST_RUNNER_TZ=UTC xcodebuild test -quiet \
    -project MindMapAI.xcodeproj -scheme MindMapAI \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived" \
    -resultBundlePath "$results" \
    -only-testing:"MindMapAITests/MacSnapshotTests${SNAPSHOT_TEST:+/$SNAPSHOT_TEST}" \
    -testLanguage "$language" -testRegion "$region" \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES || status=$?

  xcrun xcresulttool export attachments --path "$results" --output-path "$attachments" >/dev/null 2>&1 || true
  # Attachments are exported under generated names; the manifest maps them
  # back to the names the test gave (reference./actual./diff.<scene>.png).
  if [[ -f "$attachments/manifest.json" ]]; then
    /usr/bin/python3 - "$attachments" "$references" "$mode" <<'PY'
import json, os, re, shutil, sys
folder, references, mode = sys.argv[1:4]
with open(os.path.join(folder, "manifest.json")) as f:
    manifest = json.load(f)
for test in manifest:
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        exported = os.path.join(folder, attachment["exportedFileName"])
        # Xcode appends "_<n>_<UUID>" before the extension.
        base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(?=\.png$)", "", name)
        if base.startswith("reference."):
            if mode == "record":
                shutil.copy(exported, os.path.join(references, base[len("reference."):]))
        else:
            shutil.copy(exported, os.path.join(folder, base))
        os.remove(exported)
PY
  fi
  if [[ $status -ne 0 ]]; then
    echo "Snapshots differ in $language: drawn images and diffs are in $attachments" >&2
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then exit 1; fi
if [[ $mode == record ]]; then
  printf '\nReferences written to %s. Look at each one before committing it.\n' "$references"
else
  printf '\nSnapshots match.\n'
fi
