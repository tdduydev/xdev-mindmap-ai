# Apple Watch app

Design from MM-112 (ADR 0012) for FR-WCH-01..04. MM-116 builds it, after iCloud sync is on (MM-100). [Đề xuất] marks a choice the product owner has not confirmed. [Chưa kiểm chứng] marks an Apple behaviour no source or test confirms yet.

## As built (MM-116)

- **Targets:** `MindMapWatch` (single-target watchOS 26 app, `asia.xdev.mindmapai.watchkitapp`, folder `MindMapWatch/`) embeds `MindMapWatchWidgets` (`asia.xdev.mindmapai.watchkitapp.widgets`). The iOS app embeds the watch app in `Watch/` through an "Embed Watch Content" phase with `platformFilter = ios`, so the Mac build is unchanged. Shared scheme `MindMapWatch`.
- **Core:** `InboxCapture` and `ReadOnlyTopic` in `MindMapSharing` (`InboxCapture.swift`). `InboxCapture.addIdea(_:inboxTitle:)` reads the Inbox ID from an `InboxMapIDStore`, adds through `QuickCapture.addIdea(_:to:)` (one `InsertOutlineCommand`, origin `.user`, saved change set), and makes a new Inbox when the stored one is missing or in Recently Deleted. `UbiquitousInboxStore` keeps the ID under `inbox.mapID` in `NSUbiquitousKeyValueStore`. No new `GraphCommand`, no schema change. `Package.swift` adds `.watchOS(.v26)`; the watch links Domain, Graph, Persistence, Interchange and Sharing (Persistence pulls in AICore, Interchange pulls in Images; both build for watchOS).
- **iCloud:** like the app, the watch target signs with `Entitlements/MindMapWatch+iCloud.entitlements` (CloudKit container, key-value store `$(TeamIdentifierPrefix)asia.xdev.mindmapai`, `aps-environment`) only when `MINDMAP_ICLOUD=YES`, which also opens the store with `.appContainer`. ci.sh builds without it, so the Simulator build keeps the store on the watch. "iCloud Is Off" shows when the build has no iCloud or `FileManager.ubiquityIdentityToken` is nil.
- **Not done yet:** Background Modes ▸ Remote notifications (set it with the Xcode capability once the leader's profile is installed, so the key Xcode writes is the right one for watchOS); the size measurement on a real watch; the key-value sharing check between phone and watch on devices; a watchOS UI test (no watchOS Simulator runtime on the Mac mini on 2026-10-03); Settings ▸ Inbox Map on the phone and Mac.
- **Capture asks for time** with `ProcessInfo.performExpiringActivity` while it saves; whether that is enough after the wrist drops is not checked on a device [Chưa kiểm chứng].

## What it does

1. **Capture an idea** (FR-WCH-01): one button opens a text field. watchOS offers dictation, Scribble and the keyboard there. Each idea becomes one topic under the central topic of the Inbox map. A haptic and "Added to Inbox" confirm it. Saved on the watch at once, so it is never lost offline.
2. **Recent maps** (FR-WCH-02): up to 20 maps [Đề xuất], by last edit, without Recently Deleted. Tapping one shows its outline, read-only, with collapse and expand, Dynamic Type and VoiceOver. No canvas, no editing beyond capture, no AI (FR-WCH does not ask for it, and the screen is too small to review a suggestion before Accept).
3. **Complication and Smart Stack** (FR-WCH-03): open the capture screen directly.
4. **iCloud off** (FR-WCH-04): the watch says "Turn on iCloud for MindMap AI on your iPhone to see your maps here." Capture still saves on the watch and syncs once iCloud is on.

## Sync: SwiftData with CloudKit, not WatchConnectivity

| | SwiftData + CloudKit mirroring | WatchConnectivity |
| --- | --- | --- |
| Available on watchOS | `ModelConfiguration.CloudKitDatabase` from watchOS 10 ([SwiftData](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)) | `transferUserInfo` from watchOS 2, queued and delivered in order ([WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))) |
| Needs the iPhone app nearby | No: Wi-Fi or cellular is enough | Yes |
| Maps from the Mac | Yes, through iCloud | Only after the iPhone has synced them |
| Code paths | The same store and repository as the app | A second sync channel and its own merge rules |
| Testing | Store tests run anywhere; sync on devices | The Simulator does not support `transferUserInfo` (same source) |

**Decision:** SwiftData with mirroring to the private database of `iCloud.asia.xdev.mindmapai`, with the same schema version as the iOS app of the same build (SchemaV3 today). The watch opens its store through `PersistenceController` with `.privateDatabase`, and writes through `QuickCapture` (`MindMapSharing`), the same code the Share Extension and the Add Idea intent use. So every write is a graph command and a change set, and the repair rules of [cloudkit-sync](cloudkit-sync.md) apply unchanged.

Requirements from Apple ([Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)): the iCloud capability with CloudKit and the container, Background Modes ▸ Remote notifications, and push.

Open points for MM-116:

- **Size on the watch.** Mirroring copies the whole private zone, images (`ImageRecord`, external storage) and chat turns included. Whether CloudKit assets download eagerly is not documented in the sources read [Chưa kiểm chứng]. MM-116 measures a library with 100 maps and 50 images on a real watch. If the store is too large, the fallback is a watch store whose model holds only the map and topic records, which needs a read-only repository on the watch. Whether mirroring with a smaller model skips the other record types safely is not verified [Chưa kiểm chứng].
- **When an idea goes up.** Mirroring exports while the app runs. A watch app is suspended soon after the wrist drops, so an idea may stay on the watch until the next launch [Chưa kiểm chứng]. It is never lost, only late. Capture asks for a short extension of running time (`ProcessInfo.performExpiringActivity`) to finish the save [Đề xuất].
- **Schema versions.** The watch app and the iOS app ship in one build, but each device updates on its own. CloudKit schemas only grow, so an older watch ignores new fields, as an older iPhone does ([data-model](data-model.md)).
- **Package platforms.** `Packages/MindMapCore/Package.swift` gains `.watchOS(.v26)`. The watch links Domain, Graph, Persistence, Interchange and Sharing. All of them import only Foundation, SwiftData, Core Data and OSLog today. Not linked: Intents (CoreSpotlight), AI, MCP, Capture, Layout.

## Inbox map without a schema change

- The Inbox map's ID is in **iCloud key-value storage**, key `inbox.mapID` (a UUID string). The app already uses that store for preferences (MM-45, `PreferenceCloudSync`). `NSUbiquitousKeyValueStore` is available from watchOS 9, with 1 MB and 1,024 keys per app ([Foundation](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)).
- The watch app sets its key-value store identifier to the app's, `$(TeamIdentifierPrefix)asia.xdev.mindmapai` (`com.apple.developer.ubiquity-kvstore-identifier`, watchOS 2 and later, [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.ubiquity-kvstore-identifier)). Apps of one team can share a store through one identifier, but the pages read only document the entitlement, not the sharing [Chưa kiểm chứng]. MM-116 checks this on devices first. If the watch cannot read the phone's value, the fallback is an `isInbox` flag in a SchemaV4 (see below).
- **Capture:** read `inbox.mapID`. If the map exists and is not in Recently Deleted, call `QuickCapture.addIdea(_:to:)`. If not, create a map titled "Inbox" (localized, en/vi/ja), write its ID to the key, then add the idea.
- **Two Inboxes:** two devices can both create one before the key syncs. The key-value store keeps the last write. The other map stays an ordinary map with its ideas. Nothing is lost, and nothing merges automatically [Đề xuất].
- **Changing the Inbox** (FR-WCH-01 [Đề xuất]): Settings ▸ General ▸ Inbox Map on iPhone, iPad and Mac lists the maps and writes the key. Deleting the Inbox map lets the next capture make a new one.
- Like other values in that store, no map content goes there: only an ID. Apple warns against personal data in it (same source).
- **No SchemaV4.** If a later feature needs a schema change anyway, an `isInbox` flag could move there. Not before.

## Complication and Smart Stack

- Widget extension `MindMapWatchWidgets` with WidgetKit accessory widgets ([Creating accessory widgets and watch complications](https://developer.apple.com/documentation/widgetkit/creating-accessory-widgets-and-watch-complications)): circular, corner, rectangular and inline. The same widgets appear in the Smart Stack.
- Static content: the app's mark and "Add Idea". No map data, so the widget needs no App Group and no timeline reloads. `widgetURL` opens the capture screen.
- A relevance hint so the Smart Stack can surface it is optional and depends on the watchOS 26 relevance API, not checked [Chưa kiểm chứng].
- A Control for the Control Center on watchOS 26: later, not in FR-WCH.

## Targets and identifiers

| Target | Bundle ID | Capabilities |
| --- | --- | --- |
| `MindMapWatch` (single-target watch app, watchOS 26) | `asia.xdev.mindmapai.watchkitapp` | iCloud (CloudKit, `iCloud.asia.xdev.mindmapai`; key-value storage with the app's identifier), Push Notifications, Background Modes ▸ Remote notifications |
| `MindMapWatchWidgets` (widget extension) | `asia.xdev.mindmapai.watchkitapp.widgets` | none |

- `WKCompanionAppBundleIdentifier` = `asia.xdev.mindmapai`. Runs without the iOS app installed (`WKRunsIndependentlyOfCompanionApp` = YES [Đề xuất]), since it needs only iCloud.
- It ships inside the iOS app's upload, in the same App Store record. Universal purchase is unchanged.
- Strings in its own `Localizable.xcstrings` with en, vi, ja. Colours and type come from the design system (`MindMapUI`, see [app-clip](app-clip.md#modules-and-size)), with watch sizes.

## Privacy

- **App Privacy label:** unchanged, "Data Not Collected". Maps go to the person's own iCloud, as on the other devices.
- **`PrivacyInfo.xcprivacy`** for the watch app and the widget extension: no tracking, no collected data. `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` if they use `UserDefaults`. The key-value store is not a required-reason API.
- Ideas are map content: never logged ([privacy](privacy.md)).

## Apple account (leader)

1. **Bundle IDs** `asia.xdev.mindmapai.watchkitapp` (watchOS) with iCloud (CloudKit, container `iCloud.asia.xdev.mindmapai`) and Push Notifications, and `asia.xdev.mindmapai.watchkitapp.widgets`.
2. **Profiles**, App Store and development, for both. The Mac mini is the only build machine. A development profile needs a registered watch to run on a device.
3. **CloudKit**: nothing new. Same container, same schema, already in production (SchemaV3, 2026-10-03).
4. **App Store Connect**: watch screenshots for the iOS version (sizes from App Store Connect help; not checked here [Chưa kiểm chứng]). Review notes say the watch needs iCloud.
5. **`scripts/upload-testflight.sh ios`**: add both bundle IDs to the export options.
