import Foundation
import NaturalLanguage

/// A language the app asks the model to answer in: the three languages of the
/// app's interface.
public enum AILanguage: String, Hashable, Sendable, CaseIterable, Codable {
    case english = "en"
    case vietnamese = "vi"
    case japanese = "ja"

    /// The locale handed to the model's language checks.
    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .vietnamese: Locale(identifier: "vi_VN")
        case .japanese: Locale(identifier: "ja_JP")
        }
    }

    /// How instructions, which are always written in English, name the language.
    public var englishName: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Vietnamese"
        case .japanese: "Japanese"
        }
    }

    /// The output language for someone using `locale`: Vietnamese or Japanese
    /// for those locales, English otherwise.
    public init(preferredFor locale: Locale) {
        switch locale.language.languageCode?.identifier {
        case "vi": self = .vietnamese
        case "ja": self = .japanese
        default: self = .english
        }
    }

    /// The language most of `text` is written in, or `fallback` when the text is
    /// too short to tell. Mixed titles such as "Thiết kế backend architecture"
    /// count as Vietnamese, since the person wrote the sentence in Vietnamese.
    public static func dominant(in text: String, fallback: AILanguage) -> AILanguage {
        let recognizer = NLLanguageRecognizer()
        // Without the constraint a title written only in kanji reads as Chinese.
        recognizer.languageConstraints = [.english, .vietnamese, .japanese]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .vietnamese?: return .vietnamese
        case .japanese?: return .japanese
        case .english?: return .english
        default: return fallback
        }
    }
}
