# Settings

Design for MM-42, 2026-10-02: every pane and row of Settings on Mac, iPad and iPhone, with its English and Vietnamese name, default, where it is stored, Free or Pro, and the task that builds it. Today's code is in `MindMapAI/Features/Settings/SettingsView.swift`, `Features/AI/AISettingsSection.swift`, `Features/Interchange/ExportOptions.swift` and `Features/Store/PaywallView.swift` (`ProSettingsSection`). Requirements are FR-SET-01…09 in [[srs-3-mo-rong]]. [Đề xuất] marks a choice the product owner has not confirmed; *[Inference]* marks reasoning no source states. Apple pages were read on 2026-10-02.

## Rules

| Rule | Source |
| --- | --- |
| Settings holds general, rarely changed options. Options for one task (show or hide part of a view, filter, reorder) stay in that task's screen. | [HIG Settings](https://developer.apple.com/design/human-interface-guidelines/settings) (General settings, Task-specific options) |
| Few settings, with defaults that suit most people, so nobody has to change anything before starting. | HIG Settings (Best practices) |
| Do not ask for what the app can detect, and do not copy a system-wide setting (accessibility, scrolling, appearance of other apps) into the app. | HIG Settings (Best practices) |
| Mac: App ▸ Settings… and ⌘, open a window with a fixed, non-customisable toolbar of panes that always shows the active pane. The window title follows the pane, the last pane reopens, minimise and zoom are dimmed, no Settings button in any window toolbar. (The product owner chose an exception on 2026-10-03: see Mac below.) Per-document options go in File, not Settings. | HIG Settings (macOS), [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) |
| iPad menu bar: App ▸ Settings opens the app's page in the system Settings app; the in-app settings item sits beneath it. | The menu bar, [[design-guidelines]] (iPad) |
| A link that opens the system Settings app is fine for options that live there. | HIG Settings (System settings) |
| A switch for a setting that turns a group of things on or off; in a grouped form, a mini switch keeps row heights even. Checkboxes for a hierarchy. | [HIG Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) |
| No alert for common actions that can be undone; an alert for an uncommon destructive action that cannot be undone. A deliberately chosen action like Empty Trash does not get the destructive style; Cancel is never the default button. | [HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) |
| Restore windows and their state at relaunch. | [HIG Launching](https://developer.apple.com/design/human-interface-guidelines/launching) |
| Changes apply at once: no Apply, OK or Cancel. Common Mac practice; not stated on the HIG page (not verified). | [[design-guidelines]] (Windows, Settings) |
| One name per thing, Title Case for controls, sentence case for footers; strings in `Localizable.xcstrings` with `en` and `vi`; standard SwiftUI `Form` with `.formStyle(.grouped)`, system fonts and colours (chrome, not canvas). | `AGENTS.md`, [[design-system]] |

## Where a setting lives

| Store | Use it for | Notes |
| --- | --- | --- |
| **AppDefaults** | Everything that belongs to this device or this install | `AppDefaults.store` (UserDefaults; a throwaway suite under `-uitest`). Every `@AppStorage` passes `store: AppDefaults.store`. UserDefaults is already declared in `PrivacyInfo.xcprivacy` (CA92.1). |
| **iCloud KVS** (MM-45) | A few taste preferences that should follow the person to their other devices: default theme, export defaults | `PreferenceCloudSync` starts only when this launch uses the iCloud store. It mirrors the theme and five export keys from AppDefaults to `NSUbiquitousKeyValueStore` and takes `didChangeExternallyNotification`; map content and device choices never go there. At start, a present cloud value is read into the local copy; otherwise an existing local choice seeds the cloud. The iCloud entitlement includes the key-value store identifier. `NSUbiquitousKeyValueStore` has at most 1,024 keys and 1 MB in total; Apple says not to store personal or sensitive information there ([NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)). |
| **SwiftData, per map** | What belongs to one map: its theme, collapse state, tags | Changed in the editor (File, Format, inspector) as a `GraphCommand` with undo, never from Settings (HIG: per-document options are not app settings). |
| **Keychain** | Secrets: MCP client tokens | Never in defaults or logs ([[privacy]]). |
| **`@SceneStorage`** | Window state: section, open map, editor state | Restored by the system; not a setting. |
| **StoreKit** | Pro status | Read from `Transaction.currentEntitlements`, never cached in defaults ([[pricing]]). |
| **System** | Appearance of the system, Apple Intelligence, microphone and speech permission, Pencil's "Only Draw with Apple Pencil", window restoration | The app reads them and links to them; it does not copy them (HIG Settings). |

Keys follow the existing pattern `area.name` (`export.includeNotes`, `voiceInput.language`); `appearance` stays as it is because it has shipped.

## Layout

**Mac:** the `Settings` scene, a `TabView` with one tab per pane, 480 pt wide (`Metrics.settingsWidth`), each pane one grouped `Form`. Panes, in this order: General, Export, AI, Data, AI Apps, Pro, Privacy, About. The window title is the pane's name. To reopen the last pane, the selected tab is kept in AppDefaults (`settings.pane`) [Đề xuất] (HIG Settings: restore the most recently viewed pane).

The Mac opens Settings from App ▸ Settings… (⌘,) and, decided by the product owner on 2026-10-03 (MM-72) because ⌘, alone was hard to find, from two buttons in the library window: **Settings** (Cài đặt, `gearshape`, tooltip "Open Settings (⌘,)") at the foot of the sidebar under the iCloud status line (`AccessibilityID.Sidebar.settings`) and in the toolbar (`AccessibilityID.Library.settings`). Both are a `SettingsLink` (`Features/Settings/SettingsButton.swift`), so they open the same window as ⌘,. Map windows get no button. This departs from HIG Settings (no Settings button in a window toolbar) on purpose.

**iPad and iPhone:** the sheet from the sidebar's Settings button (`SidebarView`). With eight groups, one flat form gets long, so the sheet becomes a `NavigationStack` list in the style of the system Settings app [Đề xuất]: a Pro status row on top, then one row per pane (symbol and name) that pushes that pane's `Form`, and Done in the confirmation slot. The pane views are the same SwiftUI views as on the Mac; only the container differs (`#if os(macOS)` in `SettingsView`, as today). AI Apps does not exist on iPad and iPhone (Mac only, [[mcp]]). The iPad App menu gets the in-app item under the system one (HIG The menu bar); its title is decided in MM-43 (*[Inference]* "MindMap AI Settings…" keeps the system's "Settings" item distinct).

Symbols: General `gearshape`, Export `square.and.arrow.up`, AI `sparkles`, Data `externaldrive` (`icloud` once sync ships), AI Apps `point.3.connected.trianglepath.dotted`, Pro `star`, Privacy `hand.raised`, About `info.circle`. Pane names on the Mac tab bar and the iOS list are the same.

As built in MM-43: `SettingsPane` holds the order; Data and AI Apps are added by MM-45 and MM-46 (no empty panes before). `settings.pane` is read on the Mac only; a stored pane that is not offered (AI on an Intel Mac) opens General. The iOS list keeps no last page. The iPad item is **MindMap AI Settings…** (Cài đặt MindMap AI…), after `.appSettings`, with no shortcut because ⌘, belongs to the system's Settings item *[Inference: not checked on an iPad with a hardware keyboard]*.

Columns in the tables below: **Free/Pro**, and **Task** (✅ already on `main`).

## General (Chung)

| Row (en / vi) | Control and default | Store | Free/Pro | Task |
| --- | --- | --- | --- | --- |
| Appearance / Giao diện | Picker: System (Theo hệ thống), Light (Sáng), Dark (Tối). Default System | AppDefaults `appearance` | Free | ✅ MM-0f |
| Theme for New Maps / Bộ màu cho sơ đồ mới | Picker: Standard (Tiêu chuẩn), xDev Blue, Graphite. Default Standard. The map's own theme stays in the map (Change Theme, MM-18). A Pro theme shows a `star` and opens the paywall when chosen without Pro; if Pro is refunded, new maps fall back to Standard and the stored value is kept | AppDefaults `newMap.theme`, later iCloud KVS (after MM-6) | Standard free; others Pro (`ProFeature.extraThemes`) | ✅ MM-43 |

Considered and left out [Đề xuất], each for a reason the next task should keep unless the product owner decides otherwise:

| Suggested row | Why not | Instead |
| --- | --- | --- |
| Layout for New Maps | Only `HorizontalTreeLayout` exists; per-branch structures are V1.x ([[node-organization]]). A picker with one choice is noise (HIG: minimise settings) | Add the row with the second layout engine |
| Return and Tab behaviour | Return and Tab already follow the standard meaning (new sibling, new child, only while no text field edits); repurposing standard keys is against [HIG Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) | Help ▸ Keyboard Shortcuts |
| Confirm Before Deleting | Delete Map moves to Recently Deleted and has Undo, so it gets no alert; Delete Permanently and Empty Recently Deleted always confirm (HIG Alerts). A switch would only add an alert to an undoable action | — |
| Reopen Windows at Launch | macOS has a system-wide choice (System Settings ▸ Desktop & Dock ▸ "Close windows when quitting an application" *[Inference: name from memory, not verified]*); copying it is against HIG Settings. The app restores state through `@SceneStorage` (MM-17) | Respect the system |
| Apple Pencil (FR-SET-06) | Pencil draws and fingers pan with no mode switch (FR-PEN-03); "Only Draw with Apple Pencil" and double tap are system settings | MM-9 adds an iPad row only if it needs one, e.g. a choice the system has no setting for |

## Export (Xuất)

The export sheet starts from these values and writing a choice in the sheet updates the same key, as Include Notes already does, so Settings and the sheet never disagree. All are device-local first and move to iCloud KVS after MM-6 (decided 2026-10-02).

| Row (en / vi) | Control and default | Store | Free/Pro | Task |
| --- | --- | --- | --- | --- |
| Include Notes / Kèm ghi chú | Switch, default on. Footer: "Applies to Markdown and plain text exports." | AppDefaults `export.includeNotes` | Free | ✅ MM-10, moved to Export in MM-43 |
| PNG Resolution / Độ phân giải PNG | Picker: Standard (1×), High (2×), Very High (3×). Default High (2×) with Pro, Standard (1×) without; 2× and 3× show `star`. The stored choice is kept when Pro is missing; the sheet uses the highest allowed value | AppDefaults `export.png.scale` (absent = the Pro-dependent default) | 1× free; 2×, 3× Pro (`highResolutionPNGExport`) | ✅ MM-43 |
| PDF Pages / Trang PDF | Picker: Fit to One Page (Vừa một trang), Actual Size on Several Pages (Kích thước thật, chia nhiều trang). Default Fit to One Page | AppDefaults `export.pdf.pages` | One page free; several pages Pro (`vectorPDFExport`) | ✅ MM-43 |
| Paper Size / Khổ giấy | Picker: Automatic, A4, US Letter. Default Automatic = `PaperSize.preferred()` by region, so the app detects instead of asking (HIG Settings) | AppDefaults `export.pdf.paper` (absent = Automatic) | Free | ✅ MM-43 |
| Background / Nền | Picker: Match Appearance (Theo giao diện), White (Trắng). Default Match Appearance; applies to PNG and PDF | AppDefaults `export.background` | Free | ✅ MM-43 |

The format itself is not a setting: the sheet remembers the last format used (`export.format`) [Đề xuất], a task option rather than a preference (HIG: task-specific options).

As built in MM-43: `ExportPreferences` (`Features/Interchange/ExportOptions.swift`) reads the keys for the sheet and writes back only the options changed in it, so a paper size or resolution nobody touched stays Automatic or default. A Pro choice opens the paywall from Settings too, and is stored only if Pro is unlocked there; the sheet opens on the free counterpart of a stored Pro choice while Pro is missing.

## AI (AI)

Hidden on devices that can never run Apple Intelligence, like every AI entry point (`AIService.showsEntryPoints`, MM-21); then Voice Input moves into General as its own section, since voice uses Speech, not the language model ([[architecture]]).

| Row (en / vi) | Control and default | Store | Free/Pro | Task |
| --- | --- | --- | --- | --- |
| Apple Intelligence / Apple Intelligence | Status text: Ready, Getting Ready, Off, Language Not Supported (`AIAvailabilityText`), with the footer that says what to do | Read from `AIService` | Free | ✅ MM-8 (FR-SET-05) |
| Open Apple Intelligence Settings… / Mở cài đặt Apple Intelligence… | Button, shown only when the state is Off. Mac: opens `x-apple.systempreferences:com.apple.Siri-Settings.extension` (`AppLinks.appleIntelligenceSettings`), the pane titled "Apple Intelligence & Siri" on Macs with Apple Intelligence; its Info.plist sets `allowsXAppleSystemPreferencesURLScheme` (checked on macOS 27.0.1, not on macOS 26, and not by clicking: the test Mac's screen was locked). iPad, iPhone: no public URL to that page found (not verified); `openSettingsURLString` opens the app's own page, which is the wrong place, so the footer gives the path as text instead | — | Free | ✅ MM-44 |
| Use AI Features / Dùng tính năng AI | Switch, default on. Off hides the AI menu items (disabled with "AI is turned off in Settings", since the Mac menu bar never hides items), the toolbar menu, canvas button, topic menu items, New Map with AI…, chat and Suggest Tags, Groups and Boundary titles. Suggestions already on a canvas stay until accepted or discarded. Nothing else changes | AppDefaults `ai.enabled` (device-local: AI availability differs per device) | Free | ✅ MM-44 |
| Response Language / Ngôn ngữ trả lời | Picker: Automatic, English, Tiếng Việt. Default Automatic: the language of the request or the selected topics, else the app's language (FR-AI-13, [[chat]]). An explicit choice only sets "You MUST respond in …"; Rewrite ▸ in Vietnamese / in English keep their own target | AppDefaults `ai.responseLanguage` | Free | Left out (decided 2026-10-02): Automatic is the only behaviour until people ask for a choice |
| Voice Input Language / Ngôn ngữ nhập giọng nói | Picker: English, Tiếng Việt. Default the first supported language in `Locale.preferredLanguages`. The voice sheet keeps its own picker on the same key, so the choice is made where it is used (HIG task-specific) and both show the same value | AppDefaults `voiceInput.language` | Pro (`voiceInput`), row visible to everyone and changeable without Pro (the footer says voice is Pro), so the language is right once Pro unlocks | ✅ MM-44 (MM-20 for the sheet) |
| Show AI Privacy Notice Again / Hiện lại thông báo quyền riêng tư AI | Not a row [Đề xuất]: the notice's content is always in Privacy; the flag `ai.privacyNoticeShown` stays internal | AppDefaults | — | — |

As built in MM-44: `AIService.isEnabled` reads and writes `ai.enabled`, so the switch applies in every window at once. `AIService.showsControls` (device can run AI and the switch is on) gates the toolbar menu, the canvas button, the topic context menu and New Map with AI…; the menu bar's AI menu follows `showsEntryPoints` only, and every item in it is disabled through `AIAssistant.canRun`, which is false while off, under the line "AI is turned off in Settings." (`AIService.unavailableReason`). Accept All Suggestions and Discard Suggestions stay enabled for suggestions already on a canvas. The AI pane has three sections: Apple Intelligence status (with the Mac button), Use AI Features, Voice Input; on a device without Apple Intelligence the Voice Input section is in General. Voice input is not affected by Use AI Features: it uses Speech, not the language model. The chat (MM-41) reads `showsControls` too.

Left out [Đề xuất]:

| Suggested row | Why not |
| --- | --- |
| Tag Suggestions on/off | Suggest Tags is a command the person runs (⌃⌘T), never automatic ([[node-organization]]); the tag field's completions are from existing tags, not AI. Use AI Features covers turning AI off |
| Keep Chat History / Clear History | The chat keeps no history: one session per conversation, not persisted ([[chat]], ADR 0009). Clear Conversation is in the chat panel. If history is ever stored, add a switch here (default off) and a Privacy row in the same task |

## Data (Dữ liệu)

| Row (en / vi) | Control and default | Store | Free/Pro | Task |
| --- | --- | --- | --- | --- |
| iCloud Sync / Đồng bộ iCloud | MM-6 built the iCloud section (Mac: switch and status; iPad/iPhone: status only, see open question 3) in a Data pane that MM-45 completes. The switch applies at the next launch, not by reopening the store [Đề xuất, MM-6]. Switch, default on. Footer gives the state from `CloudSyncState` in plain words: Up to Date, Syncing, Waiting for Network (not an error), Not Signed In to iCloud (with the path to sign in), Off for This App in System Settings, Error (one line and what to do) (FR-SYN-03). Turning it off keeps the maps on this device and stops syncing; it deletes nothing. Changing it reopens the store, so the switch is disabled while that runs | AppDefaults `sync.iCloudEnabled` (device-local by nature) | Free ([[pricing]]) | MM-45 (needs MM-6) |
| Recently Deleted / Đã xoá gần đây | Count ("3 maps") and Show in Library, which selects the library section. Maps stay 30 days; the period is fixed, not a setting | Repository (`fetchDeletedMaps`) | Free | MM-45 (MM-19 ✅ for the section) |
| Empty Recently Deleted… / Xoá hết mục đã xoá gần đây… | Button, disabled when empty. Alert: "Delete N maps permanently?", "This can’t be undone.", buttons Cancel and Delete Permanently (no destructive style, no default, as Empty Trash; HIG Alerts). Spotlight entries go too | Repository purge | Free | MM-45 |
| Export All Maps… / Xuất tất cả sơ đồ… | Button: a folder with one file per map, made off the main actor with progress, then `fileExporter`. Format: see *Open questions* | — | One `MapArchive` file per map (MM-54, [[interchange]] *Map archive*), the same writer as File ▸ Export… ▸ MindMap AI Backup; no Markdown-only Export All | MM-45 |
| Import Maps… / Nhập sơ đồ… | Button: same importer as File ▸ Import… (several files); each file becomes a new map, existing maps are never overwritten | — | Free | MM-45 |

## AI Apps (Ứng dụng AI), Mac only

From [[mcp]] (M2) and ADR 0008, all [Đề xuất] there. Name: mcp.md proposes "AI Apps"; the board calls MM-46 "Integrations". One name only: **AI Apps** [Đề xuất], since it says what connects; "Integrations" would also suggest Shortcuts and the Share Extension, which have no settings.

| Row (en / vi) | Control and default | Store | Free/Pro | Task |
| --- | --- | --- | --- | --- |
| Allow AI Apps to Read Maps / Cho phép ứng dụng AI đọc sơ đồ | Switch, **default off**. Footer before turning it on: connected apps read map text and send it under their own terms; xDev receives nothing; text in a map can try to steer the app that reads it. Off closes the port and revokes nothing | AppDefaults `mcp.enabled` | Free [Đề xuất] | ✅ MM-46 |
| Port / Cổng | Number field, fixed default in the dynamic range (value chosen in MM-40). If taken, the row says so; the app never picks another port silently | AppDefaults `mcp.port` | Free | ✅ MM-46 |
| Connected Apps / Ứng dụng đã kết nối | List: name, last request ("Read 2 minutes ago"), Revoke. Activity in memory only | Names and token IDs in Keychain items; activity in memory | Free | ✅ MM-46 |
| Add App… / Thêm ứng dụng… | Sheet: name ("Claude Code"), makes the token, shows it once with copy-ready snippets for Claude Code (`claude mcp add …`), ChatGPT desktop (Codex config), Cursor, VS Code; Claude Desktop once the relay helper ships (M4). The app never writes another app's config (App Review 2.4.5(ii), [[mcp]]) | Token in Keychain | Free | ✅ MM-46 |
| Allow Suggestions / Cho phép đề xuất | Switch, default off, shown once `propose_topics` ships (M5): connected apps may add suggestions labelled with their name; nothing is edited or deleted through MCP | AppDefaults `mcp.allowSuggestions` | Free | after M5 |

As built in MM-46 ([[mcp]], *In the app*): the pane is `SettingsPane.aiApps`, offered on the Mac only (`available(showsAI:showsAIApps:)`). Rows: the switch, Port (text field, 1024–65535, a value outside is refused with a footer line), Status (Off, Starting…, Ready, Port N Is Unavailable) and Address while Ready; the privacy footer is always shown under the switch, so it is read before turning it on (no extra confirmation sheet). Connected Apps rows say "Read 2 minutes ago" or "Not used since MindMap AI opened" (activity is in memory, so after a relaunch nothing is known), and Revoke… asks first: the app's setup stops working and cannot be restored, only replaced (HIG Alerts). Add App… picks the app (Claude Code, ChatGPT, Cursor, VS Code, Other) and a name, then shows the snippet and token once. Names: the pane is "AI Apps" / "Ứng dụng AI" [Đề xuất, still waiting for the product owner]; the token is "token" / "mã truy cập".
## Pro (MindMap AI Pro)

| Row (en / vi) | Control and default | Store | Free/Pro | Task |
| --- | --- | --- | --- | --- |
| Status / Trạng thái | Unlocked (Đã mở khoá) / Not unlocked (Chưa mở khoá) | StoreKit | — | ✅ MM-13 |
| See What’s in Pro… / Xem Pro có gì… | Button, opens `PaywallView`; hidden when unlocked | — | — | ✅ MM-13 |
| Restore Purchases / Khôi phục giao dịch mua | Button, `AppStore.sync()`, result alert (FR-SET-09) | StoreKit | — | ✅ MM-13 |

The pane's header is "MindMap AI Pro"; the tab is "Pro". No change planned.

## Privacy (Quyền riêng tư)

Each row states what is true on this device right now, so rows read the live state instead of fixed text. The tasks that change a behaviour change its row and [[privacy]], the privacy policy (`docs/web/privacy-policy.md`) and, if needed, `PrivacyInfo.xcprivacy` and the App Store label, in the same commit ([[app-store-readiness]]).

| Row (en / vi) | Value | Changes in |
| --- | --- | --- |
| Data Storage / Lưu trữ dữ liệu | "On this device" while sync is off or unavailable; "On this device and in your private iCloud" while on | MM-45 (today ✅ fixed text) |
| xDev Servers / Máy chủ xDev | "None. Your maps are never sent to xDev." Stays true with iCloud (the person's own iCloud), MCP (the person's own apps) and chat (on the device) | ✅ |
| Analytics / Thống kê sử dụng | "None" | ✅ |
| AI / AI | "On this device. Nothing is sent to xDev." Covers the chat too (Foundation Models on the device only, ADR 0009). "Turned off" when Use AI Features is off. Hidden on devices without AI | ✅ MM-8, MM-44 |
| Voice Input / Nhập bằng giọng nói | "On this device. Audio is not kept." (privacy.md: neither stored nor sent) | ✅ MM-44 |
| AI Apps / Ứng dụng AI (Mac) | "Off", or "On: apps you connect can read your maps and handle them under their own terms" | ✅ MM-46 |
| Privacy Policy / Chính sách quyền riêng tư | Link to `AppLinks.privacyPolicy` | ✅ MM-0h |

If any row would say data reaches someone other than the person or their own apps (for example a cloud AI provider), the label and the policy change first (privacy.md: each request names the provider before it is sent).

## About (Giới thiệu)

| Row (en / vi) | Value | Task |
| --- | --- | --- |
| `BrandMark` lockup | — | ✅ MM-0i |
| Version / Phiên bản | `1.0.0 (42)`, numbers only | ✅ MM-0f |
| Tagline | "Think. Draw. Connect." | ✅ |
| Website / Trang web, Support / Hỗ trợ | Links (`AppLinks`) | ✅ MM-0f, MM-0h |
| Acknowledgements / Ghi nhận [Đề xuất] | Not added (MM-43). Both fonts are SIL OFL 1.1; its condition 2 asks that each copy of the fonts contain the copyright notice and licence, "either as stand-alone text files, human-readable headers or in the appropriate machine-readable metadata fields". `Fonts/OFL.txt`, with both families' copyright lines, ships in the app bundle next to the fonts, which meets that. *[Inference: my reading of the licence, not a legal review.]* Add the row if the product owner wants credits shown anyway | — |

## Menus and shortcuts

- Mac: App ▸ Settings… ⌘, (from the `Settings` scene) is the only way in; no pane has its own menu item, and no toolbar has a Settings button (HIG Settings). Nothing in this design adds or changes a menu shortcut.
- Use AI Features off keeps AI menu items visible and disabled, with the reason, as the menu bar rule requires ([[design-guidelines]]).
- A setting never changes a map: the theme for new maps applies when a map is made; changing a map's theme stays a command in the editor with undo.

## Testing

For each task below: Swift Testing for the defaults (a fresh `AppDefaults` suite gives each default in this document), read and write through the same key from Settings and from the place that uses it (export sheet, voice sheet, new map), Pro fallback (a Pro value stored without Pro), and the Privacy rows for each state. UI tests per [[testing]] (MM-23): open Settings with ⌘, and from the sidebar, change Appearance, run in `en` and `vi`.

## Gotchas found while writing this

- ~~`VoiceInput` defaults to `UserDefaults.standard`~~: it defaults to `AppDefaults.store` since MM-44, and reads the key again each time the sheet opens, so a change in Settings shows in a map that is already open.
- ~~Include Notes sits in the General tab on the Mac~~: moved to Export in MM-43.
- The New Mind Map intent (Shortcuts, `MindMapIntentServices.newMap`), the Share Extension and imports still make Standard maps: they run in the package or the extension, which cannot see the Pro entitlement. Only New Mind Map and New Map with AI… in the app read Theme for New Maps.

## Open questions

1. **Backup format.** Decided 2026-10-02 and built in MM-54: Markdown drops tags, colours, symbols, connections, boundaries and themes (FR-ORG-10), so the backup is `MapArchive`, one versioned JSON file per map from the Codable domain types ([[interchange]] *Map archive*). Export All Maps (MM-45) writes it; there is no Markdown-only Export All.
2. **iCloud KVS** for theme and export defaults: decided 2026-10-02, yes, built after MM-6 and only while iCloud sync is on; never map content.
3. **iCloud Sync switch** (FR-SYN-06, S) next to the system's per-app iCloud control: the system already lets people turn off iCloud for an app on iPhone and iPad *[Inference, not verified for CloudKit-only apps on macOS]*; HIG Settings warns against copies of system settings. Decided 2026-10-02: keep the in-app switch only where the system has no per-app control; otherwise show status and a path to System Settings. MM-6: the Mac gets the switch, iPad and iPhone the status; the Mac finding is *[Unverified]* until a person checks System Settings with the signed build ([[cloudkit-sync]], *Status and Settings*).
4. **Response Language**: dropped (decided 2026-10-02, see AI).

## Proposed task criteria (for the leader)

Replace the provisional notes of MM-43…46 with these; each adds `en` and `vi` strings, keeps the Mac menu bar unchanged, applies at once, and has the tests in *Testing*.

- **MM-43 Settings General and Export.** Mac pane order and `settings.pane` restore; iPad/iPhone list with one page per pane; iPad App menu item beneath the system Settings item. General: Appearance (exists), Theme for New Maps (Pro themes with paywall and refund fallback; New Mind Map and New Map with AI… read it). Export pane: move Include Notes, add PNG Resolution, PDF Pages, Paper Size (Automatic), Background, shared keys with the export sheet. Acknowledgements only if a font licence requires it. Not in scope: layout, Return/Tab, delete confirmation, reopen windows (reasons above). FR-SET-01, 02, 07.
- **MM-44 Settings AI and voice.** Apple Intelligence status (exists) and the open-settings button where a URL is verified; Use AI Features (hides or disables every AI entry point, menu items disabled with reason, chat included once MM-41 lands); Response Language if the product owner keeps it; Voice Input Language on the voice sheet's key, moved to General on Intel; `VoiceInput` reads `AppDefaults.store`; Privacy rows AI (off state) and Voice Input. No tag-suggestion or chat-history switches. Depends on MM-41 only for hiding the chat. FR-SET-05, FR-AI-02, FR-AI-19.
- **MM-45 Settings Data.** `DataSettingsSection` adds Recently Deleted count, Show in Library, Empty Recently Deleted… with an alert; Export All Maps… writes one `MapArchive` JSON per live map into a folder through `fileExporter`, and Import Maps… uses `FileTransfer.importFile` for multiple selections. `DataSettingsModel` owns the repository work and removes purged IDs from Spotlight. `PreferenceCloudSync` mirrors theme and export defaults when iCloud is active. The iCloud switch and status, and Privacy Data Storage row, remain from MM-6. Tests: `DataSettingsTests` for purge, archive export and import without overwriting; `CloudSyncTests` covers status strings. FR-SET-04, FR-SYN-03, FR-SYN-06.
- **MM-46 Settings AI Apps (Mac only).** Rename from "Integrations" to "AI Apps" on the board if the product owner agrees. Switch (off), port, Connected Apps with last request and Revoke, Add App… with tokens in the Keychain and copy-only snippets, privacy footer before turning on, Privacy row AI Apps; Allow Suggestions waits for M5. `privacy.md`, privacy policy and Review Notes in the same task. Depends on MM-40.
