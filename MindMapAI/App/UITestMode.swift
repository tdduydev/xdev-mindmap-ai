import Foundation
import MindMapDomain
import MindMapGraph
import MindMapIntents

/// The launch mode UI tests start the app in (docs/testing.md): an in-memory
/// store seeded with a fixture, preferences that start empty each launch, and
/// no animation. Nil in release builds and whenever `-uitest` is absent, so the
/// app behaves exactly as shipped.
struct UITestMode {
    let fixture: UITestFixture
    /// Nil leaves the real model in place.
    var ai: UITestAI?

    static let current: UITestMode? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(UITestLaunch.flag) else { return nil }
        let fixture = arguments.firstIndex(of: UITestLaunch.fixture)
            .flatMap { arguments.indices.contains($0 + 1) ? UITestFixture(rawValue: arguments[$0 + 1]) : nil }
        let ai = arguments.firstIndex(of: UITestLaunch.ai)
            .flatMap { arguments.indices.contains($0 + 1) ? UITestAI(rawValue: arguments[$0 + 1]) : nil }
        return UITestMode(fixture: fixture ?? .empty, ai: ai)
        #else
        return nil
        #endif
    }()

    static var isActive: Bool { current != nil }

    private static let defaultsSuite = "asia.xdev.mindmapai.uitest"

    /// A suite of its own, emptied at launch, so a test never reads or changes
    /// the person's real preferences (on the Mac the test app shares them).
    /// Values passed as `-key value` launch arguments are copied in, so a test
    /// can still start with, say, `-appearance dark`.
    func makeDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: Self.defaultsSuite) else { return .standard }
        defaults.removePersistentDomain(forName: Self.defaultsSuite)
        // No first-run screens in the way of a test; one that checks the AI
        // privacy notice passes `-ai.privacyNoticeShown NO`.
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
        for (key, value) in UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain) {
            defaults.set(value, forKey: key)
        }
        return defaults
    }
}

/// The preferences store every `@AppStorage` and defaults reader in the app uses.
enum AppDefaults {
    static let store: UserDefaults = UITestMode.current?.makeDefaults() ?? .standard
}

extension UITestFixture {
    /// The fixture's maps, built with graph commands like any edit, and their
    /// favorites. Edit times are fixed and one minute apart, so the library order is too.
    func makeMaps() throws -> (graphs: [GraphState], favorites: [MapID]) {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        switch self {
        case .empty:
            return ([], [])
        case .sample:
            let favorite = try Self.graph(Title.favorite, editedAt: start)
            let plan = try Self.graph(Title.plan, editedAt: start.addingTimeInterval(60)) { engine, root in
                let research = NodeID()
                try engine.execute(AddNodeCommand(nodeID: research, .child(of: root), title: Title.research))
                try engine.execute(AddNodeCommand(.child(of: research), title: Title.interviews))
                try engine.execute(AddNodeCommand(.child(of: root), title: Title.design))
                try engine.execute(AddNodeCommand(.child(of: root), title: Title.marketing))
            }
            return ([favorite, plan], [favorite.map.id])
        case .large:
            let large = try Self.graph(Title.large, editedAt: start) { engine, root in
                // Nine branches of 110 topics under the central topic: 1,000 in all.
                for branch in 1...9 {
                    let branchID = NodeID()
                    try engine.execute(AddNodeCommand(nodeID: branchID, .child(of: root), title: "Branch \(branch)"))
                    for topic in 1...110 {
                        try engine.execute(AddNodeCommand(.child(of: branchID), title: "Topic \(branch).\(topic)"))
                    }
                }
            }
            return ([large], [])
        case .showcaseEn, .showcaseVi:
            let vietnamese = self == .showcaseVi
            let title = Title.showcase(vietnamese ? "vi" : "en")
            let branches: [(String, [String])] = vietnamese ? [
                ("Khám phá", ["Phỏng vấn người dùng", "Nhu cầu chính", "Cơ hội mới"]),
                ("Thiết kế", ["Luồng trải nghiệm", "Bộ nhận diện", "Thử nghiệm mẫu"]),
                ("Ra mắt", ["Trang giới thiệu", "Thông điệp", "Cộng đồng"]),
                ("Đo lường", ["Phản hồi", "Mức độ gắn bó", "Bước tiếp theo"]),
            ] : [
                ("Discover", ["User interviews", "Key needs", "New opportunities"]),
                ("Design", ["Experience flow", "Visual identity", "Prototype testing"]),
                ("Launch", ["Landing page", "Messaging", "Community"]),
                ("Measure", ["Feedback", "Engagement", "Next steps"]),
            ]
            let graph = try Self.graph(title, editedAt: start) { engine, root in
                for (heading, children) in branches {
                    let branch = NodeID()
                    try engine.execute(AddNodeCommand(nodeID: branch, .child(of: root), title: heading))
                    for child in children {
                        try engine.execute(AddNodeCommand(.child(of: branch), title: child))
                    }
                }
            }
            return ([graph], [])
        }
    }

    private static func graph(
        _ title: String,
        editedAt date: Date,
        build: (inout GraphEngine, NodeID) throws -> Void = { _, _ in }
    ) throws -> GraphState {
        let state = GraphState.newMap(title: title, now: date)
        var engine = try GraphEngine(state: state, clock: { date })
        guard let root = state.map.rootNodeID else { return state }
        try build(&engine, root)
        return engine.state
    }
}

/// Indexes nothing: UI test maps stay out of Spotlight.
struct NoSearchIndex: MapSearchIndex {
    func replaceAll(with maps: [MindMap]) async {}
    func update(_ map: MindMap) async {}
    func remove(_ mapID: MapID) async {}
}
