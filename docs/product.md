# Product

**MindMap AI by xDev**: AI-native visual thinking for iPhone and iPad. Short name *MindMap AI*, tagline *Think. Draw. Connect.*, bundle ID `asia.xdev.mindmapai`, website <https://xdev.asia/mindmap>.

## Promise

Users spend time thinking, not formatting diagrams. Any input (typing, Apple Pencil, voice, paste, share, import) becomes a structured, editable map:

```
Thought → Input → Semantic understanding → Nodes and relationships → Graph → AI reasoning → Editable visual structure
```

AI is not a chatbot bolted onto a diagram tool. It works on the selected part of the graph and proposes changes the user accepts or rejects. The map stays useful without AI.

## Principles

1. **Native first.** Swift and SwiftUI. UIKit only where SwiftUI falls short, behind a small wrapper. No cross-platform UI frameworks, no web view as the app.
2. **iPad first.** The iPad is where maps are made. The iPhone is a first-class companion for capture, voice, review, light editing and AI commands, with its own layouts rather than a shrunken iPad.
3. **Local first.** Every map works offline. Network, iCloud and AI being unavailable never blocks editing.
4. **Backendless.** No xDev server, API, database or account in V1. A backend needs a written case (see ADR 0001).
5. **Firebase optional.** If ever added (crash reports, analytics, remote config), it sits behind a protocol and the app runs without it.
6. **Privacy first.** Maps may hold personal or confidential data. Prefer on-device processing, never log or collect map content, and say where AI runs.

## Platforms

iPadOS (primary) and iOS, from version 26. Portrait and landscape, Split View, Stage Manager, keyboard, trackpad, mouse, Apple Pencil and touch, light and dark mode, Dynamic Type, VoiceOver. Mac is out of scope.

## MVP scope

| Area | Items |
| --- | --- |
| Maps | Create, rename, delete; All, Recent, Favorites; search |
| Nodes | Root, child, sibling, edit, delete, reparent, collapse and expand |
| Canvas | Auto layout, pan, zoom, undo and redo |
| Data | SwiftData persistence, iCloud sync |
| Files | Markdown import and export, PNG and PDF export |
| Input | Basic Apple Pencil interaction, Share Extension foundation |
| AI | Generate map, expand node, brainstorm, rewrite, summarize |
| Quality | Dark mode, English, Vietnamese |

## Not in the MVP

Real-time collaboration, team workspaces, any custom backend, Firebase authentication, comments, chat, project management or Gantt charts, a presentation engine, web, Android, Windows or macOS apps, a marketplace or plugins, public cloud sharing.

## AI behaviour

- AI acts on context the user chose: the selected node, its ancestors, a bounded set of descendants and relationships, the map title and the request. Large maps are summarized in stages, never sent whole.
- Output is structured (Foundation Models guided generation), turned into graph commands, validated, previewed, and applied only when the user accepts.
- Suggested nodes look different from permanent ones, calmly, never like errors.
- Suggestions are phrased as possibilities ("Possible missing topics"), never as corrections.
- Where Apple Intelligence is unavailable, AI entry points are hidden or disabled with a short explanation; everything else works.

## Monetization (later)

StoreKit 2 when the time comes. Core mind mapping is never crippled and there are no ads. Possible Pro features: PDF to map, advanced export and themes, version history, advanced AI workflows.

## Positioning

App Store name *MindMap AI by xDev*, subtitle *Think, Draw & Brainstorm*. Keywords: AI mind map, visual thinking, brainstorm, Apple Pencil, iPad, notes, ideas, privacy, on-device AI. The product carries xDev subtly ("by xDev") and has its own identity; it must not look like XMind, MindNode, Freeform or Miro.
