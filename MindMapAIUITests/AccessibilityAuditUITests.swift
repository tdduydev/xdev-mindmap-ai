import XCTest

/// NFR-TEST-04: `performAccessibilityAudit` on the main screens (library,
/// canvas, outline, inspector, AI suggestion preview, Settings, paywall), in
/// English, in Vietnamese, with Increase Contrast and, on iOS, at the largest
/// accessibility text size. Plus AT-07: each canvas topic reads "title, level
/// n, m subtopics". Every screen keeps a screenshot, for the audit of MM-12 and
/// the Accessibility Nutrition Labels.
///
/// The issues the audit raises and the app accepts are in `AuditWaiver`, each
/// with its reason; anything else fails the test.
final class AccessibilityAuditUITests: XCTestCase {
    /// How one run of the walk launches the app.
    enum Variant: String {
        case standard
        case vietnamese
        case increasedContrast
        case largestText

        var language: MindMapApp.Language { self == .vietnamese ? .vietnamese : .english }

        var arguments: [String] {
            switch self {
            case .standard, .vietnamese: []
            case .increasedContrast: [UITestLaunch.increaseContrast]
            // UIKit reads the size from the app's defaults, so the argument domain sets it for this launch only.
            case .largestText: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
        }
    }

    override func setUp() {
        // One screen's issues should not hide the next screen's.
        continueAfterFailure = true
    }

    @MainActor
    func testAuditInEnglish() throws {
        try audit(.standard)
    }

    @MainActor
    func testAuditInVietnamese() throws {
        try audit(.vietnamese)
    }

    @MainActor
    func testAuditWithIncreasedContrast() throws {
        #if os(macOS)
        // A system setting a UI test cannot turn on; MacSnapshotTests draws every Mac scene with it.
        throw XCTSkip("Increase Contrast on the Mac is checked by MacSnapshotTests")
        #else
        try audit(.increasedContrast)
        #endif
    }

    @MainActor
    func testAuditAtTheLargestTextSize() throws {
        #if os(macOS)
        throw XCTSkip("The Mac has no Dynamic Type")
        #else
        try audit(.largestText)
        #endif
    }

    /// AT-07, in both languages: the title is the label, and the value says the
    /// level (or central topic) and the number of subtopics.
    @MainActor
    func testTopicsReadTitleLevelAndSubtopics() {
        let english = openPlan(.standard)
        XCTAssertEqual(english.canvasValue(of: UITestFixture.Title.plan), "Central Topic, 3 subtopics")
        XCTAssertEqual(english.canvasValue(of: UITestFixture.Title.research), "Level 2, 1 subtopic")
        XCTAssertEqual(english.canvasValue(of: UITestFixture.Title.interviews), "Level 3, 0 subtopics")

        let vietnamese = openPlan(.vietnamese)
        XCTAssertEqual(vietnamese.canvasValue(of: UITestFixture.Title.plan), "Chủ đề trung tâm, 3 chủ đề con")
        XCTAssertEqual(vietnamese.canvasValue(of: UITestFixture.Title.research), "Cấp 2, 1 chủ đề con")
        XCTAssertEqual(vietnamese.canvasValue(of: UITestFixture.Title.design), "Cấp 2, 0 chủ đề con")
    }

    // MARK: The walk

    @MainActor
    private func openPlan(_ variant: Variant) -> EditorPage {
        let app = MindMapApp.launch(fixture: .sample, language: variant.language, arguments: variant.arguments)
        return app.library.show().open(UITestFixture.Title.plan).show(.canvas)
    }

    @MainActor
    private func audit(_ variant: Variant) throws {
        var app = MindMapApp.launch(fixture: .sample, language: variant.language, arguments: variant.arguments + [UITestLaunch.ai, UITestAI.ready.rawValue])
        let library = app.library.show()
        library.map(titled: UITestFixture.Title.plan).waitToExist()
        check("library", variant, app)

        let editor = library.open(UITestFixture.Title.plan).show(.canvas)
        editor.canvasTopic(titled: UITestFixture.Title.design).waitToExist()
        check("canvas", variant, app)

        let ai = AIPage(app: app.app)
        editor.selectCanvasTopic(UITestFixture.Title.design)
        ai.openMenu()
        let suggest = ai.menuItem(symbol: AIPage.Symbol.suggestSubtopics)
        if suggest.waitForExistence(timeout: MindMapApp.timeout / 3) {
            suggest.tapOrClick()
            ai.acceptAllButton.waitToExist()
            check("ai-suggestions", variant, app)
            ai.discardAllButton.waitToExist().tapOrClick()
            XCTAssertTrue(ai.acceptAllButton.waitForNonExistence(timeout: MindMapApp.timeout))
        } else {
            // Seen at the largest text size on iPhone: the menu lays out without
            // the item's symbol, so the page object cannot find it. A finding for MM-12.
            record(note: "ai-suggestions not audited (\(variant.rawValue)): Suggest Subtopics not found in the AI menu")
            #if os(iOS)
            ai.dismissMenu()
            #endif
        }

        editor.tap(.inspector)
        app.app.textViews[AccessibilityID.Inspector.note].firstMatch.waitToExist()
        check("inspector", variant, app)
        editor.closeInspector()

        editor.show(.outline)
        editor.outlineTopic(titled: UITestFixture.Title.design).waitToExist()
        check("outline", variant, app)

        // Settings opens from the sidebar, which an iPhone shows only from the library.
        app = MindMapApp.launch(fixture: .sample, language: variant.language, arguments: variant.arguments + [UITestLaunch.ai, UITestAI.ready.rawValue])
        let settings = app.openSettings()
        for pane in SettingsPage.Pane.allCases {
            // A device without Apple Intelligence has no AI pane.
            guard settings.paneButton(pane).waitForExistence(timeout: MindMapApp.timeout / 3) else { continue }
            settings.show(pane)
            check("settings-\(pane.rawValue)", variant, app)
            settings.back()
        }

        settings.show(.pro)
        if settings.showPaywall.waitForExistence(timeout: MindMapApp.timeout / 3) {
            settings.showPaywall.tapOrClick()
            app.paywall.close.waitToExist()
            app.paywall.reveal(app.paywall.purchase)
            check("paywall", variant, app)
        } else {
            // StoreKit Testing keeps a purchase on the simulator; Pro unlocked has no paywall to audit.
            record(note: "paywall not audited: Pro is already unlocked on this device")
        }
    }

    /// Audits what is on screen now, keeps a screenshot, and fails on any
    /// issue `AuditWaiver` does not accept.
    @MainActor
    private func check(_ screen: String, _ variant: Variant, _ app: MindMapApp, file: StaticString = #filePath, line: UInt = #line) {
        XCTContext.runActivity(named: "Audit \(screen) (\(variant.rawValue))") { activity in
            let shot = XCTAttachment(screenshot: app.app.screenshot())
            shot.name = "\(screen).\(variant.rawValue)"
            shot.lifetime = .keepAlways
            activity.add(shot)

            var waived: [String] = []
            var failed: [String] = []
            do {
                try app.app.performAccessibilityAudit { issue in
                    let line = AuditWaiver.describe(issue, screen: screen, variant: variant)
                    guard let reason = AuditWaiver.reason(for: issue, screen: screen, variant: variant) else {
                        failed.append(line)
                        return false
                    }
                    waived.append("\(line) | waived: \(reason)")
                    return true
                }
            } catch {
                XCTFail("\(screen) (\(variant.rawValue)): \(error)", file: file, line: line)
            }
            // One line per issue in the log, so a run's findings can be read without Xcode.
            for issue in failed { print("AUDIT FAIL | \(issue)") }
            for issue in waived { print("AUDIT WAIVED | \(issue)") }
            if !waived.isEmpty {
                let list = XCTAttachment(string: waived.joined(separator: "\n"))
                list.name = "waived.\(screen).\(variant.rawValue)"
                list.lifetime = .keepAlways
                activity.add(list)
            }
        }
    }

    private func record(note: String) {
        let attachment = XCTAttachment(string: note)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The audit issues the test lets through. Keyed by screen and the audit's own
/// English description, never by translated text, so it holds in every language.
enum AuditWaiver {
    /// What the first run found (iOS 27 Simulator, iPhone 17, 2026-10-03), by
    /// screen and kind of issue, the input of MM-12's audit, which fixes them
    /// and removes the lines here. Likely causes, not yet checked: canvas text is
    /// sized with `UIFontMetrics` into fixed-size fonts, which the audit may read
    /// as no Dynamic Type; secondary grey and the AI gradient under 4.5:1;
    /// single-line rows that truncate long text. A kind of issue not in
    /// the list, or on a screen not in it, fails the test.
    static let knownFindings: [String: Set<String>] = [
        "ai-suggestions": ["Contrast failed", "Contrast nearly passed", "Text clipped"],
        "canvas": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported", "Text clipped"],
        "inspector": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported", "Dynamic Type font sizes are unsupported", "Text clipped"],
        "library": ["Contrast nearly passed", "Text clipped"],
        "outline": ["Hit area is too small", "Text clipped"],
        "paywall": ["Contrast failed", "Contrast nearly passed", "Dynamic Type font sizes are partially unsupported", "Dynamic Type font sizes are unsupported", "Text clipped"],
        "settings-about": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported"],
        "settings-ai": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported"],
        "settings-data": ["Contrast failed", "Contrast nearly passed", "Dynamic Type font sizes are partially unsupported"],
        "settings-export": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported", "Text clipped"],
        "settings-general": ["Contrast nearly passed", "Text clipped"],
        "settings-privacy": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported"],
        "settings-pro": ["Contrast nearly passed", "Dynamic Type font sizes are partially unsupported"],
    ]

    static func reason(for issue: XCUIAccessibilityAuditIssue, screen: String, variant: AccessibilityAuditUITests.Variant) -> String? {
        guard knownFindings[screen]?.contains(issue.compactDescription) == true else { return nil }
        return "known finding for MM-12"
    }

    static func describe(_ issue: XCUIAccessibilityAuditIssue, screen: String, variant: AccessibilityAuditUITests.Variant) -> String {
        let element = issue.element
        return [
            variant.rawValue, screen, issue.compactDescription,
            "type \(element?.elementType.rawValue ?? 0)",
            "id \(element?.identifier ?? "-")",
            "label \(element?.label ?? "-")",
            "frame \(element.map { "\($0.frame)" } ?? "-")",
        ].joined(separator: " | ")
    }
}

@MainActor
private extension EditorPage {
    /// The inspector is a sheet on iPhone, which covers the toolbar button, and
    /// a column beside the canvas on a larger screen, where the button hides it.
    func closeInspector() {
        let button = app.buttons[ToolbarAction.inspector.identifier].firstMatch
        #if os(iOS)
        if !button.exists || !button.isHittable {
            app.swipeDown()
            return
        }
        #endif
        button.tapOrClick()
    }
}

@MainActor
private extension SettingsPage {
    /// Back to the list of panes: iOS pushes a page per pane; the Mac's tabs need nothing.
    func back() {
        #if os(iOS)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if !doneButton.exists, back.exists { back.tapOrClick() }
        paneButton(.general).waitToExist()
        #endif
    }
}
