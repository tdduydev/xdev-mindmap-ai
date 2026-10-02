# Testing

How the app is tested, from the package up to the UI. The table per layer is in [[architecture]] and [[module-structure]]; this page is about running tests and writing UI tests.

## What runs where

| Suite | Runs with | When |
| --- | --- | --- |
| `MindMapCore` package tests | `swift test` (in `scripts/ci.sh`) | Every change |
| `MindMapAITests` (hosted app tests, macOS) | `scripts/ci.sh` | Every change |
| Universal macOS Release build (`arm64` and `x86_64`, checked with `lipo`) | `scripts/ci.sh` | Every change |
| iOS Simulator build | `scripts/ci.sh` | Every change |
| Core and app tests as x86_64 under Rosetta | `scripts/rosetta-tests.sh` | Before merging a change to the AI gate, build settings or code under `#if arch` ([[architecture]], Platforms) |
| `MindMapAIUITests` (XCUITest, macOS and iOS Simulator) | `scripts/ui-tests.sh` | Before merging a change to the interface |

`scripts/ci.sh` stays fast and does not run UI tests (NFR-TEST-03). Warnings are errors in both scripts.

## Running UI tests

```sh
scripts/ui-tests.sh                 # macOS, then the iOS Simulator
scripts/ui-tests.sh ios             # one platform: macos or ios
scripts/ui-tests.sh macos -only-testing:MindMapAIUITests/FoundationUITests/testSampleFixtureListsItsMaps
IOS_SIMULATOR="iPad Pro 13-inch (M5)" scripts/ui-tests.sh ios
```

Extra arguments go to `xcodebuild test`. Results are in `scripts/out/UITestResults/<platform>.xcresult`; open one in Xcode to see screenshots and the element tree of a failure. The scheme is `MindMapAIUITests`, so Xcode runs the same tests with ⌘U on that scheme.

### macOS: allow automation once

XCUITest on the Mac drives the app through the Accessibility API. On a new machine the first run stops with "Timed out while enabling automation mode" or a prompt for permission. Allow it once:

1. Run `sudo automationmodetool enable-automationmode-without-authentication` (stops the password prompt on each run; needs an admin account), or accept the prompt when it appears.
2. System Settings ▸ Privacy & Security ▸ Accessibility: turn on Xcode (and `xcodebuild`'s host Terminal, or the agent's shell, when running from a script).
3. Keep the Mac awake and unlocked while the tests run; a locked screen fails every macOS UI test.

The iOS Simulator needs none of this.

### A busy machine

A cold simulator, or a Mac running many builds at once, can take a minute to launch the app. Queries wait `MindMapApp.timeout` (30 s) after launch. If the runner crashes with "operation never finished bootstrapping" before the first test, the simulator was still booting: run again.

## The UI test mode

UI tests launch the app with `-uitest` (`Shared/UITestLaunch.swift`). The mode is read in Debug builds only (`UITestMode`); a Release build ignores the arguments, and without `-uitest` the app behaves exactly as shipped. In the mode:

- **Store:** SwiftData in memory (`PersistenceController.makeRepository(at: .inMemory)`), seeded with a fixture before the library loads. Nothing a test does survives the launch, and the person's maps are never read (the App Group store is not opened). Spotlight gets a no-op index (`NoSearchIndex`), so fixture maps never show in the Mac's search.
- **Preferences:** a throwaway `UserDefaults` suite, emptied at launch (`AppDefaults.store`). Every `@AppStorage` and defaults reader in the app uses `AppDefaults.store`, never `.standard`, so tests do not share preferences with the real app on the Mac. `-key value` launch arguments are copied in, so a test can start with a preference set (`arguments: ["-appearance", "dark"]`).
- **No onboarding:** first-run screens start as seen. Today that is the AI privacy notice; a test that checks it passes `-ai.privacyNoticeShown NO`.
- **No animation:** `Motion` returns no animation, and on iOS `UIView` animations are off, so a query never finds a view halfway through moving.
- **Language:** `MindMapApp.launch(language:)` passes `-AppleLanguages` and `-AppleLocale` (English by default), so a run does not depend on the machine's language.
- **Windows:** `-ApplePersistenceIgnoreState YES`, so the Mac does not reopen the windows of the previous run.

New state that persists across launches (a file, a preference, a first-run flag) must go through the same mode, or UI tests become order-dependent.

## Fixtures

`UITestFixture` (`Shared/UITestLaunch.swift`) names the maps a test starts with; `-uitest-fixture <name>` picks one, default `empty`. The app builds them in `UITestMode.swift` with `GraphCommand`s run by a `GraphEngine`, like any edit, with fixed times one minute apart so the library order is stable.

| Fixture | Maps |
| --- | --- |
| `empty` | None |
| `sample` | "Product Launch" (Research ▸ Interviews, Design, Marketing) and "Reading List" (favorite, central topic only) |
| `large` | "Large Map": a central topic and 9 branches of 110 topics, 1,000 topics in all |

Titles are data, not interface text, so they are the same in every language. Tests refer to them through `UITestFixture.Title`, never as string literals. A new fixture is a new case and a `makeMaps()` branch; keep existing ones unchanged, because other suites count their topics.

## Accessibility identifiers

Identifiers live in one enum, `AccessibilityID` (`Shared/AccessibilityID.swift`), compiled into both the app and the UI test target: renaming one breaks the build instead of a test run.

- Form: `area.element` in lowerCamelCase: `library.newMap`, `editor.addChild`, `outline.topic`, `settings.appearance`.
- Repeated elements (library rows, outline rows, canvas topics) share one identifier. A test tells them apart by label or value, which is the title the person sees, not by an index in the identifier. Which of the two holds the title can differ by platform (a combined library row is a static text with the title in its value on macOS, a cell with it in its label on iOS); the page object checks both.
- Every interactive control a test needs gets an identifier. Do not find controls by their label: labels are translated.
- Identifiers are not shown to VoiceOver and never contain map content.

## Writing a UI test

- One `XCTestCase` per area (MM-23 library and outline, MM-24 canvas, …), each test `@MainActor`, starting with `MindMapApp.launch(fixture:language:)`.
- Go through page objects in `MindMapAIUITests/Pages/`: `LibraryPage`, `EditorPage`. Add elements and steps there, not in the test, so a UI change is fixed in one place. Pages return the next page (`library.open(title)` returns an `EditorPage`).
- Wait, do not sleep: `waitToExist()` and `waitForCount(_:)` fail at the caller's line.
- Pick segments, menus and sections by identifier or position, never by translated text. A test that checks the text itself (a Vietnamese run) compares to the expected string on purpose.
- iPhone shows the split view as a stack: `LibraryPage.show()` opens All Maps from the sidebar when the list is not on screen.
- Platform differences (`#if os(macOS)`) stay in the pages, not the tests.
- No network and no real AI model (NFR-TEST-06). Time an operation with `XCTMetric` if useful, but do not assert on the number.
- Every UI test runs on both macOS and the iOS Simulator unless it covers a platform-only feature; mark those with `#if os(...)` around the whole test.
