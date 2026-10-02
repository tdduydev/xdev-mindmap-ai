# Roadmap

Each bold ID is a task on xDev Hive (project `xdev-mindmap-ai-ios`) whose note holds the acceptance criteria. Status lives on the task; this file says what each phase covers and in what order. A phase starts only when the one it builds on is stable.

The detailed requirements (FR and NFR IDs, acceptance scenarios, open questions) live in the SRS on Hive (`project/xdev-mindmap-ai-ios/srs`, Vietnamese); task notes cite its IDs. Phase numbers give the reading order, not a strict sequence: the task dependencies on Hive decide what can run in parallel. Since 2026-10-02 the layout engine (MM-4), the AI foundation (MM-7) and the Markdown/text interchange (MM-10a) depend only on the core package, so they run beside MM-1, and the canvas (MM-3) waits for the layout engine.

## 0. Foundation (Milestone 0)

- **MM-0a** Core package: domain types, `GraphState`, `GraphCommand`, Add, Update, Delete and Reparent commands, `GraphValidator` (cycles refused), `GraphRepair`, `GraphEngine` with undo and redo, Swift Testing coverage.
- **MM-0b** SwiftData persistence: schema V1 (CloudKit-ready, sync off), migration plan, `MapRepository` and its SwiftData actor, tests for create, save, reopen from disk and migration.
- **MM-0c** App shell: multiplatform Xcode project `MindMapAI` (`asia.xdev.mindmapai`, version 26), run on macOS first, design system foundation, Library screen with empty state, minimal outline editor on the graph engine with the Edit menu's undo, English and Vietnamese strings, app tests on macOS, `scripts/ci.sh`.
- **MM-0d** Documentation: README, architecture, data model, graph engine, privacy, ADRs 0001 to 0006, this roadmap, mirrored to Hive.
- **MM-0e** Research: on-device AI, module structure, design guidelines, App Store readiness.
- **MM-0f** Menu commands, Settings, privacy manifest, export compliance key.
- **MM-0g** App icon and wordmark in the xDev brand.
- **MM-0h** Privacy policy and support pages (en, vi), linked from Settings, Help and the startup failure screen.
- **MM-0i** Shell polish from the design guidelines: View menu sidebar command, Delete shortcut, one name per action, window title, empty state action, Increase Contrast colours, glossary.
- **MM-0j** Icon Composer icon with default, dark, clear and tinted appearances.
- **MM-0k** Design system v1 in code ([design-system.md](design-system.md), ADR 0007): colour tokens with Increase Contrast variants, branch palette and themes, bundled brand fonts, canvas metrics, `TopicStyle`, motion, a debug gallery and contrast tests.

No Foundation Models, CloudKit, Firebase or final canvas in this phase.

## 1. Graph engine

- **MM-1** Remaining commands: duplicate branch, merge nodes, split node, promote and demote, connect and remove relationship, collapse and expand all. Rename the map as a command, so it is undoable and cannot race the editor. Every new command gets an undo action name for the Edit menu (the `UndoManager` bridge exists since MM-0c). Tests for each command and its undo.

## 2. Persistence

- **MM-2** Migration harness with a stored V1 fixture, load and save timing for 1,000 and 10,000 node maps, a change stream from the repository so the library updates without polling.

## 3. Basic canvas

- **MM-3** Map editor on an infinite canvas, trackpad and mouse first: node rendering, pan, zoom, pinch, select, inline editing, add and delete nodes, viewport culling, VoiceOver elements for nodes. The outline editor stays as the accessible alternative. Builds on the layout engine (MM-4) and the design system (MM-0k), which are done first.

## 4. Layout engine

- **MM-4** `MindMapLayoutEngine` protocol and `HorizontalTreeLayout`: node sizes in, frames and edge paths out, collapse and expand, partial updates for a changed branch, deterministic results, tests without UI.

## 5. Advanced interaction

- **MM-5** Drag to reorder and reparent with clear drop targets, multi-select, keyboard shortcuts (Return, Tab, Shift-Tab, Delete, ⌘Z, ⌘⇧Z, ⌘F, ⌘A, ⌘C, ⌘V, ⌘D, ⌘+, ⌘−, ⌘0) with discoverability, context menus, copy and paste of branches as Markdown.

## 6. iCloud

- **MM-6** CloudKit private database sync, quiet sync status, signed-out and offline behaviour, conflict tests on two devices, undo history policy for remote changes.

## 7. AI foundation

- **MM-7** `AIProvider`, `AppleFoundationModelProvider`, availability detection, context builder, structured result types, proposal translator to commands, mock provider and tests. No UI coupling.

## 8. AI actions

- **MM-8** Generate map, expand node, brainstorm, rewrite (shorter, clearer, formal, simpler, technical, Vietnamese, English), summarize (to note on request), find missing ideas, with suggested-node preview and accept or reject.

## 9. Apple Pencil

- **MM-9** iPad only. Structured mode (tap, select, drag, create) and sketch mode with PencilKit, drawings stored apart from nodes, ready for handwriting recognition later.

## 10. Import and export

- **MM-10a** `MindMapInterchange` package: plain text and Markdown import (indented lists, headings) and export (notes optional), as graph commands, without UI.
- **MM-10** File ▸ Import and Export in the app, PNG and high-resolution PDF export (fit to page, pagination), all on-device.

## 11. Share and system integration

- **MM-11** Share Extension on macOS and iOS (text, URLs, images, PDFs: add to a map or create one), App Intents and Shortcuts (new map, map from clipboard, add idea, open recent), Spotlight for map titles.

## 12. Polish

- **MM-12** Onboarding (three screens) and sample map, settings, motion with Reduce Motion, accessibility audit, large-map performance with Instruments, error messages, localization review, App Store assets and privacy labels.

## 13. Purchases

- **MM-13** StoreKit 2 for a free app with a one-time Pro unlock: entitlement check, Restore Purchases in Settings, a paywall that states price and terms. The price and the Pro feature list are still to be decided.

## 14. Release

- **MM-14** App Store submission kit for the Mac-only first release: metadata in English and Vietnamese, screenshots, Review Notes on AI availability, privacy and accessibility labels, age rating, TestFlight builds as 0.x, 1.0.0 for the public release.

## UI tests

UI tests (XCUITest) run on macOS and the iOS Simulator through `scripts/ui-tests.sh`; `scripts/ci.sh` stays fast and does not run them. A feature with new UI ships with its UI tests once MM-22 is in.

- **MM-22** Foundation: the `MindMapAIUITests` target, a `-uitest` launch mode (in-memory store, no animation, fixed locale, no onboarding), fixture maps, one accessibility identifier convention, page objects, `scripts/ui-tests.sh`, `docs/testing.md`.
- **MM-23** Library, outline editor, menus and shortcuts, Settings, search, in English and Vietnamese.
- **MM-24** Canvas: selection, inline editing, zoom and pan, drag to reparent, multi-select, copy and paste, a 1,000-topic map.
- **MM-25** AI flows with the mock provider, including partial accept, discard, undo and the unavailable states.
- **MM-26** Import and export, Recently Deleted, voice input with a fake transcriber.
- **MM-27** Pro purchase and Restore Purchases with StoreKitTest.
- **MM-28** Automated accessibility audits, Dynamic Type, Increase Contrast and Vietnamese.
- **MM-29** App Store screenshots taken by a UI test, in English and Vietnamese, light and dark.

## Cross-cutting

These run beside the phases above once their dependency is done.

- **MM-15** Search: maps by title and topic text in the library, Find in the open map, diacritic-insensitive for Vietnamese.
- **MM-16** Topic inspector: notes and details, toggled from the toolbar and the View menu.
- **MM-17** Multiple windows: one session per map shared by its windows, one window per map on iPad, state restoration at relaunch.
- **MM-18** Map themes: Standard, xDev Blue and Graphite branch palettes, chosen per map as an undoable command.
- **MM-19** Recently Deleted: deleted maps kept for 30 days and restorable, with schema V2 and its migration test.
- **MM-20** Voice input: dictate topics in Vietnamese (`DictationTranscriber`) or English (`SpeechTranscriber`), on the device.
- **MM-21** Intel Mac support: universal build for macOS 26, AI hidden on Intel, checked under Rosetta or on an Intel Mac.
