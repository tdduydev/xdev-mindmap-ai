// Runs the benchmark's ten prompts through Apple Foundation Models with the
// app's @Generable shapes, for comparison with local-llm-bench.py (MM-77).
// Research only. Run: xcrun swift scripts/research/foundation-models-bench.swift OUT.jsonl
import Foundation
import FoundationModels

@Generable struct GeneratedTreeTopic { var temporaryID: String; var parentTemporaryID: String; var title: String }
@Generable struct GeneratedMindMap { var title: String; @Guide(.maximumCount(30)) var topics: [GeneratedTreeTopic] }
@Generable struct GeneratedTopic { var title: String }
@Generable struct GeneratedTopicList { @Guide(.maximumCount(12)) var topics: [GeneratedTopic] }
@Generable struct GeneratedRewrites { @Guide(.maximumCount(3)) var titles: [String] }

let common = """
You help a person build a mind map: a tree of short topics around one central topic.
A topic title is a short phrase of at most eight words, not a sentence.
Keep names, technical terms and mixed Vietnamese and English wording exactly as the person wrote them.
Never repeat a topic that is already in the map.
"""
let rules = [
    "generateMap": "Create a mind map for the subject the person describes, with a short title.\nGive each topic a unique temporaryID such as t1, t2 and t3.\nA main topic has an empty parentTemporaryID; a subtopic names the temporaryID of its parent, listed before it.",
    "expandTopic": "Suggest subtopics that belong directly under the focus topic.",
    "brainstorm": "Brainstorm varied ideas related to the focus topic. Mix practical and unexpected ideas.",
    "rewrite": "Rewrite the title of the focus topic as asked. Keep its meaning.",
    "summarize": "Summarize the focus topic and its subtopics in plain sentences. Do not add facts that are not in the map.",
]
// Same text as CASES in local-llm-bench.py.
let cases: [(String, String, String)] = [
    ("generateMap", "en", "Subject: Launch plan for a mobile budgeting app\nCreate a mind map with at most 20 topics and at most three levels."),
    ("generateMap", "vi", "Subject: Kế hoạch ôn thi tốt nghiệp THPT môn Toán trong 3 tháng\nCreate a mind map with at most 20 topics and at most three levels."),
    ("expandTopic", "en", "Map: Healthy habits\nFocus topic: Sleep\nExisting subtopics:\n- Fixed bedtime\nTopics beside the focus topic: Exercise; Nutrition; Stress\nSuggest up to 6 new subtopics for the focus topic."),
    ("expandTopic", "vi", "Map: Du lịch Đà Nẵng 4 ngày\nPath to the focus topic: Du lịch Đà Nẵng 4 ngày\nFocus topic: Ẩm thực\nExisting subtopics:\n- Mì Quảng\nTopics beside the focus topic: Lịch trình; Chi phí; Khách sạn\nSuggest up to 6 new subtopics for the focus topic."),
    ("brainstorm", "en", "Map: Team offsite\nFocus topic: Team-building activities\nBrainstorm up to 8 ideas around the focus topic."),
    ("brainstorm", "vi", "Map: Cửa hàng cà phê nhỏ\nFocus topic: Tăng khách quen\nBrainstorm up to 8 ideas around the focus topic."),
    ("rewrite", "en", "Map: Q4 roadmap\nFocus topic: we should probably look into making the onboarding flow faster for new users\nGive up to 3 alternative titles for the focus topic. Make it shorter."),
    ("rewrite", "vi", "Map: Kế hoạch dự án HIS\nFocus topic: cần phải xem lại cái backend architecture vì nó chạy chậm quá khi nhiều user\nGive up to 3 alternative titles for the focus topic. Make it clearer."),
    ("summarize", "en", "Map: Home renovation\nFocus topic: Kitchen\nExisting subtopics:\n- Budget: 12,000 USD\n- New cabinets\n  - Oak, matte finish\n- Move the sink under the window\n- Contractor: start in March\nSummarize this branch in two to four sentences."),
    ("summarize", "vi", "Map: Khởi nghiệp\nFocus topic: Gọi vốn vòng hạt giống\nExisting subtopics:\n- Mục tiêu 500.000 USD\n- Nhà đầu tư thiên thần\n  - Anh Minh (đã gặp)\n- Pitch deck 12 trang\n- Hạn chót: tháng 6\nSummarize this branch in two to four sentences."),
]

func encode<T: Encodable>(_ value: T) -> String { String(decoding: try! JSONEncoder().encode(value), as: UTF8.self) }

let out = FileHandle(forWritingAtPath: CommandLine.arguments[1]) ?? {
    FileManager.default.createFile(atPath: CommandLine.arguments[1], contents: nil)
    return FileHandle(forWritingAtPath: CommandLine.arguments[1])!
}()
let model = SystemLanguageModel.default
print("availability", model.availability, "context", model.contextSize)
for (feature, lang, prompt) in cases {
    let instructions = [common, rules[feature]!, "The person's locale is \(lang == "vi" ? "vi_VN" : "en_US").",
                        "You MUST respond in \(lang == "vi" ? "Vietnamese" : "English")."].joined(separator: "\n")
    let guardrails: SystemLanguageModel.Guardrails = (feature == "rewrite" || feature == "summarize") ? .permissiveContentTransformations : .default
    let session = LanguageModelSession(model: SystemLanguageModel(guardrails: guardrails), instructions: instructions)
    let start = Date()
    var output = ""
    var error = ""
    do {
        switch feature {
        case "generateMap":
            let r = try await session.respond(to: prompt, generating: GeneratedMindMap.self).content
            output = "title: \(r.title)\n" + r.topics.map { "\($0.temporaryID) <- \($0.parentTemporaryID): \($0.title)" }.joined(separator: "\n")
        case "expandTopic", "brainstorm":
            output = try await session.respond(to: prompt, generating: GeneratedTopicList.self).content.topics.map(\.title).joined(separator: "\n")
        case "rewrite":
            output = try await session.respond(to: prompt, generating: GeneratedRewrites.self).content.titles.joined(separator: "\n")
        default:
            output = try await session.respond(to: prompt).content
        }
    } catch let e {
        error = String(describing: e)
    }
    let seconds = Date().timeIntervalSince(start)
    let record: [String: String] = ["model": "apple-foundation-models", "feature": feature, "lang": lang,
                                    "total_s": String(format: "%.2f", seconds), "chars": "\(output.count)",
                                    "error": error, "output": output]
    out.seekToEndOfFile()
    out.write((encode(record) + "\n").data(using: .utf8)!)
    print(feature, lang, String(format: "%.1fs", seconds), error.isEmpty ? "ok" : error)
}
print("FM DONE")
