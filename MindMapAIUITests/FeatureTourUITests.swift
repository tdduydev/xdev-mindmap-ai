import XCTest

/// The feature tour (MM-71): walks through every feature on main, one step
/// at a time, and keeps a screenshot of each step named "NN-feature", for the
/// product owner to look at. Each step checks one thing; a failed step is
/// recorded and the tour goes on, so one run shows everything that works.
///
/// Off unless `MINDMAP_FEATURE_TOUR=1` reaches the runner, so
/// scripts/ui-tests.sh skips it: run scripts/feature-tour.sh [ios|macos] [en|vi],
/// which also sets `MINDMAP_FEATURE_TOUR_LANGUAGE` and exports the screenshots.
/// Steps tell views apart by identifier, position or fixture title, never by
/// interface text, so the same tour runs in English and Vietnamese.
///
/// Test methods run in name order and each launches the app again; the
/// paywall comes before AI and voice, which are Pro features.
final class FeatureTourUITests: XCTestCase {
    private var language = MindMapApp.Language.english
    private var currentTour: Tour?

    /// Made on first use, on the main actor where XCUITest runs.
    @MainActor private var tour: Tour {
        if let currentTour { return currentTour }
        let tour = Tour(test: self, language: language)
        currentTour = tour
        return tour
    }

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["MINDMAP_FEATURE_TOUR"] == "1", "The feature tour runs from scripts/feature-tour.sh")
        continueAfterFailure = true
        language = environment["MINDMAP_FEATURE_TOUR_LANGUAGE"].flatMap(MindMapApp.Language.init(rawValue:)) ?? .english
        currentTour = nil
    }

    // MARK: Library

    @MainActor
    func test01Library() {
        tour.launch(fixture: .empty)
        tour.step("01-library-empty") { app in
            let library = app.library.show()
            library.maps.waitForCount(0)
            library.newMapButton.waitToExist()
        }

        tour.launch(fixture: .sample)
        tour.step("02-library-maps") { app in
            app.library.show().maps.waitForCount(2)
        }
        tour.step("03-library-favorites") { app in
            let library = app.library.select(.favorites)
            library.maps.waitForCount(1)
            library.map(titled: UITestFixture.Title.favorite).waitToExist()
        }
        tour.step("04-library-recent") { app in
            app.library.select(.recent).list.waitToExist()
        }
        tour.step("05-library-search") { app in
            // "Interviews" is a topic of Product Launch, not a map title.
            let library = app.library.select(.all).search(UITestFixture.Title.interviews.lowercased())
            library.maps.waitForCount(1)
            library.map(titled: UITestFixture.Title.plan).waitToExist()
        }

        tour.launch(fixture: .sample)
        tour.step("06-library-recently-deleted") { app in
            let library = app.library.show()
            let row = library.map(titled: UITestFixture.Title.favorite).waitToExist()
            #if os(iOS)
            row.swipeLeft()
            app.app.buttons[AccessibilityID.Library.delete].firstMatch.waitToExist().tapOrClick()
            #else
            row.click()
            app.app.typeKey(.delete, modifierFlags: .command)
            #endif
            library.maps.waitForCount(1)
            library.select(.recentlyDeleted).maps.waitForCount(1)
            library.map(titled: UITestFixture.Title.favorite).waitToExist()
        }
        tour.step("07-create-map") { app in
            let editor = app.library.select(.all).createMap()
            editor.show(.canvas)
            editor.canvasTopics.firstMatch.waitToExist()
        }
    }

    // MARK: Canvas

    @MainActor
    func test02Canvas() {
        let editor = tour.openPlan(.canvas)
        tour.step("08-canvas") { _ in
            editor.canvasTopics.waitForCount(5)
        }
        tour.step("09-canvas-select") { _ in
            let design = editor.canvasTopic(UITestFixture.Title.design).waitToExist()
            design.tapOrClick()
            XCTAssertTrue(editor.canvasTopic(UITestFixture.Title.design).waitForSelection(), "Design is not selected")
        }
        tour.step("10-canvas-add-buttons") { _ in
            // The + buttons around a selected topic are drawn, not accessibility
            // elements; the screenshot shows them while Design stays selected.
            XCTAssertTrue(editor.canvasTopic(UITestFixture.Title.design).isSelected)
        }
        tour.step("11-canvas-rename") { app in
            editor.canvasTopic(UITestFixture.Title.design).waitToExist().doubleTapOrClick()
            let field = editor.canvas.textFields.firstMatch.waitToExist()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: UITestFixture.Title.design.count + 2) + "Prototype\n")
            editor.canvasTopic("Prototype").waitToExist()
        }
        tour.step("12-canvas-add-child") { app in
            editor.canvasTopic("Prototype").waitToExist().tapOrClick()
            editor.tap(.addChild)
            editor.canvasTopics.waitForCount(6)
            tour.finishTyping("Mockups")
        }
        tour.step("13-canvas-add-sibling") { app in
            editor.tap(.addSibling)
            editor.canvasTopics.waitForCount(7)
            tour.finishTyping("Usability Test")
        }
        tour.step("14-canvas-collapse") { _ in
            // Collapsing is a topic action on the canvas (VoiceOver, context
            // menu); the outline's disclosure sets the same state.
            editor.show(.outline)
            editor.outlineDisclosures.firstMatch.waitToExist()
            editor.outlineDisclosures.element(boundBy: 1).tapOrClick()
            editor.show(.canvas)
            editor.canvasTopic(UITestFixture.Title.research).waitToExist()
            XCTAssertFalse(editor.canvasTopic(UITestFixture.Title.interviews).exists, "Interviews still shows under collapsed Research")
        }
        tour.step("15-canvas-zoom") { app in
            let level = app.app.buttons[AccessibilityID.Canvas.actualSize].firstMatch.waitToExist()
            let before = level.value as? String
            app.app.buttons[AccessibilityID.Canvas.zoomIn].firstMatch.waitToExist().tapOrClick()
            app.app.buttons[AccessibilityID.Canvas.zoomIn].firstMatch.tapOrClick()
            XCTAssertNotEqual(level.value as? String, before, "zoom level stayed \(before ?? "")")
        }
        tour.step("16-canvas-zoom-to-fit") { app in
            app.app.buttons[AccessibilityID.Canvas.zoomToFit].firstMatch.waitToExist().tapOrClick()
            editor.canvasTopic(UITestFixture.Title.plan).waitToExist()
        }
    }

    // MARK: Outline

    @MainActor
    func test03Outline() {
        let editor = tour.openPlan(.outline)
        tour.step("17-outline") { _ in
            editor.outlineTopics.waitForCount(5)
        }
        tour.step("18-outline-rename") { _ in
            editor.renameOutlineTopic(UITestFixture.Title.marketing, to: "Launch Event")
            editor.outlineTopic(titled: "Launch Event").waitToExist()
        }
        tour.step("19-outline-undo") { _ in
            editor.undoButton.waitToExist().tapOrClick()
            editor.outlineTopic(titled: UITestFixture.Title.marketing).waitToExist()
        }
        tour.step("20-outline-redo") { _ in
            editor.redoButton.waitToExist().tapOrClick()
            editor.outlineTopic(titled: "Launch Event").waitToExist()
        }
        tour.step("21-outline-collapse") { _ in
            editor.outlineDisclosures.waitForCount(2)
            editor.outlineDisclosures.element(boundBy: 1).tapOrClick()
            editor.outlineTopics.waitForCount(4)
        }
    }

    // MARK: Inspector

    @MainActor
    func test04Inspector() {
        let editor = tour.openPlan(.outline)
        tour.step("22-inspector") { app in
            editor.selectOutlineTopic(UITestFixture.Title.design)
            editor.tap(.inspector)
            app.app.textViews[AccessibilityID.Inspector.note].firstMatch.waitToExist()
        }
        tour.step("23-inspector-note") { app in
            let note = app.app.textViews[AccessibilityID.Inspector.note].firstMatch.waitToExist()
            note.tapOrClick()
            note.typeText("Ask five customers first.")
            XCTAssertTrue((note.value as? String ?? "").contains("five customers"), "note reads \(note.value ?? "")")
        }
        tour.step("24-inspector-link") { app in
            let field = app.app.textFields[AccessibilityID.Link.field].firstMatch.waitToExist()
            field.tapOrClick()
            field.typeText("example.com/design\n")
            app.app.buttons[AccessibilityID.Link.open].firstMatch.waitToExist()
        }
        tour.step("25-inspector-tag") { app in
            let field = app.app.textFields[AccessibilityID.Inspector.tagField].firstMatch
            tour.scrollTo(field)
            field.waitToExist().tapOrClick()
            field.typeText("launch\n")
            app.app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "launch")).firstMatch.waitToExist()
        }
        tour.step("26-inspector-theme") { app in
            let theme = app.app.descendants(matching: .any)[AccessibilityID.Inspector.theme].firstMatch
            tour.scrollTo(theme)
            theme.waitToExist()
        }
    }

    // MARK: Find

    @MainActor
    func test05Find() {
        let editor = tour.openPlan(.outline)
        tour.step("27-find") { _ in
            editor.find("e")
            editor.findStatus.waitToExist()
        }
        tour.step("28-find-next") { _ in
            let before = editor.findStatus.shownText
            editor.findNextButton.waitToExist().tapOrClick()
            XCTAssertNotEqual(editor.findStatus.shownText, before, "Next did not move from \(before)")
        }
        tour.step("29-find-no-results") { _ in
            editor.findField.typeText("zzzz")
            editor.findNextButton.waitToExist()
            XCTAssertFalse(editor.findNextButton.isEnabled, "Next is enabled with no results")
        }
    }

    // MARK: Pro (before the Pro features below)

    @MainActor
    func test06Paywall() {
        tour.launch(fixture: .sample)
        var isUnlocked = false
        tour.step("30-settings-pro") { app in
            app.openSettings().show(.pro)
            // StoreKit Testing keeps a purchase on the simulator between runs;
            // then the pane says Unlocked and has no paywall button.
            isUnlocked = !app.app.buttons[AccessibilityID.Settings.showPaywall].firstMatch
                .waitForExistence(timeout: MindMapApp.timeout / 3)
        }
        guard !isUnlocked else { return }
        tour.step("31-paywall") { app in
            app.app.buttons[AccessibilityID.Settings.showPaywall].firstMatch.tapOrClick()
            // The price comes from MindMapAITests/MindMapAI.storekit, which
            // the MindMapAIUITests scheme runs the app with.
            app.app.buttons[AccessibilityID.Paywall.purchase].firstMatch.waitToExist()
        }
        tour.step("32-paywall-purchase") { app in
            app.app.buttons[AccessibilityID.Paywall.purchase].firstMatch.tapOrClick()
            tour.confirmStoreKitPurchase()
            // Unlocked, the paywall shows a thank-you instead of the button.
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.app.buttons[AccessibilityID.Paywall.purchase].firstMatch)
            XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: MindMapApp.timeout), .completed, "Pro did not unlock")
        }
    }

    // MARK: AI

    @MainActor
    func test07AI() {
        let editor = tour.openPlan(.canvas, ai: .ready)
        tour.step("33-ai-menu") { app in
            editor.canvasTopic(UITestFixture.Title.design).waitToExist().tapOrClick()
            tour.openAIMenu()
            tour.menuItem(symbol: "arrow.turn.down.right").waitToExist()
        }
        tour.step("34-ai-expand") { app in
            tour.menuItem(symbol: "arrow.turn.down.right").tapOrClick()
            app.app.buttons[AccessibilityID.Suggestions.acceptAll].firstMatch.waitToExist()
            editor.canvasTopics.waitForCount(5 + UITestAI.subtopics.count)
        }
        tour.step("35-ai-review") { app in
            app.app.buttons[AccessibilityID.Suggestions.review].firstMatch.waitToExist().tapOrClick()
            app.app.buttons.matching(identifier: AccessibilityID.Suggestions.discard).waitForCount(UITestAI.subtopics.count)
        }
        tour.step("36-ai-discard-one") { app in
            app.app.buttons.matching(identifier: AccessibilityID.Suggestions.discard).element(boundBy: 0).tapOrClick()
            app.app.buttons.matching(identifier: AccessibilityID.Suggestions.discard).waitForCount(UITestAI.subtopics.count - 1)
            tour.dismissPopover()
        }
        tour.step("37-ai-accept") { app in
            app.app.buttons[AccessibilityID.Suggestions.acceptAll].firstMatch.waitToExist().tapOrClick()
            editor.canvasTopic(UITestAI.subtopics[1]).waitToExist()
            XCTAssertFalse(app.app.buttons[AccessibilityID.Suggestions.acceptAll].firstMatch.exists)
        }
        tour.step("38-ai-undo") { _ in
            editor.undoButton.waitToExist().tapOrClick()
            editor.canvasTopics.waitForCount(5)
        }
        tour.step("39-ai-discard-all") { app in
            editor.canvasTopic(UITestFixture.Title.marketing).waitToExist().tapOrClick()
            tour.openAIMenu()
            tour.menuItem(symbol: "arrow.turn.down.right").waitToExist().tapOrClick()
            app.app.buttons[AccessibilityID.Suggestions.discardAll].firstMatch.waitToExist().tapOrClick()
            editor.canvasTopics.waitForCount(5)
        }
    }

    // MARK: Chat

    @MainActor
    func test08Chat() {
        let editor = tour.openPlan(.canvas, ai: .ready)
        let chat = ChatPage(app: editor.app)
        tour.step("40-chat") { _ in
            // On iPhone the chat button moves into the More menu, where items
            // keep only their title; find it by symbol so Vietnamese works too.
            tour.tapToolbarItem(AccessibilityID.Chat.toolbar, symbol: "bubble.left.and.text.bubble.right")
            chat.field.waitToExist()
        }
        tour.step("41-chat-answer") { _ in
            chat.ask("Where are the interviews?")
            chat.citation(titled: UITestFixture.Title.interviews).waitToExist()
        }
    }

    // MARK: Theme

    @MainActor
    func test09Theme() {
        let editor = tour.openPlan(.canvas)
        tour.step("42-theme") { app in
            editor.tap(.inspector)
            let theme = app.app.descendants(matching: .any)[AccessibilityID.Inspector.theme].firstMatch
            tour.scrollTo(theme)
            theme.waitToExist()
            // The inline picker's rows, in `MindMapTheme` order: pick the second.
            // On iOS the identifier lands on the picker's "Theme" label and its
            // rows are the form's cells below it, not its children.
            let options = theme.buttons
            if options.count > 1 {
                options.element(boundBy: 1).tapOrClick()
            } else {
                // The picker is the form's last section; the sheet's own swipe
                // only grows it, so scroll the form itself to the end.
                let form = app.app.collectionViews.firstMatch
                for _ in 0..<3 { form.swipeUp() }
                let rows = app.app.collectionViews.cells.allElementsBoundByIndex
                    .filter { $0.frame.minY >= theme.frame.maxY - 1 }
                if rows.count > 1 { rows[1].tapOrClick() } else { XCTFail("no theme rows below \(theme)") }
            }
            editor.undoButton.waitToExist()
            XCTAssertTrue(editor.undoButton.isEnabled, "picking a theme left nothing to undo")
        }
        tour.step("43-theme-canvas") { app in
            tour.dismissInspector()
            editor.canvasTopic(UITestFixture.Title.plan).waitToExist()
        }
    }

    // MARK: Export and import

    @MainActor
    func test10Export() {
        let editor = tour.openPlan(.canvas)
        // ExportFormat order: Markdown, Plain Text, PNG, PDF, Backup.
        let formats = [("44-export-markdown", 0), ("45-export-png", 2), ("46-export-pdf", 3), ("47-export-backup", 4)]
        tour.step("44-export-markdown") { app in
            editor.tap(.export)
            app.app.buttons[AccessibilityID.Export.export].firstMatch.waitToExist()
        }
        for (name, index) in formats.dropFirst() {
            tour.step(name) { app in
                tour.pick(index, in: app.app.descendants(matching: .any)[AccessibilityID.Export.format].firstMatch)
                // PNG and PDF are Pro; this run has not bought it, so Export… may be off.
                app.app.buttons[AccessibilityID.Export.export].firstMatch.waitToExist()
            }
        }
        tour.step("48-export-save") { app in
            tour.pick(0, in: app.app.descendants(matching: .any)[AccessibilityID.Export.format].firstMatch)
            app.app.buttons[AccessibilityID.Export.export].firstMatch.tapOrClick()
            // The system's save panel or document picker.
            tour.waitForSystemFilePanel()
        }
        tour.dismissSystemFilePanel()
    }

    @MainActor
    func test11Import() {
        tour.launch(fixture: .sample)
        tour.step("49-import") { app in
            app.library.show()
            tour.tapToolbarItem(AccessibilityID.Library.importMap, symbol: "square.and.arrow.down")
            tour.waitForSystemFilePanel()
        }
        tour.dismissSystemFilePanel()
    }

    // MARK: Voice

    @MainActor
    func test12Voice() {
        let editor = tour.openPlan(.outline)
        tour.step("50-voice") { app in
            editor.selectOutlineTopic(UITestFixture.Title.marketing)
            editor.tap(.voice)
            app.app.buttons[AccessibilityID.Voice.addTopics].firstMatch.waitToExist()
        }
        tour.step("51-voice-heard") { app in
            // Pro is bought in test06Paywall; StoreKit Testing keeps it for the simulator.
            let listen = app.app.buttons[AccessibilityID.Voice.listen].firstMatch
            if listen.waitForExistence(timeout: MindMapApp.timeout / 6) { listen.tapOrClick() }
            app.app.textFields.matching(NSPredicate(format: "value == %@", UITestVoice.topics[0])).firstMatch.waitToExist()
        }
        tour.step("52-voice-added") { app in
            app.app.buttons[AccessibilityID.Voice.addTopics].firstMatch.tapOrClick()
            editor.outlineTopic(titled: UITestVoice.topics[1]).waitToExist()
        }
    }

    // MARK: Settings

    @MainActor
    func test13Settings() {
        tour.launch(fixture: .sample, ai: .ready)
        // A control each pane shows, when it has one with an identifier.
        let panes: [(String, SettingsPage.Pane?, String?)] = [
            ("53-settings", nil, nil),
            ("54-settings-general", .general, AccessibilityID.Settings.appearance),
            ("55-settings-export", .export, AccessibilityID.Settings.includeNotes),
            ("56-settings-ai", .ai, AccessibilityID.Settings.aiStatus),
            ("57-settings-data", .data, AccessibilityID.Settings.iCloudStatus),
            ("58-settings-pro", .pro, nil),
            ("59-settings-privacy", .privacy, AccessibilityID.Settings.privacyAI),
            ("60-settings-about", .about, nil),
        ]
        var settings: SettingsPage?
        for (name, pane, control) in panes {
            tour.step(name) { app in
                let page = settings ?? app.openSettings()
                settings = page
                guard let pane else { return }
                #if os(iOS)
                // Each pane is a page of its own: back to the list first.
                if !page.paneButton(pane).waitForExistence(timeout: MindMapApp.timeout / 6) {
                    app.app.navigationBars.buttons.element(boundBy: 0).tapOrClick()
                }
                #endif
                page.show(pane)
                if let control {
                    app.app.descendants(matching: .any)[control].firstMatch.waitToExist()
                }
            }
        }
        #if os(macOS)
        tour.step("61-settings-ai-apps") { app in
            (settings ?? app.openSettings()).show(.aiApps)
            app.app.descendants(matching: .any)[AccessibilityID.Settings.aiAppsSwitch].firstMatch.waitToExist()
        }
        #endif
    }
}

/// The steps of one tour test: each step's screenshot and pass or fail, as
/// attachments that scripts/feature-tour.sh reads back from the result bundle.
@MainActor
final class Tour {
    private unowned let test: XCTestCase
    let language: MindMapApp.Language
    private(set) var app: MindMapApp?

    init(test: XCTestCase, language: MindMapApp.Language) {
        self.test = test
        self.language = language
    }

    var xcApp: XCUIApplication { app?.app ?? XCUIApplication() }

    @discardableResult
    func launch(fixture: UITestFixture, ai: UITestAI? = nil) -> MindMapApp {
        app?.app.terminate()
        let arguments = ai.map { [UITestLaunch.ai, $0.rawValue] } ?? []
        let launched = MindMapApp.launch(fixture: fixture, language: language, arguments: arguments)
        app = launched
        return launched
    }

    /// Product Launch, open in `presentation`.
    func openPlan(_ presentation: EditorPage.Presentation, ai: UITestAI? = nil) -> EditorPage {
        launch(fixture: .sample, ai: ai).library.show().open(UITestFixture.Title.plan).show(presentation)
    }

    /// Runs `body`, then keeps a screenshot named `name` and whether the step
    /// passed, which is whether it recorded no new failure.
    func step(_ name: String, _ body: (MindMapApp) -> Void) {
        let before = test.testRun?.totalFailureCount ?? 0
        XCTContext.runActivity(named: name) { _ in
            if let app { body(app) } else { XCTFail("No app launched before \(name)") }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            test.add(screenshot)
        }
        let passed = (test.testRun?.totalFailureCount ?? 0) == before
        let result = XCTAttachment(string: passed ? "PASS" : "FAIL")
        result.name = "result.\(name)"
        result.lifetime = .keepAlways
        test.add(result)
    }

    /// Commits a topic that opened for typing: a new topic starts in its title field.
    func finishTyping(_ title: String) {
        #if os(iOS)
        guard xcApp.keyboards.firstMatch.waitForExistence(timeout: MindMapApp.timeout / 6) else { return }
        xcApp.typeText(title + "\n")
        #else
        xcApp.typeText(title + "\r")
        #endif
    }

    /// The toolbar's AI menu, from the toolbar or its More menu on iPhone.
    func openAIMenu() {
        let button = xcApp.buttons[AccessibilityID.Editor.ai].firstMatch
        if button.waitForExistence(timeout: MindMapApp.timeout / 6) {
            button.tapOrClick()
            return
        }
        #if os(iOS)
        // In the More menu the AI menu is a submenu titled AI, in both languages.
        let overflow = xcApp.buttons.matching(identifier: "OverflowBarButtonItem")
        overflow.element(boundBy: max(overflow.count - 1, 0)).waitToExist().tapOrClick()
        xcApp.buttons.matching(NSPredicate(format: "label == %@", "AI")).firstMatch.waitToExist().tapOrClick()
        #else
        button.waitToExist()
        #endif
    }

    /// An item of the open menu, by its SF Symbol, the same in every language.
    func menuItem(symbol: String) -> XCUIElement {
        #if os(iOS)
        xcApp.collectionViews.buttons.containing(.image, identifier: symbol).firstMatch
        #else
        xcApp.menuItems.containing(.image, identifier: symbol).firstMatch
        #endif
    }

    /// Taps a toolbar button by identifier, or finds it in the iPhone's More menu by symbol.
    func tapToolbarItem(_ identifier: String, symbol: String) {
        let button = xcApp.buttons[identifier].firstMatch
        #if os(iOS)
        if !button.waitForExistence(timeout: MindMapApp.timeout / 6) {
            let overflow = xcApp.buttons.matching(identifier: "OverflowBarButtonItem")
            overflow.element(boundBy: max(overflow.count - 1, 0)).waitToExist().tapOrClick()
            xcApp.collectionViews.buttons.containing(.image, identifier: symbol).firstMatch.waitToExist().tapOrClick()
            return
        }
        #endif
        button.waitToExist().tapOrClick()
    }

    /// Picks an option of a menu picker by position.
    func pick(_ index: Int, in picker: XCUIElement) {
        picker.waitToExist().tapOrClick()
        #if os(macOS)
        picker.menuItems.element(boundBy: index).waitToExist().tapOrClick()
        #else
        // The open menu is the only collection of buttons over the sheet.
        xcApp.collectionViews.buttons.element(boundBy: index).waitToExist().tapOrClick()
        #endif
    }

    /// Scrolls the inspector until `element` is on screen, when it is below.
    func scrollTo(_ element: XCUIElement) {
        #if os(iOS)
        for _ in 0..<4 where !(element.exists && element.isHittable) {
            xcApp.swipeUp()
        }
        #endif
    }

    func dismissPopover() {
        #if os(iOS)
        // A popover on iPad, a sheet on iPhone: a tap outside or a swipe down closes either.
        let dismiss = xcApp.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.exists { dismiss.tapOrClick() } else { xcApp.swipeDown() }
        #else
        xcApp.typeKey(.escape, modifierFlags: [])
        #endif
    }

    /// The inspector is a sheet on iPhone; beside the map elsewhere, it may stay.
    func dismissInspector() {
        #if os(iOS)
        // Narrower than an iPad's compact width: an iPhone, where it is a sheet.
        if xcApp.windows.firstMatch.frame.width < 500 { xcApp.swipeDown(velocity: .fast) }
        #endif
    }

    /// StoreKit Testing's purchase sheet: on iOS a system sheet with a
    /// Purchase or Subscribe button, outside the app's process.
    func confirmStoreKitPurchase() {
        #if os(iOS)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let buttons = [xcApp, springboard].map { $0.buttons.matching(NSPredicate(format: "label IN %@", ["Purchase", "Mua", "Subscribe", "Buy"])).firstMatch }
        let deadline = Date().addingTimeInterval(MindMapApp.timeout)
        while Date() < deadline {
            if let button = buttons.first(where: \.exists) {
                button.tapOrClick()
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        // "You're all set": the confirmation alert after a test purchase.
        let ok = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["OK", "Done"])).firstMatch
        if ok.waitForExistence(timeout: MindMapApp.timeout / 3) { ok.tapOrClick() }
        #endif
    }

    /// The document picker on iOS, the open or save panel on the Mac.
    func waitForSystemFilePanel() {
        #if os(iOS)
        let picker = xcApp.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'DOC'")).firstMatch
        let browser = xcApp.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'DOC' OR identifier CONTAINS 'FullDocumentManager'")).firstMatch
        let cancel = xcApp.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Hủy", "Huỷ"])).firstMatch
        let shown = [picker, browser, cancel].contains { $0.waitForExistence(timeout: MindMapApp.timeout / 3) }
        XCTAssertTrue(shown, "no document picker")
        #else
        XCTAssertTrue(xcApp.sheets.firstMatch.waitForExistence(timeout: MindMapApp.timeout / 3) || xcApp.dialogs.firstMatch.exists, "no file panel")
        #endif
    }

    func dismissSystemFilePanel() {
        #if os(iOS)
        let cancel = xcApp.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Hủy", "Huỷ"])).firstMatch
        if cancel.waitForExistence(timeout: MindMapApp.timeout / 6) { cancel.tapOrClick() }
        #else
        xcApp.typeKey(.escape, modifierFlags: [])
        #endif
    }
}

@MainActor
extension EditorPage {
    /// A topic on the canvas; its label is its title.
    func canvasTopic(_ title: String) -> XCUIElement {
        canvasTopics.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }
}

@MainActor
extension XCUIElement {
    /// `doubleTap()` is a touch, which macOS 27 never delivers (see `tapOrClick()`).
    func doubleTapOrClick() {
        #if os(macOS)
        doubleClick()
        #else
        doubleTap()
        #endif
    }

    /// Waits until the element is selected.
    func waitForSelection(timeout: TimeInterval = MindMapApp.timeout / 3) -> Bool {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter().wait(for: [selected], timeout: timeout) == .completed
    }
}
