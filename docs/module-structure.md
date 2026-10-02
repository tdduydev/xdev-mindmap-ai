# Module structure

Research for MM-0e, 2026-10-02: how the repository grows through the phases. The rule is to split layers into packages, and keep features in the app target until a second target needs them.

## What the sources say

- Apple recommends local packages to keep code maintainable ([Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)). Its [Backyard Birds](https://github.com/apple/sample-backyard-birds) sample uses one multiplatform app folder, local packages for data and UI, and a separate widgets target.
- Large apps go further. Point-Free's [isowords](https://github.com/pointfreeco/isowords) splits into 86 modules for compile times, preview stability and a small App Clip; Tuist's [TMA](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/features/projects/tma-architecture.md) gives each module an interface, tests and test support.
- With a SwiftUI UI, use one multiplatform target. Use `#if canImport` for a missing framework, `#if os` for a missing symbol, and leave a whole file out of a platform in Compile Sources ([Configuring a multiplatform app target](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target)). In packages, use `.when(platforms:)` for platform-only dependencies.
- App Intents can live in a Swift package since 2025: each target declares an `AppIntentsPackage` that includes the shared one ([WWDC25 session 244](https://developer.apple.com/videos/play/wwdc2025/244/)).
- An app and its extensions share a SwiftData store through an App Group (`ModelConfiguration.GroupContainer`).

## Target tree

```
MindMapAI.xcodeproj
├─ MindMapAI/                 app target (macOS, iPadOS, iOS): App/, Features/<Feature>/, Resources
├─ MindMapShareExtension/     ✓ MM-11, macOS and iOS
├─ MindMapAITests/            hosted app tests on macOS
└─ MindMapAIUITests/          MM-3 and later
Packages/
├─ MindMapCore/               no UI; `swift test` on the Mac
│  ├─ MindMapDomain           ✓
│  ├─ MindMapGraph            ✓
│  ├─ MindMapPersistence      ✓, plus App Group store and CloudKit config (MM-6)
│  ├─ MindMapLayout           ✓ (MM-4), see [[layout-engine]]
│  ├─ MindMapInterchange      ✓ Markdown and text (MM-10a), see [[interchange]]; OPML later
│  ├─ MindMapSearch           ✓ text search (MM-15): folding, library index and ranking, Find; `Embedder` protocol later
│  ├─ MindMapSharing          ✓ (MM-11): QuickCapture, SharedContent, ShareInbox for the extension and the intents
│  ├─ MindMapIntents          ✓ (MM-11): entities, queries, intents, AppIntentsPackage, Spotlight index; see [[system-integration]]
│  ├─ MindMapAICore           ✓ (MM-7): AIProvider, requests, AIProposal, ContextBuilder, ProposalTranslator, AICapabilities
│  ├─ MindMapAIApple          ✓ (MM-7): Foundation Models provider, @Generable types, prompts catalog; Translation glue later
│  ├─ MindMapCapture          ✓ speech (MM-20): `VoiceTranscribing`, `AppleSpeechTranscriber`, `SpokenTopics`; OCR, PDF text, ink later
│  └─ MindMapTestSupport      fixtures, MockAIProvider (✓ MM-7), in-memory repository (tests only)
├─ MindMapUI/                 SwiftUI, no SwiftData
│  ├─ MindMapDesignSystem     moved out of the app target when the Share Extension needs it
│  └─ MindMapCanvas           rendering, viewport, hit testing, gestures, PNG/PDF rendering; in the app target (Features/Canvas) until a second target needs it, see [[canvas]]
└─ MindMapLocalModels/        optional, later: MLX or Core AI models
```

## Why each boundary

| Boundary | Reason |
| --- | --- |
| Features stay in the app target | Every package boundary forces `public` APIs (ADR 0002). A feature moves out only when a second target needs it. |
| Layout apart from Graph | Graph never sees screen coordinates; layout is nothing but coordinates. Sizes in, frames out, tested without UI. |
| Interchange is pure parsing | The Share Extension and App Intents import text without UI or AI. |
| Search holds protocols and ranking | Embedding backends (NaturalLanguage, or a local model) plug in behind `Embedder`; tests use fakes. |
| AICore apart from AIApple | AICore never imports FoundationModels, so Graph, UI and tests depend on plain values. Providers swap behind one protocol. Prompts live next to the provider that uses them. |
| Capture wraps OS frameworks | OCR, Translation and speech have device and Simulator limits; protocols let tests and the Simulator use fakes. |
| UI package without SwiftData | Keeps Core free of SwiftUI and lets the extension reuse the design system. |
| Intents in one package | `MindMapIntents`, a target of `MindMapCore` (one package reference, tested by `swift test`); the app includes it through its own `AppIntentsPackage`. |
| Local models in their own package | MLX's Metal shaders do not build with the SwiftPM command line, which would break `swift test` for Core. |
| Share Extension links the minimum | Domain, Graph, Persistence, Interchange, Sharing; no AI, no AppIntents. It uses standard SwiftUI controls, so it does not need the design system yet. Images and PDFs go to an inbox in the App Group container; the app reads them later. Extension memory limits are not verified. |

## Platform code

`#if os(macOS)` for a modifier; a whole-file `#if os` (or a Compile Sources filter) for a view that differs; `.when(platforms:)` for package dependencies. Shared logic never branches on platform (ADR 0006).

## Testing per layer

| Layer | Tests |
| --- | --- |
| Domain, Graph, Layout, Interchange, Search, AICore | Swift Testing with `swift test`; `MockAIProvider` and golden proposals |
| Persistence | In-memory and on-disk stores, the App Group path |
| AIApple | Hosted on the Mac and gated with `.enabled(if: SystemLanguageModel.default.isAvailable)`; Evaluations framework for prompt quality |
| Capture | Vietnamese and English fixtures, on the Mac and a device (not the Simulator) |
| Intents | AppIntentsTesting |
| Canvas | Previews from TestSupport fixtures, then UI tests |
