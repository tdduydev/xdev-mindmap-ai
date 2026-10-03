# iCloud sync

Status: built in MM-6; on from 1.1 (MM-100): `scripts/upload-testflight.sh` sets `MINDMAP_ICLOUD = YES` for macOS and iOS, while the project default stays `NO` so `scripts/ci.sh` builds without a certificate. 1.0.0 shipped with sync off. The schema is CloudKit-ready (see [data-model.md](data-model.md)); SchemaV3 is deployed to production.

## Goals

- Maps sync between the person's own Mac, iPad and iPhone through their private iCloud database (FR-SYN-01).
- No xDev account and no sync button.
- Editing never waits for sync. The device is always fully usable on its own: offline, signed out of iCloud, or with sync off (FR-SYN-02).

## How it works

| Part | Where | What it does |
| --- | --- | --- |
| Store | `PersistenceController.makeContainer(at:sync:)` | `Sync.privateDatabase(containerIdentifier:)` sets SwiftData's `cloudKitDatabase: .private("iCloud.asia.xdev.mindmapai")`; `.off` keeps `.none`. The same file opens either way, and persistent history stays on, so what was written while sync was off goes up once it is on. Tests, previews, UI tests and the Share Extension always use `.off`. |
| Choice at launch | `CloudSyncMonitor.storeSync` | `.appContainer` only when the build is entitled (`MINDMAP_ICLOUD`), the device's switch is on (`sync.iCloudEnabled`, default on) and it is not a UI test run. A build without the entitlement never touches CloudKit, because CloudKit stops a process that asks for a container it is not entitled to. |
| Changes from outside | `SwiftDataMapRepository` publishes `.storeChanged` for every transaction not signed by itself (CloudKit's import, the Share Extension, intents in another process) | Each open map runs `EditorSession.takeStoredChanges()`: saves its pending edits, loads the map, and gives it to `GraphEngine.takeStored(_:now:)`, which repairs, diffs and updates the canvas (FR-SYN-04). A burst of notices loads the map at most twice. |
| Map deleted elsewhere | `EditorSession.removedElsewhere` | The window shows "Map Not Found" or "Map in Recently Deleted" instead of the editor, so a later save cannot bring the map back. |
| Status | `CloudSyncMonitor` → `CloudSyncState` | Account status (`CKContainer.accountStatus`, `CKAccountChanged`, again on activation), network (`NWPathMonitor`) and the mirroring's events (`NSPersistentCloudKitContainer.eventChangedNotification`, which SwiftData's mirroring posts too). |

### Repair is shown, not saved

`takeStored` repairs what it loaded but does not save the repair. A topic that arrives before its parent hangs under the root only until the parent arrives; saving the repair would move it there for good and send that move to every device. `EditorSession.open` still saves its repairs, as before MM-6 (see *Open questions*).

## Maps from 1.0 (FR-SYN-08)

1.0 kept the library in the App Group store with sync off. 1.1 opens the same file with `cloudKitDatabase: .private(…)`; nothing is copied or migrated.

- What the mirroring needs is checked in `CloudUpgradeTests` against `Fixtures/V3.store` (written by 1.0): turning sync on points at the same file; the model CloudKit mirrors is compatible with the store's metadata, so no migration runs; the store opens with persistent history tracking (1.0 kept history on) and every record is there once; edits made while sync is off land in history.
- *[Chưa kiểm chứng]* That `NSPersistentCloudKitContainer` (which SwiftData's mirroring uses) exports records that existed before mirroring was turned on. Apple's Core Data with CloudKit pages say to add the capability and container options to an app that already uses Core Data, but do not state what happens to existing rows; a CloudKit process cannot run in the unentitled test process. Checked by step 0 of *Testing on real devices*.
- Duplicates. Each record has its own ID, so maps made on two devices are two maps, not a conflict. The one case that sends the same map ID up twice is a 1.0 library restored onto a second device (backup or device migration) before both turn sync on: each device exports its copy as its own CloudKit record. The library lists a map ID once (`SwiftDataMapRepository.fetchMaps` and `fetchDeletedMaps`, newest first) and the next save of that map folds the records into one (`mapRecord(for:)`); topics, links and other records were already folded per ID.

## First run and the sample map (FR-ONB-01, FR-SYN-08)

On a second device or after a reinstall the store starts empty while CloudKit is still bringing the library down. The 1.0 rule (MM-108: an empty library and Recently Deleted on first launch get the sample map) would then add a sample, sync it up, and add another one per device. `FirstRunGate` (MM-120) decides instead, after the window's first load:

1. A map in the library or Recently Deleted: no sample, no introduction.
2. Store not in iCloud this launch (switch off, build without the entitlement): as MM-108.
3. `onboarding.completed` set in the iCloud key-value store (`NSUbiquitousKeyValueStore`, beside the preferences of `PreferenceCloudSync`): another device had the first run; no sample.
4. iCloud account not available (signed out, restricted, needs attention, unknown): nothing can arrive, so as MM-108.
5. Otherwise wait until the first successful CloudKit import of this launch ends (`NSPersistentCloudKitContainer.eventChangedNotification`, type `.import`, seen by `FirstCloudImport`, which listens from before the store opens), the key-value flag arrives, or 20 seconds pass *[Đề xuất]*; then reload and apply 1 and 3 again; still empty means the sample.

Every device with its store in iCloud writes the key-value flag once it has had the first run, including one that finished it before 1.1. A device with sync off does not, so it cannot stop another device's sample for maps it never sent up. The library list keeps following the store during the wait. A failed import (offline) does not end the wait early.

*[Chưa kiểm chứng]* Whether the first `.import` event of a fresh install already holds every map, or CloudKit brings a large library in several imports. If only part arrives, step 1 still sees a map; only an import that ends with no map at all, on an account whose devices never wrote the flag, could still lead to a sample. Checked by step 0b of *Testing on real devices*.

## Undo after a change from another device (FR-UND-05)

Decided 2026-10-02 (Q5): drop the undo steps that touch the topics the remote change touched and keep the rest.

How `GraphEngine.takeStored` applies it:

- The change from outside is the difference between the open graph and the repaired stored graph. It **writes** a record when the record differs, and **removes** it when it is gone. The map record counts only when a graph field changed (title, root, theme, layout): every edit moves `updatedAt`, and the favorite flag and Recently Deleted are library data.
- An undo step is dropped when it writes a record the outside change wrote, or points at a record the outside change removed (a parent, the ends of a link, the topic or tag of a tag link, the ends of a boundary). A step that only adds a topic under a topic renamed elsewhere stays.
- Then every step that depends on a dropped step goes too: one writes a record the other points at or writes. Without this, undoing the add of a parent whose child's add is gone would leave the child without its parent.
- Redo is emptied whenever a step is dropped or a redo step touches the change, since the window's `UndoManager` cannot rebuild redo actions.
- The window's undo actions are registered again from `GraphEngine.undoStepNames`, one group each, with their names (`EditorSession.rebuildUndoActions`). If the undo manager is inside an open group, history is cleared instead of merging steps into one.
- Safety net: once steps were dropped, `undo()` and `redo()` validate the graph before a step lands. A step that would break it clears history and changes nothing.

## Status and Settings (FR-SYN-03, FR-SYN-06, FR-SET-04)

| `CloudSyncState` | Status line under the library sidebar | Settings ▸ Data ▸ iCloud |
| --- | --- | --- |
| `upToDate` | nothing | Up to Date |
| `syncing` | Syncing… | Syncing… |
| `waitingForNetwork` (offline, or a step failed on the network) | Waiting for Network | Waiting for Network; "Changes stay on this device and sync when you're back online." Not an error. |
| `notSignedIn` (no account, or the account went away mid-sync) | nothing | Not Using iCloud, with where to sign in |
| `restricted`, `accountNeedsAttention` | nothing | the state and where to look |
| `error(.quotaExceeded)`, `error(.other)` | iCloud Storage Is Full / Couldn't Sync | the same with what to do |
| `off`, `unavailable` | nothing | Off / Not Available |

Never an alert. Every state that is not syncing says the maps are still on this device. The Privacy row Data Storage reads "On this device and in your private iCloud" while the state is active. CloudKit errors are logged by code only.

**The switch.** The PO decided (2026-10-02) to keep an in-app switch only where the system has no per-app iCloud switch. iPhone and iPad list apps that use iCloud in Settings ▸ [name] ▸ iCloud with a switch each *[Inference, not checked on a device for a CloudKit-only app]*, so they show the status only. On the Mac, System Settings ▸ Apple Account ▸ iCloud lists apps that sync through iCloud Drive; a CloudKit-only app is not expected there *[Unverified: not checked on this Mac, no CloudKit-only app installed to compare; a person must look once the signed build exists]*. So the Mac gets the switch (Settings ▸ Data ▸ iCloud Sync). Turning it off keeps the maps and stops syncing; it deletes nothing. It applies at the next launch ("Quit and reopen MindMap AI to apply this change."): reopening the store under open windows was not worth the risk [Đề xuất; settings.md had planned to reopen at once].

## Conflicts

Sync merges per record, last writer wins per record. The design keeps that safe:

| Case | Outcome | Test (`SyncConflictTests`) |
| --- | --- | --- |
| Two devices edit different nodes | Both edits survive (one record each). | `editsOfDifferentTopicsBothSurvive` |
| Two devices edit the same node | Last writer wins for that node only; the losing device's undo keeps its other steps. | `theLastWriterWinsForTheSameTopicOnly`, `undoOnTheLosingDeviceKeepsOnlyUntouchedSteps` |
| A node arrives before its parent | Stored as is; shown under the root until the parent arrives, then under its parent. | `aTopicThatArrivesBeforeItsParentWaitsUnderTheRoot` |
| One device deletes a branch, another adds under it | The added nodes hang under the root; nothing is silently lost. | `topicsAddedUnderABranchDeletedElsewhereHangUnderTheRoot` |
| Two devices move nodes under each other | A loop; repair cuts it at the most recently edited node, the same way on both. | `movesUnderEachOtherAreCutTheSameWayOnBothDevices` |
| Offline edits on both, synced in either order | Same result on both. | `theOrderOfPullsDoesNotChangeTheResult` |
| The same record arrives twice | The newest `updatedAt` wins on load; the repository folds duplicates on save. | `SwiftDataMapRepositoryTests.duplicateRecordsAreFolded` |

Repair is deterministic, so devices reach the same result independently (FR-SYN-05).

`SyncConflictTests` simulates two devices: each has its own store and an open `GraphEngine`; a third store plays the private database. A push writes the device's change sets record by record (last push wins per record), a pull writes what differs into the device's store and the editor takes it in with `takeStored`. It does not simulate CloudKit's own behaviour (field-level merges, server-side tombstones, account changes). `StoredChangeSessionTests` (app) covers the editor: a second repository on the same file plays CloudKit's import, including the undo manager rebuild and a map deleted elsewhere.

## Turning it on (needs the Apple Developer account)

Not done by agents. In this order:

1. **Container.** developer.apple.com ▸ Certificates, Identifiers & Profiles ▸ Identifiers ▸ iCloud Containers: create `iCloud.asia.xdev.mindmapai`. *[Unverified]* The App Store Connect API has no endpoint for iCloud containers, so this step is on the website.
2. **Capability.** On the App ID `asia.xdev.mindmapai` enable iCloud (CloudKit, with the container above) and Push Notifications. The Share Extension (`asia.xdev.mindmapai.share`) needs neither: it writes to the shared store without mirroring, and the app sends those changes up.
3. **Profiles.** Regenerate the development and "MindMap AI Mac App Store" profiles of the app after the capability change (App Store Connect API `POST /v1/profiles`, or the website) and install them on the Mac mini. iOS profiles when iOS ships.
4. **Build setting.** Done in MM-100: `scripts/upload-testflight.sh` passes `MINDMAP_ICLOUD=YES` for both platforms (with `MINDMAP_MAC_APP_GROUP=YES` on the Mac). It picks `Entitlements/MindMapAI+iCloud-macOS.entitlements` or `-iOS.entitlements` (container, CloudKit, push, App Group) and compiles `MINDMAP_ICLOUD`. Leave the project default `NO`, so `scripts/ci.sh` keeps building without a certificate.
5. **Schema (FR-SYN-07).** `scripts/init-cloudkit-schema.sh` runs a Debug build signed for the container once with the launch argument `-InitializeCloudKitSchema` and waits for the result in the log (`PersistenceController.initializeCloudKitSchema`, Core Data's `initializeCloudKitSchema` on the same model, in a throwaway store). Check the record types in the CloudKit Console (development), then **Deploy Schema Changes** to production before the first TestFlight build with sync. Production only grows: never deploy a field before the schema that has it ships ([data-model.md](data-model.md)). SchemaV3 (MM-55) adds the `ChatTurnRecord` type. Done for V3 on 2026-10-03: created from a V3 build and deployed to production ([release.md](release.md), *iCloud before it can ship*).
6. **Two-device test** (a person): the tests below.

The `aps-environment` value in the entitlements files is `development`; the App Store export takes the profile's value. `scripts/upload-testflight.sh` exports locally first and runs `scripts/check-icloud-entitlements.sh`, which reads the signed app with `codesign -d --entitlements` and stops the upload unless it has the container, CloudKit, `aps-environment` `production`, the key-value store and the App Group. `UPLOAD=NO scripts/upload-testflight.sh [ios]` runs only the archive, export and check. Both platforms passed on 2026-10-03 ([release.md](release.md), *iCloud*).

## Testing on real devices (a person)

With two devices on the same Apple Account and a TestFlight build of 1.1:

0. **Maps from 1.0.** On one device, install 1.0.0 (App Store) or a 1.0 TestFlight build, make two maps (one with a chat, one in Recently Deleted), then update to 1.1 signed in to iCloud → the maps are still there once each, and appear on the second device with their topics, tags, images and chat. Repeat with the 1.0 library on both devices (a restored backup): each map is listed once on both.
0b. **No second sample map.** With 1.1 installed and a map on the first device (signed in to iCloud), install 1.1 on the second device signed in to the same account (or delete and reinstall it) → no sample map appears there, only the first device's maps once they arrive, and the first device does not get a second "sample". Repeat with the second device offline for the first launch: after 20 seconds it may show the sample only if the first device never ran 1.1 (no key-value flag).
1. Mac (or iPad) creates a map → the other device shows it without relaunching; the other edits a topic → the first shows the edit, and its undo menu no longer offers the step that touched that topic.
2. Airplane mode on one device, edit on both, reconnect → both edits survive (different topics), last writer wins (same topic); the status line says Waiting for Network while offline, never an alert.
3. Signed out of iCloud: the app opens and edits normally; Settings says Not Using iCloud.
4. Turn the Mac switch off, relaunch: edits stay local and do not reach the other device; turn it on, relaunch: they go up.
5. Delete a map that is open on the other device → that window shows "Map Not Found".
6. Fill iCloud storage (or use an account that is full) → Settings says iCloud Storage Is Full; nothing is lost.
7. Sign out and sign in with another Apple Account: what happens to the maps on the device *[Unverified: NSPersistentCloudKitContainer is reported to remove mirrored data from the store when the account changes; must be observed before release, and the privacy policy and Settings text checked against it]*.

## Open questions

- Whether `EditorSession.open` should stop saving tree repairs too (a topic whose parent has not arrived is moved under the root for good when the map is opened at that moment).
- Whether the map record's `updatedAt` should come from the server's modification time, so "Recent" ordering agrees across devices.
- Persistent history is never pruned; CloudKit mirroring needs it, so pruning waits for a measurement on a large store.
- `PreferenceCloudSync` (MM-45) mirrors the default theme and export defaults through iCloud key-value storage only while the app opens its iCloud store. Device-specific choices and map content are excluded; see [settings.md](settings.md).
