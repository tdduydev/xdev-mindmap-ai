# ADR 0002: Core logic in a local Swift package

- Status: accepted
- Date: 2026-10-02

## Context

The graph engine must stay independent of SwiftUI, SwiftData, CloudKit, AI and screen coordinates. Folder conventions alone do not enforce that, and testing core logic through an iOS Simulator is slow. The Share Extension and App Intents will need the domain and persistence code without the app's UI.

## Decision

Domain, graph and persistence code live in `Packages/MindMapCore`, a local Swift package with one library per layer: `MindMapDomain`, `MindMapGraph`, `MindMapPersistence`. Each module declares its dependencies, so the compiler rejects an import that breaks the layering. The app target holds the shell, features, design system and resources.

The package lists macOS 26 next to iOS 26 only so `swift test` can run the core tests on the Mac host in seconds. There is no Mac product.

Later layers (layout, AI, import, export) become further modules of the same package.

## Consequences

- Core tests run without a simulator; `scripts/ci.sh` runs them first.
- Extensions link only the modules they need.
- The folder layout differs from a single-target project: `Core/` folders live in the package rather than under `MindMapAI/`.
- APIs between modules must be `public`, which makes the surface of each layer explicit.
