import Foundation
import NaturalLanguage

/// A language the app asks the model to answer in. V1 supports the two
/// languages of the app's interface.
public enum AILanguage: String, Hashable, Sendable, CaseIterable, Codable {
    case english = "en"
    case vietnamese = "vi"

    /// The locale handed to the model's language checks.
    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .vietnamese: Locale(identifier: "vi_VN")
        }
    }

    /// How instructions, which are always written in English, name the language.
    public var englishName: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Vietnamese"
        }
    }

    /// The output language for someone using `locale`: Vietnamese for a
    /// Vietnamese locale, English otherwise.
    public init(preferredFor locale: Locale) {
        self = locale.language.languageCode?.identifier == "vi" ? .vietnamese : .english
    }

    /// The language most of `text` is written in, or `fallback` when the text is
    /// too short to tell. Mixed titles such as "Thiết kế backend architecture"
    /// count as Vietnamese, since the person wrote the sentence in Vietnamese.
    public static func dominant(in text: String, fallback: AILanguage) -> AILanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .vietnamese]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .vietnamese?: return .vietnamese
        case .english?: return .english
        default: return fallback
        }
    }
}
