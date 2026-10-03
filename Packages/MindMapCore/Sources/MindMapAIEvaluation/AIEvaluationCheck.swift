import Foundation
import MindMapAICore

/// What an evaluation looks for in an answer, beyond the shape the provider
/// already checked: the right language and, where the case names one, a fact
/// from the map. Deliberately loose: it catches the failures MM-77 saw (wrong
/// language, empty or invented answers), not style.
public enum AIEvaluationCheck {
    /// Whether `text` is written in `language`. Names and technical terms in
    /// English are allowed in every language, so this looks for the marks
    /// that only the expected language has, and the absence of the others'.
    public static func isWritten(in language: AILanguage, _ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let japanese = letters.filter(isJapanese).count
        let vietnamese = text.lowercased().unicodeScalars.filter { vietnameseLetters.contains($0) }.count
        switch language {
        case .japanese:
            return Double(japanese) / Double(letters.count) >= 0.3
        case .vietnamese:
            return japanese == 0 && vietnamese > 0
        case .english:
            return japanese == 0 && Double(vietnamese) / Double(letters.count) < 0.02
        }
    }

    /// Hiragana, katakana and CJK ideographs.
    static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xFF66...0xFF9F: true
        default: false
        }
    }

    /// Letters Vietnamese has and English does not: đ, the hats and horns,
    /// and every tone mark. French or Spanish accents overlap a few of them,
    /// which no case here uses.
    static let vietnameseLetters = Set("ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ".unicodeScalars)
}
