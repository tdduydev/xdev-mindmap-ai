import XCTest
#if os(macOS)
import AppKit
#endif

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
        let editor = openFitted(title, in: launched)
        capture("01-canvas", in: launched.app)

        // Review the mock model's proposed topics without changing the map.
        editor.show(.outline)
        commit(editor.selectOutlineTopic(title))
        openAIMenu(in: launched.app)
        let suggestTitle = language == .vietnamese ? "Đề xuất chủ đề con" : "Suggest Subtopics"
        #if os(macOS)
        // A menu item on the Mac, whose name is its title.
        let suggest = launched.app.menuItems.matching(NSPredicate(format: "title == %@", suggestTitle)).firstMatch
        #else
        let suggest = launched.app.buttons.matching(NSPredicate(format: "label == %@", suggestTitle)).firstMatch
        #endif
        suggest.waitToExist().tapOrClick()
        launched.app.buttons[AccessibilityID.Suggestions.review].firstMatch.waitToExist().tapOrClick()
        capture("02-ai-suggestions", in: launched.app)

        // A fresh launch closes the proposal while preserving the original fixture.
        let second = MindMapApp.launch(fixture: fixture, language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance])
        let outline = openFitted(title, in: second).show(.outline)
        let design = language == .vietnamese ? "Thiết kế" : "Design"
        commit(outline.selectOutlineTopic(design))
        capture("03-outline", in: second.app)

        let third = MindMapApp.launch(fixture: fixture, language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance])
        openFitted(title, in: third)
        let chat = ChatPage(app: third.app)
        chat.open(label: language == .vietnamese ? "Hỏi về sơ đồ này" : "Ask About This Map")
        chat.ask(language == .vietnamese ? "Thiết kế gồm những gì?" : "What is in Design?")
        chat.answers.firstMatch.waitToExist()
        // The Ask button returns once the answer is complete, replacing Stop.
        chat.sendButton.waitToExist()
        #if os(iOS)
        if third.app.keyboards.firstMatch.exists {
            third.app.descendants(matching: .any)[AccessibilityID.Chat.panel].scrollViews.firstMatch.swipeUp()
            _ = third.app.keyboards.firstMatch.waitForNonExistence(timeout: MindMapApp.timeout / 6)
        }
        #endif
        capture("04-ask-map", in: third.app)

        let fourth = MindMapApp.launch(fixture: fixture, language: language,
            arguments: [UITestLaunch.ai, UITestAI.ready.rawValue, "-appearance", appearance])
        fourth.openSettings().show(.privacy)
        fourth.app.descendants(matching: .any)[AccessibilityID.Settings.privacyAI].firstMatch.waitToExist()
        capture("05-privacy", in: fourth.app)
    }

    @MainActor
    private func capture(_ name: String, in app: XCUIApplication) {
        #if os(macOS)
        dismissSystemPrompts()
        let attachment = XCTAttachment(data: windowsPNG(of: app), uniformTypeIdentifier: "public.png")
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(macOS)
    /// The Mac is shared: another app's permission prompt or crash report can
    /// float over the window. Each is answered with its refusing button.
    @MainActor
    private func dismissSystemPrompts() {
        // CoreServicesUIAgent is left out: XCUIApplication raises when that agent
        // is not running, which ends the whole capture (3/10 on macOS 27).
        let agents = ["com.apple.UserNotificationCenter"]
        let refusals = NSPredicate(format: "title IN %@ OR label IN %@",
                                   ["Don’t Allow", "Don't Allow", "Deny", "Ignore"],
                                   ["Don’t Allow", "Don't Allow", "Deny", "Ignore"])
        for agent in agents {
            let prompt = XCUIApplication(bundleIdentifier: agent)
            guard prompt.state == .runningForeground || prompt.state == .runningBackground else { continue }
            // A few prompts can queue up; a button that ignores the click stops the loop.
            for _ in 0..<5 {
                let button = prompt.buttons.matching(refusals).firstMatch
                guard button.exists else { break }
                button.click()
            }
        }
    }

    /// The app's windows cut out of the screen: a whole-screen capture shows
    /// the desktop and other apps, and one window alone would leave Settings
    /// out of 05-privacy. Element frames and the image both start top left.
    @MainActor
    private func windowsPNG(of app: XCUIApplication) -> Data {
        let frames = app.windows.allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty }
        let screen = XCUIScreen.main.screenshot()
        guard let first = frames.first,
              let image = screen.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let points = NSScreen.main?.frame.width else {
            return screen.pngRepresentation
        }
        let scale = CGFloat(image.width) / points
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let pixels = CGRect(x: union.minX * scale, y: union.minY * scale,
                            width: union.width * scale, height: union.height * scale).integral
        guard let cropped = image.cropping(to: pixels) else { return screen.pngRepresentation }
        let bitmap = NSBitmapImageRep(cgImage: cropped)
        return bitmap.representation(using: .png, properties: [:]) ?? screen.pngRepresentation
    }
    #endif

    /// Opens the map on the canvas, fitted. On iOS 27 a map opened at its
    /// last zoom cuts the leaf topics at both edges, and until Zoom to Fit
    /// runs the View As picker ignores taps (seen on iPhone and iPad, MM-87).
    @MainActor
    @discardableResult
    private func openFitted(_ title: String, in launched: MindMapApp) -> EditorPage {
        let editor = launched.library.show().open(title).show(.canvas)
        editor.canvasTopics.firstMatch.waitToExist()
        launched.app.buttons[AccessibilityID.Canvas.zoomToFit].firstMatch.waitToExist().tapOrClick()
        waitUntilVisible(editor.canvasTopics, in: launched.app)
        return editor
    }

    /// Waits for Zoom to Fit to settle: every topic inside the window.
    @MainActor
    private func waitUntilVisible(_ topics: XCUIElementQuery, in app: XCUIApplication) {
        let inside = NSPredicate { _, _ in
            let window = app.windows.firstMatch.frame
            return topics.allElementsBoundByIndex.allSatisfy { window.contains($0.frame) }
        }
        let expectation = XCTNSPredicateExpectation(predicate: inside, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: MindMapApp.timeout / 3), .completed,
                       "Zoom to Fit left a topic outside the window")
    }

    /// iPhone puts the selected row into editing and raises the keyboard, which
    /// would cover the capture; iPad sometimes selects the row without focus,
    /// where typing fails, so Return is sent only to a focused field.
    @MainActor
    private func commit(_ field: XCUIElement) {
        if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
            field.typeText("\n")
        }
    }

    @MainActor
    private func openAIMenu(in app: XCUIApplication) {
        #if os(macOS)
        // A pull-down menu is a menu button on the Mac, not a button.
        app.menuButtons[AccessibilityID.Editor.ai].firstMatch.waitToExist().tapOrClick()
        #else
        // MapEditorView names the toolbar menu editor.ai, over AIToolbarMenu's own identifier.
        let menu = app.buttons[AccessibilityID.Editor.ai].firstMatch
        if !menu.waitForExistence(timeout: MindMapApp.timeout / 6) {
            app.buttons["OverflowBarButtonItem"].firstMatch.waitToExist().tapOrClick()
            app.collectionViews.buttons.matching(NSPredicate(format: "label == 'AI'")).firstMatch.waitToExist().tapOrClick()
            return
        }
        menu.tapOrClick()
        #endif
    }
}
