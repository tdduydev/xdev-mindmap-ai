/// The launch arguments of the UI test mode, shared by the app and the UI
/// tests. Debug builds only read them; a release build ignores them.
nonisolated enum UITestLaunch {
    /// Turns the mode on: in-memory store, throwaway preferences, no animation.
    static let flag = "-uitest"
    /// Followed by a `UITestFixture` raw value. Without it the library starts empty.
    static let fixture = "-uitest-fixture"
    /// Followed by a `UITestAI` raw value: a scripted model in place of Apple
    /// Intelligence, so AI screens can be tested on any machine.
    static let ai = "-uitest-ai"
    /// Seeds the app's pasteboard in its own process for image-paste UI tests.
    static let imageClipboard = "-uitest-image-clipboard"
    /// Stands in for the system's open and save panels: Import… reads
    /// `UITestFile.markdown`, Export… writes into the app's temporary folder
    /// and reports the file on screen (`AccessibilityID.UITest.exportedFile`).
    static let files = "-uitest-files"
    /// Pro starts unlocked, without StoreKit: a purchase on a fresh simulator
    /// can stop at an Apple Account sign-in the test cannot answer.
    static let pro = "-uitest-pro"
}

/// How the scripted model of the UI test mode behaves.
nonisolated enum UITestAI: String, CaseIterable {
    /// Ready in English, Vietnamese and Japanese. The chat answers with the first topic
    /// whose title matches a word of the question, and cites it.
    case ready
    /// A device that can never run Apple Intelligence: every AI entry point is hidden.
    case ineligible

    /// What Suggest Subtopics proposes in the `ready` mode, in this order.
    static let subtopics = ["Budget", "Timeline", "Risks"]
    static let subtopicsVi = ["Ngân sách", "Lịch trình", "Rủi ro"]
    static let subtopicsJa = ["予算", "スケジュール", "リスク"]

    /// Follows the app language (`-AppleLanguages`), not the topic's, so a test
    /// knows the titles from how it launched: the Vietnamese and Japanese
    /// screenshots show suggestions in their language while the counts stay the same.
    static func subtopics(languageCode: String) -> [String] {
        if languageCode.hasPrefix("vi") { return subtopicsVi }
        if languageCode.hasPrefix("ja") { return subtopicsJa }
        return subtopics
    }
}

/// What voice input hears in the UI test mode, where the Simulator has no
/// speech model: one topic per sentence, then nothing more.
nonisolated enum UITestVoice {
    static let heard = "Call the venue. Book the flights."
    static let topics = ["Call the venue", "Book the flights"]
}

/// The file Import… opens when `UITestLaunch.files` stands in for the open
/// panel. Written the way people write Markdown (`*` and `-` items, no blank
/// lines), so exporting it again shows the structure survived, not the text.
nonisolated enum UITestFile {
    static let name = "Trip Plan.md"
    static let markdown = """
        # Trip Plan
        ## Travel
        * Book the flights
          * Window seat
        - Rent a car
        ## Packing
        - Passport
        """
    /// The same outline as the Markdown export writes it (docs/interchange.md),
    /// blank lines left out.
    static let exportedLines = [
        "# Trip Plan",
        "## Travel",
        "- Book the flights",
        "  - Window seat",
        "- Rent a car",
        "## Packing",
        "- Passport",
    ]
    /// The map the import makes: its single top-level heading names it.
    static let mapTitle = "Trip Plan"
}

/// The maps a UI test can start with. Titles are data, not interface text,
/// so they stay the same in every language.
nonisolated enum UITestFixture: String, CaseIterable {
    /// No maps.
    case empty
    /// Two maps: a small plan three levels deep, and a favorite with one topic.
    case sample
    /// One map with a central topic and 999 topics below it, for scrolling and performance.
    case large
    /// Localized, fictional launch plan for App Store screenshots.
    case showcaseEn
    case showcaseVi
    case showcaseJa

    enum Title {
        static let plan = "Product Launch"
        static let research = "Research"
        static let design = "Design"
        static let interviews = "Interviews"
        static let marketing = "Marketing"
        static let favorite = "Reading List"
        static let large = "Large Map"
        static func showcase(_ language: String) -> String {
            switch language {
            case "vi": "Ra mắt ứng dụng sáng tạo"
            case "ja": "クリエイティブアプリの発売"
            default: "Creative App Launch"
            }
        }
    }

    static let largeTopicCount = 1_000
}
