# MindMap AI by xDev

AI-native mind mapping for Mac, iPad and iPhone.

**Think. Draw. Connect.**

MindMap AI turns typed, drawn, spoken and pasted thoughts into structured, editable mind maps. The map is a semantic graph that AI can reason about, not a picture with a chatbot next to it. The user stays in control: AI proposes, the user accepts.

## Features

The current milestone is the foundation (Milestone 0). Planned for the MVP:

- Create, rename and delete maps; Recent and Favorites.
- Add, edit, delete, move and reparent nodes; collapse and expand branches; undo and redo everything.
- Automatic layout, pan and zoom on an infinite canvas, keyboard shortcuts on iPad.
- Local-first storage with iCloud sync between the user's own devices. No account.
- On-device AI where the device supports it: generate a map, expand a node, brainstorm, rewrite, summarize, find missing ideas.
- Markdown import and export, PNG and PDF export, Apple Pencil, Share Extension.
- English and Vietnamese, light and dark mode, VoiceOver and Dynamic Type.

See [docs/product.md](docs/product.md) for scope and [docs/roadmap.md](docs/roadmap.md) for phases.

## Architecture

Native Swift and SwiftUI. No backend: data lives in SwiftData on the device and syncs through the user's iCloud.

```
SwiftUI features ─▶ GraphEngine (commands, validation, undo) ─▶ MapRepository ─▶ SwiftData ─▶ CloudKit (later)
```

The graph, its commands and its persistence live in a local Swift package (`Packages/MindMapCore`) that has no UI dependency and is tested on its own. See [docs/architecture.md](docs/architecture.md).

## Requirements

- Xcode 26 or later
- macOS 26 or later to run the Mac app (built first, see ADR 0006); iOS and iPadOS 26 or later
- A Mac on Apple silicon

No third-party dependencies, no secrets, no server.

## Getting Started

```bash
git clone git@github.com:tdduydev/xdev-mindmap-ai-ios.git
cd xdev-mindmap-ai-ios
open MindMapAI.xcodeproj
```

Run the `MindMapAI` scheme on **My Mac**; the same target also runs on iPad and iPhone simulators. To sign for a device or distribution, choose your team under Signing & Capabilities.

Run every local check (core tests, app tests on macOS, then an iOS Simulator build):

```bash
scripts/ci.sh
```

The core package alone:

```bash
swift test --package-path Packages/MindMapCore
```

## Project Structure

```
MindMapAI/                 Multiplatform app target (macOS, iPadOS, iOS): shell, features, design system, resources
  App/                     Entry point, dependencies, navigation
  Features/                Library, Editor (one folder per feature)
  DesignSystem/            Colors, typography, spacing, motion
MindMapAITests/            App-level tests, hosted on macOS
Packages/MindMapCore/      Swift package, no UI
  MindMapDomain            Value types: MindMap, MindNode, MindEdge
  MindMapGraph             GraphState, commands, validation, repair, undo
  MindMapPersistence       SwiftData schema, migrations, repository
docs/                      Architecture, data model, decisions (adr/), roadmap
scripts/ci.sh              The local check every change must pass
```

## Privacy

Maps stay on the user's devices and in their own iCloud. There is no xDev server, no xDev account, and no analytics on map content. AI runs on-device where supported. See [docs/privacy.md](docs/privacy.md).

## Roadmap

Development runs in phases, from the graph engine through canvas, sync, AI, Pencil, import and export, to polish. Each item is a task on xDev Hive (project `xdev-mindmap-ai-ios`). See [docs/roadmap.md](docs/roadmap.md).

## Contributing

- Trunk-based: short branches off `main` (`feature/*`, `fix/*`, `refactor/*`, `chore/*`; agent work uses `ai/<task-id>`).
- [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- Run `scripts/ci.sh` before merging. There is no hosted CI.
- Structural decisions get an ADR in `docs/adr/`.

## License

Copyright © 2026 xDev. All rights reserved.
