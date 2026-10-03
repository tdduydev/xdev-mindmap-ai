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
| `MacSnapshotTests` (the Mac interface drawn off screen, compared with reference PNGs) | `scripts/snapshot-tests.sh` | Before merging a change to the Mac interface; runs while the screen is locked |
| `FeatureTourUITests` (every feature, one screenshot per step) | `scripts/feature-tour.sh [ios\|macos] [en\|vi\|ja]` | When someone wants to see every feature, such as before a release; skipped by `scripts/ui-tests.sh` |

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

### StoreKit tests and other test runs

StoreKit Testing keeps one set of transactions per app on the Mac, not per test process. Two runs of `MindMapAITests` at once (two worktrees, an agent and the leader) see each other's purchases, and one run's `clearTransactions()` wipes what the other just bought: `refundLocksAgain`, `askToBuyStaysPendingAndUnlocksOnApproval` and `redeemedCodeUnlocksPro` failed this way, then passed alone (MM-69). Releasing a lock when the suite ended was not enough either: the end of the first process still reset StoreKit while the second run's suite was buying.

So every test or suite that creates an `SKTestSession` takes the `.storeKitTestLock` trait (`MindMapAITests/StoreKitTestLock.swift`). The first one in a process takes a file lock in the app's temporary directory and keeps it until the process exits; another run's StoreKit tests wait for it, up to 15 minutes, while its other tests go on. Expect the Pro entitlement suite to start late when another run of the app tests is going. Inside a test, look for the transaction the test made (`pendingAskToBuyConfirmation`, the ID `buyProduct` returns), not the first one listed.

The lock is a file in the app's temporary directory. The test host is the sandboxed app, so that directory is in the app's container, which macOS keys by bundle ID: every worktree's run of `MindMapAITests` finds the same file. On a Mac running several builds, StoreKit still applies a purchase, refund or `clearTransactions()` late, sometimes after more than five seconds (MM-88). So `eventually` waits up to 30 seconds, and each test's `init` asks for the clear again and stops the test with a clear message if StoreKit still lists a transaction, rather than letting the next test fail on the previous test's purchase.

The lock does not cover everything that touches the store. While a macOS UI test run (another worktree) launched the app, which carries the StoreKit configuration in the `MindMapAIUITests` scheme, a purchase never reached `Transaction.updates` or a refund left Pro unlocked for 30 seconds, then the same tests passed. Why the store changed is not proven. So `purchaseFromElsewhereUnlocksWhileRunning` and `refundLocksAgain` check whether StoreKit lost the transaction they made or another transaction unlocks Pro; only then do they clear the store and run again (up to three times, logging "StoreKit changed outside this test"). Any other failure still fails.

### Waiting and timing on a busy machine

Agents and the leader run `scripts/ci.sh` in several worktrees at once, so any test that depends on a short span of real time fails at random (MM-88):

- Wait for an event, not a span of time: `AIAppsTests.waitUntil` uses `Observations` on the host's state and only gives up after 60 seconds to stop a hung test. Never count `Task.yield()` calls or sleep for a fixed time and then check once.
- Do not bind a fixed port. Pick one at random and try another when it is taken (`AIAppsTests.listenOnAFreePort`); `MCPListener` takes port 0 in core tests.
- A test that times code checks the median of several runs and only fails far over the budget. `CommandCostTests` fails a default run when a 1,000-topic command takes a median over 1 s, ten times its 100 ms budget, which still catches a command that has gone quadratic. The 100 ms budget is checked on a quiet Mac with `MINDMAP_BENCHMARKS=1 swift test --package-path Packages/MindMapCore --filter CommandCostTests`. Other timings (layout, canvas, persistence) are printed, never asserted.

## Snapshot tests

XCUITest on the Mac needs an unlocked login session, and the shared Mac mini locks its screen when no one is at it. Snapshot tests check the Mac's own interface without one: `MacSnapshotTests` (`MindMapAITests/Snapshots/`) draws each scene into an off-screen window and compares the pixels with a reference PNG kept in the repo. They are hosted app tests, so they run while the Mac is locked, like the rest of `MindMapAITests`.

```sh
scripts/snapshot-tests.sh            # compare, in English, Vietnamese then Japanese (about 3 minutes)
scripts/snapshot-tests.sh ja         # one language: en, vi or ja
scripts/snapshot-tests.sh --record   # draw new references, on purpose
```

The script prints whether the screen was locked, so a run's log says which case it checked. `scripts/ci.sh` does not run the suite: it is skipped unless `MINDMAP_SNAPSHOTS` is `compare` or `record`, and an OS or Xcode update that changes how AppKit draws would otherwise fail every merge until someone records again.

**What is covered.** From the `sample` fixture of the UI test mode (`UITestFixture.makeMaps()`), in light, dark and Increase Contrast, in English, Vietnamese and Japanese (region JP, MM-96): the main window with the library (`library`), with a map on the canvas (`canvas`) and in the outline (`outline`); the sidebar, the inspector with a topic selected, and the AI suggestion bar with three suggestions from `MockAIProvider` (`sidebar`, `inspector`, `suggestionBar`); every Settings pane (`settings-<pane>`); the paywall with the product from `MindMapAI.storekit` (`paywall`). References are named `<scene>.<appearance>.<language>.png`.

**How it draws.** An `NSHostingView` in a titled `NSWindow` placed off every display; AppKit's `cacheDisplay` draws the window's frame view (title bar and toolbar included) into a 1× bitmap, whatever the screen's scale, so references stay small and the same on any Mac. The capture repeats until two in a row match, because the toolbar and environment settle a few frames after the content. `ImageRenderer` is not used for windows: it draws grouped Forms and AppKit controls blank. The opposite holds for Liquid Glass: `cacheDisplay` draws nothing of a glass view or of what it floats over, which is why the sidebar and inspector are drawn on their own, outside the split view (they show blank in the main window scenes), and why the suggestion bar, a SwiftUI view with no AppKit controls, goes through `ImageRenderer`.

**What it fixes.** Preferences: the test host shares the real app's defaults, so `SnapshotApp` puts every preference a Mac view reads at its default in the argument domain, which wins over stored values and is never written. AI: a ready `MockAIProvider`, so AI controls show on any Mac. Pro is not unlocked. Library dates are set a fixed number of days before now, so "Edited 2 days ago" reads the same every day; the inspector's dates are absolute, so the script sets `TZ=UTC`. The test host is never the active app, so views get `controlActiveState` `.key`; the traffic lights still draw inactive. Settings panes get the app environment as `MindMapAIApp` passes it, without which the Data pane leaves out Recently Deleted, Export All Maps and Import Maps; for that pane one map (`Reading List`) is in Recently Deleted, so the count reads 1 and Empty Recently Deleted is enabled.

**Comparing.** Self-written (no dependency, [[adr-0001]]): both images are drawn into sRGB RGBA bytes; a pixel differs when a channel moves more than 24 of 255 and no pixel within one pixel of it in the other image matches it, checked both ways round; a scene fails when more than 0.2% of its pixels differ, or when the size changed. The one-pixel neighbourhood is there because text antialiasing on the shared Mac mini moves glyph edges by a pixel between runs and OS updates (MM-81), which failed every scene with text; a missing line, a changed colour or a view moved two pixels or more still counts. `SnapshotComparisonTests` checks these rules on small bitmaps and runs in `scripts/ci.sh`. A capture is taken once three captures 250 ms apart are the same, because the first map window of a run sometimes held a toolbar item blank for two. A failure leaves `actual.<name>.png` and `diff.<name>.png` (differing pixels in red over the faded reference) in `scripts/out/snapshots/<language>/`. Hosted tests run in the app sandbox and cannot write into the repo, so the test records images as attachments and the script takes them out of the result bundle; references reach the test as resources of the test bundle, which means a rebuild, done by the script.

**Updating references.** Only on purpose: after a deliberate interface change, or after an OS or Xcode update that changes drawing. Run `--record`, open every changed PNG (`git diff --stat`, then look at each), and commit them with the change that caused them. Never record to make a failure you do not understand go away. References belong to the machine that recorded them (macOS version, fonts); record on the Mac that runs the suite. The current references were recorded on the Mac mini with macOS 27.0.1 (26A434) and Xcode 27.0 (27A266a) (MM-98, 2026-10-03).

**Before committing a recording, look at every toolbar.** The off-screen capture sometimes draws a glass toolbar item blank (the selected Map/Outline segment as a white pill, or an empty Search button), and the item stays blank long enough to pass the three-equal-captures check. A reference with a blank segment fails the next comparison; record that scene again until it draws (MM-98).

**Snapshot or UI test.** A snapshot says how a screen looks: layout, colours in each appearance, Increase Contrast, Vietnamese or Japanese text that no longer fits. It does not click, type or open menus. A flow (rename then undo, ⌘ shortcuts, the menu bar, focus, drag and drop, sheets opening) needs a UI test: on the iOS Simulator any time, and on macOS when someone has unlocked the Mac (`scripts/ui-tests.sh macos`). A change to the Mac interface runs both: snapshots right away, the macOS UI tests the next time the Mac is unlocked.

## Feature tour

`FeatureTourUITests` walks through every feature on main (library, canvas, outline, inspector, Find, Pro and the paywall, AI suggestions, chat, theme, export, import, voice, each Settings pane) and keeps a screenshot of each step, named `NN-feature`. Each step checks one thing and the tour goes on after a failed step, so one run shows everything that works. It is skipped unless `MINDMAP_FEATURE_TOUR=1` reaches the test runner, which `scripts/feature-tour.sh` sets:

```sh
scripts/feature-tour.sh ios en                                  # iPhone 17 simulator
IOS_SIMULATOR="iPad Pro 11-inch (M5)" scripts/feature-tour.sh ios vi
scripts/feature-tour.sh ios ja                                  # Japanese
scripts/feature-tour.sh macos en                                # takes the mouse and keyboard
```

The script takes the screenshots out of the result bundle into `scripts/out/feature-tour/<platform>-<language>/` and prints a table of the steps with PASS, FAIL or NOT RUN. Test methods run in name order and each launches the app again; the paywall test buys Pro before the AI and voice tests, which need it. A new feature adds a step (next free number) to the matching test method, or a new `testNN…` method.

## The UI test mode

UI tests launch the app with `-uitest` (`Shared/UITestLaunch.swift`). The mode is read in Debug builds only (`UITestMode`); a Release build ignores the arguments, and without `-uitest` the app behaves exactly as shipped. In the mode:

- **Store:** SwiftData in memory (`PersistenceController.makeRepository(at: .inMemory)`), seeded with a fixture before the library loads. Nothing a test does survives the launch, and the person's maps are never read (the App Group store is not opened). Spotlight gets a no-op index (`NoSearchIndex`), so fixture maps never show in the Mac's search.
- **Preferences:** a throwaway `UserDefaults` suite, emptied at launch (`AppDefaults.store`). Every `@AppStorage` and defaults reader in the app uses `AppDefaults.store`, never `.standard`, so tests do not share preferences with the real app on the Mac. `-key value` launch arguments are copied in, so a test can start with a preference set (`arguments: ["-appearance", "dark"]`).
- **No onboarding:** first-run screens start as seen. Today that is the AI privacy notice; a test that checks it passes `-ai.privacyNoticeShown NO`.
- **No animation:** `Motion` returns no animation, and on iOS `UIView` animations are off, so a query never finds a view halfway through moving.
- **Language:** `MindMapApp.launch(language:)` passes `-AppleLanguages` and `-AppleLocale` (English by default), so a run does not depend on the machine's language.
- **Windows:** `-ApplePersistenceIgnoreState YES`, so the Mac does not reopen the windows of the previous run.
- **Pro (only with `-uitest-pro`):** `ProEntitlement` starts and stays unlocked whatever StoreKit says, so a test of a Pro feature does not depend on a purchase: on a fresh iOS 27 simulator the StoreKit purchase sheet stopped at "You must enter both your Apple Account and password" (MM-26). Tests of the paywall and the purchase itself leave it off.
- **Files (only with `-uitest-files`):** `UITestFiles` (`MindMapAI/App/UITestFiles.swift`) stands in for the system's open and save panels. Import… and Import into Map… read `UITestFile.markdown` (`Shared/UITestLaunch.swift`) from the app's temporary folder; Export… writes the file there, reads it back and shows a small report at the bottom of the window (`AccessibilityID.UITest.exportedFile`: the file name in the label, the text, or `png <bytes>` / `pdf <bytes>` by the file's signature, in the value). The code before and after the panel is the shipping code. The real panels are another process, look different on each OS version and cannot reach a fixture, so a test of what import and export do uses the stand-in; `ImportUITests` and `DataSettingsUITests` still check that the real panels open.

New state that persists across launches (a file, a preference, a first-run flag) must go through the same mode, or UI tests become order-dependent.

## Fixtures

`UITestFixture` (`Shared/UITestLaunch.swift`) names the maps a test starts with; `-uitest-fixture <name>` picks one, default `empty`. The app builds them in `UITestMode.swift` with `GraphCommand`s run by a `GraphEngine`, like any edit, with fixed times one minute apart so the library order is stable.

| Fixture | Maps |
| --- | --- |
| `empty` | None |
| `sample` | "Product Launch" (Research ▸ Interviews, Design, Marketing) and "Reading List" (favorite, central topic only) |
| `large` | "Large Map": a central topic and 9 branches of 110 topics, 1,000 topics in all |

`-uitest-ai <mode>` (`UITestAI`) replaces Apple Intelligence with a scripted model, so AI screens can be tested on a machine without it: `ready` (English and Vietnamese; the chat answers with the first topic whose title matches a word of the question, and cites it) `ineligible` (every AI entry point hidden), `fiveSuggestions` (ready; Suggest Subtopics proposes five, for AT-04), `guardrail` (ready; the guardrails block every request) or `appleIntelligenceOff` (entry points stay, with the line on how to turn Apple Intelligence on). Without it the real model is used. The scripted model lives in the app (`UITestAIService.swift`, Debug only) rather than linking `MockAIProvider` from `MindMapTestSupport`, so the app target never depends on the test-support package.

In the `ready` mode Suggest Subtopics answers with `UITestAI.subtopics` (Budget, Timeline, Risks) under the focus topic (`UITestAI.fiveSubtopics` in `fiveSuggestions`); Generate Map proposes `UITestAI.generatedTopics`, Rewrite Topic offers `UITestAI.rewrites` and Summarize Branch returns `UITestAI.summary`. The other features (Brainstorm, Find Missing Topics, tags, groups, boundary titles) still fail like a bad answer. Voice input in the mode hears `UITestVoice.heard` (two sentences, two topics) instead of using the Speech framework, which the Simulator does not have. The `MindMapAIUITests` scheme runs the app with `MindMapAITests/MindMapAI.storekit`, so the paywall shows a price and a purchase goes through StoreKit Testing; a purchase stays on that simulator until the test transactions are deleted.

Titles are data, not interface text, so they are the same in every language. Tests refer to them through `UITestFixture.Title`, never as string literals. A new fixture is a new case and a `makeMaps()` branch; keep existing ones unchanged, because other suites count their topics.

## Accessibility identifiers

Identifiers live in one enum, `AccessibilityID` (`Shared/AccessibilityID.swift`), compiled into both the app and the UI test target: renaming one breaks the build instead of a test run.

- Form: `area.element` in lowerCamelCase: `library.newMap`, `editor.addChild`, `outline.topic`, `settings.appearance`.
- Repeated elements (library rows, outline rows, canvas topics) share one identifier. A test tells them apart by label or value, which is the title the person sees, not by an index in the identifier. Which of the two holds the title can differ by platform (a combined library row is a static text with the title in its value on macOS, a cell with it in its label on iOS); the page object checks both.
- Every interactive control a test needs gets an identifier. Do not find controls by their label: labels are translated.
- Identifiers are not shown to VoiceOver and never contain map content.

## Suites

| Suite | Covers | Platforms |
| --- | --- | --- |
| `FoundationUITests` | The UI test mode itself: fixtures, a fresh store per launch, language | macOS, iOS |
| `LibraryUITests` | Sections, New Mind Map, search by title and topic text, diacritic folding, Vietnamese | macOS, iOS |
| `OutlineUITests` | Rename, add sibling, delete a branch, each with undo and redo; collapse; Vietnamese VoiceOver labels | macOS, iOS |
| `FindUITests` | Find in map: match count, Next and Previous, no results, folding, Done, Vietnamese | macOS, iOS |
| `SettingsUITests` | Opening Settings (⌘, or the sidebar button), panes, Appearance kept across a reopen, Vietnamese | macOS, iOS |
| `PaywallUITests` | Settings ▸ Pro ▸ See What’s in Pro… shows the purchase button with its price, English and Vietnamese (skips when the device already owns Pro) | macOS, iOS |
| `DataSettingsUITests` | Settings present one dialog and keep Settings open: Empty Recently Deleted asks first, Export All Maps opens the folder picker (iOS); Add App opens one sheet (macOS) | macOS, iOS |
| `CanvasUITests` | Canvas: tap to select, double-tap to edit a title in place (Return commits, Esc cancels), add and delete with undo and redo, ⌘− ⌘+ ⌘0 and Zoom to Fit, pan, drag to a new parent and the refused drop into the dragged branch (AT-03), Add to Selection then one-step delete, Copy and Paste of a branch (the Markdown text checked on macOS), selection kept across canvas and outline; the 1,000-topic map opened and panned, timed with `XCTClockMetric`, not asserted (AT-02). Context menu items by English title, so English only | macOS, iOS |
| `AIUITests` | Scripted model: five suggestions previewed, two accepted, one undo and redo (AT-04); Discard leaves nothing to undo; Generate Map; Rewrite Topic; Summarize Branch into the note only on Add to Note; a guardrail refusal says to reword and offers Edit Request…; Apple Intelligence off shows one line; an ineligible device has no AI in the toolbar, More menu, topic menu or Settings and editing still works (AT-05) | iOS (written for macOS too; topic-menu and More-menu checks are iOS only) |
| `FileTransferUITests` | With `-uitest-files`: a Markdown file imported then exported again keeps its headings and nested lists (AT-06); PNG and PDF exports write a non-empty file of that type | macOS, iOS |
| `RecentlyDeletedUITests` | Delete moves a map to Recently Deleted, Restore brings it back, Delete Permanently asks first | macOS, iOS |
| `VoiceInputUITests` | Add Topics by Voice with the scripted transcriber: the topics heard are added under the selected topic, one undo removes them all, redo adds them back (`-uitest-pro`) | macOS, iOS |
| `MenuShortcutUITests` | Menu items disabled without a map, ⌘N, ⌘1/⌘2, ⇧⌘Return with ⌘Z and ⇧⌘Z, ⌘F/⌘G/⇧⌘G/Esc, ⌘, | macOS only |

Menu bar items have no accessibility identifier (SwiftUI `Commands` do not pass one on), so `MenuShortcutUITests` finds them by their English titles and runs in English only. On iPhone the editor toolbar moves what does not fit into an overflow menu; its items lose their identifiers, so `EditorPage.tap(_:)` opens the menu and finds the item by its SF Symbol name, which is not translated.

## Writing a UI test

- One `XCTestCase` per area (MM-23 library and outline, MM-24 canvas, …), each test `@MainActor`, starting with `MindMapApp.launch(fixture:language:)`.
- Go through page objects in `MindMapAIUITests/Pages/`: `LibraryPage`, `EditorPage`, `SettingsPage`. Add elements and steps there, not in the test, so a UI change is fixed in one place. Pages return the next page (`library.open(title)` returns an `EditorPage`).
- Wait, do not sleep: `waitToExist()` and `waitForCount(_:)` fail at the caller's line.
- Pick segments, menus and sections by identifier or position, never by translated text. A test that checks the text itself (a Vietnamese run) compares to the expected string on purpose.
- iPhone shows the split view as a stack: `LibraryPage.show()` opens All Maps from the sidebar when the list is not on screen.
- Platform differences (`#if os(macOS)`) stay in the pages, not the tests.
- No network and no real AI model (NFR-TEST-06). Time an operation with `XCTMetric` if useful, but do not assert on the number.
- Every UI test runs on both macOS and the iOS Simulator unless it covers a platform-only feature; mark those with `#if os(...)` around the whole test.
