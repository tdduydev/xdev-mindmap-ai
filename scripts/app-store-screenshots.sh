#!/usr/bin/env bash
# Opt-in UI capture. Run one device at a time: [iphone|ipad|mac] [en|vi|all] [light|dark|all].
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

platform=${1:-iphone}
language=${2:-all}
appearance=${3:-all}
case "$platform" in
  iphone) device='iPhone 18 Pro Max'; width=1320; height=2868 ;;
  ipad) device='iPad Pro 13-inch (M5)'; width=2064; height=2752 ;;
  mac) device=''; width=2880; height=1800 ;;
  *) echo 'platform: iphone, ipad or mac' >&2; exit 64 ;;
esac
case "$language" in en|vi|all) ;; *) exit 64 ;; esac
case "$appearance" in light|dark|all) ;; *) exit 64 ;; esac

if [[ "$platform" == mac ]]; then
  destination='platform=macOS,arch=arm64'
else
  id=$(xcrun simctl list devices available | sed -n "s/.*$device (\([A-F0-9-]*\)) (.*/\1/p" | head -n 1)
  [[ -n "$id" ]] || { echo "Simulator unavailable: $device" >&2; exit 1; }
  destination="platform=iOS Simulator,id=$id"
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b
  xcrun simctl status_bar "$id" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
fi

output=docs/app-store/screenshots
work=scripts/out/app-store-screenshots
mkdir -p "$work"
swiftc scripts/compose-app-store-screenshots.swift -o "$work/compose"

languages=(en vi)
[[ "$language" == all ]] || languages=("$language")
appearances=(light dark)
[[ "$appearance" == all ]] || appearances=("$appearance")
for lang in "${languages[@]}"; do
  for mode in "${appearances[@]}"; do
    label="$platform-$lang-$mode"
    result="$work/$label.xcresult"
    attachments="$work/$label-attachments"
    if [[ "${MINDMAP_SCREENSHOT_REUSE_RESULTS:-0}" != 1 ]]; then
      rm -rf "$result"
    fi
    rm -rf "$attachments"
    mkdir -p "$attachments"
    echo "==> Capture $label"
    if [[ "${MINDMAP_SCREENSHOT_REUSE_RESULTS:-0}" != 1 ]]; then
      TEST_RUNNER_MINDMAP_STORE_SCREENSHOTS=1 \
      TEST_RUNNER_MINDMAP_SCREENSHOT_LANGUAGE="$lang" \
      TEST_RUNNER_MINDMAP_SCREENSHOT_APPEARANCE="$mode" \
      xcodebuild test -quiet -project MindMapAI.xcodeproj -scheme MindMapAIUITests \
        -destination "$destination" -derivedDataPath scripts/out/DerivedData \
        -resultBundlePath "$result" -parallel-testing-enabled NO \
        -collect-test-diagnostics never \
        -only-testing:MindMapAIUITests/AppStoreScreenshotUITests \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    fi
    xcrun xcresulttool export attachments --path "$result" --output-path "$attachments" >/dev/null
    raw="$output/raw/$platform/$lang"
    [[ "$mode" == dark ]] && raw="$raw/dark"
    mkdir -p "$raw" "$output/$platform/$lang"
    python3 - "$attachments" "$raw" <<'PY'
import json, pathlib, shutil, sys
source, target = map(pathlib.Path, sys.argv[1:])
records = json.loads((source / 'manifest.json').read_text())
found = {}
for record in records:
    for attachment in record['attachments']:
        name = attachment['suggestedHumanReadableName'].split('_0_', 1)[0]
        if name in {'01-canvas', '02-ai-suggestions', '03-outline', '04-ask-map', '05-privacy'}:
            shutil.copyfile(source / attachment['exportedFileName'], target / (name + '.png'))
            found[name] = True
if len(found) != 5:
    raise SystemExit(f'Expected 5 captures, found {sorted(found)}')
PY
    if [[ "$mode" == light ]]; then
      for screenshot in "$raw"/*.png; do
        name=$(basename "$screenshot" .png)
        caption=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])' "$output/captions.json" "$lang" "$name")
        background="$output/backgrounds/$platform/$lang/$name.png"
        target="$output/$platform/$lang/$name.png"
        if [[ -f "$background" ]]; then
          "$work/compose" "$screenshot" "$target" "$width" "$height" "$caption" "$background"
        else
          "$work/compose" "$screenshot" "$target" "$width" "$height" "$caption"
        fi
        dimensions=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$target")
        grep -q "pixelWidth: $width" <<<"$dimensions"
        grep -q "pixelHeight: $height" <<<"$dimensions"
        grep -q 'hasAlpha: no' <<<"$dimensions"
      done
    fi
  done
done
echo "App Store screenshots ready: $output/$platform"
