#!/bin/zsh
# Builds the two spike binaries (MM-48) into ./out, sandboxed, with an
# embedded Info.plist and the App Group in $GROUP.
#   IDENTITY="-"                     ad-hoc (no team; what scripts/ci.sh has)
#   IDENTITY="Apple Development: …"  team-signed, from the build keychain
#   NETWORK=YES                      also claim network.client/server (control)
set -euo pipefail
cd "${0:A:h}"
IDENTITY=${IDENTITY:--}
GROUP=${GROUP:-M6C7NX9MUZ.asia.xdev.mindmapai}
rm -rf out && mkdir -p out

for name in server helper; do
  id="asia.xdev.mindmapai.${SPIKE_PREFIX:-spike}-$name"
  cat > "out/$name-Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleName</key><string>$name</string>
</dict></plist>
PLIST
  network=""
  if [[ ${NETWORK:-NO} == YES ]]; then
    network="<key>com.apple.security.network.client</key><true/><key>com.apple.security.network.server</key><true/>"
  fi
  cat > "out/$name.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
$network
</dict></plist>
PLIST
  xcrun swiftc -O -parse-as-library Socket.swift "$name.swift" -o "out/$name" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "out/$name-Info.plist"
  codesign --force --options runtime --timestamp=none -s "$IDENTITY" \
    --identifier "$id" --entitlements "out/$name.entitlements" "out/$name"
done
codesign -d --entitlements - --xml out/helper 2>/dev/null | plutil -p - || true
