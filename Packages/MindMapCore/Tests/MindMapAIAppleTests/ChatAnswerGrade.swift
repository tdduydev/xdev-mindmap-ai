import Foundation
import MindMapAICore
import NaturalLanguage

/// One finished chat answer, as the evaluation keeps it: the text the person
/// reads and the titles of the topics it cites.
struct ChatEvaluationAnswer: Codable, Sendable, Hashable {
    var text: String
    var citedTitles: [String]
    /// Why no answer came (the model refused, ran out of room…), for the report.
    var failure: String?

    static func failed(_ reason: String) -> ChatEvaluationAnswer {
        ChatEvaluationAnswer(text: "", citedTitles: [], failure: reason)
    }
}

/// How one answer scores against its sample. Plain string checks, no model, so
/// the grading itself is unit tested and the same answer always scores the same.
struct ChatAnswerGrade: Equatable {
    /// `nil` where the check does not apply to the sample's kind.
    var answerFound: Bool?
    var citationsCorrect: Bool?
    /// Cited titles that are sources, over all cited titles.
    var citationPrecision: Double?
    var saysNotFound: Bool?
    var inQuestionLanguage: Bool

    init(_ answer: ChatEvaluationAnswer, for sample: ChatEvaluationSample) {
        let text = Self.folded(answer.text)
        switch sample.kind {
        case .found:
            answerFound = answer.failure == nil && sample.facts.allSatisfy { spellings in
                spellings.contains { text.contains(Self.folded($0)) }
            }
            let sources = Set(sample.sources.map(Self.folded))
            let cited = answer.citedTitles.map(Self.folded)
            let hits = cited.filter(sources.contains).count
            citationsCorrect = hits > 0
            citationPrecision = cited.isEmpty ? 0 : Double(hits) / Double(cited.count)
        case .notFound:
            let markers = Self.notFoundMarkers[sample.language, default: []]
            let says = markers.contains { text.contains(Self.folded($0)) }
            let invents = sample.forbidden.contains { text.contains(Self.folded($0)) }
            saysNotFound = answer.failure == nil && says && !invents
        }
        inQuestionLanguage = answer.failure == nil && Self.language(of: Self.prose(of: answer.text, for: sample)) == sample.language
    }

    /// The answer without handles and without the map's own words: "We stay
    /// at Mường Thanh" is English, though a short answer reads as Vietnamese
    /// to the recognizer while the hotel's name is in it.
    static func prose(of answer: String, for sample: ChatEvaluationSample) -> String {
        let quoted = (sample.facts.flatMap { $0 } + sample.sources).sorted { $0.count > $1.count }
        return quoted.reduce(CitationTable.displayText(answer)) { text, words in
            text.replacingOccurrences(of: words, with: " ", options: [.caseInsensitive, .diacriticInsensitive])
        }
    }

    /// Words an answer uses to say the map does not hold something. Loose on
    /// purpose: "not found" is judged by meaning, and the forbidden words of
    /// each sample catch an answer that says "not" and invents anyway.
    static let notFoundMarkers: [AILanguage: [String]] = [
        .english: ["not ", "n't", "no ", "nothing", "none", "unable", "cannot"],
        .vietnamese: ["không", "chưa"],
        .japanese: ["ありません", "見つかりません", "ない"],
    ]

    /// Case and accents folded, so "Mường Thanh" matches "muong thanh" and
    /// "may 12" matches "May 12". The Vietnamese đ is not an accent to
    /// Foundation, so both sides keep it.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func language(of text: String) -> AILanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = AILanguage.allCases.map { NLLanguage($0.rawValue) }
        recognizer.processString(text)
        return recognizer.dominantLanguage.flatMap { AILanguage(rawValue: $0.rawValue) }
    }
}
