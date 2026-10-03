# Release

How a build of MindMap AI reaches TestFlight and the Mac App Store. Set up on 2026-10-02 on the Mac mini that runs the team's agents (hc-duytd20-macmini).

## App Store Connect

| Item | Value |
| --- | --- |
| App | MindMap AI by xDev, Apple ID 6818476277, SKU `MINDMAPAI-MAC`, primary language English (U.S.) |
| Platforms | macOS first; iOS is added to the same app later (universal purchase, ADR 0006) |
| Bundle ID | `asia.xdev.mindmapai`, registered as UNIVERSAL so iOS can share it. Capabilities: In-App Purchase, Push Notifications, iCloud (CloudKit, container `iCloud.asia.xdev.mindmapai`), App Groups (`group.asia.xdev.mindmapai`); the Share Extension `asia.xdev.mindmapai.share` has App Groups. Set on 2026-10-02 |
| More bundle IDs (2026-10-03, ADR 0012) | App Clip `asia.xdev.mindmapai.Clip` (App Clip type, parent `asia.xdev.mindmapai`; App Groups `group.asia.xdev.mindmapai.clip`, Associated Domains, On Demand Install Capable); watch app `asia.xdev.mindmapai.watchkitapp` (iCloud with container `iCloud.asia.xdev.mindmapai`, Push Notifications); watch widgets `asia.xdev.mindmapai.watchkitapp.widgets`. The app itself gained Associated Domains and the second App Group `group.asia.xdev.mindmapai.clip` the same day |
| Model downloader (2026-10-03, MM-106) | `asia.xdev.mindmapai.modeldownloader` (UNIVERSAL, App Groups `group.asia.xdev.mindmapai`), profiles "MindMap AI Model Downloader Mac App Store" and "MindMap AI Model Downloader iOS App Store", for the Background Assets extension that `scripts/upload-testflight.sh` exports once MM-106 is on `main` |
| Team ID | `M6C7NX9MUZ`, passed as `DEVELOPMENT_TEAM` by `scripts/upload-testflight.sh` only; the project leaves it empty so `scripts/ci.sh` builds on machines without a signing certificate |
| Version | 0.1.0 for the TestFlight beta; 1.0.0 for the first public release (submitted 2026-10-03, tag `v1.0.0`); `main` is 1.1.0 from 2026-10-03. The build number is the upload time (`YYYYMMDDHHmm`) |

## What lives outside the repo

Nothing below is ever committed or written to Hive. If the machine is replaced, recreate it as described.

| Path | What | Mode |
| --- | --- | --- |
| `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` | App Store Connect API key "MindMap AI CI", role App Manager | 600 |
| `~/.appstoreconnect/mindmap.env` | `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` | 600 |
| `~/.appstoreconnect/signing/` | Private keys of the two distribution certificates, the keychain password | 700 / 600 |
| `~/Library/Keychains/mindmap-build.keychain-db` | Keychain with the Apple Distribution and Mac Installer Distribution identities, the Apple Development identity (created through the API on 2026-10-03 for `scripts/init-cloudkit-schema.sh`, expires 2027-10-02; the Mac mini is registered as device "hc-duytd20-macmini") and the Apple WWDR G3 intermediate | — |
| `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` | Profiles "MindMap AI Mac App Store" (app) and "MindMap AI Share Mac App Store" (Share Extension, bundle ID `asia.xdev.mindmapai.share`, created 2026-10-02 with the same Apple Distribution certificate as the app, expires 2027-10-02), both MAC_APP_STORE | — |
| Same folder and `~/Library/MobileDevice/Provisioning Profiles/` | Since 2026-10-03, after the capability changes for ADR 0012: "MindMap AI iOS App Store" and "MindMap AI Mac App Store" generated again, and new IOS_APP_STORE profiles "MindMap AI Clip iOS App Store", "MindMap AI Watch App Store" and "MindMap AI Watch Widgets App Store". On this Mac a new profile file sometimes shows up in only one of the two folders; copy it to both | — |

The API key has the App Manager role, which cannot use Xcode's cloud-managed distribution certificates. So the certificates were created through the API from locally generated keys, and the export signs manually. A key with the Admin role would allow cloud signing instead; it was not created, to keep the key's rights small.

The certificates and the profile expire on 2027-10-02.

## iCloud

The container and capabilities exist and both profiles carry them (recreated on 2026-10-02 after the capability change). MM-45 added the iCloud key-value store identifier to the app's iCloud entitlements for theme and export preferences; confirm the app profile permits it before an iCloud-signed archive. The product owner chose on 2026-10-03 to turn sync on in 1.1 (MM-100).

1. Done on 2026-10-03: the development schema was created from a SchemaV3 build with `scripts/init-cloudkit-schema.sh` on the Mac mini (signed in to iCloud), and **Deploy Schema Changes** sent it to production: record types `CD_ChatTurnRecord`, `CD_EdgeRecord`, `CD_GroupRecord`, `CD_ImageRecord`, `CD_MapRecord`, `CD_NodeRecord`, `CD_NodeTagRecord`, `CD_TagRecord` with their indexes. Production only grows: a SchemaV4 runs the script again from a V4 build and deploys before the first upload that has it.
2. From MM-100 (1.1), `scripts/upload-testflight.sh` archives with `MINDMAP_ICLOUD=YES` on both platforms. The project default stays `NO`, so `scripts/ci.sh` and any build without the signing keychain have no iCloud entitlement and never open CloudKit.
3. Before each upload the script exports locally and runs `scripts/check-icloud-entitlements.sh` on the export (`codesign -d --entitlements`): the container `iCloud.asia.xdev.mindmapai`, CloudKit, `aps-environment` `production` (`com.apple.developer.aps-environment` on the Mac), the key-value store `M6C7NX9MUZ.asia.xdev.mindmapai` and the App Group. A missing one stops the upload. `UPLOAD=NO scripts/upload-testflight.sh [ios]` stops after the check. Run on 2026-10-03 from `1b409dc` with `UPLOAD=NO` for macOS (`.pkg`) and iOS (`.ipa`): all five present in both, plus `com.apple.developer.icloud-container-environment` `Production`, which the export adds.
4. The iOS export also carries the watch app (MM-116): `MindMap AI Watch App Store` and `MindMap AI Watch Widgets App Store` are in the export options for `ios`. `check-icloud-entitlements.sh` checks only the phone app; check the watch's with `codesign -d --entitlements - "Payload/MindMap AI.app/Watch/MindMapWatch.app"` in the unpacked `.ipa` (container, CloudKit, key-value store, `aps-environment`) until the script does it.
5. Test two devices as in docs/cloudkit-sync.md *Testing on real devices* (the product owner, on the first 1.1 TestFlight build), including step 0, maps from 1.0.

1.0.0 (builds 202610031203 and 202610031207) shipped with iCloud off.

## Upload a build

Run it on the Mac mini: the signing keychain, profile and API key exist only there.

### Uploads

Every upload adds a row here with the commit it was archived from, so whether a schema has shipped can be read from this table (see *V2 or V3* in [data-model.md](data-model.md)).

| Build | Version | Uploaded (UTC) | Commit | Schema |
| --- | --- | --- | --- | --- |
| 202610021635 | 0.1.0 | 2026-10-02 09:38 | not recorded | V1 |
| 202610021704 | 0.1.0 | 2026-10-02 10:07 | not recorded | V1 |
| 202610021725 | 0.1.0 | 2026-10-02 10:31 | not recorded | V1 |
| 202610021848 | 0.1.0 | 2026-10-02 11:51 | `a9f7028` | V1 |
| 202610030024 | 0.1.0 (macOS) | 2026-10-02 17:30 | `a2b8ef3` | V2 (node types) |
| 202610030030 (iOS, iPhone and iPad) | 0.1.0 | 2026-10-02 17:34 | `a2b8ef3` | V2 (node types) |
| 202610031203 (macOS) | 1.0.0 | 2026-10-03 05:05 | `a5e2508` | V3 (chat history) |
| 202610031207 (iOS, iPhone and iPad) | 1.0.0 | 2026-10-03 05:09 | `a5e2508` | V3 (chat history) |
| 202610031802 (macOS) | 1.1.0 | 2026-10-03 11:09 | `116da74` | V3, first upload with iCloud sync on (MM-100) |
| 202610031809 (iOS, iPhone and iPad) | 1.1.0 | 2026-10-03 11:16 | `116da74` | V3, iCloud sync on. Hangs at launch on iPhone once the library has maps (library chat inspector, fixed in `bdd33bd`); expired in TestFlight |
| 202610032345 (iOS, iPhone and iPad) | 1.1.0 | 2026-10-03 17:06 | `579438d` | V3, iCloud on, the hang fixed, first upload after the iOS Simulator smoke test |
| 202610040006 (macOS) | 1.1.0 | 2026-10-03 17:21 | `579438d` | Refused in processing, ITMS-90284: the Swift package resource bundles of MLX kept the development signature (fixed in `7dbbf33`) |
| 202610040024 (macOS) | 1.1.0 | 2026-10-03 17:39 | `7dbbf33` | V3, iCloud on, package bundles signed for distribution |

The first four are processed (`VALID`) in App Store Connect, read through the API on 2026-10-02, and none contains SchemaV2: `SchemaV2.swift` first appears in `9766bc0`, committed at 11:54 UTC, after the last of them was archived (the build number is the archive time, UTC+7). A later upload stopped by hand while sending left no build.

From 202610030024 on, SchemaV2 has shipped to testers, and from the 1.0.0 builds 202610031203 and 202610031207 SchemaV3: a schema change now needs SchemaV4 and a migration stage ([data-model.md](data-model.md)). The iOS platform was added to the same app record on 2026-10-03 (universal purchase, ADR 0006). On 2026-10-03 the product owner chose to submit 1.0.0 for Mac, iPhone and iPad together, released as soon as App Review approves it (release type `AFTER_APPROVAL`). Internal testers are in the TestFlight group "xDev Internal", which gets every build.

```bash
scripts/upload-testflight.sh        # Mac
scripts/upload-testflight.sh ios    # iPhone and iPad
```

Before an iOS upload it runs `LibraryUITests` on the iOS Simulator (a library with maps) and stops if they fail: TestFlight 1.1.0 build 202610031809 hung at launch on iPhone in an endless layout loop that `scripts/ci.sh` (no UI tests) and the Mac never showed. `SKIP_SMOKE=YES` skips the check. It unlocks the build keychain, archives the Release configuration for macOS with the API key, and exports with `destination upload`. The build shows up in TestFlight once Apple finishes processing it (usually 10–30 minutes). Set `BUILD_NUMBER` to override the time-based number.

## Recreating the signing setup

1. In App Store Connect, Users and Access › Integrations › Team Keys: generate a key with the App Manager role, download the `.p8` once into `~/.appstoreconnect/private_keys/`, and write `mindmap.env`.
2. Generate two RSA keys and CSRs with `openssl`, then create a `DISTRIBUTION` and a `MAC_INSTALLER_DISTRIBUTION` certificate with `POST /v1/certificates`.
3. Create the keychain, import both identities with access for `codesign` and `productbuild`, run `security set-key-partition-list`, add the keychain to the user search list, and import `AppleWWDRCAG3.cer` from apple.com/certificateauthority.
4. Create a MAC_APP_STORE profile for each bundle ID (`asia.xdev.mindmapai` and `asia.xdev.mindmapai.share`, registered with `POST /v1/bundleIds`) and the distribution certificate with `POST /v1/profiles`, and save them into the profiles folder. Every new extension needs its own bundle ID, profile and a line in the export options of `scripts/upload-testflight.sh`.
