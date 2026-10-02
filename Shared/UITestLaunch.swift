/// The launch arguments of the UI test mode, shared by the app and the UI
/// tests. Debug builds only read them; a release build ignores them.
nonisolated enum UITestLaunch {
    /// Turns the mode on: in-memory store, throwaway preferences, no animation.
    static let flag = "-uitest"
    /// Followed by a `UITestFixture` raw value. Without it the library starts empty.
    static let fixture = "-uitest-fixture"
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

    enum Title {
        static let plan = "Product Launch"
        static let research = "Research"
        static let design = "Design"
        static let interviews = "Interviews"
        static let marketing = "Marketing"
        static let favorite = "Reading List"
        static let large = "Large Map"
    }

    static let largeTopicCount = 1_000
}
