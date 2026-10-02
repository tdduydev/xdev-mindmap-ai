# App Store readiness

Research for MM-0e, 2026-10-02. It is a checklist for shipping MindMap AI on the Mac App Store first, then on iPad and iPhone under the same app record (ADR 0006). Each row gives the guideline number and an Apple source; the guideline numbers refer to the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). "Not verified" means no Apple page confirmed it. *[Inference]* means the point is reasoned, not documented. Recheck the guidelines before each submission, since Apple changes them several times a year.

## Summary

- **Blocking before the first submission:** a privacy policy URL, reachable in App Store Connect and inside the app (5.1.1(i)), and a support URL. The app has neither yet.
- **Toolchain:** since 2026-04-28, uploads need Xcode 26 and the 26 SDKs. From April 2027, iOS and iPadOS uploads need the 27 SDKs; the macOS SDK rule is not verified ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/), [news 2026-09-09](https://developer.apple.com/news/?id=k1mtkt1k)).
- **Privacy label:** "Data Not Collected" holds while everything stays on the device, including Foundation Models ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)). Revisit it if sync, analytics or cloud AI changes that.
- **Pricing:** a one-time unlock (non-consumable) is the lower-risk model for a backendless app. A subscription has to show ongoing value (3.1.2(a)) *[Inference]*.
- **Universal purchase:** one app record, one bundle ID `asia.xdev.mindmapai`. Never create a second record for iOS; records cannot be merged later ([universal purchase](https://developer.apple.com/support/universal-purchase/)).

## Toolchain and platform

| Rule | Requirement | Status | Source |
| --- | --- | --- | --- |
| Minimum SDK | Xcode 26 and the 26 SDKs for every upload since 2026-04-28. iOS and iPadOS 27 SDK from April 2027. The macOS rule for 2027 is not verified. | Met: the project builds with Xcode 26 or later and targets OS 26 | [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/), [news](https://developer.apple.com/news/?id=k1mtkt1k) |
| Intel Macs | macOS 26 is the last release for Intel Macs. macOS 27 is the last release with Rosetta. | Foundation Models needs Apple silicon anyway; ship an arm64 and x86_64 build only if the product wants Intel customers on macOS 26 | [news 2026-09-01](https://developer.apple.com/news/?id=w5ngl9k2) |
| Quarantine attribute | Remove `com.apple.quarantine` from every file in the bundle before upload (since 2025-02-18) | Applies if images or files are added from downloads; check with `xattr -r` before archiving | [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) |

## Completeness and metadata (2.1, 2.3)

| Guideline | Requirement | For MindMap AI |
| --- | --- | --- |
| 2.1(a) | Final build: no crashes, no placeholder text, working links. A demo account is needed only with a login. | No login. The startup recovery screen is not a placeholder, but "contact xDev support" needs a real support link. Apple says over 40% of unresolved issues are 2.1 ([App Review](https://developer.apple.com/distribute/app-review/)). |
| 2.1(b) | Every in-app purchase complete and findable by the reviewer, or explained in Review Notes | MM-13 (StoreKit), below |
| 2.3.1(a) | No hidden features. Review Notes describe new features specifically. | Explain AI availability in Review Notes: it needs Apple Intelligence on, on an eligible device, and is hidden otherwise ([on-device AI](on-device-ai.md)). |
| 2.3.2 | Description and screenshots say which features need a purchase | Mark paid features once pricing exists |
| 2.3.3 | Screenshots show the app in use, not a title screen | Use a sample map, not an empty library |
| 2.3.7 | Name of 30 characters or fewer; no trademarks, other app names or prices in metadata; subtitle makes no unverifiable claims | "MindMap AI by xDev" is 18 characters. Avoid "best", "#1" and other apps' names. |
| 2.3.8 | Metadata suits 4+, even when the rating is higher. Name and icon match on every platform. | One icon artwork for Mac, iPad and iPhone (MM-0g) |
| 2.3.10 | No other mobile platforms named or shown | Do not mention Android or Windows |
| 5.2.5 | Do not look confusingly similar to Apple products; no Apple emoji | The icon uses the xDev X, not an Apple glyph. Rules for writing "Apple Pencil", "iCloud" and "for iPad" in metadata: not verified (Apple's [trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) were not read). *[Inference]* Keep Apple names out of the app name and use them only in descriptive text, with the exact capitalisation. |

### Field limits

From [app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) and [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information):

| Field | Limit | Note |
| --- | --- | --- |
| Name | 2–30 characters | Same on every platform |
| Subtitle | 30 characters | |
| Keywords | 100 bytes | Bytes, not characters: Vietnamese letters with diacritics take 2–3 bytes each in UTF-8 |
| Promotional text | 170 characters | Can change without a new build |
| Description | 4,000 characters | |
| What's New | 4,000 characters | |
| Review Notes | 4,000 bytes | |
| Privacy policy URL | Required on iOS and macOS | |
| Category | On macOS, must match `LSApplicationCategoryType` | The project sets `public.app-category.productivity`; choose Productivity in App Store Connect |

Localise the name, subtitle, keywords, description and screenshots in English and Vietnamese, like the app.

### Screenshots

JPEG or PNG, no transparency, 1 to 10 per set ([screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)). Smaller devices scale from the nearest set uploaded.

| Device | Accepted sizes (px) | Required |
| --- | --- | --- |
| Mac, 16:10 | 1280×800, 1440×900, 2560×1600, 2880×1800 | Yes, first release |
| iPad 13-inch | 2064×2752 or 2048×2732, portrait or landscape | Yes, when the iPad version ships |
| iPhone 6.9-inch | 1260×2736, 1290×2796 or 1320×2868 | Yes, unless 6.5-inch screenshots are given |
| iPhone 6.5-inch | 1284×2778 or 1242×2688 | Only without 6.9-inch |

## Mac App Store (2.4.5)

| Item | Requirement | Status |
| --- | --- | --- |
| 2.4.5(i) | Sandboxed, follows the macOS file system rules | Met: `ENABLE_APP_SANDBOX = YES`. Import and export (MM-10) need user-selected file access, so add `ENABLE_USER_SELECTED_FILES = readwrite` (or the matching entitlement) then. |
| 2.4.5(ii) | Packaged and submitted with Xcode, one self-contained bundle | Met: single app target |
| 2.4.5(iii) | No launch at login and no processes left after quit without consent | Met: none planned |
| 2.4.5(iv) | No downloading apps, code or resources that add features | Applies to any later downloadable local model; see 2.5.2 below |
| 2.4.5(v) | No root escalation or setuid | Met |
| 2.4.5(vi) | No license screen at launch, license keys or own copy protection | Met. Unlocks go through StoreKit only. |
| 2.4.5(vii) | Updates only through the Mac App Store; no Sparkle | Met |
| 2.4.5(viii) | Runs on the current OS; no deprecated or optional technologies | Recheck on each macOS release |
| 2.4.5(ix) | Every language in the one bundle | Met: `Localizable.xcstrings` with en and vi |

Source: [2.4.5 hardware compatibility](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility). The hardened runtime (`ENABLE_HARDENED_RUNTIME = YES`) is set too, as ADR 0006 asks.

## Software, design and functionality (2.5, 4)

| Guideline | Requirement | For MindMap AI |
| --- | --- | --- |
| 2.5.1 | Public APIs only, for their intended purpose; mention the integration in the description | Foundation Models, Vision, Speech, PencilKit, CloudKit are all public |
| 2.5.2 | Self-contained; no downloading or running code that adds or changes features | Prompts and templates ship in the bundle. A downloaded open model (the "Optional local models" section of [on-device AI](on-device-ai.md)) needs its own App Review check first; whether weights count as code is not verified. |
| 2.5.11 | SiriKit and Shortcuts | App Intents in MM-11. No App Intents-specific guideline text found (not verified). |
| 2.5.16 | Widgets, extensions and notifications relate to the app's content | The Share Extension (MM-11) only adds content to maps |
| 4.0 | Minimum design standards; apps that degrade can be removed | See [design guidelines](design-guidelines.md) |
| 4.1(a)–(c) | No copycats; 4.1(c) (2025-11-13): no other developer's icon, brand or product name without approval | Name and icon are original ([news](https://developer.apple.com/news/?id=ey6d8onl)) |
| 4.2 | Enough functionality to be an app, not a thin wrapper | *[Inference]* The first release needs at least the canvas (MM-3) and import or export (MM-10); the outline editor alone risks a 4.2 rejection |
| 4.2.3 | Works on its own. Downloads needed at first launch state their size and ask first. | Foundation Models assets are downloaded by the system, not by the app. Speech and translation assets (`AssetInventory`, `TranslationSession`) need a prompt that names the download. |
| 4.3 | Spam: no near-duplicate apps (clarified 2026-06-08) | One app for all platforms ([news](https://developer.apple.com/news/?id=a233fmpw)) |

## Privacy (5.1)

| Guideline | Requirement | For MindMap AI |
| --- | --- | --- |
| 5.1.1(i) | Privacy policy link in App Store Connect **and** inside the app, even if nothing is collected. It says what is collected, how it is used, third parties, retention and deletion. | **Missing.** Write a policy page (for example `https://xdev.asia/mindmap/privacy`) and link it from Settings ▸ Privacy. |
| 5.1.1(ii)–(v) | Consent before collecting; paid features never require data access; minimum data; in-app account deletion when accounts exist | No accounts, no collection |
| 5.1.2(i) | Disclose sharing personal data with third parties, "including with third-party AI", and get explicit permission first (clarified 2025-11-13) | Does not apply to on-device Foundation Models *[Inference, not verified]*: no data leaves the device and Apple is not acting as a third party receiving it. Applies in full to any cloud AI provider: name the provider and ask before each request ([privacy](privacy.md)). Source: [news](https://developer.apple.com/news/?id=ey6d8onl). |
| 5.1.3(ii) | No personal health data in iCloud | Not applicable |

### App Privacy label

"Data that is processed only on device is not 'collected' and does not need to be disclosed" ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)). So SwiftData storage and on-device AI give **Data Not Collected**. *[Inference, not verified]* The CloudKit private database, which xDev cannot read, keeps that answer; Apple's page does not mention CloudKit. Answers can change in App Store Connect without a new build; change them the day analytics, crash reporting or cloud AI is added.

### Privacy manifest and required-reason APIs

App Store Connect rejects uploads that use a required-reason API without a declared reason (since 2024-05-01) ([required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [reason codes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)).

| API | Codes that fit this app | Status |
| --- | --- | --- |
| UserDefaults (`@AppStorage`) | CA92.1 (the app's own defaults); 1C8F.1 once the Share Extension shares defaults through an App Group | CA92.1 declared in `MindMapAI/Resources/PrivacyInfo.xcprivacy` |
| File timestamp | C617.1 (files in the app or CloudKit container), DDA9.1 (dates shown to the user), 3B52.1 (files the user picked) | Not used yet. Add when import, export or file dates arrive (MM-10). |
| System boot time, disk space, active keyboards | — | Not used |

The manifest also sets `NSPrivacyTracking = false` with no tracking domains and no collected data types, which matches Data Not Collected. *[Inference, not verified]* Each extension carries its own `PrivacyInfo.xcprivacy`.

## Foundation Models acceptable use

The [acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/) forbid using the framework for: breaking the law; harming children; violence; reckless use of weapons; hateful, defamatory or harassing content; suicide or self-harm; interactions that build harmful dependency; adult content; fraud; inferring sensitive traits from biometrics; social scoring; unsupervised high-impact decisions in employment, medical, legal or finance; predicting criminality; infringing IP, publicity or privacy rights; attacking systems; **circumventing the guardrails**; reproducing or citing Apple's training data; removing watermarks or content credentials; showing Apple falsely or negatively.

For MindMap AI:

- Mind-map generation and rewriting fit the allowed uses. Keep the default guardrails, and use `.permissiveContentTransformations` only to rewrite the user's own text, as [on-device AI](on-device-ai.md) says. Never retry a `guardrailViolation` with a reworded prompt that tries to get around it.
- The Developer Program License Agreement added §3.3.11(A) (Foundation Models) and §3.2(h) on 2026-06-08 ([news](https://developer.apple.com/news/?id=a233fmpw)). The full text was not read: not verified.
- Labelling AI output: the HIG asks for it ([Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)); no App Review guideline was found that requires it (not verified). The app labels suggestions anyway ([design guidelines](design-guidelines.md#ai-generated-content)).

## Age rating

- Since 2025-07-24 the ratings are 4+, 9+, 13+, 16+ and 18+, with new questions on in-app controls, capabilities, medical or wellness topics and violent themes. Answers were due by 2026-01-31 ([news](https://developer.apple.com/news/?id=ks775ehf)). Apple says to consider "how all app features, including AI assistants and chatbot functionality, impact the frequency of sensitive content".
- Questionnaire: in-app controls, capabilities (unrestricted web access, user-generated content, social media, messaging, advertising), medical or wellness ([values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)). Social media questions are required for submissions from September 2026 ([news](https://developer.apple.com/news/?id=tlur8uvi)).
- *[Inference]* Expected answer: 4+. The content is the user's own and is not shared with other users, and Foundation Models' guardrails filter generated text. Answer "no" to user-generated content only if maps are never published to other people; shared links would change that.
- Texas SB 2420 age assurance (Declared Age Range API) ([news](https://developer.apple.com/news/?id=sg176nne)): impact on a 4+ productivity app not verified.

## Accessibility Nutrition Labels

Declared per platform in App Store Connect: VoiceOver, Voice Control, Larger Text (not offered for Mac), Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions ([overview](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)). Voluntary for now; Apple says they become required "over time", with no date announced (not verified). Declare only what passes the audit in MM-12 for the app's common tasks. Captions and Audio Descriptions do not apply: there is no video.

## Export compliance

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set in both configurations. Apple treats encryption built into the operating system, such as HTTPS through `URLSession`, as exempt ([complying with export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations), [encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)). *[Inference, not verified]* CloudKit relies on the same system encryption, so `NO` stays correct after sync. Revisit if the app ever adds its own cryptography, such as end-to-end encrypted exports. France-specific rules were not verified.

## iCloud and CloudKit

- Deploy the development schema to production before release: App Store builds use only the production environment, and production changes can only add record types and fields ([deploying a schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)). This matches the SwiftData rule of never changing a shipped schema ([data model](data-model.md)).
- The app needs the iCloud capability with a CloudKit container (`iCloud.asia.xdev.mindmapai` *[Inference]*) and the remote notification background mode on iOS. Exact entitlement setup was not checked against an Apple page (not verified).
- No App Review guideline specifically about iCloud was found beyond 5.1.3(ii).

## Share Extension and App Intents

- 2.5.16: the extension relates to the app's content. It adds text, links, images or PDFs to a map and does nothing else.
- The extension and the app share the SwiftData store through an App Group ([module structure](module-structure.md)). That needs the App Group entitlement on both targets, reason 1C8F.1 for shared defaults, and its own privacy manifest *[Inference]*.
- App Intents: no guideline beyond 2.5.11 found (not verified). The intents run on the device and send nothing anywhere.

## StoreKit (3.1)

| Guideline | Requirement | For MindMap AI |
| --- | --- | --- |
| 3.1.1 | Unlocks use in-app purchase only, no license keys. Restorable purchases need a restore mechanism. A free trial without a subscription is a non-consumable at tier 0 named "XX-day Trial", with its length, what stops afterwards and the price stated up front. | A "Restore Purchases" button in Settings. StoreKit 2 `Transaction.currentEntitlements` on launch. |
| 3.1.2(a) | Subscriptions give ongoing value, last 7 days or more, work on all the user's devices | *[Inference]* Hard to argue for an on-device app with no service cost; prefer a one-time unlock unless the product adds ongoing content |
| 3.1.2(b) | Seamless upgrades and downgrades; no accidental double subscriptions | Only with subscriptions |
| 3.1.2(c) | Before asking to subscribe, state what the price buys and the terms | Only with subscriptions |
| 3.1.3 | Exceptions (reader apps, multiplatform services) | None apply |

Source: [3.1 in-app purchase](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase). Receipts: the SHA-1 certificate expired on 2025-01-24; use `AppTransaction` and `Transaction` from StoreKit 2 ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)).

**Universal purchase:** one app record and one bundle ID for every platform, with shared in-app purchases. It turns on when App Review approves a second platform, and a platform cannot be removed afterwards ([universal purchase](https://developer.apple.com/support/universal-purchase/)). Apple's page assumes an iOS app first; *[Inference, not verified]* for a Mac-first launch, add iOS to the same record later.

## EU Digital Services Act

Every developer declares trader or non-trader status; selling a paid app or in-app purchase points to trader. A trader's address, phone and email appear on EU product pages, and the account needs a D-U-N-S Number for an organisation. Apps without a status were removed from the EU storefronts from 2025-02-17 ([DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)). This is an account-level decision for xDev, not a code change.

## Common rejection reasons

Apple's [App Review page](https://developer.apple.com/distribute/app-review/) lists: crashes and bugs; broken links (support and privacy policy links are required for every app); placeholder content; incomplete information; privacy policy problems; unclear permission purpose strings; inaccurate screenshots; substandard UI. The App Store Transparency Report was not read (not verified).

For this app, the likely risks in order *[Inference]*: missing privacy policy or support URL; AI features the reviewer cannot see on an ineligible device or with Apple Intelligence off (explain in Review Notes); minimum functionality if the first release is too thin; usage strings for microphone, speech and photos once MM-8 and MM-11 add them.

## Checked against the project

As of commit `1e18d58`:

| Item | State | Where |
| --- | --- | --- |
| Privacy manifest | Present: no tracking, no collected data, UserDefaults CA92.1 | `MindMapAI/Resources/PrivacyInfo.xcprivacy` |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` | `MindMapAI.xcodeproj/project.pbxproj` |
| Sandbox, hardened runtime | Both `YES` | same |
| Category | `public.app-category.productivity` | same |
| Copyright | `© 2026 xDev` | same |
| Deployment target | macOS 26.0, iOS 26.0 | same |
| Version | `MARKETING_VERSION = 0.1.0`; the roadmap says "version 26" for MM-0c | same; decide before the first upload |
| Localisation | en and vi in the one bundle | `MindMapAI/Resources/Localizable.xcstrings` |
| Website link | `https://xdev.asia/mindmap` in Help and Settings ▸ About | `MindMapAI/App/AppLinks.swift` |
| Privacy policy link | **Missing** in the app and on the web | — |
| Support link | **Missing**; the startup failure screen tells people to contact support without saying how | `MindMapAI/App/RootView.swift` |
| Restore purchases | Not applicable until StoreKit | — |
| Permission usage strings | None needed yet | — |

## Do now

Items that cost little now and block a submission later. None are code changes in this task.

1. **Privacy policy and support pages** on xdev.asia, in English and Vietnamese, matching [privacy](privacy.md): on-device storage, no xDev servers, no analytics, on-device AI, iCloud once sync ships. Add `AppLinks.privacyPolicy` and `AppLinks.support`; link them from Settings ▸ Privacy, the Help menu and the startup failure screen.
2. **Decide the version scheme** (`MARKETING_VERSION` 0.1.0 against "version 26" in the roadmap) before the first TestFlight upload; the build number must grow with every upload.
3. **Create the App Store Connect record** for `asia.xdev.mindmapai` as a macOS app, reserving the name, and set the DSA trader status for the xDev account.
4. **Add a release checklist** to MM-12: screenshots per device, Review Notes text for AI availability, privacy label answers, accessibility labels, age rating answers, quarantine check, CloudKit schema deployed.

## Proposed tasks

| Proposed | Scope |
| --- | --- |
| MM-0h | Privacy policy and support pages, `AppLinks` entries, links in Settings, Help and the startup failure screen (en, vi) |
| MM-13 | Pricing decision and StoreKit 2: one-time unlock or subscription, restore in Settings, paywall copy that meets 3.1.1 and 3.1.2, StoreKit configuration file for tests |
| MM-14 | App Store submission kit: metadata in en and vi within the field limits, screenshots per device, Review Notes, privacy and accessibility label answers, age rating, TestFlight build |
