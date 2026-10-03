# Product

**MindMap AI by xDev**: AI-native visual thinking for Mac, iPad and iPhone. Short name *MindMap AI*, tagline *Think. Draw. Connect.*, bundle ID `asia.xdev.mindmapai`, website <https://xdev.asia/mindmap>.

## Promise

Users spend time thinking, not formatting diagrams. Any input (typing, Apple Pencil, voice, paste, share, import) becomes a structured, editable map:

```
Thought → Input → Semantic understanding → Nodes and relationships → Graph → AI reasoning → Editable visual structure
```

AI is not a chatbot bolted onto a diagram tool. It works on the selected part of the graph and proposes changes the user accepts or rejects. The map stays useful without AI.

## Principles

1. **Native first.** Swift and SwiftUI. UIKit only where SwiftUI falls short, behind a small wrapper. No cross-platform UI frameworks, no web view as the app.
2. **Mac first, then iPad and iPhone.** One SwiftUI multiplatform app. The Mac is built and run first (ADR 0006); the iPad follows as the touch and Apple Pencil platform; the iPhone is a first-class companion for capture, voice, review, light editing and AI commands, with its own layouts rather than a shrunken Mac or iPad.
3. **Local first.** Every map works offline. Network, iCloud and AI being unavailable never blocks editing.
4. **Backendless.** No xDev server, API, database or account in V1. A backend needs a written case (see ADR 0001).
5. **Firebase optional.** If ever added (crash reports, analytics, remote config), it sits behind a protocol and the app runs without it.
6. **Privacy first.** Maps may hold personal or confidential data. Prefer on-device processing, never log or collect map content, and say where AI runs.

## Platforms

macOS (developed first), iPadOS and iOS, all from version 26. The first release, 1.0.0, ships on all three together; the product owner decided this on 2026-10-03, replacing the earlier Mac-only plan. The Mac app runs on Apple silicon and on Intel Macs that run macOS 26; on-device AI needs Apple silicon, so it is hidden on Intel. Windows, keyboard, trackpad and mouse on the Mac; portrait and landscape, Split View, Stage Manager, Apple Pencil and touch on iPad; light and dark mode, Dynamic Type and VoiceOver everywhere.

Two free companions follow the 1.0 release (product owner, 2026-10-03; ADR 0012): an **App Clip** on iPhone and iPad that opens a map from a link and makes a quick map with on-device AI ([app-clip](app-clip.md)), and an **Apple Watch app** (watchOS 26) that captures ideas into an Inbox map and shows recent maps read-only, through iCloud ([watch](watch.md)). Map links carry the map in the URL fragment, so no server stores maps (ADR 0001).

## MVP scope

| Area | Items |
| --- | --- |
| Maps | Create, rename, delete; All, Recent, Favorites; search; Recently Deleted for 30 days |
| Nodes | Root, child, sibling, edit, delete, reparent, collapse and expand |
| Canvas | Auto layout, pan, zoom, undo and redo |
| Data | SwiftData persistence, iCloud sync |
| Files | Markdown import and export, PNG and PDF export |
| Input | Basic Apple Pencil interaction, Share Extension foundation |
| AI | Generate map, expand node, brainstorm, rewrite, summarize |
| Voice | Dictate topics in Vietnamese or English, on the device |
| Quality | Dark mode, English, Vietnamese |

## Not in the MVP

Real-time collaboration, team workspaces, any custom backend, Firebase authentication, comments, chat, project management or Gantt charts, a presentation engine, web, Android or Windows apps, a marketplace or plugins, public cloud sharing.

## AI behaviour

- AI acts on context the user chose: the selected node, its ancestors, a bounded set of descendants and relationships, the map title and the request. Large maps are summarized in stages, never sent whole.
- Output is structured (Foundation Models guided generation), turned into graph commands, validated, previewed, and applied only when the user accepts.
- Suggested nodes look different from permanent ones, calmly, never like errors.
- Suggestions are phrased as possibilities ("Possible missing topics"), never as corrections.
- Where Apple Intelligence is unavailable, AI entry points are hidden or disabled with a short explanation; everything else works.

## Monetization

Free app with a one-time Pro unlock at USD 14.99 (non-consumable, StoreKit 2, one purchase for every platform), decided on 2026-10-02. Pro covers advanced export, themes beyond Standard, advanced AI and voice input; core mind mapping is never crippled and there are no ads. Details and the market check are in [pricing.md](pricing.md).

## Positioning

App Store name *MindMap AI by xDev* (Mac App Store and App Store), subtitle *Think, Draw & Brainstorm*. Keywords: AI mind map, visual thinking, brainstorm, Apple Pencil, iPad, notes, ideas, privacy, on-device AI. The product carries xDev subtly ("by xDev") and has its own identity; it must not look like XMind, MindNode, Freeform or Miro.
