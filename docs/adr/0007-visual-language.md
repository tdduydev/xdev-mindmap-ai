# ADR 0007: Visual language and brand fonts

- Status: accepted
- Date: 2026-10-02
- Decided by: the product owner, choosing between options shown as rendered previews

## Context

The Human Interface Guidelines research (MM-0e, [design-guidelines.md](../design-guidelines.md)) settled how the app behaves on each platform, but not what the map itself looks like. The product must look like xDev's and not like XMind, MindNode, Freeform or Miro ([product.md](../product.md)). The xDev brand already has colours, fonts and motion tokens (`xdev-hive/packages/ui/src/tokens/`).

## Decision

| Question | Choice | Alternatives not taken |
| --- | --- | --- |
| Topic style | Hierarchical cards: filled navy central topic, tinted level-1 cards with a branch-coloured stroke, lightly tinted subtopics | Text on branch lines without boxes; capsules with solid branch fills |
| Edges | Curved (cubic Bézier), thinner with depth | Elbow connectors; straight lines |
| Branch colours | One colour per level-1 branch from a six-colour palette based on the xDev chart colours, plus per-map themes | A single xDev blue for everything |
| Dark canvas | xDev navy `#142745` | The system's dark background |
| Fonts | Be Vietnam Pro and Space Grotesk, bundled, for map content and display headlines only; system fonts for the app chrome | System font everywhere; SF Pro Rounded |
| AI signature | The xDev blue gradient on the `sparkles` symbol and on suggestion outlines, solid with Increase Contrast | Dashed outline in the branch colour; a separate violet |
| Default layout | Two-sided, balanced | One-sided to the right |

The details, values and contrast figures are in [design-system.md](../design-system.md).

## Consequences

- The app bundles two OFL font families (licence file in `MindMapAI/Resources/Fonts/`). Topic text uses `Font.custom(_:size:relativeTo:)` so Dynamic Type still works on iOS and iPadOS. This departs from the HIG's preference for system fonts on the canvas only; menus, lists, Settings and toolbars stay on the system font.
- The canvas has its own background colour in both modes, while the window chrome follows the system. Screenshots and the icon must be checked against both.
- Every custom colour needs four variants (light, dark, and both with Increase Contrast); a unit test checks their contrast.
- Gradients appear only on AI elements, never behind text, and turn solid with Increase Contrast or Reduce Transparency.
- Themes change only the branch colours, so they need no layout or schema change: `MindMap.theme` already exists and stores unknown values with a fallback.
- The layout engine (MM-4) defaults to two-sided balanced; one-sided stays a configuration option.
