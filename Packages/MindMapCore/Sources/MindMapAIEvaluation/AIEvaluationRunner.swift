import Foundation
import MindMapAICore

/// The result of one case on one provider. `output` is the answer as text, for
/// reading failures by hand; the cases are made up, never a person's map.
public struct AIEvaluationOutcome: Codable, Sendable {
    public var id: String
    public var feature: String
    public var language: String
    public var passed: Bool
    /// Why it failed, in a few words; nil when it passed.
    public var reason: String?
    public var seconds: Double
    public var output: String
}

/// Answers the chat case: instructions and prompt in, text out.
public typealias AIEvaluationChatModel = @Sendable (_ instructions: String, _ prompt: String) async throws -> String

public enum AIEvaluationRunner {
    public static func run(_ evaluation: AIEvaluationCase, provider: any AIProvider, chat: AIEvaluationChatModel) async -> AIEvaluationOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        let result: (reason: String?, output: String)
        do {
            result = try await answer(evaluation, provider: provider, chat: chat)
        } catch {
            result = ("error: \(error)", "")
        }
        let elapsed = start.duration(to: clock.now)
        return AIEvaluationOutcome(
            id: evaluation.id, feature: evaluation.feature.rawValue, language: evaluation.language.rawValue,
            passed: result.reason == nil, reason: result.reason,
            seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            output: result.output
        )
    }

    /// The answer as text and the first check it fails.
    static func answer(_ evaluation: AIEvaluationCase, provider: any AIProvider, chat: AIEvaluationChatModel) async throws -> (String?, String) {
        let language = evaluation.language
        switch evaluation.request {
        case .suggestion(let request):
            let proposal = try await provider.suggest(request)
            let titles = proposal.topics.map(\.title)
            var reason = check(titles, language: language, minimum: evaluation.minimumCount)
            // The common rules forbid it, and MM-105's first run showed the
            // small model doing it: Accept would add a duplicate topic.
            let existing = Set(evaluation.existingTitles.map { $0.lowercased() })
            if reason == nil, let repeated = titles.first(where: { existing.contains($0.lowercased()) }) {
                reason = "repeats \(repeated)"
            }
            return (reason, titles.joined(separator: " | "))
        case .rewrite(let request):
            let titles = try await provider.rewrite(request).suggestions
            return (check(titles, language: language, minimum: evaluation.minimumCount), titles.joined(separator: " | "))
        case .summarize(let request):
            let text = try await provider.summarize(request).text
            return (check([text], language: language, minimum: 1, fact: evaluation.expectedFact), text)
        case .tags(let request):
            let suggestions = try await provider.suggestTags(request)
            let names = suggestions.entries.flatMap(\.names)
            return (check(names, language: language, minimum: evaluation.minimumCount, languageOptional: true), names.joined(separator: " | "))
        case .groups(let request):
            let groups = try await provider.suggestGroups(request).groups
            let titles = groups.map(\.title)
            return (check(titles, language: language, minimum: evaluation.minimumCount), titles.joined(separator: " | "))
        case .boundaryTitle(let request):
            let title = try await provider.summarizeBoundary(request).title
            return (check([title], language: language, minimum: 1), title)
        case .chat(let question):
            let text = try await chat(chatInstructions(question), chatPrompt(question))
            var reason = check([text], language: language, minimum: 1, fact: evaluation.expectedFact)
            if reason == nil, !text.contains("[\(question.answerHandle)]") { reason = "no citation [\(question.answerHandle)]" }
            return (reason, text)
        }
    }

    static func check(_ texts: [String], language: AILanguage, minimum: Int, fact: String? = nil, languageOptional: Bool = false) -> String? {
        let texts = texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if texts.count < minimum { return "\(texts.count) items, wanted \(minimum)" }
        // Tags are often one English word ("travel") in any language, which is
        // fine for a tag, so they only need to exist.
        if !languageOptional, !AIEvaluationCheck.isWritten(in: language, texts.joined(separator: " ")) { return "wrong language" }
        if let fact, !texts.contains(where: { $0.replacingOccurrences(of: " ", with: "").contains(fact.replacingOccurrences(of: " ", with: "")) }) {
            return "missing fact \(fact)"
        }
        return nil
    }

    /// The chat's rules without its tools: the outline arrives in the prompt
    /// with the handles the tools would have returned.
    public static func chatInstructions(_ chat: AIEvaluationChat) -> String {
        """
        You answer questions about the person's mind map, a tree of topics, using only the outline in the prompt.
        Topics have handles such as T1. After each fact, cite its topic in brackets, for example [T1]. Only cite handles from the outline.
        If the outline does not answer the question, say so. Never invent topics, facts or handles.
        Answer in a few sentences or a short list.
        The person's locale is \(chat.language.locale.identifier).
        """
    }

    public static func chatPrompt(_ chat: AIEvaluationChat) -> String {
        (["Map: \(chat.mapTitle)", "Outline:"] + chat.outline.enumerated().map { index, line in
            (index == 0 ? "- " : "  - ") + "\(line.handle): \(line.title)"
        } + ["Question: \(chat.question)", "You MUST respond in \(chat.language.englishName)."]).joined(separator: "\n")
    }
}
