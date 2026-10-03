#!/usr/bin/env bash
# Checks that an exported build carries what iCloud sync needs (docs/release.md,
# *iCloud*): the container, CloudKit, aps-environment production, the key-value
# store and the App Group. Takes the export folder of upload-testflight.sh, or a
# .app, .pkg or .ipa.
#
#   scripts/check-icloud-entitlements.sh scripts/out/testflight-macos/export
set -euo pipefail

target=${1:?usage: $0 <export folder | .app | .pkg | .ipa>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ -d $target && $target != *.app ]]; then
  found=$(find "$target" -maxdepth 1 \( -name '*.pkg' -o -name '*.ipa' -o -name '*.app' \) | head -n 1)
  [[ -n $found ]] || { echo "No .pkg, .ipa or .app in $target" >&2; exit 1; }
  target=$found
fi

case "$target" in
  *.pkg)
    pkgutil --expand-full "$target" "$work/pkg" >/dev/null
    app=$(find "$work/pkg" -name 'MindMap AI.app' -type d -prune | head -n 1) ;;
  *.ipa)
    ditto -x -k "$target" "$work/ipa"
    app=$(find "$work/ipa/Payload" -maxdepth 1 -name '*.app' | head -n 1) ;;
  *.app) app=$target ;;
  *) echo "Not a .app, .pkg or .ipa: $target" >&2; exit 64 ;;
esac
[[ -n ${app:-} && -d $app ]] || { echo "No app found in $target" >&2; exit 1; }

codesign -d --entitlements - --xml "$app" 2>/dev/null > "$work/entitlements.plist"
printf 'Entitlements of %s:\n' "$app"
plutil -p "$work/entitlements.plist"

# iOS names the key aps-environment, macOS com.apple.developer.aps-environment.
python3 - "$work/entitlements.plist" <<'PY'
import plistlib, sys
e = plistlib.load(open(sys.argv[1], 'rb'))
aps = e.get('aps-environment', e.get('com.apple.developer.aps-environment'))
checks = {
    'iCloud container iCloud.asia.xdev.mindmapai':
        'iCloud.asia.xdev.mindmapai' in e.get('com.apple.developer.icloud-container-identifiers', []),
    'iCloud service CloudKit': 'CloudKit' in e.get('com.apple.developer.icloud-services', []),
    'aps-environment production': aps == 'production',
    'key-value store M6C7NX9MUZ.asia.xdev.mindmapai':
        e.get('com.apple.developer.ubiquity-kvstore-identifier') == 'M6C7NX9MUZ.asia.xdev.mindmapai',
    'App Group group.asia.xdev.mindmapai':
        'group.asia.xdev.mindmapai' in e.get('com.apple.security.application-groups', []),
}
for name, ok in checks.items():
    print(('ok      ' if ok else 'MISSING ') + name)
sys.exit(0 if all(checks.values()) else 1)
PY

# Every signed resource bundle inside the app must carry the distribution
# signature, or App Store Connect refuses the build (ITMS-90284, build
# 202610040006: the Swift package bundles of MLX kept the development one).
bad=0
while IFS= read -r -d '' bundle; do
  authority=$(codesign -dvv "$bundle" 2>&1 | sed -n 's/^Authority=//p' | head -n 1) || true
  [[ -z $authority ]] && continue
  if [[ $authority == "Apple Distribution:"* ]]; then
    printf 'ok      signed for distribution: %s\n' "${bundle#"$app"/}"
  else
    printf 'WRONG   %s is signed by %s\n' "${bundle#"$app"/}" "$authority"
    bad=1
  fi
done < <(find "$app" -name '*.bundle' -type d -print0)
exit $bad
