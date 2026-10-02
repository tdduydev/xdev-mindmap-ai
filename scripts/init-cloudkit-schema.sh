#!/usr/bin/env bash
# Creates the CloudKit development schema for iCloud sync (docs/cloudkit-sync.md,
# *Schema*; FR-SYN-07): builds a Debug app signed for the iCloud container and
# runs it once with -InitializeCloudKitSchema, which writes every SwiftData
# record type to CloudKit's development environment. Then check the record
# types in the CloudKit Console and deploy them to production.
#
#   scripts/init-cloudkit-schema.sh
#
# Needs a Mac signed in to iCloud (System Settings › Apple Account), with an Xcode account in team M6C7NX9MUZ for
# automatic signing (or the App Store Connect key in ~/.appstoreconnect, as on
# the Mac mini). Rerun after every schema change, before deploying it.
set -euo pipefail
cd "$(dirname "$0")/.."
# Command Line Tools ship no SwiftData macro plugins; use Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# On the Mac mini the development identity lives in the build keychain
# (docs/release.md); elsewhere Xcode's own account signs.
keychain="$HOME/Library/Keychains/mindmap-build.keychain-db"
if [[ -f "$HOME/.appstoreconnect/signing/keychain.pass" && -f "$keychain" ]]; then
  security unlock-keychain -p "$(cat "$HOME/.appstoreconnect/signing/keychain.pass")" "$keychain"
fi

auth=()
if [[ -f "$HOME/.appstoreconnect/mindmap.env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.appstoreconnect/mindmap.env"
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

derived=scripts/out/SchemaDerivedData
echo "==> Building a Debug app signed for iCloud"
xcodebuild build -quiet \
  -project MindMapAI.xcodeproj -scheme MindMapAI -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$derived" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
  DEVELOPMENT_TEAM=M6C7NX9MUZ CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  MINDMAP_ICLOUD=YES MINDMAP_MAC_APP_GROUP=YES

app=$(find "$derived/Build/Products/Debug" -maxdepth 1 -name '*.app' | head -n 1)
executable=$(defaults read "$PWD/$app/Contents/Info" CFBundleExecutable)
start=$(date '+%Y-%m-%d %H:%M:%S')

echo "==> Creating the schema (up to 5 minutes)"
"$app/Contents/MacOS/$executable" -InitializeCloudKitSchema >/dev/null 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

# The app logs one line when initializeCloudKitSchema returns (AppEnvironment).
result=""
for _ in $(seq 1 60); do
  sleep 5
  result=$(log show --start "$start" --style compact \
    --predicate 'subsystem == "asia.xdev.mindmapai" AND category == "Persistence"' 2>/dev/null \
    | grep -E "CloudKit development schema initialized|Initializing the CloudKit schema failed" || true)
  [[ -n "$result" ]] && break
done

if [[ "$result" == *"schema initialized"* ]]; then
  echo "Done. Next: CloudKit Console › iCloud.asia.xdev.mindmapai › Development › Record Types (CD_* types),"
  echo "then Deploy Schema Changes to production."
  exit 0
fi
# Without an iCloud account the app keeps a local store and never tries, so
# nothing is logged. (macOS 27 no longer has the MobileMeAccounts defaults an
# up-front check could read.)
# CloudKit can time out ("the requests timed out (a 30s wait failed)") on a busy
# Mac or network; running the script again has been enough.
echo "${result:-No result logged within 5 minutes. Is this Mac signed in to iCloud, and is iCloud on for MindMap AI in Settings?}" >&2
exit 1
