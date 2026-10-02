import XCTest

/// Opt-in capture; the store, AI and preferences are isolated by the UI test mode.
final class AppStoreScreenshotUITests: XCTestCase {
    @MainActor
    func testCapture() throws {
        let values = ProcessInfo.processInfo.environment
        guard values["MINDMAP_STORE_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Run with scripts/app-store-screenshots.sh")
        }
        let language: MindMapApp.Language = values["MINDMAP_SCREENSHOT_LANGUAGE"] == "vi" ? .vietnamese : .english
        let appearance = values["MINDMAP_SCREENSHOT_APPEARANCE"] == "dark" ? "dark" : "light"
        let fixture: UITestFixture = language == .vietnamese ? .showcaseVi : .showcaseEn
        let title = UITestFixture.Title.showcase(language.rawValue)
        let launched = MindMapApp.launch(
            fixture: fixture,
            language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance]
        )
        let editor = launched.library.show().open(title).show(.canvas)
        editor.canvasTopics.firstMatch.waitToExist()
        capture("01-canvas", in: launched.app)

        // Review the mock model's proposed topics without changing the map.
        editor.show(.outline)
        editor.selectOutlineTopic(title).typeText("\n")
        openAIMenu(in: launched.app)
        let suggest = launched.app.buttons.matching(NSPredicate(format: "label == %@", language == .vietnamese ? "Đề xuất chủ đề con" : "Suggest Subtopics")).firstMatch
        suggest.waitToExist().tap()
        launched.app.buttons[AccessibilityID.ScreenshotAI.review].firstMatch.waitToExist().tap()
        capture("02-ai-suggestions", in: launched.app)

        // A fresh launch closes the proposal while preserving the original fixture.
        let second = MindMapApp.launch(fixture: fixture, language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance])
        let outline = second.library.show().open(title).show(.outline)
        let design = language == .vietnamese ? "Thiết kế" : "Design"
        outline.selectOutlineTopic(design).typeText("\n")
        capture("03-outline", in: second.app)

        let third = MindMapApp.launch(fixture: fixture, language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance])
        third.library.show().open(title).show(.canvas)
        let chat = ChatPage(app: third.app)
        chat.open(label: language == .vietnamese ? "Hỏi về sơ đồ này" : "Ask About This Map")
        chat.ask(language == .vietnamese ? "Thiết kế gồm những gì?" : "What is in Design?")
        chat.answers.firstMatch.waitToExist()
        capture("04-ask-map", in: third.app)

        let fourth = MindMapApp.launch(fixture: fixture, language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance])
        fourth.openSettings().show(.privacy)
        fourth.app.descendants(matching: .any)[AccessibilityID.Settings.privacyAI].firstMatch.waitToExist()
        capture("05-privacy", in: fourth.app)
    }

    @MainActor
    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openAIMenu(in app: XCUIApplication) {
        let menu = app.buttons[AccessibilityID.ScreenshotAI.menu].firstMatch
        #if os(iOS)
        if !menu.waitForExistence(timeout: MindMapApp.timeout / 6) {
            app.buttons["OverflowBarButtonItem"].firstMatch.waitToExist().tap()
            app.collectionViews.buttons.matching(NSPredicate(format: "label == 'AI'")).firstMatch.waitToExist().tap()
            return
        }
        #endif
        menu.waitToExist().tap()
    }
}
