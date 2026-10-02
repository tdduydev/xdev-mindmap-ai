# App Store submission kit

What goes into App Store Connect for MindMap AI by xDev (MM-14), kept here so a change is reviewed like code.

| File | What |
| --- | --- |
| `metadata.json` | Name, subtitle, description, keywords and promotional text per platform (`MAC_OS`, `IOS`) and locale (`en-US`, `vi`), the Pro in-app purchase text and the App Review notes, with measured lengths in `checks` |
| `build_metadata.py` | Writes `metadata.json` and checks every field against its limit (keywords in UTF-8 bytes) |
| `screenshots/` | App Store screenshots per platform and locale (MM-29, MM-74) |

Set in App Store Connect on 2026-10-03 through the API: the texts above, privacy policy, support and marketing URLs on xdev.asia, category Productivity (secondary Education), age rating answers (all none, 4+), version 1.0.0 for macOS and iOS, copyright "© 2026 Trần Duy (xDev)", content rights (no third-party content). Still by hand in App Store Connect: App Privacy ("Data Not Collected"), App Review contact details, screenshots until they are uploaded, and the build to submit (1.0.0; TestFlight builds are 0.x).

Rules for these texts are in [app-store-readiness.md](../app-store-readiness.md): describe only what the shipped build does, no other apps' names, no prices.
