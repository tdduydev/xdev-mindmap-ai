# Design system

Version 1, 2026-10-02. The visual language of MindMap AI: tokens, the canvas components and how they adapt to each platform and accessibility setting. The product owner chose the options in [ADR 0007](adr/0007-visual-language.md); the HIG rules behind them are in [design-guidelines.md](design-guidelines.md). Code lives in `MindMapAI/DesignSystem/`; views use these names, never raw values.

Contrast figures are WCAG 2 ratios computed from the hex values below against the canvas they sit on. Values marked *[Proposal]* are starting points the implementation may tune, with the reason written in the task note.

## Principles

1. **Brand on the canvas, platform in the chrome.** The map (topics, edges, the canvas, onboarding and empty-state headlines) carries the xDev identity: its fonts, branch colours and navy dark canvas. Sidebar, toolbar, menus, lists, sheets and Settings use system fonts, colours and materials, so the app still feels like a Mac app.
2. **Glass for controls only.** Liquid Glass is for toolbars, the sidebar and the floating canvas controls. Topics, edges, the canvas and AI suggestions are opaque fills.
3. **Hierarchy you can see without colour.** Level shows in size, weight and shape, not only in colour. Selection has a ring, AI suggestions have a dashed outline and a symbol, collapsed branches have a count.
4. **Every colour has four values:** light, dark, light with Increase Contrast, dark with Increase Contrast.
5. **One token, one meaning.** A colour named for a role (`topicText`, `selectionRing`) is used for that role only.

## Colour

### Brand primitives

From the xDev design tokens (`xdev-hive/packages/ui/src/tokens/primitives.css`). Never used directly in views; semantic tokens below refer to them.

| Name | Hex | Name | Hex |
| --- | --- | --- | --- |
| brand blue light | `#7BD4FF` | navy 950 | `#0B1830` |
| brand blue mid | `#1E90FF` | navy 850 (brand navy) | `#142745` |
| brand blue deep | `#004CFF` | ink (neutral 700) | `#344568` |
| blue 400 | `#4AAEFF` | neutral 800 | `#22314F` |
| blue 800 | `#0038C2` | neutral 600 | `#5B6885` |
| canvas | `#F7F9FC` | navy 100 | `#E8ECF8` |

### Semantic tokens

| Token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast | Use |
| --- | --- | --- | --- | --- | --- |
| `canvasBackground` | `#F7F9FC` | `#142745` | `#FFFFFF` | `#0B1830` | Canvas behind the map |
| `topicText` | `#22314F` (12.3:1) | `#F4F6FC` (13.8:1) | `#0C1A33` | `#FFFFFF` | Topic titles |
| `topicTextSecondary` | `#5B6885` (5.3:1) | `#9DAAC7` (6.4:1) | `#344568` | `#E8ECF8` | Note previews, AI suggestion text, counts |
| `centralFill` | `#142745` | `#E8ECF8` | `#0B1830` | `#FFFFFF` | Central topic |
| `centralText` | `#FFFFFF` (14.9:1) | `#142745` (12.7:1) | `#FFFFFF` | `#0B1830` | Central topic title |
| `accent` (AccentColor) | `#004CFF` (5.7:1) | `#4AAEFF` (6.3:1) | `#0038C2` | `#7BD4FF` | Tint, selection, drop targets |
| `selectionRing` | = accent | = accent | = accent | = accent | 2 pt ring, 3 pt with Increase Contrast |
| `crossLink` | `#5B6885` (5.3:1) | `#9DAAC7` (6.4:1) | `#344568` | `#E8ECF8` | Cross-link lines and arrowheads |
| `searchMatchFill` | `#FFF4DB` | `#3D3423` | `#FFE7B3` | `#4A3B1E` | Find results behind the title |
| `searchMatchBorder` | `#B26A00` (4.0:1) | `#FFC35C` (9.4:1) | `#8B5300` | `#FFD285` | Outline of a find result |
| `favorite` | `#B26A00` (was `#F2A516`, 2.1:1 on white, below the 3:1 for graphics) | `#FFC35C` | `#9A5B00` | `#FFD285` | Star |
| `warningFill` / `warningText` | `#FFF4DB` / `#9A5B00` | `#3D3423` / `#FFC35C` | `#FFE7B3` / `#7A4600` | `#4A3B1E` / `#FFD285` | Save-failure banner (existing assets) |
| `danger` | `#C62828` | `#FF8A8A` | `#A51F1F` | `#FFB4B4` | Destructive confirmation text |
| `success` | `#0F7A4A` | `#4ADE9B` | `#0B5E39` | `#7EE2A8` | Sync on, export done |

The canvas uses its own `canvasBackground` in both modes; every other surface (sidebar, lists, sheets, the window behind the canvas controls) uses system colours.

### Branch palette

Each level-1 branch takes the next colour in the theme's palette, in order of `sortOrder`, cycling after the last. Descendants inherit their level-1 ancestor's colour. The Standard palette is the xDev chart palette, darkened for light mode so every line reaches at least 4:1 against the canvas (3:1 is the WCAG minimum for graphics).

| Branch | Light | vs `#F7F9FC` | Dark | vs `#142745` | Light IC | Dark IC |
| --- | --- | --- | --- | --- | --- | --- |
| blue | `#0B6CF5` | 4.5:1 | `#4AAEFF` | 6.3:1 | `#0954BF` | `#77C2FF` |
| teal | `#0B7F74` | 4.6:1 | `#3CCFBE` | 7.7:1 | `#09635A` | `#6DDBCE` |
| amber | `#B26A00` | 4.0:1 | `#FFC35C` | 9.4:1 | `#8B5300` | `#FFD285` |
| violet | `#6A4DF0` | 5.1:1 | `#A594FF` | 5.9:1 | `#533CBB` | `#BCAFFF` |
| rose | `#C2385E` | 5.0:1 | `#FF7FA0` | 6.3:1 | `#972C49` | `#FF9FB8` |
| green | `#1F8A55` | 4.1:1 | `#4ADE9B` | 8.7:1 | `#186C42` | `#77E6B4` |

Derived colours, computed in code from the branch colour so themes only define the line colour:

| Derived | Light | Dark | Increase Contrast |
| --- | --- | --- | --- |
| `mainFill` (level 1) | branch at 12% over the canvas | branch at 20% over the canvas | 18% light, 28% dark |
| `subFill` (level 2 and deeper) | branch at 7% | branch at 12% | 12% light, 20% dark |
| `mainStroke` | branch, 1.5 pt | branch, 1.5 pt | IC branch, 2 pt |
| `edge` | branch | branch | IC branch |
| `badgeFill` | IC branch (white text ≥ 6.3:1) | branch (navy text ≥ 5.9:1) | IC branch |

Topic text on any of these fills stays `topicText`; it measures 9.2:1 or more on every main and sub fill above.

### Themes

A map's `theme` (`MindMapTheme`, stored as a raw string) picks the branch palette. Three themes for V1 (MM-18, FR-THM-02); Standard is free, the other two are MindMap AI Pro (docs/pricing.md):

| Theme | Stored value | Branch colours (light / dark / light IC / dark IC) |
| --- | --- | --- |
| Standard (default) | `standard` | The six-colour palette above |
| xDev Blue | `xdevBlue` | Every branch the Standard blue: `#0B6CF5` / `#4AAEFF` / `#0954BF` / `#77C2FF`; levels told apart by shape and weight only |
| Graphite | `graphite` | Every branch neutral: `#5B6885` / `#9DAAC7` / `#465270` / `#BAC4DA`, for printing and calm maps |

Fills and badges derive from the line colour as for Standard (`BranchColors`), so a theme is one `BranchPalette`. A stored value this build does not know (written by a newer version) opens as Standard; the map is not rewritten until the user edits it, but the next save does store `standard`. The theme is picked per map in View ▸ Theme and in the inspector (Show Inspector, ⌃⌘I); each pick is one "Change Theme" undo step (`ChangeThemeCommand`).

Themes change colour only, never layout, fonts or shapes.

### AI gradient

The AI signature is the xDev gradient, drawn at 135°:

| | Light | Dark | Increase Contrast |
| --- | --- | --- | --- |
| Gradient | `#1E90FF` → `#004CFF` (ends 3.1:1 and 5.7:1 on the canvas) | `#7BD4FF` → `#4AAEFF` (9.0:1 and 6.3:1) | Solid `#0038C2` / `#7BD4FF` |

Used for: the `sparkles` symbol on AI buttons and menu items, the dashed outline of suggested topics, and the progress indicator while AI works. Never as a fill behind text, never on glass. With Increase Contrast or Reduce Transparency, the gradient becomes the solid colour in the last column.

## Typography

Two typefaces, both under the SIL Open Font License 1.1 with Vietnamese glyphs (checked in `google/fonts`, `ofl/bevietnampro` and `ofl/spacegrotesk`): **Be Vietnam Pro** for topic text and **Space Grotesk** for the central topic and display headlines. They ship in `MindMapAI/Resources/Fonts/` with one `OFL.txt` holding both families' copyright lines (the synchronized group copies resources flat into the bundle, so two files named `OFL.txt` would collide). `BrandFont.registerAll()` registers them with CoreText for the process when the app starts, on iOS and macOS alike: the generated Info.plist cannot hold the `UIAppFonts` array, and one code path is easier to test than two plist keys. Space Grotesk ships as a static SemiBold file (`SpaceGrotesk-SemiBold.ttf`, an instance of the variable font) so its PostScript name is fixed: upstream publishes static Light, Regular, Medium and Bold only, so this file is `SpaceGrotesk[wght].ttf` instanced at `wght` 600 with fontTools' `varLib.instancer`, named `Space Grotesk` / `SemiBold`. PostScript names: `BeVietnamPro-Regular`, `BeVietnamPro-Medium`, `BeVietnamPro-SemiBold`, `SpaceGrotesk-SemiBold`.

**Japanese (MM-96, NFR-L10N).** Neither family has kana or kanji. `ContentFont` gives each brand face a CoreText cascade list: Hiragino Sans first (W3 beside Be Vietnam Pro Regular, W6 beside Medium, SemiBold and Space Grotesk; iOS has only W3, W6 and W7), then the system's cascade for Japanese. Without it, a Mac or iPhone set to English or Vietnamese draws kana in Hiragino Sans but kanji and 、。「」 in PingFang SC, so one title mixes Chinese and Japanese glyph forms. Someone whose languages list Chinese before Japanese keeps the system cascade. The canvas (topic titles, marks, tag chips, callouts, the title editor) draws with `ContentFont.font` at the size it already scaled for Dynamic Type, and `TopicMeasurer` measures with the same `CTFont`. On macOS every content style uses it too; on iOS `ContentStyle.font` keeps `relativeTo` (a `CTFont` cannot follow Dynamic Type), so outside the canvas kanji fall back by the system's languages. SwiftUI sets each line at least as tall as the brand face and adds the brand face's leading, never Hiragino's 0.5 em, so the measurer does the same (`JapaneseTypographyTests`).

Content styles (canvas points at 100% zoom). On iOS and iPadOS each is `Font.custom(_:size:relativeTo:)`, so it scales with Dynamic Type; macOS has no Dynamic Type and uses the size as is.

| Role | Family, weight | Size / line | Relative to | Used for |
| --- | --- | --- | --- | --- |
| `central` | Space Grotesk SemiBold (600) | 20 / 26 | `.title3` | Central topic |
| `main` | Be Vietnam Pro SemiBold | 15 / 20 | `.body` | Level-1 topics |
| `sub` | Be Vietnam Pro Regular | 14 / 19 | `.callout` | Level 2 |
| `deep` | Be Vietnam Pro Regular | 13 / 18 | `.subheadline` | Level 3 and deeper |
| `outlineTopic` | Be Vietnam Pro Regular / SemiBold for the root | 14 / 20 | `.body` | Outline editor rows |
| `note` | Be Vietnam Pro Regular | 14 / 21 | `.body` | Note text in the inspector |
| `badge` | Be Vietnam Pro SemiBold | 11 / 14 | `.caption2` | Collapse count, AI label |
| `display` | Space Grotesk SemiBold | 28 / 34 | `.largeTitle` | Onboarding and empty-state headlines |

Chrome keeps system text styles (`Typography.rowTitle`, `.rowDetail`, `.banner` and the like): sidebar, library list, toolbar, menus, Settings, alerts. Rules: no weight below Regular, no italics for emphasis on the canvas, numbers in tabular figures where they line up (counts, zoom percentage).

## Space and size

The 4-point grid of `Spacing` (2, 4, 8, 12, 16, 24, 32) stays. Canvas metrics are a separate enum, `CanvasMetrics`:

| Token | Central | Main | Sub and deeper |
| --- | --- | --- | --- |
| Padding (horizontal × vertical) | 16 × 12 | 12 × 8 | 10 × 6 |
| Minimum width | 96 | 56 | 40 |
| Maximum width (then wrap) | 280 | 240 | 220 |
| Corner radius | 12 | 10 | 8 |
| Gap to the parent (horizontal) | — | 64 | 40 |
| Gap between siblings (vertical) | — | 20 | 10 |
| Edge width from the parent | — | 3 | 2 (1.5 from level 3) |

- Titles wrap and are never truncated on the canvas; the outline truncates to one line with the full title in the accessibility label.
- Hit target: the visual box on the Mac (minimum 28 pt high); on iOS and iPadOS the tappable area grows to 44 × 44 pt around small topics without changing the drawing.
- Selection ring: 2 pt outside the topic with a 2 pt gap, 3 pt with Increase Contrast.
- Collapse badge: a capsule 18 pt high on the Mac, 22 pt on iOS, on the side away from the parent.

## Edges

| Kind | Shape | Stroke | Colour |
| --- | --- | --- | --- |
| Hierarchy | Cubic Bézier from the parent's side centre to the child's side centre, both control points at half the horizontal distance | Width by level (table above), round caps | Branch colour |
| Connection (cross-link) | Gentle arc between the closest sides, arrowhead at the target for `reference`, none for `relationship` | 1.5 pt, dashed 4–3 | `crossLink` |
| Connection label | Capsule on the arc's midpoint, `badge` text | — | `canvasBackground` fill, `crossLink` stroke |
| AI suggestion | As hierarchy | 1.5 pt, dashed 3–3 | AI gradient |

Edges are drawn under topics and never cross a topic's box; the layout engine (MM-4) owns the routing, the canvas only draws.

## Topic states

| State | Appearance |
| --- | --- |
| Default | Central: `centralFill`. Main: `mainFill` with `mainStroke`. Sub: `subFill`, no stroke |
| Hover (pointer) | Fill 4% darker in light, 6% lighter in dark; the + buttons show (below) |
| Add buttons (hover or selected) | Round `accent` circle as tall as the collapse badge (18 pt Mac, 22 pt iOS), bold `plus` in `canvasBackground` with a 1.5 pt `canvasBackground` ring; solid, not glass, since it is content. Add child: outside the card on the side away from the parent, beyond the collapse badge when there is one. Add sibling: under the card, centred, the circle 4 pt beyond the selection ring; only when its whole tap area fits before the next topic, none on the central topic. The buttons and their `Metrics.minimumHitTarget` hit areas (24 pt Mac, 44 pt iOS) stay in screen coordinates through detail zoom and never overlap a topic. Shown on the hovered topic and on the primary selection (touch has no hover); not while a title is edited, during a drag or a selection rectangle, on suggestions, or below the detail zoom. Leaving waits `Motion.hoverExitDelay` (0.2 s) so crossing to a button or an edge does not blink them. Hidden from VoiceOver: the topic element has Add Child Topic and Add Sibling Topic |
| Selected | `selectionRing` around the box |
| Multi-selected | Same ring on each topic; the toolbar shows the count |
| Editing | Ring stays; the title becomes a text field in the same font, size and position, so nothing jumps |
| Drag source | Topic at 60% opacity in place; a copy follows the pointer with the drag shadow |
| Drop target | Accent dashed outline (2 pt) on the new parent, or a 3 pt accent bar where it will be inserted |
| Collapsed | Badge with the number of hidden topics (`badgeFill`, `badge` text) |
| Has note | `note.text` symbol, 11 pt, `topicTextSecondary`, after the title |
| Topic colour (MM-32) | The token's `BranchColors` replace the branch colour for the topic and its descendants without their own; the central topic keeps its card |
| Topic symbol (MM-32) | Before the title on its first baseline, in the title's font and `topicText`; box 1.25 × title size (`CanvasMetrics.topicSymbolWidthFactor`), 4 pt gap (`topicMarkGap`) |
| Colour shape (MM-32) | With Differentiate Without Color, and always in export: the colour's shape (`TopicColor.shapeSymbol`), 9 pt (`topicColorShapeSize`), in the line colour, before the symbol |
| Search match | `searchMatchFill` behind the title, `searchMatchBorder` outline; the current match also gets the selection ring |
| AI suggestion | Canvas-coloured fill, dashed AI-gradient outline, `sparkles` in the gradient on the top-leading corner, title in `topicTextSecondary`; Accept and Discard buttons under the topic on hover or selection. MM-8 put the symbol on the corner rather than before the title so the title keeps the measured width of a plain topic |
| Accepted AI topic | Looks like any topic (its origin is kept in `metadata.origin`) |

## Node types

Drawing rules for the V1 node types designed in [node-organization.md](node-organization.md) *Node types* (MM-58). Content, not controls: none of them uses glass. Values marked [Đề xuất] are proposals for the implementing task; the contrast test covers every new colour pair.

### New colour tokens

| Token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast | Use |
| --- | --- | --- | --- | --- | --- |
| `calloutFill` | `#EEF2FA` | `#1E3358` | `#FFFFFF` | `#0B1830` | Callout bubble; `topicText` on it is 11.6:1 light and dark, 17.3:1 and 17.7:1 with Increase Contrast |
| `calloutStroke` | = `crossLink` | = `crossLink` | = `crossLink` | = `crossLink` | Bubble outline and tail; 5.3:1 and 6.4:1 on `canvasBackground` (above the 3:1 for graphics), so the bubble reads even where its fill is close to the canvas (1.1:1 in light) |
| `summaryBracket` | = `crossLink` | = `crossLink` | = `crossLink` | = `crossLink` | The bracket, unless the summary has a `colorToken` (then the branch colour of that token) |

Ratios computed with the WCAG formula from the hex values above. Reusing `crossLink` for strokes adds no new asset; `calloutFill` is a new colour set with all four appearances.

### New `CanvasMetrics`

| Token | Value | Use |
| --- | --- | --- |
| `linkSymbolSize` | 11 pt (as the note mark) | Link icon after the title |
| `imageWidthSmall`, `imageWidthMedium`, `imageWidthLarge` | 96, 160, 240 pt [Đề xuất] | Image display width; never wider than the level's maximum width |
| `imageMaxAspect` | 1.5 (height ÷ width) | Taller images are cropped to fill |
| `imageCornerRadius` | Topic corner radius − 4 pt | Image inside the card |
| `imageGap` | `Spacing` 8 | Between image and title |
| `calloutGap` | `Spacing` 8 | Between the bubble's tail and the card |
| `calloutPadding` | 8 × 6 pt | Inside the bubble |
| `calloutCornerRadius` | 8 pt | Bubble |
| `calloutTail` | 8 pt wide, 6 pt high | Triangle centred on the bubble's bottom edge, pointing at the card |
| `summaryBracketGap` | 12 pt | From the run's outer edge to the bracket |
| `summaryBracketDepth` | 10 pt | How far the bracket's tip stands out |
| `summaryBracketWidth` | 1.5 pt (2 pt with Increase Contrast) | Bracket stroke, round caps |
| `floatingTopicNudge` | 24 pt [Đề xuất] | Step when Add Floating Topic looks for a free spot |
| `boundaryPadding` | 8 pt | From the members to the frame; reserved by the layout |
| `boundaryTitleHeight` | 20 pt | Title room above a titled boundary's members; the title capsule is centred in it |
| `boundaryCornerRadius` | 12 pt | Frame |
| `boundaryStrokeWidth` | 1.5 pt (2 pt with Increase Contrast) | Frame and title capsule stroke |
| `boundaryTitlePadding` | 6 × 2 pt | Inside the title capsule |
| `boundaryTitleMaxWidth` | 200 pt | The title capsule truncates past it; also the in-place title field's width |

### How each draws

| Element | Drawing |
| --- | --- |
| Link | `link` (`envelope` for `mailto`) after the title and the note mark, `linkSymbolSize`, `topicTextSecondary` (`centralText` on the central topic); pointing-hand pointer and a help tag with the URL on the Mac; hit target `Metrics.minimumHitTarget` |
| Image | Above the title inside the card, `imageGap` to the title, `imageCornerRadius`; card padding as for the level. Below the detail zoom: a rectangle in the card's stroke colour at 30% |
| Callout | Rounded bubble (`calloutCornerRadius`, `calloutPadding`) above the card, `calloutGap` away, `calloutFill`, 1 pt `calloutStroke` (2 pt with Increase Contrast), tail toward the card; text in the sub-topic content font, `topicText`, wraps at the topic's maximum width. Selected: the selection ring around the bubble |
| Summary bracket | A curly bracket path along the run's outer edge, `summaryBracketGap` away, tip `summaryBracketDepth` toward the summary topic; `summaryBracket` colour, `summaryBracketWidth`. Solid, like boundaries: dashed stays for AI and drop targets. Selected: drawn in `selectionRing` |
| Boundary (MM-37) | Rounded rectangle (`boundaryCornerRadius`) under every edge and topic: fill = the colour's sub-topic fill (`BranchColors.subFill`, so dark and Increase Contrast come with it), solid `boundaryStrokeWidth` stroke in its line colour; graphite when it has no colour. Title: `badge` text in a `canvasBackground` capsule with the same stroke, `boundaryPadding` from the leading edge, in the title room. Selected: the selection ring `selectionRingGap` outside the frame. AI preview (Suggest Groups, Summarize Boundary): `canvasBackground` fill and the AI dashed stroke on frame and capsule |
| Summary topic | Drawn as a topic one level below the run's parent (so a summary over main topics looks like a main topic) |
| Floating topic | Main-topic style (level 1), next branch colour after the main topics; no connector to the tree |

Motion: a callout, image or summary appearing fades in with the topic-added motion (`base` enter, fade only with Reduce Motion); the tree moving to make room uses the relayout motion (`slow`, jump with Reduce Motion); moving a floating topic follows the pointer with no animation.

## Elevation

The map is flat: no shadows on topics at rest. Only two things lift:

| Element | Light | Dark |
| --- | --- | --- |
| Dragged topic | `0 8 24` navy 18% + `0 2 6` navy 8% | `0 8 24` black 45% |
| Floating canvas controls | System glass (`GlassEffectContainer`) | System glass |

Popovers, menus and sheets are system components with system shadows.

## Motion

From the xDev motion tokens. All animation goes through `Motion`; with Reduce Motion, movement becomes a fast crossfade or nothing.

| Token | Duration | Curve |
| --- | --- | --- |
| `instant` | 80 ms | standard |
| `fast` | 120 ms | standard |
| `base` | 180 ms | standard (0.2, 0, 0, 1) |
| `slow` | 240 ms | standard |
| `slower` | 320 ms | emphasized (0.3, 0, 0, 1) |
| curves | | enter (0, 0, 0.2, 1), exit (0.4, 0, 1, 1) |

| Change | Motion | With Reduce Motion |
| --- | --- | --- |
| Topic added | Fade in and scale 0.96 → 1, `base` enter | Fade, `fast` |
| Topic deleted | Fade out, `fast` exit | Remove |
| Collapse, expand, relayout | Topics move to their new frames, `slow` | Jump |
| Zoom to fit, jump to a search result | Camera move, `slower` | Jump |
| AI suggestions arriving | Each fades in, 40 ms apart, `base` enter | All appear at once |
| Selection ring | `instant` | None |

## Symbols

SF Symbols only, outline style in toolbars and menus. Names to verify in the SF Symbols app when implementing.

| Action | Symbol | Action | Symbol |
| --- | --- | --- | --- |
| New Mind Map | `square.and.pencil` | AI actions | `sparkles` (AI gradient) |
| Add Child Topic | `arrow.turn.down.right` | Note | `note.text` |
| Add Sibling Topic | `return` | Connection (cross-link) | `point.topleft.down.to.point.bottomright.curvepath` [verify name; was `link`, which now means a URL] |
| Delete Topic | `trash` | Search | `magnifyingglass` |
| Collapse / Expand | `chevron.down` / `chevron.right` | Inspector | `sidebar.right` |
| Zoom In / Out | `plus.magnifyingglass` / `minus.magnifyingglass` | iCloud on / off / error | `icloud` / `icloud.slash` / `exclamationmark.icloud` |
| Zoom to Fit | `arrow.up.left.and.arrow.down.right` | Voice input | `mic` |
| Favorite | `star` / `star.fill` | Restore from Recently Deleted | `arrow.uturn.backward` |
| Link (URL) | `link`; `envelope` for `mailto` | Image | `photo` |
| Floating topic | `square.dashed` [verify] | Summary | `curlybraces` [verify] |
| Callout | `text.bubble` | | |

## Components

| Component | Built from | Notes |
| --- | --- | --- |
| `TopicView` | Content font by level, fills and strokes from the theme, state from the session | One accessibility element: "title, level n, m subtopics", plus actions |
| `EdgeLayer` | One `Canvas` (SwiftUI) per visible region | Draws hierarchy, cross-links and suggestion edges from layout output |
| `CanvasControls` | `GlassEffectContainer` with zoom out, zoom percentage, zoom in, fit, add topic, AI | Trailing bottom on Mac and iPad; above the home indicator on iPhone |
| `CollapseBadge` | Capsule, `badge` text | Tap or click expands |
| `AISuggestionBar` | Glass bar above the canvas: "n suggestions", Accept All, Discard | Per-topic Accept and Discard live on each suggestion |
| `EmptyState` | `ContentUnavailableView` with a `display` headline on the canvas, system text in lists | Always with an action button |
| `SyncStatusLine` | Caption text and symbol in the sidebar footer | Never an alert |
| `TopicInspector` | `.inspector`, note editor in the `note` font | Sheet on iPhone |
| `BrandMark` | `BrandMark` image set (from `docs/brand/mindmap-ai-icon-v1.png`, 64 pt at @1x/@2x/@3x) in a continuous rounded square, plus live text: "MindMap AI" in `display` (Space Grotesk SemiBold) and "by xDev" in `brandByline` | Lockup in the library's empty state and Settings ▸ About; icon alone, 32 pt, on the storage recovery screen. Never in the sidebar or toolbar. One VoiceOver element, "MindMap AI by xDev" |

## Accessibility

- **Contrast:** text 4.5:1 or more, graphics 3:1 or more, in all four colour variants. The tables above give the figures; a unit test recomputes them from the tokens so a change cannot regress.
- **Increase Contrast:** IC colours, 2 pt strokes, 3 pt selection ring, gradients become solid.
- **Reduce Transparency:** canvas controls use the system's frosted fallback; nothing on the canvas is translucent anyway.
- **Differentiate Without Color:** levels differ in font size and weight and in shape (central filled, main outlined, sub plain); suggestions have the dashed outline and the symbol; search matches have an outline.
- **Dynamic Type (iOS, iPadOS):** content fonts scale with `relativeTo`; topics grow and the layout reflows. At accessibility sizes the canvas starts zoomed to fit the central topic and its children.
- **VoiceOver:** see FR-CNV-07 in the SRS; the outline editor remains the full alternative.

## Platforms

| | Mac | iPad | iPhone |
| --- | --- | --- | --- |
| Canvas controls | Toolbar items plus the floating cluster | Floating cluster | Floating cluster, compact |
| Topic hit area | Visual box | 44 pt minimum | 44 pt minimum |
| Pointer | Hover state, open and closed hand while panning | Hover state | — |
| Default zoom | 100% | 100% | Fit width of the central topic and level 1 |

## Implementation

| Swift name | Holds |
| --- | --- |
| `Palette` | Semantic colours (asset catalog colour sets with Any, Dark and High Contrast appearances); `Palette.Tokens` holds the same values for code that computes with them, and a test keeps the two equal |
| `BranchPalette`, `MapTheme` | Branch colours per theme and the derived fills (computed, so no asset per derived colour) |
| `Typography` | Chrome styles (system) and `Typography.Content` (brand fonts, `relativeTo`) |
| `Spacing`, `Radius`, `Metrics` | Existing scales |
| `CanvasMetrics` | The canvas table above |
| `Elevation` | The drag shadow |
| `Motion` | Durations, curves and the Reduce Motion rule |
| `TopicStyle` | `resolve(level:branch:theme:colorScheme:contrast:)`: fill, stroke, font, padding and radius for a level, the index of its level-1 branch, theme, colour scheme and contrast setting |

- A debug-only `DesignSystemGallery` view shows every token and topic state in both modes for review and screenshots.
- Colour sets are named after their token (`CanvasBackground`, `TopicText`…), each with Any, Dark, and High Contrast variants.
- Tests: WCAG contrast of every text and graphic pair in the four variants; `TopicStyle` resolution per level and theme; the fonts load on both platforms; Japanese falls back to Hiragino Sans and a Japanese title is drawn as tall as measured (`JapaneseTypographyTests`).

## Not decided yet

- The exact list and colours of themes beyond Standard (MM-18).
- Whether the app icon picks up the AI gradient (the icon itself is in [design-guidelines.md](design-guidelines.md), MM-0j).
- Topic shapes chosen by the user (not in V1). Topic colour and symbol per topic are designed in [node-organization.md](node-organization.md) (MM-32).
