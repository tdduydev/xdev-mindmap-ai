# Privacy

Mind maps can hold personal notes, research, company plans and confidential ideas. The app treats them that way.

## What the app does

| Topic | Answer |
| --- | --- |
| Data storage | On the device (SwiftData) and, while iCloud sync is on, in the person's own private CloudKit database (MM-6, [cloudkit-sync](cloudkit-sync.md)); xDev cannot read it. Sync is on by default when signed in to iCloud; off on the Mac in Settings ▸ Data, on iPhone and iPad in the system's iCloud settings. The Share Extension never talks to iCloud itself |
| xDev backend | None. Maps are never sent to xDev. |
| Account | None required |
| AI processing | On-device (Apple Foundation Models) where the device supports it |
| Voice input | On-device (`SpeechAnalyzer`; `SFSpeechRecognizer` only asks the permission and never recognizes, since it sends Vietnamese to a server). Audio is neither stored nor sent; text stays in the sheet until the user adds it. Microphone and speech recognition access are asked the first time someone opens Add Topics by Voice |
| Analytics | None in V1 |
| Share Extension | Writes shared text and links into the store in the App Group container on the device; images and PDFs are copied there to wait for the app |
| Spotlight | Map titles only, in the device's own index; maps moved to Recently Deleted or deleted are removed |
| Clipboard | Read only when the user runs Map from Clipboard |
| Sync status | Reads the iCloud account status, the network status and the mirroring's events on the device, to show them; nothing about them leaves the device. CloudKit errors are logged by code only |
| AI apps over MCP (Mac) | Off by default (Settings ▸ AI Apps, MM-46; [mcp](mcp.md), ADR 0008). While on, the app listens on 127.0.0.1 only, and only while it runs. An AI app the person added (one token each, in the Keychain, device-only, never synced) can list, read and search map titles, notes and structure, and may send what it reads to its own provider (Anthropic, OpenAI…) under its own terms; xDev receives nothing. The footer under the switch says so before it is turned on, and Settings ▸ Privacy shows whether it is on. Revoke stops a token at once; turning the switch off closes the port and keeps the apps. Last read times are kept in memory only. Logs hold tool names and sizes; app names are `.private`; arguments and map text are never logged |

## Planned

- **AI apps writing suggestions** (M5 in [mcp.md](mcp.md)): proposals only, labelled with the app's name, accepted in the app; adds an "Allow Suggestions" switch and changes the row above.
- **Chat** ([chat.md](chat.md), ADR 0009, not built): on the device like the other AI features; conversations are not saved [Đề xuất].

- **Map links and the App Clip** ([app-clip](app-clip.md), ADR 0012): Share Link puts the map in the URL fragment, which browsers do not send to xdev.asia; anyone with the link can read the map, and the sheet says so. The App Clip keeps nothing but the maps it opened, in an App Group only the app can read. Label unchanged.
- **Apple Watch** ([watch](watch.md), ADR 0012): the same private iCloud database; the Inbox map's ID (no content) in iCloud key-value storage. Label unchanged.

## Rules for the code

- Never log map titles, node text, notes, drawings, imported documents, AI prompts or chat questions and answers (saved with each map since MM-55, so they are map content). Use `os.Logger` with private interpolation for anything that might hold user content.
- Never send content anywhere without an explicit user action that says where it goes.
- No API secrets or private keys in the repository. V1 needs no credentials; if one is ever needed it goes in the Keychain.
- Optional services (analytics, crash reports, remote config) sit behind protocols with a no-op default, and the app compiles and runs without them.
- If analytics is ever enabled, only event names such as `map_created` or `ai_action_invoked` are allowed, never content.

## What users see

Settings explains, in plain words, where data is stored, that there is no xDev backend, and where AI runs. The public privacy policy (`https://xdev.asia/mindmap/privacy`, text in [web/privacy-policy.md](web/privacy-policy.md)) says the same and changes with this page. If a cloud AI provider is ever added, each request says which provider processes it, before it is sent.
