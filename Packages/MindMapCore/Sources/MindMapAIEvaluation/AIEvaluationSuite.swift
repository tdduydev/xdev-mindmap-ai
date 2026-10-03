import Foundation
import MindMapAICore
import MindMapDomain

/// One evaluation: a request a person could make, in one language.
public struct AIEvaluationCase: Sendable, Identifiable {
    public enum Request: Sendable {
        case suggestion(SuggestionRequest)
        case rewrite(RewriteRequest)
        case summarize(SummarizeRequest)
        case tags(SuggestTagsRequest)
        case groups(SuggestGroupsRequest)
        case boundaryTitle(SummarizeBoundaryRequest)
        /// The chat without tools: the outline is in the prompt, so both
        /// providers answer from the same text (`AIEvaluationChat`).
        case chat(AIEvaluationChat)
    }

    public var id: String { "\(feature.rawValue).\(language.rawValue)" }
    public var feature: AIFeature
    public var language: AILanguage
    public var request: Request
    /// Text the answer must contain, such as a number from the map, so a
    /// summary that invents its facts fails.
    public var expectedFact: String?
    /// Fewest items a list answer may have.
    public var minimumCount: Int
}

/// A chat question with the map it is about, written out with handles as the
/// chat's tools would return them.
public struct AIEvaluationChat: Sendable {
    public var mapTitle: String
    public var outline: [(handle: String, title: String)]
    public var question: String
    public var language: AILanguage
    /// The handle of the topic that answers the question.
    public var answerHandle: String
}

/// Every AI feature and the chat in English, Vietnamese and Japanese
/// (FR-AI-31, NFR-PERF-07): one case per feature and language, the same for
/// every provider so their pass rates compare.
public enum AIEvaluationSuite {
    public static var cases: [AIEvaluationCase] {
        AILanguage.allCases.flatMap { cases(for: Fixture.for($0)) }
    }

    static func cases(for f: Fixture) -> [AIEvaluationCase] {
        let language = f.language
        let locale = language.locale.identifier
        let mapID = MapID()
        let root = ContextTopic(nodeID: NodeID(), parentID: nil, title: f.mapTitle, depth: 0)
        let focusID = NodeID()
        let focus = ContextTopic(nodeID: focusID, parentID: root.nodeID, title: f.focus, depth: 1)
        let children = f.children.map { ContextTopic(nodeID: NodeID(), parentID: focusID, title: $0, depth: 2) }
        let siblings = f.siblings.map { ContextTopic(nodeID: NodeID(), parentID: root.nodeID, title: $0, depth: 1) }
        let context = AIContext(mapID: mapID, mapTitle: f.mapTitle, focus: focus, ancestors: [root], siblings: siblings,
                                descendants: children, language: language, userLocaleIdentifier: locale)
        let longFocus = ContextTopic(nodeID: NodeID(), parentID: root.nodeID, title: f.longTitle, depth: 1)
        let rewriteContext = AIContext(mapID: mapID, mapTitle: f.mapTitle, focus: longFocus, ancestors: [root],
                                       language: language, userLocaleIdentifier: locale)
        let summaryFocus = ContextTopic(nodeID: NodeID(), parentID: root.nodeID, title: f.summaryFocus, depth: 1)
        let summaryContext = AIContext(
            mapID: mapID, mapTitle: f.mapTitle, focus: summaryFocus, ancestors: [root],
            descendants: f.summaryChildren.map { ContextTopic(nodeID: NodeID(), parentID: summaryFocus.nodeID, title: $0, depth: 2) },
            language: language, userLocaleIdentifier: locale
        )
        let tagTopics = f.groupChildren.enumerated().map {
            TagSuggestionTopic(reference: "t\($0.offset + 1)", nodeID: NodeID(), title: $0.element, path: [f.mapTitle, f.focus])
        }
        let groupChildren = f.groupChildren.enumerated().map {
            GroupSuggestionTopic(reference: "T\($0.offset + 1)", nodeID: NodeID(), title: $0.element)
        }
        let outline = ([f.summaryFocus] + f.summaryChildren).enumerated().map { (handle: "T\($0.offset + 1)", title: $0.element) }
        let answerIndex = f.summaryChildren.firstIndex { $0.contains(f.fact) } ?? 0

        func make(_ feature: AIFeature, _ request: AIEvaluationCase.Request, fact: String? = nil, minimum: Int = 1) -> AIEvaluationCase {
            AIEvaluationCase(feature: feature, language: language, request: request, expectedFact: fact, minimumCount: minimum)
        }
        return [
            make(.generateMap, .suggestion(.generateMap(GenerateMapRequest(prompt: f.subject, language: language, userLocaleIdentifier: locale))), minimum: 5),
            make(.expandTopic, .suggestion(.expandTopic(ExpandTopicRequest(context: context))), minimum: 2),
            make(.brainstorm, .suggestion(.brainstorm(BrainstormRequest(context: context))), minimum: 3),
            make(.findMissingTopics, .suggestion(.findMissingTopics(MissingTopicsRequest(context: context))), minimum: 1),
            make(.rewrite, .rewrite(RewriteRequest(context: rewriteContext, style: .shorter))),
            make(.summarize, .summarize(SummarizeRequest(context: summaryContext)), fact: f.fact),
            make(.suggestTags, .tags(SuggestTagsRequest(mapTitle: f.mapTitle, topics: tagTopics, availableTags: [],
                                                       language: language, userLocaleIdentifier: locale))),
            make(.suggestGroups, .groups(SuggestGroupsRequest(mapTitle: f.mapTitle, parentID: focusID, parentTitle: f.focus,
                                                             path: [f.mapTitle], children: groupChildren,
                                                             language: language, userLocaleIdentifier: locale))),
            make(.summarizeBoundary, .boundaryTitle(SummarizeBoundaryRequest(
                mapTitle: f.mapTitle, groupID: GroupID(), parentTitle: f.focus,
                outline: f.groupChildren.prefix(3).map { .init(depth: 0, title: $0) },
                language: language, userLocaleIdentifier: locale))),
            make(.chat, .chat(AIEvaluationChat(mapTitle: f.mapTitle, outline: outline, question: f.chatQuestion,
                                               language: language, answerHandle: "T\(answerIndex + 2)")), fact: f.fact),
        ]
    }
}

/// The map content of one language's cases, written as a person using that
/// language would, mixed English terms included.
struct Fixture {
    var language: AILanguage
    var subject: String
    var mapTitle: String
    var focus: String
    var children: [String]
    var siblings: [String]
    var longTitle: String
    var summaryFocus: String
    var summaryChildren: [String]
    /// In one of `summaryChildren`; the summary and the chat must keep it.
    var fact: String
    var chatQuestion: String
    var groupChildren: [String]

    static func `for`(_ language: AILanguage) -> Fixture {
        switch language {
        case .english:
            Fixture(language: language, subject: "Launch plan for a mobile budgeting app",
                    mapTitle: "Healthy habits", focus: "Sleep", children: ["Fixed bedtime"],
                    siblings: ["Exercise", "Nutrition", "Stress"],
                    longTitle: "we should probably look into making the onboarding flow faster for new users",
                    summaryFocus: "Kitchen renovation",
                    summaryChildren: ["Budget: 12,000 USD", "New oak cabinets", "Move the sink under the window", "Contractor starts in March"],
                    fact: "12,000", chatQuestion: "What is the budget for the kitchen?",
                    groupChildren: ["Book flights", "Renew passport", "Pack sunscreen", "Reserve hotel", "Buy travel insurance", "Pack chargers"])
        case .vietnamese:
            Fixture(language: language, subject: "Kế hoạch ôn thi tốt nghiệp THPT môn Toán trong 3 tháng",
                    mapTitle: "Du lịch Đà Nẵng 4 ngày", focus: "Ẩm thực", children: ["Mì Quảng"],
                    siblings: ["Lịch trình", "Chi phí", "Khách sạn"],
                    longTitle: "cần phải xem lại cái backend architecture vì nó chạy chậm quá khi nhiều user",
                    summaryFocus: "Gọi vốn vòng hạt giống",
                    summaryChildren: ["Mục tiêu 500.000 USD", "Nhà đầu tư thiên thần", "Pitch deck 12 trang", "Hạn chót tháng 6"],
                    fact: "500.000", chatQuestion: "Mục tiêu gọi vốn là bao nhiêu?",
                    groupChildren: ["Đặt vé máy bay", "Gia hạn hộ chiếu", "Mua kem chống nắng", "Đặt khách sạn", "Mua bảo hiểm du lịch", "Mang sạc điện thoại"])
        case .japanese:
            Fixture(language: language, subject: "小さなカフェを開業するための計画",
                    mapTitle: "健康的な習慣", focus: "睡眠", children: ["決まった就寝時間"],
                    siblings: ["運動", "食事", "ストレス"],
                    longTitle: "新しいユーザーのためにオンボーディングの流れをもっと速くする方法を検討したほうがいいと思う",
                    summaryFocus: "キッチンのリフォーム",
                    summaryChildren: ["予算は150万円", "オーク材の新しい棚", "シンクを窓の下に移動", "工事は3月開始"],
                    fact: "150万", chatQuestion: "キッチンの予算はいくらですか？",
                    groupChildren: ["航空券を予約", "パスポートを更新", "日焼け止めを買う", "ホテルを予約", "旅行保険に入る", "充電器を準備"])
        }
    }
}
