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
        case .ready: AICapabilities(model: .ready, supportedLanguages: Set(AILanguage.allCases), contextSize: 4_096)
        case .ineligible: .notEligible
        }
        return AIService(
            provider: { UITestAIProvider(current: capabilities) },
            chatProvider: { UITestChatProvider(current: capabilities, queries: queries) },
            entitlements: entitlements
        )
    }
}

/// Reports the mode's capabilities; the suggestion features are not
/// scripted yet, so each one fails the way a bad answer would.
private struct UITestAIProvider: AIProvider {
    let current: AICapabilities

    func capabilities() async -> AICapabilities { current }
    func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal { throw AIError.generationFailed }
    func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal { throw AIError.generationFailed }
    func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal { throw AIError.generationFailed }
    func rewrite(_ request: RewriteRequest) async throws -> AIRewrite { throw AIError.generationFailed }
    func summarize(_ request: SummarizeRequest) async throws -> AISummary { throw AIError.generationFailed }
    func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal { throw AIError.generationFailed }
    func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions { throw AIError.generationFailed }
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
                    for word in message.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where hit == nil {
                        hit = try? await queries.search(String(word), in: mapID, under: message.branch?.nodeID, limit: 1).first
                    }
                    let text: String
                    if let hit {
                        let handle = table.handle(for: hit.ref.nodeID, in: mapID, title: hit.title)
                        text = "\(hit.title) is in the map [\(handle)]."
                    } else {
                        text = "The map does not seem to cover that."
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
