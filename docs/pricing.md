# Pricing

Decided 2026-10-02: MindMap AI is free, with one **Pro** unlock at **USD 14.99**, bought once (non-consumable, StoreKit 2), shared by Mac, iPad and iPhone through universal purchase, and with Family Sharing on (decided 2026-10-02; once on in App Store Connect it cannot be turned off). Core mind mapping is never locked and there are no ads.

## What Pro unlocks

| Pro | Stays free |
| --- | --- |
| Advanced export: multi-page vector PDF, high-resolution PNG, OPML | Markdown and plain text import and export |
| Themes beyond Standard (xDev Blue, Graphite and later ones) | The Standard theme |
| Advanced AI: generate a map from a long description, summarize a whole map, find missing ideas | Expand a topic, brainstorm, rewrite, summarize a branch |
| Voice input | Everything else: maps, topics, canvas, outline, search, iCloud sync, Recently Deleted |

The list lives in one place in code, so it can change without touching the features themselves.

## In code

- Product ID `asia.xdev.mindmapai.pro`, non-consumable, in `MindMapAITests/MindMapAI.storekit` (local testing and the scheme's Run action). The App Store Connect product must use the same ID.
- `ProFeature` (`MindMapAI/Features/Store/ProFeature.swift`) lists what Pro unlocks. A Pro feature asks `ProEntitlement.allows(_:)` before it runs and opens `PaywallView(feature:)` when the answer is no; free features never ask.
- `ProEntitlement` reads `Transaction.currentEntitlements` at launch and whenever the app becomes active, listens to `Transaction.updates`, and finishes transactions. A refunded transaction locks Pro again. Nothing is cached in defaults.
- Settings ▸ MindMap AI Pro shows the status, opens the paywall and has Restore Purchases (`AppStore.sync()`).
- Family Sharing is on (decided 2026-10-02), in the configuration file and in App Store Connect. It cannot be turned off again once on.

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
