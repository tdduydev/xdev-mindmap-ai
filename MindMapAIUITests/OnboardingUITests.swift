import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    func testFirstLaunchOpensLocalizedSampleAndCanSkip() {
        for language in [MindMapApp.Language.english, .vietnamese, .japanese] {
            let app = MindMapApp.launch(
                fixture: .empty, language: language,
                arguments: ["-onboarding.completed", "NO"]
            )
            app.app.buttons[AccessibilityID.Onboarding.skip].waitToExist().tapOrClick()
            app.editor.canvasTopic(UITestFixture.Title.showcase(language.rawValue)).waitToExist()
            app.app.terminate()
        }
    }

    func testThreePagesAndOnlyOnce() {
        let first = MindMapApp.launch(
            fixture: .empty,
            arguments: ["-onboarding.completed", "NO"]
        )
        let next = first.app.buttons[AccessibilityID.Onboarding.next].waitToExist()
        next.tapOrClick()
        next.tapOrClick()
        first.app.staticTexts["Explore More"].waitToExist()
        next.tapOrClick()
        XCTAssertFalse(first.app.buttons[AccessibilityID.Onboarding.skip].exists)
        first.app.terminate()

        let second = MindMapApp.launch(fixture: .empty, arguments: [UITestLaunch.preserveDefaults])
        second.library.show()
        XCTAssertFalse(second.app.buttons[AccessibilityID.Onboarding.skip].exists)
    }

    func testExistingMapsDoNotShowOnboarding() {
        let app = MindMapApp.launch(
            fixture: .sample,
            arguments: ["-onboarding.completed", "NO"]
        )
        app.library.show().map(titled: UITestFixture.Title.plan).waitToExist()
        XCTAssertFalse(app.app.buttons[AccessibilityID.Onboarding.skip].exists)
        XCTAssertFalse(app.library.map(titled: UITestFixture.Title.showcase("en")).exists)
    }
}
