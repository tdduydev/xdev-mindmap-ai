import Foundation
@testable import MindMapAIApple
import MindMapAICore
import Testing
#if canImport(Evaluations)
import Evaluations
#endif

/// The grading the evaluation relies on, without the model: it runs on every
/// `swift test`, so a broken check shows before anyone reads a score.
@Suite("Chat evaluation grading")
struct ChatAnswerGradeTests {
    let budget = ChatEvaluationSample.english[2]
    let designer = ChatEvaluationSample.english[4]
    let hotel = ChatEvaluationSample.vietnamese[1]
    let driver = ChatEvaluationSample.vietnamese[4]

    @Test func aFoundAnswerNeedsTheFactAndASourceCitation() {
        let good = ChatAnswerGrade(ChatEvaluationAnswer(text: "The total budget is $12,000 [T1].", citedTitles: ["Budget"]), for: budget)
        #expect(good.answerFound == true)
        #expect(good.citationsCorrect == true)
        #expect(good.citationPrecision == 1)
        #expect(good.saysNotFound == nil)
        #expect(good.inQuestionLanguage)

        let uncited = ChatAnswerGrade(ChatEvaluationAnswer(text: "The total budget is $12,000.", citedTitles: []), for: budget)
        #expect(uncited.answerFound == true)
        #expect(uncited.citationsCorrect == false)
        #expect(uncited.citationPrecision == 0)

        let wrong = ChatAnswerGrade(ChatEvaluationAnswer(text: "The budget is $10,000 [T2].", citedTitles: ["Beta"]), for: budget)
        #expect(wrong.answerFound == false)
        #expect(wrong.citationsCorrect == false)
    }

    @Test func precisionCountsCitationsOutsideTheSources() {
        let grade = ChatAnswerGrade(
            ChatEvaluationAnswer(text: "It is $12,000 [T1], see also the beta [T2].", citedTitles: ["Budget", "Beta"]),
            for: budget
        )
        #expect(grade.citationsCorrect == true)
        #expect(grade.citationPrecision == 0.5)
    }

    @Test func vietnameseFactsMatchWithoutAccentsOrCase() {
        let grade = ChatAnswerGrade(
            ChatEvaluationAnswer(text: "Chúng ta ở khách sạn MUONG THANH [T1], nhận phòng lúc 14 giờ.", citedTitles: ["Khách sạn"]),
            for: hotel
        )
        #expect(grade.answerFound == true)
        #expect(grade.inQuestionLanguage)
    }

    @Test func notFoundNeedsTheAnswerToSaySoInItsLanguage() {
        #expect(ChatAnswerGrade(ChatEvaluationAnswer(text: "The map doesn't name a lead designer.", citedTitles: []), for: designer).saysNotFound == true)
        #expect(ChatAnswerGrade(ChatEvaluationAnswer(text: "Mai Tran is the lead designer [T1].", citedTitles: ["Press release"]), for: designer).saysNotFound == false)
        #expect(ChatAnswerGrade(ChatEvaluationAnswer(text: "Sơ đồ không nói ai lái xe đưa đón.", citedTitles: []), for: driver).saysNotFound == true)
    }

    @Test func notFoundFailsWhenTheAnswerInventsAnyway() {
        let price = ChatEvaluationSample.english[5]
        let grade = ChatAnswerGrade(ChatEvaluationAnswer(text: "It's not in the map, but probably $2.99.", citedTitles: []), for: price)
        #expect(grade.saysNotFound == false)
    }

    @Test func anAnswerInTheWrongLanguageIsMarked() {
        let grade = ChatAnswerGrade(ChatEvaluationAnswer(text: "We stay at the Mường Thanh hotel and check in at 2 pm [T1].", citedTitles: ["Khách sạn"]), for: hotel)
        #expect(grade.answerFound == true)
        #expect(!grade.inQuestionLanguage)
    }

    @Test func theMapsOwnWordsDoNotDecideTheLanguage() {
        let crossLanguage = ChatEvaluationSample.english[6]
        let grade = ChatAnswerGrade(ChatEvaluationAnswer(text: "We stay at Mường Thanh [T4].", citedTitles: ["Khách sạn"]), for: crossLanguage)
        #expect(grade.answerFound == true)
        #expect(grade.inQuestionLanguage)
    }

    @Test func aFailedAnswerPassesNothing() {
        let grade = ChatAnswerGrade(.failed("refusal"), for: designer)
        #expect(grade.saysNotFound == false)
        #expect(!grade.inQuestionLanguage)
    }

    @Test func everyFoundSampleNamesFactsAndSourcesThatAreInItsMap() throws {
        for sample in ChatEvaluationSample.all {
            let fixture = try sample.map.makeFixture()
            let titles = Set(fixture.state.nodes.values.map(\.title))
            switch sample.kind {
            case .found:
                #expect(!sample.facts.isEmpty, "\(sample.id)")
                #expect(!sample.sources.isEmpty && sample.sources.allSatisfy(titles.contains), "\(sample.id)")
            case .notFound:
                #expect(sample.facts.isEmpty && sample.sources.isEmpty, "\(sample.id)")
            }
        }
        #expect(Set(ChatEvaluationSample.all.map(\.id)).count == ChatEvaluationSample.all.count)
        for language in [AILanguage.english, .vietnamese] {
            let kinds = ChatEvaluationSample.all.filter { $0.language == language }.map(\.kind)
            #expect(kinds.contains(.found) && kinds.contains(.notFound))
        }
    }
}

#if canImport(Evaluations)
/// Outside the suite, which cannot name its own type in its traits.
enum ChatEvaluationOutput {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["MINDMAP_CHAT_EVALUATIONS"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
}

/// The evaluation on the real model, for the 26.4 and 27 chat prompts. Slow
/// (a few minutes) and opt-in: `scripts/chat-evaluations.sh` sets
/// `MINDMAP_CHAT_EVALUATIONS` to the folder for the JSON reports.
@Suite(
    "Chat evaluations",
    .enabled(if: ChatEvaluationOutput.folder != nil, "Set MINDMAP_CHAT_EVALUATIONS to run them"),
    .enabled(if: AppleCapabilityProbe.current().model == .ready, "Needs the on-device model"),
    .serialized
)
struct ChatEvaluationRun {
    @Test(arguments: [PromptVersion.v26_4, .v27_0])
    func chatPrompts(_ version: PromptVersion) async throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let evaluation = try await ChatEvaluation.make(version: version)
        let result = try await evaluation.run(info: ["prompts": version.rawValue, "os": ProcessInfo.processInfo.operatingSystemVersionString])

        if let folder = ChatEvaluationOutput.folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let report = folder.appending(path: "chat-\(version.rawValue).json")
            try result.jsonData(includeTranscripts: true).write(to: report)
        }
        print("Chat evaluation, prompts \(version.rawValue):\n\(result.groupedSummary)")
        #expect(!result.errors.hasFailures, "\(result.errors)")
        for floor in ChatEvaluation.floors {
            let mean = result.aggregateValue(.mean(of: floor.metric))
            #expect(mean >= floor.minimum, "\(floor.metric.name) is \(mean) with the \(version.rawValue) prompts")
        }
    }
}
#endif
