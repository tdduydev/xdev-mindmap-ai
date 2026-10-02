# Release

How a build of MindMap AI reaches TestFlight and the Mac App Store. Set up on 2026-10-02 on the Mac mini that runs the team's agents (hc-duytd20-macmini).

## App Store Connect

| Item | Value |
| --- | --- |
| App | MindMap AI by xDev, Apple ID 6818476277, SKU `MINDMAPAI-MAC`, primary language English (U.S.) |
| Platforms | macOS first; iOS is added to the same app later (universal purchase, ADR 0006) |
| Bundle ID | `asia.xdev.mindmapai`, registered as UNIVERSAL so iOS can share it. Capabilities: In-App Purchase, Push Notifications, iCloud (CloudKit, container `iCloud.asia.xdev.mindmapai`), App Groups (`group.asia.xdev.mindmapai`); the Share Extension `asia.xdev.mindmapai.share` has App Groups. Set on 2026-10-02 |
| Team ID | `M6C7NX9MUZ`, passed as `DEVELOPMENT_TEAM` by `scripts/upload-testflight.sh` only; the project leaves it empty so `scripts/ci.sh` builds on machines without a signing certificate |
| Version | 0.x for TestFlight while in beta, 1.0.0 for the public release; the build number is the upload time (`YYYYMMDDHHmm`) |

## What lives outside the repo

Nothing below is ever committed or written to Hive. If the machine is replaced, recreate it as described.

| Path | What | Mode |
| --- | --- | --- |
| `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` | App Store Connect API key "MindMap AI CI", role App Manager | 600 |
| `~/.appstoreconnect/mindmap.env` | `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` | 600 |
| `~/.appstoreconnect/signing/` | Private keys of the two distribution certificates, the keychain password | 700 / 600 |
| `~/Library/Keychains/mindmap-build.keychain-db` | Keychain with the Apple Distribution and Mac Installer Distribution identities and the Apple WWDR G3 intermediate | — |
| `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` | Profiles "MindMap AI Mac App Store" (app) and "MindMap AI Share Mac App Store" (Share Extension, bundle ID `asia.xdev.mindmapai.share`, created 2026-10-02 with the same Apple Distribution certificate as the app, expires 2027-10-02), both MAC_APP_STORE | — |

The API key has the App Manager role, which cannot use Xcode's cloud-managed distribution certificates. So the certificates were created through the API from locally generated keys, and the export signs manually. A key with the Admin role would allow cloud signing instead; it was not created, to keep the key's rights small.

The certificates and the profile expire on 2027-10-02.

## iCloud before it can ship

The container and capabilities exist and both profiles carry them (recreated on 2026-10-02 after the capability change). Two steps remain before `MINDMAP_ICLOUD=YES` can go into the upload script, and both need a Mac signed in to iCloud (the Mac mini is not):

1. Run a Debug build with `MINDMAP_ICLOUD=YES` once with CloudKit schema initialisation (docs/cloudkit-sync.md), check the record types in CloudKit Console, then **Deploy Schema Changes** to production. TestFlight and App Store builds use only the production schema.
2. Test two devices as in docs/cloudkit-sync.md *Testing*.

Until then uploads keep iCloud off; the App Group is on.

## Upload a build

Run it on the Mac mini: the signing keychain, profile and API key exist only there. On 2026-10-02 the first upload signed fine and was stopped by hand while sending, so build 0.1.0 is not on TestFlight yet.

```bash
scripts/upload-testflight.sh
```

It unlocks the build keychain, archives the Release configuration for macOS with the API key, and exports with `destination upload`. The build shows up in TestFlight once Apple finishes processing it (usually 10–30 minutes). Set `BUILD_NUMBER` to override the time-based number.

## Recreating the signing setup

1. In App Store Connect, Users and Access › Integrations › Team Keys: generate a key with the App Manager role, download the `.p8` once into `~/.appstoreconnect/private_keys/`, and write `mindmap.env`.
2. Generate two RSA keys and CSRs with `openssl`, then create a `DISTRIBUTION` and a `MAC_INSTALLER_DISTRIBUTION` certificate with `POST /v1/certificates`.
3. Create the keychain, import both identities with access for `codesign` and `productbuild`, run `security set-key-partition-list`, add the keychain to the user search list, and import `AppleWWDRCAG3.cer` from apple.com/certificateauthority.
4. Create a MAC_APP_STORE profile for each bundle ID (`asia.xdev.mindmapai` and `asia.xdev.mindmapai.share`, registered with `POST /v1/bundleIds`) and the distribution certificate with `POST /v1/profiles`, and save them into the profiles folder. Every new extension needs its own bundle ID, profile and a line in the export options of `scripts/upload-testflight.sh`.
