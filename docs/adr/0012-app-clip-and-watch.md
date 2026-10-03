# ADR 0012: App Clip and Apple Watch app, without a backend

- Status: proposed (MM-112, 2026-10-03); the product owner decided on 2026-10-03 to build both, free. Items marked [Đề xuất] wait for the product owner; items marked [Chưa kiểm chứng] wait for a test on a device or a source.
- Date: 2026-10-03
- Relates to: ADR 0001 (no backend), ADR 0005 (OS 26 minimum), ADR 0006 (one multiplatform target, macOS first), ADR 0011 (local model fallback)
- Design: [app-clip.md](../app-clip.md) (FR-CLP-01..05), [watch.md](../watch.md) (FR-WCH-01..04)
- Builds: MM-113 (link and web page), MM-114 (App Clip target), MM-115 (AI in the App Clip), MM-116 (watch app)

## Context

On 2026-10-03 the product owner asked for an App Clip that opens a map from a link and makes a quick map with AI, and for an Apple Watch app that captures ideas and shows maps. Both are free. ADR 0001 rules out an xDev server, so a shared map cannot be uploaded anywhere, and the watch cannot read maps from a service of ours.

## Decision

1. **The map travels inside the link.** Share Link turns a map or a branch into `https://xdev.asia/mindmap/m#1.<data>`, where `<data>` is the outline as compact JSON, compressed with the Compression framework's `COMPRESSION_ZLIB` (raw DEFLATE, RFC 1951) and encoded as base64url without padding. The map sits in the fragment, which a browser does not send to the server (RFC 3986 §3.5). Links are capped at 8,000 characters [Đề xuất]; a bigger map is not truncated: the sheet says so and offers a branch, the map without notes, or a file. Format in [app-clip.md](../app-clip.md#link-format).
2. **Who opens the link.** With the app installed, the link is a universal link (`applinks:xdev.asia`, path `/mindmap/m`) on iPhone, iPad and Mac, and opens as a new map. Without the app on iPhone and iPad, the page on xdev.asia shows the App Clip card; the App Clip shows the map read-only. Everywhere else the page renders the outline with JavaScript from the fragment.
3. **App Clip target `MindMapClip`**, bundle ID `asia.xdev.mindmapai.Clip`, iOS and iPadOS 26. It links Domain, Graph, Layout, Interchange, AICore, AIApple and the read-only canvas and design system, which move into a `MindMapUI` package so the app and the clip share them. No SwiftData store, no StoreKit purchase, no MLX model, no intents, no chat. Size budget 15 MB uncompressed, below Apple's 100 MB limit for iOS 17 and later, so a QR code stays possible [Đề xuất].
4. **Clip → app handoff through a separate App Group `group.asia.xdev.mindmapai.clip`.** The clip writes the links it opened or generated there; the full app imports them once as new maps at its first launch. The clip never gets the app's main group `group.asia.xdev.mindmapai`, which holds the person's whole library.
5. **AI in the App Clip uses Foundation Models only.** Apple's list of frameworks that do nothing in an App Clip does not name Foundation Models, so it is expected to work [Inference; Chưa kiểm chứng on a device, MM-115 checks it first]. No open-model fallback (ADR 0011) in the clip: it would not fit the budget. Without Apple Intelligence the clip says so and still opens links.
6. **Watch app `MindMapWatch`**, bundle ID `asia.xdev.mindmapai.watchkitapp`, watchOS 26, with a widget extension for complications. It syncs through SwiftData with CloudKit mirroring to the same private container `iCloud.asia.xdev.mindmapai`, with the same schema as the phone. WatchConnectivity is not used: it needs the iPhone app nearby, and CloudKit also works from the Mac and from a watch on Wi-Fi or cellular.
7. **The Inbox map needs no schema change.** Its map ID lives in iCloud key-value storage under `inbox.mapID`, which the app already uses (MM-45). No SchemaV4. If two devices create an Inbox at once, the last write wins and the other map stays an ordinary map with its topics.
8. **Free, no new data collected.** The App Privacy label stays "Data Not Collected". Each new target has its own `PrivacyInfo.xcprivacy`.

## Amends

- **ADR 0006:** the multiplatform app target stays as it is. Two targets join it, an App Clip (iOS and iPadOS) and a watchOS app with its widget extension. Their bundle IDs start with `asia.xdev.mindmapai`, and they ship in the same App Store record as the iOS app (universal purchase unchanged).
- **ADR 0001:** unchanged. No server stores or reads maps. The web page at xdev.asia is static and does not get the map, because the map is in the fragment. Its access logs hold the path only.

## Consequences

- The app, the clip and the web page need the same link codec. The Swift codec goes in `MindMapInterchange` with golden tests, and the JavaScript decoder on the page is tested against the same fixtures.
- Anyone who has a link can read the map. Links end up in chat history, browser history and iCloud Tabs. The Share Link sheet says this before it copies the link.
- `Features/Canvas` and `DesignSystem` leave the app target for a `MindMapUI` package (planned in [module-structure](../module-structure.md)), because a second target now needs them.
- The watch keeps a full copy of the library, images included [Chưa kiểm chứng: whether mirroring downloads `ImageRecord` assets eagerly]. MM-116 measures it on a large library before release.
- The leader sets up the Apple account and the website: bundle IDs, App Groups, capabilities, profiles, the App Clip experience in App Store Connect, and `apple-app-site-association` plus the page on xdev.asia. The list is in [app-clip.md](../app-clip.md#apple-account-and-website-leader) and [watch.md](../watch.md#apple-account-leader).
- Mac App Store profiles need the Associated Domains capability, and the profiles are generated again after that change.

## Open risk

**Does the App Clip get the fragment?** On a website invocation, Apple passes "the site's URL" to the App Clip ([Responding to invocations](https://developer.apple.com/documentation/appclip/responding-to-invocations)). Apple does not say whether the URL keeps its fragment [Chưa kiểm chứng]. MM-113 tests this first on a device with a TestFlight App Clip and the page on xdev.asia. If the fragment is lost, the fallbacks are:

- (a) The App Clip opens without the map and asks the person to tap the link again in Safari. The web page shows the outline.
- (b) Move the data into the query string. The server would then receive the map, which breaks the privacy promise in FR-CLP-01, so only the product owner can choose it.

## Alternatives

- **Upload the map and share a short link:** needs a server (ADR 0001).
- **CloudKit public database or share for the link:** an App Clip can only read the public database and cannot write to it, and a CKShare needs the full app ([Choosing the right functionality](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip)). A public copy is also a publication the person did not ask for.
- **LZFSE or LZMA instead of zlib:** LZMA compresses better, but browsers cannot decode either format. Browsers decode raw DEFLATE natively with `DecompressionStream("deflate-raw")`.
- **WatchConnectivity for the watch:** queued and reliable ([transferUserInfo](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))), but it needs the iPhone, adds a second sync path next to CloudKit, and the Simulator does not support it.
- **SchemaV4 with an `isInbox` flag on maps:** a production schema change and a migration for one ID. The key-value store already syncs small preferences.
