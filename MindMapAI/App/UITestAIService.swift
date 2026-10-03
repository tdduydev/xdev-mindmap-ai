#if DEBUG
import Foundation
import MindMapAICore
import MindMapDomain
import MindMapQuery

/// The scripted model of the UI test mode (`-uitest-ai`), in debug builds
/// only: UI tests reach the AI screens on a Mac or simulator without Apple
/// Intelligence, and get the same answer every run.
enum UITestAIService {
    static func make(_ mode: UITestAI, queries: MapQueries, entitlements: any ProEntitlements) -> AIService {
        let capabilities: AICapabilities = switch mode {
        case .ready, .fiveSuggestions, .guardrail:
            AICapabilities(model: .ready, supportedLanguages: Set(AILanguage.allCases), contextSize: 4_096)
        case .ineligible: .notEligible
        case .appleIntelligenceOff: AICapabilities(model: .appleIntelligenceOff)
        }
        return AIService(
            provider: { UITestAIProvider(mode: mode, current: capabilities) },
            chatProvider: { UITestChatProvider(current: capabilities, queries: queries) },
            entitlements: entitlements
        )
    }
}

/// Reports the mode's capabilities and gives fixed answers, so a test can
/// accept, edit and discard them and screenshots never depend on an installed
/// model. Suggest Subtopics answers with `UITestAI.subtopics(languageCode:)`
/// (or `UITestAI.fiveSubtopics`) under the focus topic; Generate Map, Rewrite
/// Topic and Summarize Branch with the other `UITestAI` answers; the
/// remaining features fail the way a bad answer would. In the `guardrail`
/// mode every request is blocked.
private struct UITestAIProvider: AIProvider {
    let mode: UITestAI
    let current: AICapabilities

    func capabilities() async -> AICapabilities { current }

    func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal {
        try checkGuardrail()
        return AIProposal(feature: .generateMap, anchor: .root, topics: Self.topics(UITestAI.generatedTopics))
    }

    func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal {
        try checkGuardrail()
        let titles = mode == .fiveSuggestions
            ? UITestAI.fiveSubtopics
            : UITestAI.subtopics(languageCode: Locale.preferredLanguages.first ?? "en")
        return AIProposal(feature: .expandTopic, anchor: .node(request.context.focus.nodeID), topics: Self.topics(titles))
    }

    func rewrite(_ request: RewriteRequest) async throws -> AIRewrite {
        try checkGuardrail()
        let focus = request.context.focus
        return AIRewrite(nodeID: focus.nodeID, originalTitle: focus.title, suggestions: UITestAI.rewrites)
    }

    func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        try checkGuardrail()
        return AISummary(nodeID: request.context.focus.nodeID, text: UITestAI.summary)
    }

    func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal { throw failure }
    func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal { throw failure }
    func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions { throw failure }
    func suggestGroups(_ request: SuggestGroupsRequest) async throws -> AIGroupSuggestions { throw failure }
    func summarizeBoundary(_ request: SummarizeBoundaryRequest) async throws -> AIBoundaryTitle { throw failure }

    private var failure: AIError { mode == .guardrail ? .guardrailViolation : .generationFailed }

    private func checkGuardrail() throws {
        if mode == .guardrail { throw AIError.guardrailViolation }
    }

    private static func topics(_ titles: [String]) -> [ProposedTopic] {
        titles.enumerated().map { index, title in ProposedTopic(temporaryID: "t\(index)", title: title) }
    }
}

/// Answers by searching the map for each word of the question, through the
/// same `MapQueries` as the real chat, and cites the first topic found.
private struct UITestChatProvider: ChatProvider {
    let current: AICapabilities
    let queries: MapQueries

    func capabilities() async -> AICapabilities { current }

    func conversation(in scope: ChatScope, history: [ChatTurn]) -> any ChatConversation {
        Conversation(scope: scope, queries: queries)
    }

    private final class Conversation: ChatConversation {
        let scope: ChatScope
        let queries: MapQueries

        init(scope: ChatScope, queries: MapQueries) {
            self.scope = scope
            self.queries = queries
        }

        func send(_ message: ChatMessage) -> AsyncThrowingStream<ChatUpdate, any Error> {
            let scope = scope
            let queries = queries
            return AsyncThrowingStream { continuation in
                let task = Task {
                    guard case .map(let mapID) = scope else { return continuation.finish() }
                    continuation.yield(ChatUpdate(isReadingMap: true))
                    var table = CitationTable()
                    var hit: TopicHit?
                    // Longest words first, so "Design" wins over "is", which "Discover" also holds.
                    // Japanese has no spaces; its particles are hiragana, so the
                    // katakana and kanji runs between them are the words.
                    let isHiragana: (Character) -> Bool = { $0.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) } }
                    let spaced = message.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                    let runs = message.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber || isHiragana($0) })
                        .map(String.init).filter { !spaced.contains($0) }
                    let words = (spaced + runs).sorted { $0.count > $1.count }
                    for word in words where hit == nil {
                        hit = try? await queries.search(word, in: mapID, under: message.branch?.nodeID, limit: 1).first
                    }
                    let language = message.language
                    let text: String
                    if let hit {
                        let handle = table.handle(for: hit.ref.nodeID, in: mapID, title: hit.title)
                        let children = (try? await queries.topic(hit.ref))?.children ?? []
                        let cited = children.map { child in
                            "\(child.title) [\(table.handle(for: child.nodeID, in: mapID, title: child.title))]"
                        }
                        // The screenshots show this answer, so it reads like one about the topic's branch.
                        if cited.isEmpty {
                            text = switch language {
                            case .vietnamese: "\(hit.title) có trong sơ đồ [\(handle)]."
                            case .japanese: "\(hit.title)はマップにあります [\(handle)]。"
                            case .english: "\(hit.title) is in the map [\(handle)]."
                            }
                        } else if language == .japanese {
                            text = "\(hit.title) [\(handle)] には\(cited.joined(separator: "、"))があります。"
                        } else {
                            let vietnamese = language == .vietnamese
                            let last = cited.count > 1 ? (vietnamese ? " và " : " and ") + cited[cited.count - 1] : ""
                            let list = cited.dropLast(cited.count > 1 ? 1 : 0).joined(separator: ", ") + last
                            text = vietnamese
                                ? "\(hit.title) [\(handle)] gồm \(list)."
                                : "\(hit.title) is in the map [\(handle)]. It covers \(list)."
                        }
                    } else {
                        text = switch language {
                        case .vietnamese: "Sơ đồ có vẻ không nói tới điều này."
                        case .japanese: "マップにはこの内容が見つかりません。"
                        case .english: "The map does not seem to cover that."
                        }
                    }
                    continuation.yield(ChatUpdate(text: text, citations: table.citations(in: text), isComplete: true))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
#endif
