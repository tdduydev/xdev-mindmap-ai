# Design guidelines

Research for MM-0e, 2026-10-02. The Human Interface Guidelines rules that apply to MindMap AI on the Mac, iPad and iPhone, in the OS 26 Liquid Glass design. Sources are HIG pages and WWDC25 sessions; quotes are close paraphrases, so check the page before quoting one in an ADR. "Not verified" means no Apple page confirmed it. *[Inference]* marks reasoned points. WWDC26 and OS 27 design changes were not reviewed.

Tokens for colour, type, spacing and motion live in `MindMapAI/DesignSystem/`; this page says when to use what, not the values.

## Summary

- **Glass is for controls, never content.** Toolbars, sidebars and popovers use system Liquid Glass; nodes, edges and the canvas never do ([Materials](https://developer.apple.com/design/human-interface-guidelines/materials)).
- **Standard components first.** `NavigationSplitView`, `.toolbar`, `Settings`, `Commands`, `ContentUnavailableView` and `.searchable` take on the new design and accessibility for free. Custom glass only for the floating canvas controls.
- **On the Mac, the menu bar is the full command list.** Every toolbar item and every editor action is a menu item with its state shown, disabled rather than hidden ([The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
- **Every map is usable without the canvas.** The outline editor stays as the VoiceOver and keyboard path; the HIG asks for infographics to be "fully accessible" ([VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)).
- **AI suggests, people decide.** Generated nodes arrive as a preview with Accept, Edit and Discard, are labelled as AI, and undo in one step ([Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)).

## Liquid Glass and materials

| Rule | Source |
| --- | --- |
| Liquid Glass is a functional layer for controls and navigation that floats above content. Do not use it in the content layer, except transient controls such as a slider while in use. | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| Use custom glass sparingly; standard components adopt it automatically. Regular variant for sidebars, popovers and alerts; clear only over rich media, with a dimming layer at about 35% over bright content. | same |
| Avoid glass on glass. Things that sit on glass use fills, transparency and vibrancy. | [WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/) |
| Reduce Transparency makes glass frostier, Increase Contrast makes it nearly black or white with a border, Reduce Motion removes elastic effects. The system does this for standard materials only. | same |
| Glass has no colour of its own. Tint the background of the one primary action, not its symbol, and not several controls. | [Color](https://developer.apple.com/design/human-interface-guidelines/color) |
| Every custom colour has light, dark and increased-contrast variants. | same |
| Scroll edge effects mark where content passes under bars: soft on iOS, hard on macOS, one per view. Nest rounded shapes concentrically. | [WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/) |

SwiftUI: `glassEffect(_:in:)` (regular, capsule by default; `.tint`, `.interactive`), `GlassEffectContainer` around groups of glass views, `glassEffectID` for morphing; keep the number of containers on screen small for performance ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)).

For MindMap AI:

- Canvas controls (zoom, fit, add topic, AI) float as one `GlassEffectContainer` over the canvas. Nodes are opaque fills from `Palette`, never glass.
- Node selection uses the accent colour on the node fill or outline, not a glass highlight.
- The AI suggestion preview is content, so suggested nodes are drawn as nodes in a distinct style (see [AI-generated content](#ai-generated-content)), not as glass.

## Structure: sidebar, toolbar, split view

| Rule | Source |
| --- | --- |
| Sidebars float in the glass layer; let content extend under them, or use `backgroundExtensionEffect()`. At most two levels of hierarchy. People can hide the sidebar, but it is not hidden by default. On macOS, Show/Hide Sidebar is in the View menu. | [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) |
| Panes can be hidden and shown again in several ways: toolbar button, menu item, shortcut. Plan for compact, in-between and wide widths. | [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views) |
| Toolbar items grouped by function and frequency, at most about three groups, text actions apart from symbol actions. `.prominent` for one primary action on the trailing side. No custom toolbar background or tint. | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) |
| No hand-made overflow menu: macOS and iPadOS add one. Window title under about 15 characters and not the app name. | same |
| `ToolbarSpacer(.fixed)` / `(.flexible)` separates groups (OS 26). | [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer) |
| Search on the trailing side of the toolbar or at the top of the sidebar on Mac and iPad; at the bottom or as a search tab on iPhone. | [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) |
| An inspector for node details: no specific HIG guidance found (not verified). *[Inference]* Use SwiftUI `.inspector`, toggled from the toolbar and the View menu. | — |

For MindMap AI the layout is sidebar (sections) ▸ library (maps) ▸ editor, as `RootView` already does. The editor's window title is the map's title.

## Mac

### Menu bar

| Rule | Source |
| --- | --- |
| Order: App, File, Edit, Format, View, app menus, Window, Help. | [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) |
| Always show the same items; disable what does not apply. Use "Delete", not "Erase" or "Clear". | same |
| View has Show/Hide Toolbar, Customize Toolbar, Show/Hide Sidebar, Enter/Exit Full Screen. | same |
| App ▸ Settings is for app-wide settings; per-document settings go in File. | same |
| Every toolbar item is also a menu item. | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) |
| Menu items: title-style capitalisation, start with a verb, "…" when more input follows. Icons on all items of a group or none. | [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) |
| Undo and Redo top the Edit menu with ⌘Z and ⇧⌘Z and name the action ("Undo Typing"). Undo should be unlimited; group related changes into one step. | [Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) |

The app's menus:

| Menu | Items |
| --- | --- |
| File | New Mind Map ⌘N, New Window ⌥⌘N, Import… ⇧⌘I, Import into Map… ⌥⇧⌘I, Export… ⇧⌘E (MM-10), Delete Map ⌘⌫, Restore Map, Delete Map Permanently… ⌥⌘⌫ (MM-19; shortcuts only while the library list has focus), later Duplicate |
| Edit | Undo/Redo with the command's action name, Cut, Copy, Paste branch (MM-5), Select All, Find ⌘F |
| View | Show/Hide Sidebar, Show/Hide Inspector, Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0, Zoom to Fit, Enter Full Screen |
| Topic | Add Sibling, Add Child, Promote, Demote, Collapse/Expand, Delete (the Delete key); Add Link… ⌘K, Open Link ⇧⌘O, Add Connection… ⌘L, Add Floating Topic ⌥⌘↩, Add Image… ⌥⌘I, Add Summary ⌥⌘], Add Callout ⌥⇧⌘↩ (MM-60..MM-66, [node-organization.md](node-organization.md) *Menus and shortcuts*) |
| Format (MM-32, MM-33, MM-37, MM-64) | Topic Color, Topic Symbol, Connection line, arrows and colour, Boundary Color, Image Size; tags, tasks, filter and Focus items in Topic and View are listed in [node-organization.md](node-organization.md) |
| AI (MM-8) | Generate Map…, Expand Topic, Brainstorm…, Rewrite ▸, Summarize, Find Missing Topics; disabled with a reason when AI is unavailable |
| Help | MindMap AI Help, Website, Privacy Policy |

### Keyboard

| Rule | Source |
| --- | --- |
| Do not repurpose standard shortcuts. Modifier order Control, Option, Shift, Command; prefer Command, avoid Control. | [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) |
| Standard: ⌘N, ⌘O, ⌘S, ⇧⌘S, ⌘W, ⌘A, ⌘F, ⌘G, ⌘, (Settings), ⌃⌘F (Full Screen), ⌥⌘= / ⌥⌘− (zoom). | same |

The MM-5 shortcut list (Return, Tab, ⇧Tab, Delete, ⌘Z, ⇧⌘Z, ⌘F, ⌘A, ⌘C, ⌘V, ⌘D, ⌘+, ⌘−, ⌘0) keeps the standard meanings. Return and Tab act on the selected topic only while no text field is editing, so typing a title never creates topics by accident *[Inference]*.

### Windows, Settings, full screen, pointer

| Rule | Source |
| --- | --- |
| Restore the previous state at relaunch: windows, positions, scroll and selection. macOS has no launch screen. | [Launching](https://developer.apple.com/design/human-interface-guidelines/launching) |
| No critical information or actions in a bottom bar. | [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) |
| Settings opens with ⌘, as a window with a fixed toolbar of panes that shows the active pane; the title follows the pane, the last pane reopens, and no settings button sits in a window toolbar. | [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) |
| Settings without Apply, OK or Cancel (changes apply at once): common Mac practice, not found on the HIG page (not verified). | — |
| Use the system's full screen (green button, View menu, ⌃⌘F); no custom window-mode menu; toolbars may hide in full screen. | [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen) |
| Standard pointers: open and closed hand for panning, crosshair for precise selection; keep custom pointers simple. | [Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices) |

## iPad

| Rule | Source |
| --- | --- |
| iPadOS 26 has a menu bar (pointer at the top edge, or swipe down). Every function is also reachable in the regular UI. Same items always, ordered by use, shortcuts on common actions. | [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [WWDC25 208](https://developer.apple.com/videos/play/wwdc2025/208/) |
| App ▸ Settings opens the app's page in the system Settings app; put the in-app settings item beneath it. | [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) |
| Windows resize freely and the system keeps size and position. Window controls sit at the leading edge of the toolbar, and toolbar items must not overlap them. One window per document with a descriptive name. | [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [WWDC25 208](https://developer.apple.com/videos/play/wwdc2025/208/) |
| The pointer is precise and does not snap; hover shows a glass highlight. Padding around controls about 12 pt (bezeled) or 24 pt (unbezeled). The pointer does not replace touch. | [Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices) |
| Leave button and switch keyboard navigation to Full Keyboard Access. | [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) |
| A hold-⌘ shortcut overlay on iPadOS 26: not verified (the page describes it for visionOS). | — |
| Apple Pencil draws on first contact without a mode switch; Pencil and finger both work. Double tap follows the system setting and is never destructive. Squeeze is one non-destructive action. Hover previews but never acts. Scribble works in standard text fields; do not move a field while someone writes in it. | [Apple Pencil and Scribble](https://developer.apple.com/design/human-interface-guidelines/apple-pencil-and-scribble) |

For MindMap AI: one window per map in Stage Manager and windowed mode; the canvas works in every width the split view collapses to; in the Pencil phase (MM-9) the Pencil draws and the finger pans, with no mode toggle needed for that split.

## iPhone

| Rule | Source |
| --- | --- |
| Lay out by size class, not device, and handle all four combinations. Respect safe areas; backgrounds run under bars. | [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) |
| Tab bars navigate, never act; keep them visible with no hidden or disabled tabs. On iOS they float in glass and can minimise while scrolling. `.sidebarAdaptable` on iPad. | [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) |
| Only essential toolbar items; large titles. | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) |

The iPhone is a companion (ADR 0006): library, outline editing, quick capture and viewing. The split view collapses into a stack; canvas editing on iPhone covers pan, zoom, select and rename *[Inference]*.

## Accessibility

| Rule | Source |
| --- | --- |
| Hit targets: iOS and iPadOS default 44×44 pt, minimum 28×28 pt; macOS default 28×28 pt, minimum 20×20 pt. The Buttons page asks for a 44×44 pt hit region on every platform but visionOS; the accessibility figures are the more specific ones for the Mac. | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) |
| Contrast at least 4.5:1 for text up to 17 pt, 3:1 for 18 pt or bold. | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) |
| Text: iOS default 17 pt, minimum 11 pt; macOS default 13 pt, minimum 10 pt. Text can grow to at least 200%. | same |
| Reduce Motion: replace movement with fades; no z-axis or blur animation. | same |
| Increase Contrast: a higher-contrast colour set. Support Full Keyboard Access and Voice Control. | same |
| VoiceOver: label every element, describe meaningful images, hide decorative ones, group and order elements, announce content and layout changes, support the rotor. | [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover) |

For MindMap AI:

- **Canvas (MM-3):** each node is an accessibility element with its title, level and child count ("Marketing, level 2, 3 subtopics"), and collapse, expand, add child and delete as accessibility actions. Edges are not separate elements; a node's cross-links are listed in its custom content *[Inference]*. A rotor for topics and cross-links.
- **Announcements:** posting a notification when AI suggestions arrive, a topic is added, or an undo restores a branch.
- **Dynamic Type:** iOS and iPadOS node text uses text styles; nodes grow with the text, and the layout engine takes sizes as input (MM-4). macOS does not support Dynamic Type ([Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
- **Colour:** node colours are never the only signal; selection also has an outline, AI suggestions also have a label.
- **Motion:** every animation goes through `Motion.standard(reduceMotion:)`, which already returns no animation under Reduce Motion.

## App icon

| Rule | Source |
| --- | --- |
| Build in Icon Composer: a background layer and one or more foreground layers. The system adds highlights, refraction, shadow and blur, so layers are flat. | [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) |
| Appearances: Default, Dark, Clear (light and dark), Tinted (light and dark). The system derives any not supplied. | same |
| Unmasked square layers on a 1024×1024 px canvas; the system applies the rounded-rectangle mask, so keep the artwork centred. No text, photos, UI copies or Apple hardware. | same |
| macOS 26: an icon outside the rounded rectangle has its shadow removed and is scaled into the rounded-rectangle canvas; Apple recommends redrawing. Whether legacy icons sit in a grey container: not verified. | [WWDC25 220](https://developer.apple.com/videos/play/wwdc2025/220/) |

## Type and SF Symbols

| Rule | Source |
| --- | --- |
| SF Pro and New York; avoid Ultralight, Thin and Light. Built-in text styles; macOS body is 13 pt. | [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) |
| Rendering modes: monochrome, hierarchical, palette, multicolor. Outline symbols in toolbars and lists, filled in iOS tab bars, slash for unavailable. Variable colour for change, not depth. Use symbol effects (Draw On/Off in SF Symbols 7) with restraint. Custom symbols need accessibility labels. | [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) |

The app uses the system font through `Typography`, and SF Symbols for every control. AI actions use one symbol family consistently (for example `sparkles`) so people learn where AI is.

## Launch, onboarding, empty and loading states

| Rule | Source |
| --- | --- |
| iOS launch screen matches the first screen, without text or branding. | [Launching](https://developer.apple.com/design/human-interface-guidelines/launching) |
| Teach by doing; prefer tips in context; tutorials optional and never shown again once skipped. Ask for a permission when a feature first needs it. | [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) |
| Show something at once; determinate progress when the duration is known; let people keep working while things load. | [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) |
| `ContentUnavailableView` with a label, a description and an action; `.search` for no results. | [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview) |
| Empty states say what to do next and offer the button. | [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) |

For MindMap AI: the first launch opens a sample map rather than three screens of explanation; the MM-12 onboarding is short, skippable and shown once. The empty library offers "New Mind Map" as a button, not only text. Microphone and speech permission are asked when someone first taps dictation (MM-8), photos when someone first imports one (MM-11).

## Writing

| Rule | Source |
| --- | --- |
| Pick title case or sentence case per kind of element and keep to it. | [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) |
| Buttons are verbs ("Add Topic", not "Let's go"). No "Click here". | same |
| Errors appear near the problem, never blame, and say how to fix it. No "Oops". Avoid "we" and needless "my" or "your". | same |
| A flow starts with "Get Started" and ends with "Done". | same |
| Buttons and menu items use title-style capitalisation; on macOS, "…" when the button opens another view for more input. | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) |
| A per-platform capitalisation table: not found (not verified). | — |

House style for the app:

- **Title case** for buttons, menu items, window and section titles, tab names. **Sentence case** for descriptions, footers, alerts' messages and tips.
- **One name per thing.** "Topic" for a node everywhere in the UI ("Add Child Topic" in the menu and the toolbar, not "Add Child" in one place), "map" for a mind map, "central topic" for the root.
- **Vietnamese** follows the same structure with sentence case throughout, as Vietnamese UI usually does *[Inference]*; "chủ đề" for topic, "sơ đồ" for map. Decide the glossary once in `Localizable.xcstrings` comments.

Glossary (one name per thing, en / vi). Names approved by the product owner are marked; the others are [Đề xuất] from MM-58 until a translator or the product owner confirms them:

| Thing | English | Vietnamese | Note |
| --- | --- | --- | --- |
| A node | Topic | chủ đề | |
| A mind map | Map | sơ đồ | |
| The root | Central Topic | chủ đề trung tâm | |
| A URL on a topic | Link | liên kết | Approved 2026-10-02. "Add Link…" / "Thêm liên kết…" ⌘K |
| A cross-link between two topics | Connection | kết nối | Approved 2026-10-02. "Add Connection…" / "Thêm kết nối…" ⌘L. Code keeps `MindEdge` and "cross-link" |
| A topic with no parent | Floating Topic | chủ đề tự do | |
| A picture on a topic | Image | ảnh | |
| A bracket over siblings and its topic | Summary | tổng hợp | Not "tóm tắt", which the AI Summarize commands use. The string catalog already has the key "Summary" = "Tóm tắt" (title of the AI summary sheet, `AISheets.swift`); MM-65 renames that title to "Branch Summary" / "Tóm tắt nhánh" so the key "Summary" can mean this one thing |
| A note bubble above a topic | Callout | chú thích | Not "ghi chú", which is the topic's Note |
| A frame around siblings | Boundary | khung | |
| Category text on topics | Tag | thẻ | As built in MM-34; check the string catalog |
- Errors use the categories in [architecture](architecture.md#error-handling): what happened, then what to do.

## AI-generated content

| Rule | Source |
| --- | --- |
| Say where the app uses AI and what it can and cannot do. | [Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai) |
| Keep people in control; the app works well without AI or when they opt out. | same |
| Prefer a private model (on-device keeps data local and works offline); ask before using personal data and say how it is stored. | same |
| Reduce and flag the chance of hallucination; ask before anything irreversible. | same |
| Make refining and reverting easy, and acknowledge corrections. | same |
| When a request is blocked or the result is poor, help people improve the request. | same |
| Plan for processing time with specific feedback; consider offering alternatives. | same |
| Let people give feedback on outputs (for example thumbs up or down). | same |
| Avoid reproducing copyrighted content. | same |

How MindMap AI applies it, with the [AI architecture](ai-architecture.md):

1. **Proposal, then command.** Suggested topics stream into a preview, drawn as nodes with a dashed outline and an AI badge. Nothing changes the map until Accept; Accept is one command with one undo step ("Undo Add AI Topics").
2. **Edit before accepting.** People can rename, remove or keep part of the suggestions; Discard leaves the map as it was.
3. **Clear availability.** Follow the availability table in [on-device AI](on-device-ai.md#behaviour-by-availability): hidden on ineligible devices, one line on how to turn on Apple Intelligence, "Getting ready" while the model downloads.
4. **Errors with a way forward.** A guardrail refusal says the request could not be completed and suggests rewording; a context-size error suggests choosing a smaller branch. No retry loops that try to get around the guardrails ([App Store readiness](app-store-readiness.md#foundation-models-acceptable-use)).
5. **Say where it runs.** The AI row in Settings ▸ Privacy and the first AI sheet say processing happens on this device and nothing is sent to xDev.
6. **Remember the source.** *[Inference]* Accepted AI topics keep an "AI suggested" marker until edited, so people can tell their own text from generated text. This needs a data model field in a later schema version.
7. **Feedback stays local.** Thumbs up or down only change what the app shows next; nothing is sent, since there is no backend ([privacy](privacy.md)).

## Checked against the project

As of commit `1e18d58`; rows marked MM-0i were updated by that task.

| Area | State | Where |
| --- | --- | --- |
| Split view | Sidebar ▸ library ▸ editor in `NavigationSplitView`; collapses on iPhone | `MindMapAI/App/RootView.swift` |
| Empty states | `ContentUnavailableView` everywhere; the empty library has the `BrandMark` lockup and a New Mind Map button, an empty map has Add Central Topic on the canvas and in the outline, the startup failure screen has the small `BrandMark` and Contact Support (MM-0i) | `LibraryView.swift`, `CanvasView.swift`, `OutlineEditorView.swift`, `RootView.swift` |
| New map and window | ⌘N New Mind Map, ⌥⌘N New Window | `MindMapAI/App/AppCommands.swift` |
| Topic menu | Add Sibling (Return), Add Child (⇧⌘Return), Collapse/Expand, Delete; items disabled, not hidden | `AppCommands.swift` |
| Delete shortcut | Delete Topic answers the bare Delete key only while the canvas or the outline list has focus and no title is being typed (`EditorSession.deleteKeyDeletesTopic`, reported by `CanvasModel` and `OutlineEditorView`), and no AI suggestion is selected and no AI sheet is open (`AIAssistant.holdsDeleteKey`); otherwise the shortcut is removed so text fields and the library keep Delete, and the editor's `onDeleteCommand` discards a selected suggestion (MM-0i) | `AppCommands.swift`, `EditorSession.swift`, `MapEditorView.swift` |
| Undo | Window `UndoManager` with action names (MM-0c); also toolbar Undo/Redo buttons | `MindMapAI/Features/Editor/OutlineEditorView.swift` |
| View menu | `SidebarCommands()` adds View ▸ Show/Hide Sidebar with ⌃⌘S (MM-0i), next to `InspectorCommands()` | `MindMapAI/App/MindMapAIApp.swift` |
| Help menu | Website only; no privacy policy or help page | `AppCommands.swift` |
| Settings | Mac: `Settings` scene, one tab per pane (General, Export, AI, Pro, Privacy, About), last pane reopens, applies at once, fixed 480 pt width. iPad and iPhone: sheet from a sidebar toolbar button, a list with one page per pane; iPad App menu ▸ MindMap AI Settings… ([[settings]]). | `MindMapAI/Features/Settings/SettingsView.swift`, `MindMapAI/Features/Library/SidebarView.swift` |
| Window title | The editor's `navigationTitle` is the map's title ("Untitled Map" when empty); the sidebar has no title on the Mac, so the app name never becomes the window title (MM-0i) | `MapEditorView.swift`, `SidebarView.swift` |
| Toolbar labels | Toolbar and Topic menu both say "Add Child Topic", "Add Sibling Topic", "Delete Topic" (MM-0i) | `MapEditorView.swift` |
| Hit targets | `Metrics.minimumHitTarget` 44 pt on iOS, 24 pt on macOS (inside HIG's 20–28 pt) | `MindMapAI/DesignSystem/Layout/Spacing.swift` |
| Reduce Motion | `Motion.standard(reduceMotion:)` returns no animation | `MindMapAI/DesignSystem/Motion/Motion.swift` |
| VoiceOver | Outline rows labelled "Central Topic" / "Topic, level n"; disclosure labelled and hidden when empty | `OutlineEditorView.swift` |
| App icon | Icon Composer `.icon`: background fill `#F7F9FC` (navy 850 `#142745` in dark), one glass group with the X (brand gradient) and the three navy branches (`#E8ECF8` in dark) as flat SVG layers; clear and tinted derived by the system (MM-0j). `swift scripts/render-app-icon.swift` renders every appearance to `docs/brand/mindmap-ai-app-icon-appearances.png` | `MindMapAI/AppIcon.icon` |
| Increase Contrast colours | No colour set has a high-contrast variant | `Assets.xcassets/*.colorset` |

## Do now

Small gaps worth closing before the canvas work builds on them. Items 2–5 and 7 are done in MM-0i, item 6 in MM-0k, item 1 in MM-0j.

1. **Icon Composer icon** from the MM-0g artwork: background layer `#F7F9FC`, X and branches as foreground layers, with dark and tinted checked.
2. **View menu:** add `SidebarCommands()` (and later toolbar and inspector commands) so Show/Hide Sidebar is in the View menu with ⌃⌘S.
3. **Delete shortcut** on Delete Topic (`.delete`), active only while no text field is editing.
4. **One name per action:** make toolbar labels match menu items ("Add Child Topic"), and set the editor window title to the map's title.
5. **Empty state actions:** "New Mind Map" button in the library's empty state and "Add Central Topic" in an empty map (already in the editor).
6. **Increase Contrast variants** for `AccentColor`, `Favorite`, `WarningFill` and `WarningText`, and a contrast check of each against its background (4.5:1).
7. **Glossary:** a comment in `Localizable.xcstrings` fixing "topic / chủ đề" and "map / sơ đồ".

## Proposed tasks

| Proposed | Scope |
| --- | --- |
| MM-0i | HIG polish of the shell: items 2–7 above, with app tests for the menu commands' enabled state |
| MM-0j | Icon Composer `.icon` with default, dark, clear and tinted appearances; replace the PNG asset catalog entry |
| MM-12 (add to note) | Accessibility audit covering VoiceOver, Voice Control, Full Keyboard Access, Increase Contrast and Reduce Transparency, feeding the Accessibility Nutrition Labels |
