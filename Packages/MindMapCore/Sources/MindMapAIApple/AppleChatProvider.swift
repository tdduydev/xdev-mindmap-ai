import Foundation
import FoundationModels
import MindMapAICore
import MindMapDomain
import MindMapQuery
import os
import Synchronization

/// The chat on the on-device model (ADR 0009): `SystemLanguageModel.default`
/// only, default guardrails, tools over `MapQueries`.
public struct AppleChatProvider: ChatProvider {
    let queries: MapQueries
    let catalog: PromptCatalog

    public init(queries: MapQueries, catalog: PromptCatalog = PromptCatalog()) {
        self.queries = queries
        self.catalog = catalog
    }

    public func capabilities() async -> AICapabilities {
        AppleCapabilityProbe.current()
    }

    public func conversation(in scope: ChatScope, history: [ChatTurn]) -> any ChatConversation {
        AppleChatConversation(scope: scope, queries: queries, catalog: catalog, history: history)
    }
}

/// One `LanguageModelSession` per conversation, so the model keeps earlier
/// turns. When they no longer fit, the session is rebuilt from the latest
/// turns as plain text; tool results are the first thing to go.
final class AppleChatConversation: ChatConversation {
    private static let logger = Logger(subsystem: "asia.xdev.mindmapai", category: "AI")

    private struct State {
        var session: LanguageModelSession?
        var turns: [ChatTurn]
        /// Estimated tokens the session holds, instructions included.
        var used = 0
        var toolCost = 0
    }

    let scope: ChatScope
    private let catalog: PromptCatalog
    private let reader: ChatMapReader
    private let events = ChatToolEvents()
    private let state: Mutex<State>

    init(scope: ChatScope, queries: MapQueries, catalog: PromptCatalog, history: [ChatTurn]) {
        self.scope = scope
        self.catalog = catalog
        let mapID: MapID = switch scope {
        case .map(let id): id
        }
        // The window is known only once capabilities are read; each question
        // sets the reader's limit from it.
        reader = ChatMapReader(
            queries: queries,
            mapID: mapID,
            toolOutput: ChatBudget(contextSize: nil).toolOutput,
            table: CitationTable(history: history)
        )
        state = Mutex(State(turns: history))
    }

    func send(_ message: ChatMessage) -> AsyncThrowingStream<ChatUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.answer(message) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    // A stopped answer may leave the session mid-turn; the next
                    // question starts a session from the finished turns.
                    if error is CancellationError || Task.isCancelled { self.state.withLock { $0.session = nil } }
                    continuation.finish(throwing: error)
                }
                self.events.observe(nil)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Answering

    private func answer(_ message: ChatMessage, yield: @escaping @Sendable (ChatUpdate) -> Void) async throws {
        let capabilities = AppleCapabilityProbe.current()
        let status = capabilities.chatAvailability(in: message.language)
        guard status == .ready else { throw failure(.unavailable(status)) }
        let budget = ChatBudget(contextSize: capabilities.contextSize)
        reader.setToolOutput(budget.toolOutput)
        reader.setBranch(message.branch?.nodeID)

        let mapTitle = await reader.mapTitle()
        let prompt = catalog.chatPrompt(question: message.text, mapTitle: mapTitle, language: message.language, branchTitle: message.branch?.title)
        let questionCost = TokenEstimator.estimate(prompt)
        let tools = Self.tools(reader: reader, events: events)

        // Rebuilt before asking when the turns so far leave no room, and
        // once more, from the last turn alone, if the model still runs out.
        var leftOut = false
        var session = prepareSession(budget: budget, questionCost: questionCost, tools: tools, locale: message.userLocaleIdentifier, leftOut: &leftOut)

        let started = ContinuousClock.now
        let latest = Mutex(ChatUpdate(leftOutEarlierTurns: leftOut))
        state.withLock { $0.toolCost = 0 }
        // Cleared when the answer ends, so this holds the conversation only meanwhile.
        events.observe { name, cost in
            self.state.withLock { $0.toolCost += cost }
            Self.logger.info("Chat tool \(name, privacy: .public), about \(cost, privacy: .public) tokens")
            yield(latest.withLock { update in
                update.isReadingMap = true
                return update
            })
        }
        let reader = self.reader
        let onPartial = { (partial: String) in
            yield(latest.withLock { update in
                update.text = partial
                update.citations = reader.citationTable.citations(in: partial)
                update.isReadingMap = false
                return update
            })
        }

        let text: String
        do {
            text = try await stream(prompt, in: session, started: started, partial: onPartial)
        } catch AIError.contextSizeExceeded where !leftOut {
            leftOut = true
            session = rebuiltSession(keepingLast: 1, tools: tools, locale: message.userLocaleIdentifier)
            state.withLock { $0.toolCost = 0 }
            yield(latest.withLock { update in
                update = ChatUpdate(leftOutEarlierTurns: true)
                return update
            })
            text = try await stream(prompt, in: session, started: started, partial: onPartial)
        }

        let citations = reader.citationTable.citations(in: text)
        let turn = ChatTurn(question: message.text, answer: text, citations: citations, branch: message.branch)
        state.withLock { current in
            current.turns.append(turn)
            current.used += questionCost + current.toolCost + TokenEstimator.estimate(text)
        }
        Self.logger.info("Chat answer, \(citations.count, privacy: .public) citations, about \(questionCost, privacy: .public) prompt tokens")
        yield(ChatUpdate(text: text, citations: citations, leftOutEarlierTurns: leftOut, isComplete: true))
    }

    /// Streams the answer's text and returns it whole.
    private func stream(
        _ prompt: String,
        in session: LanguageModelSession,
        started: ContinuousClock.Instant,
        partial: (String) -> Void
    ) async throws -> String {
        var reportedFirst = false
        do {
            let stream = session.streamResponse(to: prompt)
            var last = ""
            for try await snapshot in stream {
                try Task.checkCancellation()
                last = snapshot.content
                if !reportedFirst, !last.isEmpty {
                    reportedFirst = true
                    let milliseconds = Int((ContinuousClock.now - started) / .milliseconds(1))
                    Self.logger.info("Chat first token after \(milliseconds, privacy: .public) ms")
                }
                partial(last)
            }
            let text = last.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw failure(.invalidResponse(.empty)) }
            return text
        } catch let error as AIError {
            throw error
        } catch {
            throw mapped(error)
        }
    }

    // MARK: Sessions

    private func prepareSession(
        budget: ChatBudget,
        questionCost: Int,
        tools: [any Tool],
        locale: String,
        leftOut: inout Bool
    ) -> LanguageModelSession {
        let (session, used, turns) = state.withLock { ($0.session, $0.used, $0.turns) }
        if let session, budget.fits(used: used, question: questionCost) { return session }
        let costs = turns.map { ChatBudget.cost(question: $0.question, answer: $0.answer) }
        let kept = ChatBudget.latestTurnsFitting(costs, within: budget.historyAllowance(question: questionCost))
        // Turns before this conversation's session (MM-55's saved history)
        // that do not fit are left out quietly the first time; after that the
        // panel says so once.
        if kept < turns.count, session != nil { leftOut = true }
        return rebuiltSession(keepingLast: kept, tools: tools, locale: locale)
    }

    private func rebuiltSession(keepingLast count: Int, tools: [any Tool], locale: String) -> LanguageModelSession {
        let instructions = catalog.chatInstructions(userLocaleIdentifier: locale)
        return state.withLock { current in
            let kept = Array(current.turns.suffix(count))
            var entries: [Transcript.Entry] = [
                .instructions(Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: instructions))],
                    toolDefinitions: tools.map { Transcript.ToolDefinition(tool: $0) }
                )),
            ]
            for turn in kept {
                entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: turn.question))])))
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: turn.answer))])))
            }
            let session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools, transcript: Transcript(entries: entries))
            current.session = session
            current.used = ChatBudget.instructionsReserve
                + kept.reduce(0) { $0 + ChatBudget.cost(question: $1.question, answer: $1.answer) }
            return session
        }
    }

    private static func tools(reader: ChatMapReader, events: ChatToolEvents) -> [any Tool] {
        [
            SearchTopicsTool(reader: reader, events: events),
            ReadTopicTool(reader: reader, events: events),
            ReadBranchTool(reader: reader, events: events),
        ]
    }

    // MARK: Errors

    private func mapped(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        if let toolError = error as? LanguageModelSession.ToolCallError {
            if toolError.underlyingError is CancellationError { return toolError.underlyingError }
            return failure(.generationFailed)
        }
        return failure(AppleGenerationErrors.aiError(for: error))
    }

    /// Logs the kind of failure only: questions and answers are map content.
    private func failure(_ error: AIError) -> AIError {
        Self.logger.error("Chat failed: \(error.logName, privacy: .public)")
        return error
    }
}

/// The framework's errors as `AIError`. 27 adds `LanguageModelError` and
/// deprecates `GenerationError`; either may arrive, so both are read.
enum AppleGenerationErrors {
    static func aiError(for error: any Error) -> AIError {
        if #available(macOS 27.0, iOS 27.0, *), let modelError = error as? LanguageModelError {
            if case .guardrailViolation = modelError { return .guardrailViolation }
            if case .refusal = modelError { return .refusal }
            if case .contextSizeExceeded = modelError { return .contextSizeExceeded }
            if case .unsupportedLanguageOrLocale = modelError { return .unsupportedLanguage }
            if case .rateLimited = modelError { return .rateLimited }
            return .generationFailed
        }
        guard let generationError = error as? LanguageModelSession.GenerationError else { return .generationFailed }
        if case .guardrailViolation = generationError { return .guardrailViolation }
        if case .refusal = generationError { return .refusal }
        if case .exceededContextWindowSize = generationError { return .contextSizeExceeded }
        if case .unsupportedLanguageOrLocale = generationError { return .unsupportedLanguage }
        if case .rateLimited = generationError { return .rateLimited }
        if case .assetsUnavailable = generationError { return .unavailable(.modelDownloading) }
        return .generationFailed
    }
}
