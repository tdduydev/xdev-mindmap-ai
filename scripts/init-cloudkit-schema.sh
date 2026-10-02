#!/usr/bin/env bash
# Creates the CloudKit development schema for iCloud sync (docs/cloudkit-sync.md,
# *Schema*; FR-SYN-07): builds a Debug app signed for the iCloud container and
# runs it once with -InitializeCloudKitSchema, which writes every SwiftData
# record type to CloudKit's development environment. Then check the record
# types in the CloudKit Console and deploy them to production.
#
#   scripts/init-cloudkit-schema.sh
#
# Needs a Mac signed in to iCloud, with an Xcode account in team M6C7NX9MUZ for
# automatic signing (or the App Store Connect key in ~/.appstoreconnect, as on
# the Mac mini). Rerun after every schema change, before deploying it.
set -euo pipefail
cd "$(dirname "$0")/.."
# Command Line Tools ship no SwiftData macro plugins; use Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# CloudKit creates the schema through the signed-in account; without one the
# app keeps a local store and nothing reaches CloudKit.
if ! defaults read MobileMeAccounts Accounts 2>/dev/null | grep -q AccountID; then
  echo "This Mac is not signed in to iCloud, so CloudKit cannot create the schema." >&2
  exit 1
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
  DEVELOPMENT_TEAM=M6C7NX9MUZ CODE_SIGN_STYLE=Automatic \
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
echo "${result:-No result logged within 5 minutes. Is iCloud on for MindMap AI in Settings?}" >&2
exit 1
