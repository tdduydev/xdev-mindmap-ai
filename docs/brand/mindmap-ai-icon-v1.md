Both images were generated with Codex CLI's built-in imagegen tool for direction B chosen by the product owner, follow xdev.asia/docs/brand/brand-decisions.md, and the wordmark PNG is a concept to be redrawn as SVG.

## App icon prompt

```text
Use case: app icon, final artwork. Produce a square 1024 x 1024 PNG with a fully OPAQUE flat cool-white #F7F9FC background covering every pixel edge to edge, including every corner. No alpha/transparency. No tile, border or shadow. This must remain a simple flat-background square for the operating system to mask.
Composition, direction B: Center the entire mark inside the central 80% of canvas, leaving at least 10% empty cool-white margin on ALL FOUR SIDES. On the left, the approved xDev geometric uppercase X from the attached brand reference: upright symmetric broad diagonal strokes with straight crisp cut ends, X HEIGHT exactly about 46% of the whole canvas (less than half). Gradient inside X: light cyan #7BD4FF at center, through #1E90FF to deep blue #004CFF at tips; soft SUBTLE blue glow immediately adjacent to X only. Position X slightly left of center as root of a mind map. From the RIGHT SIDE of its central crossing, three smooth distinct navy #344568 branch curves of EVEN MEDIUM stroke weight and rounded caps fan out rightward (upper, middle, lower). Each ends in a solid navy round node about one third of X stroke width; center node may be a little larger. Ensure all three nodes and branches stay inside central 80%.
Crisp flat vector-like edges, precise geometry, premium minimal and readable at 32px. Match approved xDev X DNA. ONLY X and three branches with one node each. No other text or letters, brains, sparkles, robots, circuit traces, hexagons, social-network X styling, 3D, perspective, heavy shadows, extra decoration.
```

## Wordmark prompt

```text
Use case: logo-brand, wordmark lockup concept.
On a solid opaque white #FFFFFF background, a horizontal landscape lockup in the exact style of the attached approved reference X + HIVE / DEV HUB: at left the same gradient xDev X with its soft glow; to its right "MINDMAP" in thin, evenly stroked uppercase letters with rounded caps and joins, color #344568, cap height equal to roughly 40 percent of the X height and aligned to the X's upper half; directly below "MINDMAP", a smaller "AI" in the same stroke style and color, left aligned with "MINDMAP", like DEV HUB under HIVE. Generous spacing, precise alignment, crisp flat vector-like edges. The X geometry and gradient must match the approved xDev brand reference: geometric broad diagonal X, center light cyan #7BD4FF through #1E90FF to blue #004CFF at tips.
Text only: "MINDMAP" and "AI" next to the X. Spell MINDMAP exactly M-I-N-D-M-A-P and AI exactly A-I. No other words, no icon tile, no mockup, no shadows, no transparency.
```

## Icon Composer icon (MM-0j)

The shipped icon is `MindMapAI/AppIcon.icon`, redrawn by hand from the PNG above rather than traced:

- `Assets/x.svg`: the X as one polygon (two 120 px strokes, 444 px tall, crossing at x 371, y 512), filled with a radial gradient `#7BD4FF` → `#1E90FF` → `#004CFF`. No glow; the system adds the lighting.
- `Assets/branches.svg`: three navy `#344568` branches (24 px, round caps) from the X's right notch, ending in nodes of radius 37, 46 and 37.
- `icon.json`: background `fill-specializations` `#F7F9FC` and dark `#142745`; the branches layer turns `#E8ECF8` in dark. Clear and tinted have no overrides: the system derives them.

The composition is shifted 21 px left of the PNG so the mark is centred. Edit the SVGs or `icon.json` directly or in Icon Composer, then run `swift scripts/render-app-icon.swift` and check `docs/brand/mindmap-ai-app-icon-appearances.png` (rows iOS, macOS; columns Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark).
