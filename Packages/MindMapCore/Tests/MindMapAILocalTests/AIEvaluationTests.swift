import MindMapAICore
import Testing
@testable import MindMapAIEvaluation
@testable import MindMapAILocal

@Suite struct AIEvaluationTests {
    @Test func everyFeatureAndTheChatInEveryLanguage() {
        let ids = Set(AIEvaluationSuite.cases.map(\.id))
        for feature in AIFeature.allCases {
            for language in AILanguage.allCases {
                #expect(ids.contains("\(feature.rawValue).\(language.rawValue)"))
            }
        }
    }

    @Test(arguments: [
        ("Thiết kế backend architecture", AILanguage.vietnamese, true),
        ("Design the backend", .vietnamese, false),
        ("Design the backend", .english, true),
        ("Đặt vé máy bay", .english, false),
        ("航空券を予約", .japanese, true),
        ("Book flights", .japanese, false),
        ("オンボーディング UX を改善", .japanese, true),
        ("", .english, false),
    ])
    func language(text: String, language: AILanguage, expected: Bool) {
        #expect(AIEvaluationCheck.isWritten(in: language, text) == expected)
    }

    @Test func aSummaryMustKeepTheFact() {
        #expect(AIEvaluationRunner.check(["The budget is 12,000 USD."], language: .english, minimum: 1, fact: "12,000") == nil)
        #expect(AIEvaluationRunner.check(["The budget is large."], language: .english, minimum: 1, fact: "12,000") == "missing fact 12,000")
    }

    @Test func goodAnswersPassEveryCase() async {
        // One canned answer per shape, in the case's language: proves each case
        // builds a request the provider accepts and the checks can pass.
        for evaluation in AIEvaluationSuite.cases {
            let engine = ScriptedEngine(Self.answer(for: evaluation))
            let outcome = await AIEvaluationRunner.run(evaluation, provider: readyProvider(engine)) { _, _ in
                Self.chatAnswer[evaluation.language]!
            }
            #expect(outcome.passed, "\(evaluation.id): \(outcome.reason ?? "")")
        }
    }

    static let words: [AILanguage: [String]] = [
        .english: ["Morning light", "Quiet room", "Evening walk", "Reading time", "Warm bath", "Herbal tea"],
        .vietnamese: ["Ánh sáng buổi sáng", "Phòng yên tĩnh", "Đi dạo buổi tối", "Đọc sách", "Tắm nước ấm", "Trà thảo mộc"],
        .japanese: ["朝の光", "静かな部屋", "夜の散歩", "読書の時間", "温かいお風呂", "ハーブティー"],
    ]
    static let summary: [AILanguage: String] = [
        .english: "The kitchen has a budget of 12,000 USD and starts in March.",
        .vietnamese: "Vòng gọi vốn nhắm tới 500.000 USD với nhà đầu tư thiên thần.",
        .japanese: "キッチンのリフォームは予算150万円で、3月に始まります。",
    ]
    static let chatAnswer: [AILanguage: String] = [
        .english: "The budget is 12,000 USD [T2].",
        .vietnamese: "Mục tiêu là 500.000 USD [T2].",
        .japanese: "予算は150万円です [T2]。",
    ]

    static func answer(for evaluation: AIEvaluationCase) -> String {
        let words = Self.words[evaluation.language]!
        let list = words.map { #"{"title": "\#($0)"}"# }.joined(separator: ", ")
        switch evaluation.request {
        case .suggestion(.generateMap):
            let topics = words.enumerated().map { #"{"temporaryID": "t\#($0.offset + 1)", "parentTemporaryID": "", "title": "\#($0.element)"}"# }
            return #"{"title": "\#(words[0])", "topics": [\#(topics.joined(separator: ", "))]}"#
        case .suggestion: return #"{"topics": [\#(list)]}"#
        case .rewrite: return #"{"titles": ["\#(words[1])"]}"#
        case .summarize: return #"{"summary": "\#(summary[evaluation.language]!)"}"#
        case .tags: return #"{"topics": [{"reference": "t1", "tags": ["\#(words[2])"]}]}"#
        case .groups: return #"{"groups": [{"title": "\#(words[3])", "references": ["T1", "T2"]}]}"#
        case .boundaryTitle: return #"{"title": "\#(words[4])"}"#
        case .chat: return ""
        }
    }
}

@Suite struct AIEvaluationRepeatTests {
    @Test func aSuggestionRepeatingAnExistingTopicFails() async {
        let evaluation = AIEvaluationSuite.cases.first { $0.id == "expandTopic.en" }!
        let engine = ScriptedEngine(#"{"topics": [{"title": "Quiet room"}, {"title": "fixed bedtime"}]}"#)
        let outcome = await AIEvaluationRunner.run(evaluation, provider: readyProvider(engine)) { _, _ in "" }
        #expect(outcome.reason == "repeats fixed bedtime")
    }
}
