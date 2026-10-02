# ADR 0001: Native, local-first, backendless iOS app

- Status: accepted
- Date: 2026-10-02

## Context

MindMap AI holds private thinking: personal notes, research, company plans. It must work offline, launch fast, feel native on iPad and iPhone, and cost xDev nothing to run per user. These product decisions were approved before development started.

## Decision

1. **Native Swift and SwiftUI.** UIKit only behind small wrappers where SwiftUI is not enough. No Flutter, React Native, Electron, Capacitor or web view as the app.
2. **iPad first**, with an iPhone companion designed for capture and review.
3. **No backend in V1.** No API, server database, account service or sync server.
4. **SwiftData** for local persistence.
5. **CloudKit through the user's iCloud** for sync between their devices.
6. **No user account.** iCloud identity is enough.
7. **Apple Foundation Models** as the first AI provider, on-device.
8. **Firebase optional.** If added later, behind protocols with no-op defaults; maps, sync and sign-in never depend on it.

## Consequences

- Basic mind mapping works with no network, no iCloud and no AI.
- No server costs and no operational burden; no server-side breach surface for user content.
- Features that need a server (public sharing links, real-time collaboration, cross-platform clients) are out of scope until a concrete requirement exists.
- A future backend proposal must answer in writing: why it is required, which feature needs it, why CloudKit is insufficient, what private data would leave the device, what it costs to run, and whether Firebase could do it without custom infrastructure.
