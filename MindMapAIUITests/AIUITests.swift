import XCTest

/// The AI features with the UI test mode's scripted model (`-uitest-ai`), so
/// no run calls a real model (NFR-TEST-02): suggestions previewed, part
/// accepted and undone in one step (AT-04), Generate Map, Rewrite Topic,
/// Summarize Branch into the note, Discard, a guardrail refusal, Apple
/// Intelligence turned off, and a device that cannot run it (AT-05).
final class AIUITests: XCTestCase {
    /// Product Launch: the central topic, Research, Interviews, Design, Marketing.
    private let planTopicCount = 5

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openPlan(ai: UITestAI) -> (EditorPage, AIPage) {
        let app = MindMapApp.launch(fixture: .sample, arguments: [UITestLaunch.ai, ai.rawValue])
        let editor = app.library.show().open(UITestFixture.Title.plan).show(.canvas)
        return (editor, AIPage(app: app.app))
    }

    /// AT-04: five suggestions show on the canvas before anything changes;
    /// discarding three and accepting the rest adds two topics in one undo step.
    @MainActor
    func testAcceptTwoOfFiveSuggestionsThenOneUndoRemovesBoth() {
        let (editor, ai) = openPlan(ai: .fiveSuggestions)
        editor.canvasTopic(UITestFixture.Title.design).waitToExist().tapOrClick()

        ai.run(symbol: AIPage.Symbol.suggestSubtopics)
        ai.acceptAllButton.waitToExist()
        // Previewed on the canvas, not yet part of the map.
        editor.canvasTopics.waitForCount(planTopicCount + UITestAI.fiveSubtopics.count)
        XCTAssertFalse(editor.undoButton.isEnabled, "a preview is not an edit")

        ai.reviewButton.waitToExist().tapOrClick()
        ai.discardButtons.waitForCount(UITestAI.fiveSubtopics.count)
        for remaining in stride(from: UITestAI.fiveSubtopics.count, to: 2, by: -1) {
            ai.discardButtons.element(boundBy: remaining - 1).waitToExist().tapOrClick()
            ai.discardButtons.waitForCount(remaining - 1)
        }
        ai.dismissPopover()
        editor.canvasTopics.waitForCount(planTopicCount + 2)

        ai.acceptAllButton.waitToExist().tapOrClick()
        editor.canvasTopic(UITestAI.fiveSubtopics[0]).waitToExist()
        editor.canvasTopic(UITestAI.fiveSubtopics[1]).waitToExist()
        XCTAssertTrue(ai.acceptAllButton.waitForNonExistence(timeout: MindMapApp.timeout))
        XCTAssertFalse(editor.canvasTopic(UITestAI.fiveSubtopics[2]).exists)

        editor.undoButton.waitToExist().tapOrClick()
        editor.canvasTopics.waitForCount(planTopicCount)
        XCTAssertFalse(editor.canvasTopic(UITestAI.fiveSubtopics[0]).exists)
        XCTAssertFalse(editor.canvasTopic(UITestAI.fiveSubtopics[1]).exists)

        editor.redoButton.waitToExist().tapOrClick()
        editor.canvasTopics.waitForCount(planTopicCount + 2)
    }

    /// Discard drops every suggestion and leaves nothing to undo.
    @MainActor
    func testDiscardKeepsTheMapAsItWas() {
        let (editor, ai) = openPlan(ai: .fiveSuggestions)
        editor.canvasTopic(UITestFixture.Title.marketing).waitToExist().tapOrClick()

        ai.run(symbol: AIPage.Symbol.suggestSubtopics)
        editor.canvasTopics.waitForCount(planTopicCount + UITestAI.fiveSubtopics.count)
        ai.discardAllButton.waitToExist().tapOrClick()

        editor.canvasTopics.waitForCount(planTopicCount)
        XCTAssertFalse(ai.acceptAllButton.exists)
        XCTAssertFalse(editor.undoButton.isEnabled, "Discard changed the map")
    }

    /// Generate Map from a typed description: suggestions under the central
    /// topic, added with Accept All.
    @MainActor
    func testGenerateMapSuggestsTopicsUnderTheCentralTopic() {
        let (editor, ai) = openPlan(ai: .ready)

        ai.run(symbol: AIPage.Symbol.generateMap)
        let field = ai.promptField.waitToExist()
        field.tapOrClick()
        field.typeText("Plan a product launch")
        ai.submitButton.waitToExist().tapOrClick()

        ai.acceptAllButton.waitToExist().tapOrClick()
        for title in UITestAI.generatedTopics {
            editor.canvasTopic(title).waitToExist()
        }
        editor.canvasTopics.waitForCount(planTopicCount + UITestAI.generatedTopics.count)
        editor.undoButton.waitToExist().tapOrClick()
        editor.canvasTopics.waitForCount(planTopicCount)
    }

    /// Rewrite Topic shows the AI titles first; Use Title renames in one undo step.
    @MainActor
    func testRewriteTopicUsesTheChosenTitle() {
        let (editor, ai) = openPlan(ai: .ready)
        editor.canvasTopic(UITestFixture.Title.design).waitToExist().tapOrClick()

        ai.run(symbol: AIPage.Symbol.rewrite)
        ai.menuItem(label: "Shorter").waitToExist().tapOrClick()
        let title = ai.newTitleField.waitToExist()
        XCTAssertEqual(title.value as? String, UITestAI.rewrites[0])
        XCTAssertTrue(editor.canvasTopic(UITestFixture.Title.design).exists, "the map changed before Use Title")
        ai.useTitleButton.waitToExist().tapOrClick()

        editor.canvasTopic(UITestAI.rewrites[0]).waitToExist()
        XCTAssertFalse(editor.canvasTopic(UITestFixture.Title.design).exists)
        editor.undoButton.waitToExist().tapOrClick()
        editor.canvasTopic(UITestFixture.Title.design).waitToExist()
    }

    /// Summarize Branch only shows the summary; Add to Note puts it in the note.
    @MainActor
    func testSummarizeBranchGoesIntoTheNoteOnlyWhenChosen() {
        let (editor, ai) = openPlan(ai: .ready)
        editor.canvasTopic(UITestFixture.Title.research).waitToExist().tapOrClick()

        ai.run(symbol: AIPage.Symbol.summarize)
        XCTAssertEqual(ai.summaryText.waitToExist().shownText, UITestAI.summary)
        XCTAssertFalse(editor.undoButton.isEnabled, "the summary changed the map before Add to Note")
        ai.addToNoteButton.waitToExist().tapOrClick()
        XCTAssertTrue(ai.addToNoteButton.waitForNonExistence(timeout: MindMapApp.timeout))

        editor.tap(.inspector)
        let note = editor.app.textViews[AccessibilityID.Inspector.note].firstMatch.waitToExist()
        XCTAssertTrue((note.value as? String ?? "").contains(UITestAI.summary), "note reads \(note.value ?? "")")
    }

    /// A request the guardrails block says to reword it and offers the typed
    /// request back to edit; the map does not change.
    @MainActor
    func testGuardrailRefusalSuggestsRewording() {
        let (editor, ai) = openPlan(ai: .guardrail)

        ai.run(symbol: AIPage.Symbol.generateMap)
        let field = ai.promptField.waitToExist()
        field.tapOrClick()
        field.typeText("Plan a product launch")
        ai.submitButton.waitToExist().tapOrClick()

        let failure = ai.failure.waitToExist()
        XCTAssertTrue(failure.shownText.contains("Try wording it differently"), "failure reads \(failure.shownText)")
        XCTAssertFalse(ai.acceptAllButton.exists)
        editor.canvasTopics.waitForCount(planTopicCount)

        ai.editRequestButton.waitToExist().tapOrClick()
        XCTAssertEqual(ai.promptField.waitToExist().value as? String, "Plan a product launch")
    }

    /// Apple Intelligence turned off: the AI menu stays, with one line on how
    /// to turn it on, and its actions are disabled.
    @MainActor
    func testAppleIntelligenceOffShowsOneLineOfGuidance() {
        let (editor, ai) = openPlan(ai: .appleIntelligenceOff)
        editor.canvasTopic(UITestFixture.Title.design).waitToExist().tapOrClick()

        ai.openMenu()
        let reason = ai.unavailableReason.waitToExist()
        XCTAssertTrue(reason.shownText.contains("turn on Apple Intelligence"), "reason reads \(reason.shownText)")
        XCTAssertFalse(ai.menuItem(symbol: AIPage.Symbol.suggestSubtopics).waitToExist().isEnabled)
    }

    /// AT-05: a device that cannot run Apple Intelligence shows no way into
    /// AI, and editing still works.
    @MainActor
    func testIneligibleDeviceHidesEveryAIEntryPoint() {
        let app = MindMapApp.launch(fixture: .sample, arguments: [UITestLaunch.ai, UITestAI.ineligible.rawValue])
        let settings = app.openSettings()
        XCTAssertFalse(settings.paneButton(.ai).exists, "Settings has an AI pane")
        #if os(macOS)
        settings.window.typeKey("w", modifierFlags: .command)
        #else
        settings.doneButton.waitToExist().tapOrClick()
        #endif

        let editor = app.library.show().open(UITestFixture.Title.plan).show(.canvas)
        let ai = AIPage(app: app.app)
        editor.canvasTopic(UITestFixture.Title.design).waitToExist().tapOrClick()

        XCTAssertFalse(ai.toolbarMenu.waitForExistence(timeout: MindMapApp.timeout / 6), "the toolbar has an AI menu")
        XCTAssertFalse(editor.app.buttons[AccessibilityID.Chat.toolbar].exists, "the toolbar has Ask About This Map")
        #if os(iOS)
        // On iPhone what does not fit moves into the More menu: no AI there either.
        let overflow = editor.app.buttons.matching(identifier: "OverflowBarButtonItem")
        if overflow.count > 0 {
            overflow.element(boundBy: overflow.count - 1).tapOrClick()
            XCTAssertFalse(editor.app.buttons.matching(NSPredicate(format: "label == %@", "AI")).firstMatch
                .waitForExistence(timeout: MindMapApp.timeout / 6), "the More menu has an AI menu")
            XCTAssertFalse(ai.menuItem(symbol: AIPage.Symbol.chat).exists, "the More menu has Ask About This Map")
            ai.dismissMenu()
        }
        // The topic's context menu leaves the AI actions out. Add Summary is
        // found by title, as in TopicSummaryUITests; the tests run in English.
        editor.canvasTopic(UITestFixture.Title.design).waitToExist().press(forDuration: 1)
        editor.app.buttons["Add Summary"].firstMatch.waitToExist()
        for symbol in [AIPage.Symbol.suggestSubtopics, AIPage.Symbol.rewrite, AIPage.Symbol.summarize] {
            XCTAssertFalse(ai.menuItem(symbol: symbol).exists, "the topic menu has \(symbol)")
        }
        ai.dismissMenu()
        editor.canvasTopic(UITestFixture.Title.design).tapOrClick()
        #endif

        // Everything else still works.
        editor.tap(.addChild)
        editor.canvasTopics.waitForCount(planTopicCount + 1)
    }
}

/// The AI menus, the suggestion bar and the AI sheets.
@MainActor
struct AIPage {
    /// The SF Symbols of the AI actions (AIActionsMenu), the same in every language.
    enum Symbol {
        static let generateMap = "sparkles"
        static let suggestSubtopics = "arrow.turn.down.right"
        static let rewrite = "pencil.line"
        static let summarize = "text.alignleft"
        static let chat = "bubble.left.and.text.bubble.right"
    }

    let app: XCUIApplication

    /// A toolbar Menu is a menu button on the Mac, a button on iOS.
    var toolbarMenu: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Editor.ai].firstMatch }

    var reviewButton: XCUIElement { app.buttons[AccessibilityID.Suggestions.review].firstMatch }
    var acceptAllButton: XCUIElement { app.buttons[AccessibilityID.Suggestions.acceptAll].firstMatch }
    var discardAllButton: XCUIElement { app.buttons[AccessibilityID.Suggestions.discardAll].firstMatch }
    /// One per suggestion in the Review list, top to bottom.
    var discardButtons: XCUIElementQuery { app.buttons.matching(identifier: AccessibilityID.Suggestions.discard) }
    var failure: XCUIElement { app.staticTexts[AccessibilityID.Suggestions.failure].firstMatch }
    var editRequestButton: XCUIElement { app.buttons[AccessibilityID.Suggestions.editRequest].firstMatch }

    var promptField: XCUIElement { app.descendants(matching: .any)[AccessibilityID.AISheet.promptField].firstMatch }
    var submitButton: XCUIElement { app.buttons[AccessibilityID.AISheet.submit].firstMatch }
    var newTitleField: XCUIElement { app.descendants(matching: .any)[AccessibilityID.AISheet.newTitle].firstMatch }
    var useTitleButton: XCUIElement { app.buttons[AccessibilityID.AISheet.useTitle].firstMatch }
    var summaryText: XCUIElement { app.staticTexts[AccessibilityID.AISheet.summary].firstMatch }
    var addToNoteButton: XCUIElement { app.buttons[AccessibilityID.AISheet.addToNote].firstMatch }

    /// The one line on why AI cannot run. A menu may drop the identifier of a
    /// plain text, so the line is also found by its words (the tests run in English).
    var unavailableReason: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label CONTAINS %@ OR value CONTAINS %@",
            AccessibilityID.AIMenu.unavailableReason, "turn on Apple Intelligence", "turn on Apple Intelligence"
        )).firstMatch
    }

    /// The toolbar's AI menu, from the toolbar or its More menu on iPhone.
    func openMenu(file: StaticString = #filePath, line: UInt = #line) {
        if toolbarMenu.waitForExistence(timeout: MindMapApp.timeout / 6) {
            toolbarMenu.tapOrClick()
            return
        }
        #if os(iOS)
        // In the More menu the AI menu is a submenu titled AI, in every language.
        let overflow = app.buttons.matching(identifier: "OverflowBarButtonItem")
        overflow.element(boundBy: max(overflow.count - 1, 0)).waitToExist(file: file, line: line).tapOrClick()
        app.buttons.matching(NSPredicate(format: "label == %@", "AI")).firstMatch.waitToExist(file: file, line: line).tapOrClick()
        #else
        toolbarMenu.waitToExist(file: file, line: line)
        #endif
    }

    /// Opens the AI menu and picks the action with `symbol`.
    func run(symbol: String, file: StaticString = #filePath, line: UInt = #line) {
        openMenu(file: file, line: line)
        menuItem(symbol: symbol).waitToExist(file: file, line: line).tapOrClick()
    }

    /// An item of the open menu, by its SF Symbol.
    func menuItem(symbol: String) -> XCUIElement {
        #if os(iOS)
        // The More menu's AI submenu row shows `sparkles` too, like Generate Map.
        app.collectionViews.buttons.containing(.image, identifier: symbol)
            .matching(NSPredicate(format: "label != %@", "AI")).firstMatch
        #else
        app.menuItems.containing(.image, identifier: symbol).firstMatch
        #endif
    }

    /// An item of the open menu by its title, for items without a symbol.
    func menuItem(label: String) -> XCUIElement {
        #if os(iOS)
        app.collectionViews.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        #else
        app.menuItems.matching(NSPredicate(format: "title == %@", label)).firstMatch
        #endif
    }

    #if os(iOS)
    /// Closes an open menu with a tap on empty canvas, above the map's topics.
    func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
    }
    #endif

    func dismissPopover() {
        #if os(iOS)
        // A popover on iPad, a sheet on iPhone: a tap outside or a swipe down closes either.
        let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.exists { dismiss.tapOrClick() } else { app.swipeDown() }
        #else
        app.typeKey(.escape, modifierFlags: [])
        #endif
    }
}
