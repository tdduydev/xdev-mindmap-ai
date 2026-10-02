# System integration

MM-11: the Share Extension, App Intents and Shortcuts, and Spotlight (FR-SYS-01 to FR-SYS-04).

## Pieces

| Piece | Where | Does |
| --- | --- | --- |
| `MindMapSharing` | `Packages/MindMapCore` | `QuickCapture` adds outlines to maps through `InsertOutlineCommand` and saves the change set; `SharedContent` turns shared text and links into an `OutlineDraft`; `ShareInbox` keeps images and PDFs in the App Group. No UI, no AI. |
| `AppGroup`, `StoreRelocation` | `MindMapPersistence` | The App Group ID, the shared store path, and moving a store an older build left in the app's own container. |
| `MindMapIntents` | `Packages/MindMapCore` | `MapEntity` (an `IndexedEntity`), its query, five intents, `MindMapIntentsPackage`, `MindMapIntentServices` (what the intents do, testable without App Intents) and `SpotlightMapIndex`. |
| `MindMapShareExtension/` | Xcode target | Share sheet on macOS and iOS: reads the attachments, lets the user pick a map or a new one, then calls `QuickCapture` and `ShareInbox`. |
| App target | `App/AppEnvironment`, `App/AppShortcuts`, `App/MapOpenRequests` | Opens the App Group store, registers `MindMapIntentServices` with `AppDependencyManager`, lists App Shortcuts, opens maps the intents ask for. |

`MindMapIntents` sits in `MindMapCore` rather than a separate `MindMapSystem` package ([[module-structure]] planned one): one package reference in the project, and `swift test` covers it with the rest. It imports AppIntents and CoreSpotlight but no UI framework.

## Store

The app opens the store at `<group container>/Library/Application Support/MindMapAI.store` when it has the App Group entitlement, and moves a store found at the old location first (`StoreRelocation`: the database with its `-wal`/`-shm` files and SwiftData's support folder; an existing shared store is never replaced). Without the entitlement it keeps its own store, so unsigned builds still run.

`.standard` uses `groupContainer: .none` on purpose: SwiftData's default `.automatic` follows the first App Group entitlement, which would hide the old store from the move.

The extension never creates the store (`AppGroup.hasStore`): before the app has run once, it asks the user to open the app. It opens the store, writes through `QuickCapture`, and closes. The app reloads the library when it becomes active; a map open in an editor does not see topics the extension added until it is opened again.

## Intents

| Intent | Mode | Does |
| --- | --- | --- |
| `NewMapIntent` ("New Mind Map") | foreground | Empty map, optional title, opens it |
| `MapFromClipboardIntent` | foreground | Clipboard text as Markdown, opens the map. Foreground because iOS only gives the clipboard to a foreground app |
| `AddIdeaIntent` | background | One topic under the central topic of a chosen map, or of the most recently edited one; no map at all starts one |
| `OpenRecentMapIntent` | foreground | Opens the most recently edited map |
| `OpenMapIntent` (`OpenIntent`) | foreground | Opens a chosen map; what a Spotlight result runs |

Intents run in the app process. Opening a map sets `MapOpenRequests.pending`; the window that sees it reloads the library and selects the map. Titles and descriptions are keys in the app's `Localizable.xcstrings`; App Shortcut phrases are in `AppShortcuts.xcstrings`.

## Spotlight

Only map titles are indexed, as `MapEntity` values. `LibraryModel` rebuilds the index on the first load, then indexes new or renamed maps and removes deleted ones; a reload after the app becomes active picks up maps added by the extension or the intents.

## Signing (needs a person)

App Groups need a development team: on macOS Xcode refuses to sign the entitlement ad hoc. The project therefore has a switch:

- iOS and the iOS Simulator always use `Entitlements/MindMapAI.entitlements` and `Entitlements/MindMapShareExtension.entitlements` (`group.asia.xdev.mindmapai`).
- macOS uses them only with `MINDMAP_MAC_APP_GROUP = YES` (project build setting, `NO` by default) so `scripts/ci.sh` and unsigned local builds keep working. With `NO` the Mac app uses its own store and the Mac extension shows "Open MindMap AI First".

Before release: set `DEVELOPMENT_TEAM`, register the App Group `group.asia.xdev.mindmapai` for `asia.xdev.mindmapai` and `asia.xdev.mindmapai.share` in the developer account, set `MINDMAP_MAC_APP_GROUP = YES`, then check on a Mac and an iPhone that sharing from Safari adds a topic and that a Spotlight result opens the map.

## Not done yet

- Images and PDFs wait in the inbox (`ShareInbox`); nothing reads them yet. OCR and PDF text belong to `MindMapCapture`, which does not exist yet (FR-SYS-02).
- No UI test for the extension, and no AppIntentsTesting tests: the services under the intents are tested instead.
