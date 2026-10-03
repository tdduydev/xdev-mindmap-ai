import Foundation
import MindMapAICore
import MindMapGraph
import MindMapTestSupport

/// What a chat evaluation asks (MM-53): a question on one fixture map, and how
/// a good answer looks. Facts and sources are written here rather than judged
/// by a model, so a score moves only when the answers do.
struct ChatEvaluationSample: Codable, Sendable, CustomStringConvertible {
    enum Kind: String, Codable, Sendable {
        /// The map holds the answer: the facts must be in it and cited.
        case found
        /// The map does not: the answer must say so instead of inventing one.
        case notFound
    }

    var id: String
    var map: ChatEvaluationMap
    var question: String
    var language: AILanguage
    var kind: Kind
    /// Each entry is one fact the answer must hold, in any of its spellings.
    var facts: [[String]] = []
    /// Topic titles the answer may cite for its facts; at least one must be.
    var sources: [String] = []
    /// Words that only an invented answer would hold.
    var forbidden: [String] = []

    var description: String { "\(id): \(question)" }
}

/// The two fixture maps, one per language, built with commands as any edit.
/// Facts sit in notes as well as titles, so finding them needs `readTopic`
/// and not only `searchTopics`.
enum ChatEvaluationMap: String, Codable, Sendable, CaseIterable {
    case productLaunch
    case daNangTrip

    func makeFixture() throws -> OutlineFixture {
        switch self {
        case .productLaunch:
            var fixture = try OutlineFixture("""
            Product launch
              Beta
                Invite fifty testers
                Collect feedback in TestFlight
              Press release
              Budget
              Risks
                Late App Review
                Supplier delay
            """, mapTitle: "Product launch")
            try fixture.note("Beta", "The beta opens on May 12.")
            try fixture.note("Press release", "Mai Tran writes it. It goes out on launch day.")
            try fixture.note("Budget", "The total budget is $12,000; half of it goes to ads.")
            try fixture.note("Late App Review", "Submit the build two weeks early.")
            return fixture
        case .daNangTrip:
            var fixture = try OutlineFixture("""
            Du lịch Đà Nẵng
              Lịch trình
                Ngày 1: Bà Nà Hills
                Ngày 2: Hội An
              Chi phí
              Khách sạn
              Ăn uống
                Mì Quảng
                Bánh xèo
            """, mapTitle: "Du lịch Đà Nẵng")
            try fixture.note("Lịch trình", "Bay lúc 7 giờ sáng thứ Bảy.")
            try fixture.note("Chi phí", "Tổng chi phí 8 triệu đồng cho hai người.")
            try fixture.note("Khách sạn", "Đặt phòng ở Mường Thanh, nhận phòng lúc 14 giờ.")
            return fixture
        }
    }
}

extension ChatEvaluationSample {
    /// Seven questions per answer language: five the maps answer, one of them
    /// asked across languages, and two they do not.
    static let all: [ChatEvaluationSample] = english + vietnamese

    static let english: [ChatEvaluationSample] = [
        .init(
            id: "en-beta-date", map: .productLaunch, question: "When does the beta open?",
            language: .english, kind: .found, facts: [["May 12", "12 May", "May 12th"]], sources: ["Beta"]
        ),
        .init(
            id: "en-press-owner", map: .productLaunch, question: "Who writes the press release?",
            language: .english, kind: .found, facts: [["Mai"]], sources: ["Press release"]
        ),
        .init(
            id: "en-budget", map: .productLaunch, question: "How much is the total budget?",
            language: .english, kind: .found, facts: [["12,000", "12000", "12.000", "12k"]], sources: ["Budget"]
        ),
        .init(
            id: "en-risks", map: .productLaunch, question: "What risks does the launch have?",
            language: .english, kind: .found, facts: [["App Review"], ["supplier"]],
            sources: ["Risks", "Late App Review", "Supplier delay"]
        ),
        .init(
            id: "en-designer", map: .productLaunch, question: "Who is the lead designer?",
            language: .english, kind: .notFound, forbidden: ["Mai"]
        ),
        .init(
            id: "en-price", map: .productLaunch, question: "What will the app cost in the App Store?",
            language: .english, kind: .notFound, forbidden: ["$0.99", "$1.99", "$2.99", "$4.99", "free of charge"]
        ),
        // The map is Vietnamese and the question English: "hotel" finds no
        // title, so the model has to read the outline instead of searching.
        .init(
            id: "en-on-vi-hotel", map: .daNangTrip, question: "Which hotel do we stay at?",
            language: .english, kind: .found, facts: [["Mường Thanh"]], sources: ["Khách sạn"]
        ),
    ]

    static let vietnamese: [ChatEvaluationSample] = [
        .init(
            id: "vi-cost", map: .daNangTrip, question: "Tổng chi phí chuyến đi là bao nhiêu?",
            language: .vietnamese, kind: .found, facts: [["8 triệu", "8.000.000", "8,000,000", "tám triệu"]], sources: ["Chi phí"]
        ),
        .init(
            id: "vi-hotel", map: .daNangTrip, question: "Chúng ta ở khách sạn nào?",
            language: .vietnamese, kind: .found, facts: [["Mường Thanh"]], sources: ["Khách sạn"]
        ),
        .init(
            id: "vi-day-two", map: .daNangTrip, question: "Ngày thứ hai đi đâu?",
            language: .vietnamese, kind: .found, facts: [["Hội An"]], sources: ["Ngày 2: Hội An", "Lịch trình"]
        ),
        .init(
            id: "vi-food", map: .daNangTrip, question: "Có những món ăn nào trong kế hoạch?",
            language: .vietnamese, kind: .found, facts: [["Mì Quảng"], ["Bánh xèo"]],
            sources: ["Ăn uống", "Mì Quảng", "Bánh xèo"]
        ),
        .init(
            id: "vi-driver", map: .daNangTrip, question: "Ai lái xe đưa đón ra sân bay?",
            language: .vietnamese, kind: .notFound
        ),
        .init(
            id: "vi-ticket", map: .daNangTrip, question: "Vé máy bay giá bao nhiêu?",
            language: .vietnamese, kind: .notFound, forbidden: ["triệu đồng một vé", "nghìn đồng"]
        ),
        .init(
            id: "vi-on-en-beta", map: .productLaunch, question: "Bản beta mở vào ngày nào?",
            language: .vietnamese, kind: .found, facts: [["12/5", "12 tháng 5", "12 tháng Năm", "May 12"]], sources: ["Beta"]
        ),
    ]
}

private extension OutlineFixture {
    mutating func note(_ title: String, _ note: String) throws {
        try engine.execute(UpdateNodeCommand(nodeID: self[title], .note(note)))
    }
}
