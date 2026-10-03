#if canImport(Evaluations)
import Evaluations
import Foundation
@testable import MindMapAIApple
import MindMapAICore
import MindMapDomain
import MindMapPersistence
import MindMapQuery
import Testing

/// The chat's answer quality on the device model (MM-53, C4 in docs/chat.md),
/// for one generation of the chat prompts. Each sample is a fresh conversation
/// on its fixture map through `AppleChatProvider`, as the app asks it.
@available(macOS 27.0, iOS 27.0, *)
struct ChatEvaluation: Evaluation {
    static let answerFound = Metric("answerFound")
    static let citationsCorrect = Metric("citationsCorrect")
    static let citationPrecision = Metric("citationPrecision")
    static let saysNotFound = Metric("saysNotFound")
    static let inQuestionLanguage = Metric("inQuestionLanguage")

    /// The lowest mean each metric may reach before the run fails [Đề xuất].
    /// The model is not deterministic: in MM-53's first runs the same prompts
    /// scored 1.0 then 0.7 on answers found, as a question answered once was
    /// "not found" the next time. So the floors sit under the lowest run seen
    /// and flag a prompt or tool change that loses a kind of question, not
    /// one unlucky sample.
    static let floors: [(metric: Metric, minimum: Double)] = [
        (answerFound, 0.6),
        (citationsCorrect, 0.6),
        (saysNotFound, 0.5),
        (inQuestionLanguage, 0.85),
    ]

    let version: PromptVersion
    let samples: [ChatEvaluationSample]
    private let provider: AppleChatProvider
    private let maps: [ChatEvaluationMap: MapID]

    /// The fixture maps go into one in-memory store, read through `MapQueries`
    /// like the person's library.
    static func make(version: PromptVersion, samples: [ChatEvaluationSample] = ChatEvaluationSample.all) async throws -> ChatEvaluation {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        var maps: [ChatEvaluationMap: MapID] = [:]
        for map in ChatEvaluationMap.allCases {
            let fixture = try map.makeFixture()
            try await repository.create(fixture.state)
            maps[map] = fixture.state.map.id
        }
        let queries = MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository))
        return ChatEvaluation(
            version: version,
            samples: samples,
            provider: AppleChatProvider(queries: queries, catalog: PromptCatalog(version: version)),
            maps: maps
        )
    }

    var dataset: ArrayLoader<ChatEvaluationSample> { ArrayLoader(samples: samples) }

    func subject(from sample: ChatEvaluationSample) async throws -> ModelSubject<ChatEvaluationAnswer> {
        guard let mapID = maps[sample.map] else { throw SubjectInferenceError.failed(reason: "No fixture map \(sample.map)") }
        let conversation = provider.conversation(in: .map(mapID), history: [])
        let message = ChatMessage(text: sample.question, language: sample.language, userLocaleIdentifier: sample.language.locale.identifier)
        do {
            var last: ChatUpdate?
            for try await update in conversation.send(message) { last = update }
            guard let last, last.isComplete else { return ModelSubject(value: .failed("The answer did not finish")) }
            return ModelSubject(value: ChatEvaluationAnswer(text: last.text, citedTitles: last.citations.map(\.title)))
        } catch let error as AIError {
            // A refusal or a full context is a bad answer, not a broken run.
            return ModelSubject(value: .failed(error.logName))
        }
    }

    var evaluators: [any EvaluatorProtocol<ChatEvaluationSample, ModelSubject<ChatEvaluationAnswer>>] {
        Evaluator<ChatEvaluationSample> { sample, subject in
            let grade = ChatAnswerGrade(subject.value, for: sample)
            return Self.metric(Self.answerFound, grade.answerFound, subject.value)
        }
        Evaluator<ChatEvaluationSample> { sample, subject in
            let grade = ChatAnswerGrade(subject.value, for: sample)
            return Self.metric(Self.citationsCorrect, grade.citationsCorrect, subject.value)
        }
        Evaluator<ChatEvaluationSample> { sample, subject in
            guard let precision = ChatAnswerGrade(subject.value, for: sample).citationPrecision else {
                return Self.citationPrecision.ignore()
            }
            return Self.citationPrecision.scoring(precision, rationale: subject.value.citedTitles.joined(separator: "; "))
        }
        Evaluator<ChatEvaluationSample> { sample, subject in
            let grade = ChatAnswerGrade(subject.value, for: sample)
            return Self.metric(Self.saysNotFound, grade.saysNotFound, subject.value)
        }
        Evaluator<ChatEvaluationSample> { sample, subject in
            let grade = ChatAnswerGrade(subject.value, for: sample)
            return Self.metric(Self.inQuestionLanguage, grade.inQuestionLanguage, subject.value)
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        for metric in [Self.answerFound, Self.citationsCorrect, Self.citationPrecision, Self.saysNotFound, Self.inQuestionLanguage] {
            aggregator.computeMean(of: metric)
        }
    }

    /// The answer is the rationale, so the saved report shows why a sample failed.
    private static func metric(_ metric: Metric, _ passed: Bool?, _ answer: ChatEvaluationAnswer) -> Metric {
        guard let passed else { return metric.ignore() }
        let rationale = answer.failure ?? answer.text
        return passed ? metric.passing(rationale: rationale) : metric.failing(rationale: rationale)
    }
}

@available(macOS 27.0, iOS 27.0, *)
extension ChatEvaluationSample: SampleProtocol {
    var input: String { question }
    /// Answers are graded by facts and sources, not compared to one text.
    var expected: ChatEvaluationAnswer? { nil }
}
#endif
