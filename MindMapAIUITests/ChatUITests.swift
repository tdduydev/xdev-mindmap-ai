import XCTest

/// Ask About This Map with the UI test mode's scripted model (`-uitest-ai`),
/// which cites the first topic whose title matches a word of the question.
final class ChatUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openPlan(ai: UITestAI = .ready, language: MindMapApp.Language = .english) -> MindMapApp {
        let app = MindMapApp.launch(fixture: .sample, language: language, arguments: [UITestLaunch.ai, ai.rawValue])
        app.library.show().open(UITestFixture.Title.plan).show(.canvas)
        return app
    }

    @MainActor
    func testAskAndOpenTheCitedTopic() {
        let app = openPlan()
        let chat = ChatPage(app: app.app)

        chat.open()
        chat.ask("Where are the interviews?")

        let citation = chat.citation(titled: UITestFixture.Title.interviews).waitToExist()
        XCTAssertTrue(chat.answers.firstMatch.shownText.contains(UITestFixture.Title.interviews))
        citation.tapOrClick()
        #if os(macOS)
        // Beside the map on the Mac, the panel stays while the topic is shown.
        XCTAssertTrue(chat.field.exists)
        #endif
    }

    @MainActor
    func testAQuestionTheMapDoesNotCoverSaysSo() {
        let app = openPlan()
        let chat = ChatPage(app: app.app)

        chat.open()
        chat.ask("Weather?")

        let answer = chat.answers.firstMatch.waitToExist()
        XCTAssertEqual(answer.shownText, "The map does not seem to cover that.")
        XCTAssertFalse(chat.citations.firstMatch.exists)
        // MM-82: reading the question's label crashed the Mac app (an
        // accessibility recursion between SwiftUI and AppKit).
        XCTAssertTrue(chat.question(containing: "Weather?").exists)
    }

    /// MM-78: an empty chat offers questions that ask at once, and the scope
    /// starts at the whole map.
    @MainActor
    func testASuggestedQuestionAsksAtOnce() {
        let app = openPlan()
        let chat = ChatPage(app: app.app)

        chat.open()
        XCTAssertTrue(chat.scope.waitToExist().exists)
        let suggestion = chat.suggestions.firstMatch.waitToExist()
        XCTAssertEqual(chat.suggestions.count, 3)
        suggestion.tapOrClick()

        chat.answers.firstMatch.waitToExist()
        XCTAssertFalse(chat.suggestions.firstMatch.exists, "suggestions are for an empty chat")
    }

    @MainActor
    func testHiddenWhereAppleIntelligenceCannotRun() {
        let app = openPlan(ai: .ineligible)

        XCTAssertNil(ChatPage(app: app.app).entryPoint(timeout: MindMapApp.timeout / 6))
    }

    @MainActor
    func testVietnamese() {
        let app = openPlan(language: .vietnamese)
        let chat = ChatPage(app: app.app)

        XCTAssertNotNil(chat.entryPoint(label: "Hỏi về sơ đồ này"))
    }

    #if os(macOS)
    @MainActor
    func testControlCommandAOpensTheChatFromTheKeyboard() {
        let app = openPlan()
        let chat = ChatPage(app: app.app)

        app.app.typeKey("a", modifierFlags: [.command, .control])

        chat.field.waitToExist()
        XCTAssertTrue(app.app.menuItems["Ask About This Map…"].exists)
    }
    #endif
}

/// The chat panel: beside the map on the Mac and iPad, a sheet on iPhone.
@MainActor
struct ChatPage {
    let app: XCUIApplication

    var toolbarButton: XCUIElement { app.buttons[AccessibilityID.Chat.toolbar].firstMatch }
    var field: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Chat.field].firstMatch }
    var sendButton: XCUIElement { app.buttons[AccessibilityID.Chat.send].firstMatch }
    var answers: XCUIElementQuery { app.staticTexts.matching(identifier: AccessibilityID.Chat.answer) }
    var citations: XCUIElementQuery { app.buttons.matching(identifier: AccessibilityID.Chat.citation) }
    var suggestions: XCUIElementQuery { app.buttons.matching(identifier: AccessibilityID.Chat.suggestion) }
    var scope: XCUIElement { app.descendants(matching: .any)[AccessibilityID.Chat.scope].firstMatch }

    /// A question bubble, which VoiceOver reads as "You asked: …". The Mac
    /// puts that text in `value`, iOS in `label`.
    func question(containing text: String) -> XCUIElement {
        let asked = "You asked: \(text)"
        return app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", asked, asked)).firstMatch
    }

    func citation(titled title: String) -> XCUIElement {
        citations.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// The toolbar's chat button. A narrow window moves it into the toolbar's
    /// More menu, which this opens first. Nil when there is no chat.
    /// The More menu lists items by title only, so `label` finds it there.
    func entryPoint(label: String = "Ask About This Map", timeout: TimeInterval = MindMapApp.timeout / 3) -> XCUIElement? {
        if toolbarButton.waitForExistence(timeout: timeout) { return toolbarButton }
        let overflow = app.buttons.matching(identifier: "OverflowBarButtonItem")
        guard overflow.count > 0 else { return nil }
        overflow.element(boundBy: overflow.count - 1).tapOrClick()
        let item = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if item.waitForExistence(timeout: timeout) { return item }
        // Close the menu again, so the test sees the editor as it was.
        app.tapOrClick()
        return nil
    }

    func open(label: String = "Ask About This Map", file: StaticString = #filePath, line: UInt = #line) {
        guard let entry = entryPoint(label: label) else {
            XCTFail("No Ask About This Map button", file: file, line: line)
            return
        }
        entry.tapOrClick()
        field.waitToExist(file: file, line: line)
    }

    func ask(_ question: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = field.waitToExist(file: file, line: line)
        field.tapOrClick()
        field.typeText(question)
        sendButton.waitToExist(file: file, line: line).tapOrClick()
    }
}
