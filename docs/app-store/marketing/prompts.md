# MM-74 marketing artwork

Generated with Codex's built-in imagegen tool on 2026-10-03. The tool created **backgrounds only**; `compose.swift` adds unaltered MM-29 screenshots, simple device frames, and exact captions from `screenshots/captions.json`. No generated app interface appears in the deliverables.

## Portrait background — `artwork-portrait.png`

> Use case: ads-marketing. Asset type: abstract background artwork for MindMap AI App Store product screenshots, portrait format. Create only a sophisticated, airy background with elegant flowing translucent blue ribbons and soft luminous branching arcs suggesting ideas connecting, over a very pale cool white-blue #F7F9FC field. Use xDev brand colors #7BD4FF, #1E90FF, #004CFF with restrained navy #344568 details. Keep center and upper quarter open and quiet for a device screenshot and a large readable caption that will be added later. Premium Apple-style editorial composition, subtle depth, soft gradient lighting, crisp clean edges, no fake UI, no devices, no symbols, no letters, no words, no logo, no watermark.

## Landscape background — `artwork-landscape.png`

> Use case: ads-marketing. Asset type: abstract panoramic background artwork for MindMap AI website hero and Open Graph image, wide landscape format. Create only a premium airy abstract background: elegant layered translucent blue ribbons and gentle luminous branching arcs suggesting ideas connecting, flowing chiefly around the lower edge and right edge, on a pale cool white-blue #F7F9FC ground. xDev brand palette #7BD4FF to #1E90FF to #004CFF, one restrained navy #344568 accent. Leave generous quiet clear negative space on the left and in the upper center for a real app screenshot and layout added later. Modern editorial, subtle dimension, fine optical detail, no UI, no devices, no letters, no text, no logo, no watermark.

## Composition and source limits

Run from the repository root: `swift docs/app-store/marketing/compose.swift`. It uses only Apple system frameworks and the bundled Space Grotesk font. The output PNGs have an sRGB profile and no alpha. Odd-numbered slides mirror the artwork to vary the layout; captured app pixels and localized captions are not changed.

MM-29 currently has English and Vietnamese iPhone captures, English iPad captures, and no Mac captures. The Vietnamese iPad slides therefore use **real English iPad UI captures** with the exact Vietnamese captions; replace them after localized iPad captures arrive. The script emits Mac slides at 2880 × 1800 when real `raw/mac/<language>/` captures are supplied. The hero and Open Graph images use the real English iPad canvas capture and leave space at left for HTML copy.
