import Foundation
import MindMapAICore

/// Turns a local model's text into the app's values. Small models wrap JSON in
/// Markdown fences or a Qwen3 <think> block, so both are stripped first.
enum LocalAnswer {
    struct MindMap: Decodable {
        struct Topic: Decodable { var temporaryID: String; var parentTemporaryID: String?; var title: String }
        var title: String
        var topics: [Topic]
    }
    struct TopicList: Decodable {
        struct Topic: Decodable { var title: String }
        var topics: [Topic]
    }
    struct Rewrites: Decodable { var titles: [String] }
    struct Summary: Decodable { var summary: String }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let json = jsonObject(in: text) else { throw AIError.invalidResponse(.empty) }
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw AIError.invalidResponse(.empty)
        }
    }

    /// The first balanced {...} after removing <think> blocks and fences.
    static func jsonObject(in text: String) -> String? {
        var body = text
        while let open = body.range(of: "<think>") {
            let close = body.range(of: "</think>", range: open.upperBound..<body.endIndex)
            body.removeSubrange(open.lowerBound..<(close?.upperBound ?? body.endIndex))
        }
        guard let start = body.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in body[start...].indices {
            let character = body[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(body[start...index]) }
            default: break
            }
        }
        return nil
    }
}
