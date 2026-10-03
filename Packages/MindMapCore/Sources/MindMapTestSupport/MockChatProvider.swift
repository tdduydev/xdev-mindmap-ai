import Foundation
import MindMapAICore
import Synchronization

/// A `ChatProvider` that answers from a script, for tests, previews and the UI
/// test mode.
///
/// Queue answers with `enqueue`; each question takes the next one, or fails
/// with `AIError.generationFailed` when the queue is empty. Like the real
/// provider it refuses questions the capabilities do not allow, and it records
/// every question.
public final class MockChatProvider: ChatProvider {
    public enum Answer: Sendable {
        /// Streamed in `chunks` growing pieces, after one "reading the map"
        /// update, which carries `suggestion` as if the model called suggestTopics.
        case text(String, citations: [ChatCitation], chunks: Int = 2, suggestion: ChatSuggestion? = nil)
        case failure(AIError)
        /// Never answers; the question ends only when its task is cancelled.
        case hang
    }

    public struct Question: Hashable, Sendable {
        public let scope: ChatScope
        public let message: ChatMessage
        /// Turns the conversation held before this question.
        public let history: [ChatTurn]
    }

    private struct State {
        var capabilities: AICapabilities
        var answers: [Answer] = []
        var questions: [Question] = []
        var conversations = 0
    }

    private let state: Mutex<State>

    public init(capabilities: AICapabilities = .readyForTesting) {
        state = Mutex(State(capabilities: capabilities))
    }

    public func setCapabilities(_ capabilities: AICapabilities) {
        state.withLock { $0.capabilities = capabilities }
    }

    public func enqueue(_ answer: Answer) {
        state.withLock { $0.answers.append(answer) }
    }

    public var questions: [Question] {
        state.withLock { $0.questions }
    }

    /// How many conversations were started, so a test sees Clear start a new one.
    public var conversationCount: Int {
        state.withLock { $0.conversations }
    }

    public func capabilities() async -> AICapabilities {
        state.withLock { $0.capabilities }
    }

    public func conversation(in scope: ChatScope, history: [ChatTurn]) -> any ChatConversation {
        state.withLock { $0.conversations += 1 }
        return Conversation(provider: self, scope: scope, history: history)
    }

    fileprivate func next(for question: Question) throws -> Answer {
        try state.withLock { state in
            state.questions.append(question)
            let availability = state.capabilities.chatAvailability(in: question.message.language)
            guard availability == .ready else { throw AIError.unavailable(availability) }
            guard !state.answers.isEmpty else { throw AIError.generationFailed }
            return state.answers.removeFirst()
        }
    }

    private final class Conversation: ChatConversation {
        let provider: MockChatProvider
        let scope: ChatScope
        let history: Mutex<[ChatTurn]>

        init(provider: MockChatProvider, scope: ChatScope, history: [ChatTurn]) {
            self.provider = provider
            self.scope = scope
            self.history = Mutex(history)
        }

        func send(_ message: ChatMessage) -> AsyncThrowingStream<ChatUpdate, any Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let question = Question(scope: scope, message: message, history: history.withLock { $0 })
                        switch try provider.next(for: question) {
                        case .text(let text, let citations, let chunks, let suggestion):
                            continuation.yield(ChatUpdate(isReadingMap: true, suggestion: suggestion))
                            let pieces = max(1, chunks)
                            for piece in 1..<pieces {
                                try Task.checkCancellation()
                                let partial = String(text.prefix(text.count * piece / pieces))
                                continuation.yield(ChatUpdate(text: partial, citations: citations.filter { partial.contains("[\($0.handle)]") }, suggestion: suggestion))
                                await Task.yield()
                            }
                            try Task.checkCancellation()
                            history.withLock { $0.append(ChatTurn(question: message.text, answer: text, citations: citations, branch: message.branch)) }
                            continuation.yield(ChatUpdate(text: text, citations: citations, suggestion: suggestion, isComplete: true))
                            continuation.finish()
                        case .failure(let error):
                            continuation.finish(throwing: error)
                        case .hang:
                            continuation.yield(ChatUpdate(isReadingMap: true))
                            while !Task.isCancelled { try await Task.sleep(for: .milliseconds(20)) }
                            continuation.finish(throwing: CancellationError())
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
