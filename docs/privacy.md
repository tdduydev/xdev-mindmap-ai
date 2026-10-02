# Privacy

Mind maps can hold personal notes, research, company plans and confidential ideas. The app treats them that way.

## What the app does

| Topic | Answer |
| --- | --- |
| Data storage | On the device (SwiftData) and, once sync ships, in the user's own private iCloud database |
| xDev backend | None. Maps are never sent to xDev. |
| Account | None required |
| AI processing | On-device (Apple Foundation Models) where the device supports it |
| Voice input | On-device (`SpeechAnalyzer`; `SFSpeechRecognizer` only asks the permission and never recognizes, since it sends Vietnamese to a server). Audio is neither stored nor sent; text stays in the sheet until the user adds it. Microphone and speech recognition access are asked the first time someone opens Add Topics by Voice |
| Analytics | None in V1 |
| Share Extension | Writes shared text and links into the store in the App Group container on the device; images and PDFs are copied there to wait for the app |
| Spotlight | Map titles only, in the device's own index; maps moved to Recently Deleted or deleted are removed |
| Clipboard | Read only when the user runs Map from Clipboard |

## Planned

- **AI apps over MCP** ([mcp.md](mcp.md), ADR 0008, not built): off by default. Once the person connects an AI app such as Claude or ChatGPT, that app can read maps on the Mac and may send them to its own provider under its terms; xDev still receives nothing. The task that ships it adds a row to the table above and updates the privacy policy.
- **Chat** ([chat.md](chat.md), ADR 0009, not built): on the device like the other AI features; conversations are not saved [Đề xuất].

## Rules for the code

- Never log map titles, node text, notes, drawings, imported documents or AI prompts. Use `os.Logger` with private interpolation for anything that might hold user content.
- Never send content anywhere without an explicit user action that says where it goes.
- No API secrets or private keys in the repository. V1 needs no credentials; if one is ever needed it goes in the Keychain.
- Optional services (analytics, crash reports, remote config) sit behind protocols with a no-op default, and the app compiles and runs without them.
- If analytics is ever enabled, only event names such as `map_created` or `ai_action_invoked` are allowed, never content.

## What users see

Settings explains, in plain words, where data is stored, that there is no xDev backend, and where AI runs. The public privacy policy (`https://xdev.asia/mindmap/privacy`, text in [web/privacy-policy.md](web/privacy-policy.md)) says the same and changes with this page. If a cloud AI provider is ever added, each request says which provider processes it, before it is sent.
