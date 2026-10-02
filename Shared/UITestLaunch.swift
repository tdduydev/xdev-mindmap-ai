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
}

/// How the scripted model of the UI test mode behaves.
nonisolated enum UITestAI: String, CaseIterable {
    /// Ready in English and Vietnamese. The chat answers with the first topic
    /// whose title matches a word of the question, and cites it.
    case ready
    /// A device that can never run Apple Intelligence: every AI entry point is hidden.
    case ineligible
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

    enum Title {
        static let plan = "Product Launch"
        static let research = "Research"
        static let design = "Design"
        static let interviews = "Interviews"
        static let marketing = "Marketing"
        static let favorite = "Reading List"
        static let large = "Large Map"
        static func showcase(_ language: String) -> String {
            language == "vi" ? "Ra mắt ứng dụng sáng tạo" : "Creative App Launch"
        }
    }

    static let largeTopicCount = 1_000
}
