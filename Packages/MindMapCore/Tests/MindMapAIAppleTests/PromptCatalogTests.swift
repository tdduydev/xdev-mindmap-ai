import Foundation
@testable import MindMapAIApple
import MindMapAICore
import MindMapDomain
import MindMapTestSupport
import Testing

struct PromptCatalogTests {
    private let catalog = PromptCatalog(version: .v26_0)

    private func context(language: AILanguage = .vietnamese) throws -> AIContext {
        let fixture = try OutlineFixture("""
        Dự án HIS
          Thiết kế backend architecture
            Database
          Frontend
        """, mapTitle: "Dự án HIS")
        return try AIContextBuilder().context(
            for: fixture["Thiết kế backend architecture"],
            in: fixture.state,
            language: language,
            userLocaleIdentifier: language.locale.identifier
        )
    }

    @Test(arguments: AIFeature.allCases)
    func instructionsAreEnglishAndNameTheOutputLanguage(_ feature: AIFeature) {
        let vietnamese = catalog.instructions(for: feature, language: .vietnamese, userLocaleIdentifier: "vi_VN")
        #expect(vietnamese.contains("The person's locale is vi_VN."))
        #expect(vietnamese.hasSuffix("You MUST respond in Vietnamese."))
        #expect(vietnamese.contains("mixed Vietnamese and English wording exactly as the person wrote them"))

        let english = catalog.instructions(for: feature, language: .english, userLocaleIdentifier: "en_US")
        #expect(english.hasSuffix("You MUST respond in English."))

        let japanese = catalog.instructions(for: feature, language: .japanese, userLocaleIdentifier: "ja_JP")
        #expect(japanese.contains("The person's locale is ja_JP."))
        #expect(japanese.hasSuffix("You MUST respond in Japanese."))
    }

    @Test func japaneseChatAndRewriteNameJapanese() throws {
        let chat = catalog.chatPrompt(question: "発売日はいつ？", mapTitle: "製品発売", language: .japanese)
        #expect(chat.contains("Map: 製品発売"))
        #expect(chat.contains("Question: 発売日はいつ？"))
        #expect(chat.hasSuffix("You MUST respond in Japanese."))

        let rewrite = catalog.prompt(for: RewriteRequest(context: try context(), style: .japanese))
        #expect(rewrite.hasSuffix("Translate it into Japanese."))
    }

    @Test func thePersonsTextGoesInThePromptKeptAsWritten() throws {
        let base = try context()
        let request = ExpandTopicRequest(context: base, maximumTopics: 5)
        let prompt = catalog.prompt(for: request)

        #expect(prompt.contains("Map: Dự án HIS"))
        #expect(prompt.contains("Path to the focus topic: Dự án HIS"))
        #expect(prompt.contains("Focus topic: Thiết kế backend architecture"))
        #expect(prompt.contains("Existing subtopics:\n- Database"))
        #expect(prompt.contains("Topics beside the focus topic: Frontend"))
        #expect(prompt.hasSuffix("Suggest up to 5 new subtopics for the focus topic."))

        let instructions = catalog.instructions(for: .expandTopic, language: .vietnamese, userLocaleIdentifier: "vi_VN")
        #expect(!instructions.contains("Thiết kế"))
    }

    @Test func aTruncatedContextSaysSo() throws {
        let base = try context()
        let truncated = AIContext(
            mapID: base.mapID,
            mapTitle: base.mapTitle,
            focus: base.focus,
            descendants: base.descendants,
            omittedDescendantCount: 7,
            language: base.language,
            userLocaleIdentifier: base.userLocaleIdentifier
        )
        #expect(catalog.render(truncated).contains("(7 more subtopics are not shown.)"))
    }

    @Test func combinesPartialSummaries() throws {
        let base = try context()
        let request = SummarizeRequest(context: base, partialSummaries: ["Part one.", "Part two."])
        let prompt = catalog.prompt(for: request)

        #expect(prompt.contains("- Part one.\n- Part two."))
        #expect(prompt.hasSuffix("Combine them into one summary of two to four sentences."))
    }

    @Test func aBrainstormQuestionGoesInThePrompt() throws {
        let base = try context()
        let withQuestion = catalog.prompt(for: BrainstormRequest(context: base, question: " Rủi ro là gì? "))
        #expect(withQuestion.hasSuffix("ideas for this question: Rủi ro là gì?"))

        let withoutQuestion = catalog.prompt(for: BrainstormRequest(context: base, question: "  "))
        #expect(withoutQuestion.hasSuffix("ideas around the focus topic."))
    }

    @Test func everyModelGenerationHasPrompts() {
        for version in PromptVersion.allCases {
            let catalog = PromptCatalog(version: version)
            for feature in AIFeature.allCases {
                #expect(!catalog.instructions(for: feature, language: .english, userLocaleIdentifier: "en_US").isEmpty)
            }
        }
        #expect(PromptVersion.allCases.contains(.current))
    }
}

@Suite("Suggest Tags prompt")
struct SuggestTagsPromptTests {
    @Test func listsTopicsByReferenceWithExistingTagsAsWritten() {
        let topic = TagSuggestionTopic(reference: "t1", nodeID: NodeID(), title: "Thiết kế backend", path: ["Dự án"], tags: ["Việc"])
        let request = SuggestTagsRequest(
            mapTitle: "Kế hoạch", topics: [topic], availableTags: ["Việc", "Gấp"], language: .vietnamese, userLocaleIdentifier: "vi_VN"
        )

        let prompt = PromptCatalog().prompt(for: request)

        #expect(prompt.contains("Existing tags: Việc; Gấp"))
        #expect(prompt.contains("- t1: Thiết kế backend (under Dự án) [tags: Việc]"))
        #expect(prompt.hasSuffix("Suggest up to 3 tags for each topic, by its reference."))
    }
}
