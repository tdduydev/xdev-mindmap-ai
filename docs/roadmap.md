# Roadmap

Each bold ID is a task on xDev Hive (project `xdev-mindmap-ai-ios`) whose note holds the acceptance criteria. Status lives on the task; this file says what each phase covers and in what order. A phase starts only when the one it builds on is stable.

## 0. Foundation (Milestone 0)

- **MM-0a** Core package: domain types, `GraphState`, `GraphCommand`, Add, Update, Delete and Reparent commands, `GraphValidator` (cycles refused), `GraphRepair`, `GraphEngine` with undo and redo, Swift Testing coverage.
- **MM-0b** SwiftData persistence: schema V1 (CloudKit-ready, sync off), migration plan, `MapRepository` and its SwiftData actor, tests for create, save, reopen from disk and migration.
- **MM-0c** App shell: Xcode project `MindMapAI` (`asia.xdev.mindmapai`, iOS 26), design system foundation, Library screen with empty state, minimal outline editor on the graph engine, English and Vietnamese strings, `scripts/ci.sh`.
- **MM-0d** Documentation: README, architecture, data model, graph engine, privacy, ADRs 0001 to 0005, this roadmap, mirrored to Hive.

No Foundation Models, CloudKit, Firebase or final canvas in this phase.

## 1. Graph engine

- **MM-1** Remaining commands: duplicate branch, merge nodes, split node, promote and demote, connect and remove relationship, collapse and expand all. Bridge history to the native `UndoManager` (menu titles, shake and keyboard undo). Tests for each command and its undo.

## 2. Persistence

- **MM-2** Migration harness with a stored V1 fixture, load and save timing for 1,000 and 10,000 node maps, a change stream from the repository so the library updates without polling.

## 3. Basic canvas

- **MM-3** Map editor on an infinite canvas: node rendering, pan, zoom, pinch, select, inline editing, add and delete nodes, viewport culling, VoiceOver elements for nodes. The outline editor stays as the accessible alternative.

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

- **MM-9** Structured mode (tap, select, drag, create) and sketch mode with PencilKit, drawings stored apart from nodes, ready for handwriting recognition later.

## 10. Import and export

- **MM-10** Plain text and Markdown import (indented lists, headings), Markdown and plain text export (notes optional), PNG and high-resolution PDF export (fit to page, pagination), all on-device.

## 11. Share and system integration

- **MM-11** Share Extension (text, URLs, images, PDFs: add to a map or create one), App Intents and Shortcuts (new map, map from clipboard, add idea, open recent), Spotlight for map titles.

## 12. Polish

- **MM-12** Onboarding (three screens) and sample map, settings, motion with Reduce Motion, accessibility audit, large-map performance with Instruments, error messages, localization review, App Store assets and privacy labels.
