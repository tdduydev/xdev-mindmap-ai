# Privacy

Mind maps can hold personal notes, research, company plans and confidential ideas. The app treats them that way.

## What the app does

| Topic | Answer |
| --- | --- |
| Data storage | On the device (SwiftData) and, once sync ships, in the user's own private iCloud database |
| xDev backend | None. Maps are never sent to xDev. |
| Account | None required |
| AI processing | On-device (Apple Foundation Models) where the device supports it |
| Analytics | None in V1 |

## Rules for the code

- Never log map titles, node text, notes, drawings, imported documents or AI prompts. Use `os.Logger` with private interpolation for anything that might hold user content.
- Never send content anywhere without an explicit user action that says where it goes.
- No API secrets or private keys in the repository. V1 needs no credentials; if one is ever needed it goes in the Keychain.
- Optional services (analytics, crash reports, remote config) sit behind protocols with a no-op default, and the app compiles and runs without them.
- If analytics is ever enabled, only event names such as `map_created` or `ai_action_invoked` are allowed, never content.

## What users see

Settings explains, in plain words, where data is stored, that there is no xDev backend, and where AI runs. The public privacy policy (`https://xdev.asia/mindmap/privacy`, text in [web/privacy-policy.md](web/privacy-policy.md)) says the same and changes with this page. If a cloud AI provider is ever added, each request says which provider processes it, before it is sent.
