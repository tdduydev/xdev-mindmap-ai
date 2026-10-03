# App Store submission kit

What goes into App Store Connect for MindMap AI by xDev (MM-14), kept here so a change is reviewed like code.

| File | What |
| --- | --- |
| `metadata.json` | Name, subtitle, description, keywords and promotional text per platform (`MAC_OS`, `IOS`) and locale (`en-US`, `vi`; Japanese in `metadata-ja.json`), the Pro in-app purchase text and the App Review notes, with measured lengths in `checks` |
| `build_metadata.py` | Writes `metadata.json` and checks every field against its limit (keywords in UTF-8 bytes) |
| `screenshots/` | App Store screenshots per platform and locale (MM-29, MM-74) |

Set in App Store Connect on 2026-10-03 through the API: the texts above, privacy policy, support and marketing URLs on xdev.asia, category Productivity (secondary Education), age rating answers (all none, 4+), version 1.0.0 for macOS and iOS, copyright "© 2026 Trần Duy (xDev)", content rights (no third-party content). Also set on 2026-10-03: App Privacy published as "Data Not Collected" and the App Review contact details (by hand in App Store Connect), the screenshots and the Pro review screenshot (through the API). Before Submit for Review: a 1.0.0 build chosen on each version, and the Pro in-app purchase added to the version, since a first in-app purchase is submitted with an app version.

Rules for these texts are in [app-store-readiness.md](../app-store-readiness.md): describe only what the shipped build does, no other apps' names, no prices.

## Screenshots

`scripts/app-store-screenshots.sh <iphone|ipad|mac> <en|vi|all> <light|dark|all>` runs `AppStoreScreenshotUITests` (UI test mode: showcase map, scripted AI, status bar 9:41) and writes:

| Path | What |
| --- | --- |
| `screenshots/raw/<platform>/<language>/NN-name.png` | The app as captured, no frame; dark mode in `dark/` |
| `screenshots/captions.json` | The caption of each slide per language |
| `screenshots/<platform>/<language>/NN-name.png` | Fallback slides at App Store size: caption over a plain gradient |
| `screenshots/backgrounds/<platform>/<language>/NN-name.png` | Optional art for a slide (MM-74); when present it replaces the gradient |

To recompose after adding art without recapturing, run again with `MINDMAP_SCREENSHOT_REUSE_RESULTS=1`. Set `MINDMAP_SCREENSHOT_SIMULATOR=<udid>` to capture on a simulator no other run uses. The Mac set is captured by the leader only, because a macOS UI test takes over the mouse and keyboard.
