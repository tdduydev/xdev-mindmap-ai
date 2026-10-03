# App Clip and map links

Design from MM-112 (ADR 0012) for FR-CLP-01..05. Nothing here is built yet. MM-113 builds the link and the web page, MM-114 the App Clip, MM-115 AI in the App Clip. [Đề xuất] marks a choice the product owner has not confirmed. [Chưa kiểm chứng] marks an Apple behaviour no source or test confirms yet.

## What the person sees

| Who | Taps a map link | Gets |
| --- | --- | --- |
| Has the app (iPhone, iPad, Mac) | anywhere | The app opens the map as a new map (universal link) |
| No app, iPhone or iPad | Safari, or Messages from a contact | Page on xdev.asia with the App Clip card, then the App Clip with the map, read-only, and a Get the App button |
| No app, other device | browser | Page on xdev.asia with the outline, drawn from the fragment by JavaScript |

## Link format

```
https://xdev.asia/mindmap/m#1.<data>
```

| Part | Value | Why |
| --- | --- | --- |
| Host and path | `xdev.asia`, `/mindmap/m` | Next to the product site (`/mindmap`). The path stays short and the AASA file can match it alone |
| Fragment | `<version>.<data>` | A browser does not send the fragment to the server ([RFC 3986 §3.5](https://www.rfc-editor.org/rfc/rfc3986#section-3.5)), so xdev.asia never receives the map |
| Version | `1`, decimal | A reader that sees an unknown version says "This link needs a newer version of MindMap AI" and does not guess |
| `<data>` | base64url without padding ([RFC 4648 §5](https://www.rfc-editor.org/rfc/rfc4648#section-5)) of raw DEFLATE ([RFC 1951](https://www.rfc-editor.org/rfc/rfc1951)) of UTF-8 JSON | Every base64url character is allowed in a fragment without percent-encoding |
| Compression | `COMPRESSION_ZLIB` of Apple's Compression framework, which writes raw DEFLATE at level 5 ([COMPRESSION_ZLIB](https://developer.apple.com/documentation/compression/compression_zlib)) | Browsers decode it without a library: `DecompressionStream("deflate-raw")` ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream/DecompressionStream)). LZFSE, LZMA and Apple's newer algorithms have no browser decoder |
| Length | Whole URL at most 8,000 characters [Đề xuất] | RFC 9110 recommends supporting URIs of at least 8,000 octets ([§4.1](https://www.rfc-editor.org/rfc/rfc9110#section-4.1)). Limits of Messages, Mail and other apps are not documented [Chưa kiểm chứng]; MM-113 tries a link at the limit in Messages, Mail, Notes and Slack |

### Payload, version 1

```json
{"t":"Trip to Đà Lạt","r":{"t":"Trip","c":[{"t":"Hotel","n":"Near the lake","l":"https://example.com"},{"t":"Food","a":1}]}}
```

| Key | On | Meaning |
| --- | --- | --- |
| `t` | map | Map title |
| `r` | map | Central topic |
| `t` | topic | Title |
| `n` | topic | Note, left out when empty |
| `l` | topic | Link URL, only `http`, `https`, `mailto` (`TopicLink.validated`) |
| `a` | topic | `1` when the topic came from AI (`origin = .ai`), so an AI map made in the App Clip keeps its label |
| `c` | topic | Children in order, left out when empty |

Keys are one letter because every byte counts against the length limit. Readers ignore keys they do not know, so version 1 can gain optional keys. A change that old readers would misread needs version 2.

**Not in the link:** images, tags, colours and symbols, tasks, connections, boundaries, summaries, callouts, floating topics, collapsed state, positions, theme, chat. The Share Link sheet lists what a map loses ("Images, tags and connections aren't included in links."), like the import report of MM-101.

**Capacity [Inference]:** 8,000 characters hold about 5.9 KB of compressed data. Short titles typically compress about three to one, so that is roughly 300 to 600 topics without notes. MM-113 measures it on the sample maps.

### Reading a link safely

Universal links are an attack surface, and Apple says to validate every part and discard malformed URLs ([Supporting universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)). The decoder (`MapLinkCodec` in `MindMapInterchange`, used by the app, the App Clip and tests):

- reads only `https`, host `xdev.asia`, path `/mindmap/m` and a fragment that matches `^[0-9]+\.[A-Za-z0-9_-]+$`;
- stops inflating after 1 MB of output [Đề xuất] (a small link can expand into a large bomb);
- accepts at most 2,000 topics and a depth of 100 [Đề xuất], titles and notes clipped like an import;
- turns the payload into an `OutlineDraft` and creates the map through the same path as File ▸ Import (one new map, no undo step in another map);
- never deletes or changes an existing map.

A link it cannot read shows "This link can't be opened. It may be incomplete." and nothing else happens.

### Too big for a link

Share Link encodes before it shows anything. If the URL is longer than the limit, nothing is cut. The sheet says "This map is too big for a link." and offers, in this order [Đề xuất]:

1. **Share Without Notes**, only when the map without notes fits;
2. **Share a Branch…**, which picks a topic;
3. **Export…**, which opens the export sheet (Markdown, OPML, PNG, PDF; FR-IO).

### Sharing a branch

Share Link with a topic selected offers "Share Map" and "Share Branch". The branch's topic becomes the central topic of the link, and its title becomes the map title.

## Opening links

### In the app (iPhone, iPad, Mac)

- Entitlement `com.apple.developer.associated-domains`: `applinks:xdev.asia` and `appclips:xdev.asia`. Apple asks for the associated domain on both the app and the App Clip ([Associating your App Clip with your website](https://developer.apple.com/documentation/appclip/associating-your-app-clip-with-your-website)).
- SwiftUI gets the link from `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` and reads `webpageURL` ([Responding to invocations](https://developer.apple.com/documentation/appclip/responding-to-invocations)). It hands the link to `MapOpenRequests`, the same path the intents use.
- Universal links work on macOS too; Apple's guide has a macOS example ([Supporting universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)). Whether Safari on the Mac opens the app or the page is not verified [Chưa kiểm chứng].
- **File ▸ Open Map Link…** (no shortcut [Đề xuất]) on the Mac, and the same command in the library's add menu on iPhone and iPad, take a pasted link. That covers links that open in a browser and links read off another screen.
- Each open creates a new map, even for a link opened before. No duplicate check: duplicates are rare, and a duplicate does no harm.
- Apple requires the full app to offer what the App Clip offers ([Choosing the right functionality](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip)). The app already has open-link (above) and New Map with AI.

### App Clip invocation

- The page `https://xdev.asia/mindmap/m` carries `<meta name="apple-itunes-app" content="app-id=6818476277, app-clip-bundle-id=asia.xdev.mindmapai.Clip, app-clip-display=card">` and an `og:image` for Messages ([Supporting invocations from your website and the Messages app](https://developer.apple.com/documentation/appclip/supporting-invocations-from-your-website-and-the-messages-app)).
- One default App Clip experience in App Store Connect. No advanced experiences, no App Clip Codes, no NFC tags.
- Messages opens the App Clip only when the sender is in the recipient's Contacts. Otherwise the recipient sees the page (same source).
- The App Clip reads the invocation URL like the app does. **Whether the URL keeps its fragment is the main open risk** [Chưa kiểm chứng]. The fallbacks are in ADR 0012, *Open risk*.
- Back from the App Switcher, the App Clip gets no URL (same source). It reopens the last map from its App Group.

## App Clip

### Screens

1. **Map** (from a link): the canvas, read-only, with an Outline switch. Zoom and pan, collapse and expand, VoiceOver as in the app. No editing, because there is no store to edit.
2. **Quick Map with AI** (FR-CLP-03), when the clip opens without a link: a topic field, then Generate. The result is an AI suggestion with the AI label (dashed gradient border, sparkles), editable in the outline (rename, delete) before anything else. Then **Share Link** or **Open in App**.
3. Device without Apple Intelligence, or Apple Intelligence off: one line explains it, and opening links still works (FR-CLP-03).
4. **Get the App:** `SKOverlay` with `SKOverlay.AppClipConfiguration` at the bottom ([StoreKit](https://developer.apple.com/documentation/storekit/skoverlay/appclipconfiguration)), shown after the map has been on screen a moment, not over the first view.

No settings, no purchase, no review prompt. Apple keeps those for the full app.

### Modules and size

| Linked | Why |
| --- | --- |
| `MindMapDomain`, `MindMapGraph` | Values and the graph the canvas draws |
| `MindMapLayout` | Positions topics |
| `MindMapInterchange` | `MapLinkCodec`, `OutlineDraft` |
| `MindMapAICore`, `MindMapAIApple` | Generate Map (Foundation Models), proposal checks |
| `MindMapUI` (`MindMapDesignSystem`, `MindMapCanvas`), new | Read-only canvas, outline, AI suggestion style, brand fonts (about 500 KB) |

Not linked: `MindMapPersistence` and SwiftData, `MindMapSearch`, `MindMapSharing`, `MindMapIntents` (App Intents do nothing in an App Clip), `MindMapQuery`, `MindMapMCP`, `MindMapCapture` (Speech does nothing in an App Clip), `MindMapImages`, StoreKit purchases, MLX and local models (ADR 0011), chat.

**Apple's limits** ([Choosing the right functionality for your App Clip](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip)), for the uncompressed App Clip binary:

| iOS | Limit |
| --- | --- |
| 15 and earlier | 10 MB |
| 16 and earlier | 15 MB |
| 17 and later | 100 MB, only if the App Clip supports digital invocations only (website, Spotlight), no App Clip Codes, QR codes or NFC tags, is used where a reliable connection is likely, and does not support iOS 16 or earlier |

**Budget: 15 MB [Đề xuất].** The App Clip targets iOS 26 and is invoked from the website only, so 100 MB is allowed. Staying under 15 MB keeps launch fast and still allows a QR code for a small map later. MM-114 measures it with Xcode's App Thinning Size Report ([Verify the size of your App Clip](https://developer.apple.com/documentation/appclip/creating-an-app-clip-with-xcode#Verify-the-size-of-your-App-Clip)), records the number here, and `scripts/ci.sh` fails above the budget [Đề xuất].

### Foundation Models in the App Clip

Apple lists the frameworks that "provide no functionality at runtime" in an App Clip: App Intents, Assets Library, Background Tasks, CallKit, CareKit, Contacts, Contacts UI, Core Motion, EventKit, EventKit UI, File Provider, File Provider UI, HealthKit, HomeKit, Media Player, Messages, Message UI, Nearby Interaction, PhotoKit, ResearchKit, SensorKit, Speech ([source](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip)). Foundation Models is not in the list. The [Foundation Models](https://developer.apple.com/documentation/foundationmodels) page says nothing about App Clips.

So Foundation Models is expected to work in the App Clip [Inference], but no test on a device confirms it yet [Chưa kiểm chứng]. MM-115 starts with a TestFlight App Clip on the iPhone 17 Pro Max that calls `SystemLanguageModel.default.availability` and generates a map. If the call fails, Quick Map leaves the App Clip and stays in the full app. The App Clip cannot run in the background, so generation happens only while it is on screen.

Quick Map uses the free tier's Generate Map: a short topic, the same prompt and topic limit as the app. Advanced AI stays Pro and stays in the app (FR-STO-01).

### Handoff to the full app

Apple's way: an App Group shared by the App Clip and the app ([Sharing data between your App Clip and your full app](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app)).

- Group **`group.asia.xdev.mindmapai.clip`**, on the App Clip and on the iOS app only. It is not the main group `group.asia.xdev.mindmapai`, so the App Clip never sees the library store.
- The App Clip writes `ClipHandoff/maps.json`: up to 10 entries, newest first, each `{ "link": "<the map link>", "source": "link" | "ai", "date": "<ISO 8601>" }` [Đề xuất]. It writes after a link opens and after the person edits an AI map. The same file brings back the last map when the App Clip relaunches without a URL.
- At launch the app reads the file, imports each entry as a new map (AI entries keep `origin = .ai`), opens the newest one, and deletes the file only after every import has been saved. A failed entry stays for the next launch.
- No sensitive data goes in the group. Apple says not to store passwords there (same source).
- How long the App Group data lasts after the system removes an unused App Clip is not documented in the sources read [Chưa kiểm chứng].
- Gotcha (memory 189): SwiftData's `.automatic` group container uses the first App Group in the entitlements. The app's store already passes `groupContainer: .none` and an explicit path, so a second group changes nothing there. Keep the main group first in the entitlements anyway.

## Web page on xdev.asia (FR-CLP-05)

The leader publishes it. MM-113 writes the page and the AASA file in `docs/web/` for the leader to copy.

- `https://xdev.asia/mindmap/m`: static HTML and one script. It reads `location.hash`, decodes with `DecompressionStream("deflate-raw")`, and draws the outline as nested lists, with text inserted as text, never as HTML. Links in the payload open only if they are `http`/`https`/`mailto`. No analytics, no third-party scripts, no cookies. It shows the Smart App Banner meta tag and links to the App Store.
- Old browsers without `DecompressionStream` see "Open this link on a device with MindMap AI." [Đề xuất]. MDN lists the API as widely available since May 2023.
- The fragment never reaches the server. The host's access logs record the path `/mindmap/m` only. The website privacy policy (`docs/web/privacy-policy.md`) says so in MM-113.
- `https://xdev.asia/.well-known/apple-app-site-association`, served over HTTPS with no redirect, allowing user agents `AASA-Bot` and `CFNetwork` ([Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["M6C7NX9MUZ.asia.xdev.mindmapai"],
        "components": [
          { "/": "/mindmap/m", "comment": "Map links; the map is in the fragment" }
        ]
      }
    ]
  },
  "appclips": { "apps": ["M6C7NX9MUZ.asia.xdev.mindmapai.Clip"] }
}
```

Apple's CDN fetches the file within 24 hours, and devices check for updates about once a week (same source). Development builds can bypass the CDN with `?mode=developer` on the entitlement.

## Privacy

- **App Privacy label:** unchanged, "Data Not Collected". The App Clip collects nothing, and the link goes only where the person sends it. Whether App Store Connect asks for a separate label for the App Clip is not verified [Chưa kiểm chứng]. If it does, the answers are the same.
- **`MindMapClip/PrivacyInfo.xcprivacy`:** `NSPrivacyTracking` false, no tracking domains, no collected data types. Required-reason APIs: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `1C8F.1` if the App Clip uses the App Group's `UserDefaults`, and `CA92.1` for its own. `NSPrivacyAccessedAPICategoryFileTimestamp` only if it reads file dates (the design does not need to).
- The Share Link sheet says, once and briefly: "Anyone with this link can see the map." [Đề xuất].
- Nothing logs a link or a payload: map content rule in [privacy](privacy.md).

## Apple account and website (leader)

Agents do not do these. The leader does them before MM-114 can be tested on a device:

1. **Bundle ID** `asia.xdev.mindmapai.Clip` (explicit, iOS), capabilities **App Groups** (`group.asia.xdev.mindmapai.clip`) and **Associated Domains**. The App Clip gets `com.apple.developer.parent-application-identifiers` = `M6C7NX9MUZ.asia.xdev.mindmapai` from Xcode, and the archive adds `associated-appclip-app-identifiers` to the app ([Sharing data](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app)).
2. **App Group** `group.asia.xdev.mindmapai.clip`. Add it to `asia.xdev.mindmapai` (iOS) next to the main group.
3. **Associated Domains** on `asia.xdev.mindmapai` for iOS and macOS, with the domains `applinks:xdev.asia` and `appclips:xdev.asia`.
4. **Profiles**, generated again after the capability changes: the app's iOS and Mac App Store profiles, the Share Extension's if it changes, a new App Store profile for the App Clip. Add the App Clip to the export options of `scripts/upload-testflight.sh` ([release](release.md), *Recreating the signing setup*, step 4).
5. **App Store Connect**: after the first build with the App Clip, set up the default App Clip experience: header image (1800×1200 px [Chưa kiểm chứng: size from memory, check the form]), subtitle, action "Open". The App Clip has no record of its own: it ships inside the iOS app (one record, one bundle ID family, ADR 0006).
6. **Website**: publish `/.well-known/apple-app-site-association` and `/mindmap/m` from MM-113. In App Store Connect, the build's App Clip section, *View Status*, checks the domain.
7. **Review notes**: how to invoke the App Clip (the link page) and that Quick Map needs Apple Intelligence.
