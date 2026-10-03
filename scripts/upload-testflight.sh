#!/usr/bin/env bash
# Archives the app and uploads it to App Store Connect for TestFlight:
#
#   scripts/upload-testflight.sh          # the Mac app
#   scripts/upload-testflight.sh ios      # iPhone and iPad, same app record
#
# The API key lives outside the repo: ~/.appstoreconnect/mindmap.env names it
# (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH) and the .p8 stays in
# ~/.appstoreconnect/private_keys with mode 600. The key has the App Manager role,
# which cannot use cloud-managed distribution certificates, so the export signs
# with an Apple Distribution and a Mac Installer Distribution certificate kept in a
# separate keychain (~/Library/Keychains/mindmap-build.keychain-db, password in
# ~/.appstoreconnect/signing/keychain.pass) and the "MindMap AI Mac App Store"
# provisioning profiles of the app and of the Share Extension ("... iOS App Store"
# for iOS). The archive itself is signed with the Apple Development identity in
# the same keychain, since the App Group entitlement cannot be signed ad hoc.
# docs/release.md explains how they were made.
set -euo pipefail
cd "$(dirname "$0")/.."

platform=${1:-macos}
case "$platform" in
  macos)
    destination='generic/platform=macOS'
    platform_settings=(MINDMAP_MAC_APP_GROUP=YES)
    profile_suffix='Mac App Store'
    ;;
  ios)
    destination='generic/platform=iOS'
    platform_settings=()
    profile_suffix='iOS App Store'
    ;;
  *) echo "usage: $0 [macos|ios]" >&2; exit 64 ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

env_file="$HOME/.appstoreconnect/mindmap.env"
# shellcheck source=/dev/null
[[ -f "$env_file" ]] && source "$env_file"
: "${ASC_KEY_ID:?Set ASC_KEY_ID or create $env_file}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID or create $env_file}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH or create $env_file}"

keychain="$HOME/Library/Keychains/mindmap-build.keychain-db"
pass_file="$HOME/.appstoreconnect/signing/keychain.pass"
[[ -f "$keychain" && -f "$pass_file" ]] || { echo "Missing $keychain or $pass_file: see docs/release.md" >&2; exit 1; }
security unlock-keychain -p "$(cat "$pass_file")" "$keychain"

# App Store Connect refuses a build number it has seen, so each upload takes the time.
build_number="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
out=scripts/out/testflight-$platform
archive="$out/MindMapAI.xcarchive"
rm -rf "$out" && mkdir -p "$out"

auth=(-allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")

printf '\n==> Archive %s (build %s, commit %s)\n' "$platform" "$build_number" "$(git rev-parse --short HEAD)"
xcodebuild archive -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI -configuration Release \
  -destination "$destination" \
  -archivePath "$archive" \
  CURRENT_PROJECT_VERSION="$build_number" \
  DEVELOPMENT_TEAM=M6C7NX9MUZ \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  ${platform_settings[@]+"${platform_settings[@]}"} \
  "${auth[@]}"

cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>M6C7NX9MUZ</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
$( [[ $platform == macos ]] && echo '  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>' || true)
  <key>provisioningProfiles</key>
  <dict>
    <key>asia.xdev.mindmapai</key><string>MindMap AI $profile_suffix</string>
    <key>asia.xdev.mindmapai.share</key><string>MindMap AI Share $profile_suffix</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

printf '\n==> Upload to App Store Connect\n'
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$out/export" \
  "${auth[@]}"

printf '\nUploaded %s build %s from %s. It appears in TestFlight after Apple finishes processing;\nadd a row to the Uploads table in docs/release.md.\n' "$platform" "$build_number" "$(git rev-parse --short HEAD)"
