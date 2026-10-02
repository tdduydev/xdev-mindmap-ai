# ADR 0006: macOS first, one multiplatform target

- Status: accepted
- Date: 2026-10-02
- Changes: the "Mac is out of scope" line of the original brief, and the build order of ADR 0001's "iPad first"

## Context

The original brief made iPadOS the primary platform and left the Mac out. On 2026-10-02 the product owner asked to develop the macOS app first. Building and running natively on the development Mac is also the fastest loop: no simulator, real keyboard, trackpad and windows.

## Decision

- The app is one SwiftUI multiplatform target, `MindMapAI`, for macOS, iPadOS and iOS. Its product is `MindMap AI.app` with the bundle ID `asia.xdev.mindmapai` on every platform, so a later universal purchase stays possible.
- macOS is built, run and tested first. Every change must still compile for the iOS Simulator (`scripts/ci.sh` checks both).
- macOS runs natively with the App Sandbox and the hardened runtime, not through Mac Catalyst or "Designed for iPad".
- Platform differences stay small and local: `#if os(macOS)` / `#if os(iOS)` inside a view for a modifier or two, and separate files only when a whole view differs. Shared logic never branches on platform.
- On macOS, undo and redo go through the window's `UndoManager`, so the Edit menu and ⌘Z drive the graph engine's history.

## Consequences

- Phase order shifts toward the Mac: canvas interaction is designed for trackpad, mouse and keyboard first, then adapted for touch.
- Apple Pencil (Phase 9) stays iPad-only.
- The Share Extension and App Intents (Phase 11) target both macOS and iOS.
- Foundation Models runs on Apple silicon Macs with Apple Intelligence, so on-device AI is available on the first platform too.
- The iPhone remains a companion, with its own compact layouts rather than a scaled-down Mac or iPad UI.
