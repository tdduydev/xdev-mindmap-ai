#!/usr/bin/env bash
# Renders the review screenshot App Store Connect asks for on the MindMap AI Pro
# in-app purchase: the app's own PaywallView with the product from
# MindMapAITests/MindMapAI.storekit, light, English, in a Mac window frame.
# Writes scripts/out/review/iap-pro.png (2880×1800). Not part of scripts/ci.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

derived=scripts/out/DerivedData
out=scripts/out/review
results="$out/iap-review.xcresult"
attachments="$out/attachments"
rm -rf "$results" "$attachments"
mkdir -p "$out" "$attachments"

# The test runs inside the sandboxed app, so it cannot write into the repo; it
# records the PNG as a test attachment and the result bundle carries it out.
# xcodebuild passes TEST_RUNNER_* variables to the test process without the prefix.
TEST_RUNNER_MINDMAP_RENDER_IAP_SCREENSHOT=1 xcodebuild test -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived" \
  -resultBundlePath "$results" \
  -only-testing:MindMapAITests/IAPReviewScreenshotTests \
  -testLanguage en -testRegion US \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

xcrun xcresulttool export attachments --path "$results" --output-path "$attachments" >/dev/null
png=$(find "$attachments" -name '*.png' | head -n 1)
if [[ -z "$png" ]]; then
  echo "error: the test recorded no PNG; see $results" >&2
  exit 1
fi
cp "$png" "$out/iap-pro.png"
rm -rf "$attachments"

# App Store Connect takes 2880×1800 for Mac and refuses images with alpha.
info=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$out/iap-pro.png")
if ! grep -q 'pixelWidth: 2880' <<<"$info" || ! grep -q 'pixelHeight: 1800' <<<"$info" \
  || ! grep -q 'hasAlpha: no' <<<"$info"; then
  echo "error: $out/iap-pro.png is not a 2880×1800 opaque PNG:" >&2
  echo "$info" >&2
  exit 1
fi
printf '\nWrote %s (2880×1800).\n' "$out/iap-pro.png"
