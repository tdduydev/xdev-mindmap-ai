# Pricing

Decided 2026-10-02: MindMap AI is free, with one **Pro** unlock at **USD 14.99**, bought once (non-consumable, StoreKit 2), shared by Mac, iPad and iPhone through universal purchase, and with Family Sharing on (decided 2026-10-02; once on in App Store Connect it cannot be turned off). Core mind mapping is never locked and there are no ads.

## What Pro unlocks

| Pro | Stays free |
| --- | --- |
| Advanced export: multi-page vector PDF, high-resolution PNG (OPML joins once it is built, FR-IO-06; not offered until then) | Markdown and plain text import and export |
| Themes beyond Standard (xDev Blue, Graphite and later ones) | The Standard theme |
| Advanced AI: generate a map from a long description, summarize a whole map, find missing topics | Expand a topic, brainstorm, rewrite, summarize a branch |
| Voice input | Everything else: maps, topics, canvas, outline, search, iCloud sync, Recently Deleted |

The list lives in one place in code, so it can change without touching the features themselves.

## In code

- Product ID `asia.xdev.mindmapai.pro`, non-consumable, in `MindMapAITests/MindMapAI.storekit` (local testing and the scheme's Run action). The App Store Connect product must use the same ID.
- `ProFeature` (`MindMapAI/Features/Store/ProFeature.swift`) lists what Pro unlocks, and only what the app already has: the paywall lists every case (MM-75 removed OPML, which is not built). Its titles use the same names as the menus (Find Missing Topics). A Pro feature asks `ProEntitlement.allows(_:)` before it runs and opens `PaywallView(feature:)` when the answer is no; free features never ask.
- `ProEntitlement` reads `Transaction.currentEntitlements` at launch and whenever the app becomes active, listens to `Transaction.updates`, and finishes transactions. A refunded transaction locks Pro again. Nothing is cached in defaults.
- Themes: every theme picker (the map inspector, View ▸ Theme, Settings ▸ General ▸ Theme for New Maps) marks Pro themes with a star and opens the paywall when one is picked without Pro; the theme is applied only if Pro is unlocked there (`EditorSession.chooseTheme(_:entitlements:)`). A map that already has a Pro theme keeps showing it.
- The paywall does not name iCloud sync: a build without `MINDMAP_ICLOUD` has none, so it says "Maps, topics and everything else stay free."
- Settings ▸ MindMap AI Pro shows the status, opens the paywall and has Restore Purchases (`AppStore.sync()`).
- Family Sharing is on (decided 2026-10-02), in the configuration file and in App Store Connect. It cannot be turned off again once on.

## Pro gift codes

Asked for by the product owner on 2026-10-03 (MM-76, FR-STO-03): a way to give someone Pro for life. App Review 3.1.1 does not allow a license key of our own to unlock features, so a gift is always a code made by Apple.

**Making codes.** In App Store Connect, open the in-app purchase `asia.xdev.mindmapai.pro` and create offer codes for it (one-time-use codes, or a custom code). Apple caps how many codes an app can make; check the current number in App Store Connect before planning a giveaway. Unverified, to be checked in App Store Connect: offer codes for one-time purchases (non-consumables) came in 2025, and the older promo codes for in-app purchases are being retired, so use offer codes.

**Redeeming.** Settings ▸ MindMap AI Pro and the paywall have **Redeem Code…**, and on the Mac the app menu has it under Settings too (disabled once Pro is unlocked). It opens Apple's own redeem sheet with SwiftUI's `offerCodeRedemption`. People can also redeem in the App Store (account ▸ Redeem Gift Card or Code), or at https://apps.apple.com/redeem; the app's error alert links to that page.

**In code** (`MindMapAI/Features/Store/RedeemCode.swift`). The redeemed code becomes an ordinary transaction for the Pro product. `ProEntitlement.finishRedemption` reads the entitlements again as soon as the sheet closes, and the transaction also arrives through `Transaction.updates`. A cancelled sheet says nothing; a failure shows an alert. Checked in the Xcode 27 SDK: `offerCodeRedemption(isPresented:onCompletion:)` is available on macOS 15+ and iOS 16+ and deprecated in 27; the app targets 26, so it uses that one and, on 27, `offerCodeRedemption(options:isPresented:onCompletion:)`, which also returns the transaction. `AppStore.presentOfferCodeRedeemSheet` needs an `NSViewController`/`NSWindow` or a `UIWindowScene`, so the SwiftUI modifier is used. The SDK does not state which product types a code can be for; that is set in App Store Connect.

**Testing.** StoreKitTest cannot drive the redeem sheet. `ProEntitlementTests` stands in for a redeemed code with a transaction made outside the app, and checks cancel and failure.

## Market check

US App Store prices, checked on 2026-10-02 on each app's App Store page or the vendor's pricing page.

| App | Model | One-time | Subscription | AI |
| --- | --- | --- | --- | --- |
| MindNode | Free + subscription | — | $2.99/month, $24.99/year | In the paid tier (Apple Intelligence) |
| Xmind | Free + subscription | — | Pro $59/year, Premium $99/year | Credits, more in paid tiers |
| SimpleMind | Free + one-time unlock per platform | iPhone/iPad $10.99, Mac $29.99 | — | None built in |
| MindMeister | Free + subscription | — | $78–125.99/year | In every plan (beta) |
| Scapple | Paid, Mac only | $20.99 | — | None |
| OmniOutliner 6 | One-time or subscription | $24.99 / $99.99 | $49.99/year | Mentioned; tier not verified |
| Miro | Subscription | — | $8–20 per member/month | Credits per plan |
| Freeform | Free; extras in Apple Creator Studio | — | $12.99/month | AI images for subscribers |
| iThoughts | Discontinued (vendor ceased trading 2024-01-30) | — | — | — |

Sources: apps.apple.com pages for MindNode (id6446116532, id1289197285), Xmind (id1327661892), SimpleMind (id305727658, id439654198), MindMeister (id381073026), Scapple (id568020055), OmniOutliner 6 (id6474965689), Freeform (id6443742539); xmind.com/pricing, mindmeister.com/pricing, omnigroup.com/omnioutliner/buy, miro.com/pricing, toketaware.com.

## Why USD 14.99

*[Inference]* The reasoning, not a measured result:

- Every app that markets AI sells it by subscription. A one-time unlock that includes on-device AI has no direct competitor, and on-device AI costs xDev nothing per use.
- 14.99 sits above SimpleMind's iOS unlock (10.99), below Scapple (20.99), and below one year of MindNode's paid tier (24.99).
- One purchase for all platforms undercuts SimpleMind's separate Mac and iOS purchases (40.98 together).
- A one-time unlock avoids the App Review question of ongoing value that subscriptions face (guideline 3.1.2, see [app-store-readiness.md](app-store-readiness.md)).

## Vietnam

App Store prices in Vietnam seen on 2026-10-02: $2.99 → 99,000 ₫, $10.99 → 349,000 ₫, $20.99 → 599,000 ₫, $24.99 → 799,000 ₫, $29.99 → 999,000 ₫. Apple publishes no conversion table; it updates Vietnam prices automatically unless Vietnam is the base storefront ([Apple news, 2025-08-21](https://developer.apple.com/news/?id=yo2104n5)). Check the price App Store Connect generates for Vietnam before release, and set it by hand if it lands awkwardly (Apple has allowed per-storefront prices since 2023).
