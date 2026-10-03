import Foundation
import MindMapAICore
import MindMapDomain
import Testing

struct AICapabilitiesTests {
    @Test func aReadyModelIsReadyOnlyInItsLanguages() {
        let capabilities = AICapabilities(model: .ready, supportedLanguages: [.english], contextSize: 4_096)

        #expect(capabilities.availability(for: .expandTopic, in: .english) == .ready)
        #expect(capabilities.availability(for: .expandTopic, in: .vietnamese) == .languageUnsupported)
        #expect(capabilities.showsAIEntryPoints)
    }

    @Test(arguments: [AIAvailability.appleIntelligenceOff, .modelDownloading, .unknown])
    func aModelThatIsNotReadyKeepsEntryPointsWithItsReason(_ state: AIAvailability) {
        let capabilities = AICapabilities(model: state, supportedLanguages: [.english], contextSize: 4_096)

        for feature in AIFeature.allCases {
            #expect(capabilities.availability(for: feature, in: .english) == state)
        }
        #expect(capabilities.showsAIEntryPoints)
        // Languages and context size mean nothing until the model is ready.
        #expect(capabilities.supportedLanguages.isEmpty)
        #expect(capabilities.contextSize == nil)
    }

    @Test func anIneligibleDeviceHidesEveryEntryPoint() {
        let capabilities = AICapabilities.notEligible

        #expect(!capabilities.showsAIEntryPoints)
        for feature in AIFeature.allCases {
            for language in AILanguage.allCases {
                #expect(capabilities.availability(for: feature, in: language) == .deviceNotEligible)
            }
        }
    }
}

struct AILanguageTests {
    @Test func followsTheLocale() {
        #expect(AILanguage(preferredFor: Locale(identifier: "vi_VN")) == .vietnamese)
        #expect(AILanguage(preferredFor: Locale(identifier: "vi")) == .vietnamese)
        #expect(AILanguage(preferredFor: Locale(identifier: "en_GB")) == .english)
        #expect(AILanguage(preferredFor: Locale(identifier: "fr_FR")) == .english)
        #expect(AILanguage(preferredFor: Locale(identifier: "ja_JP")) == .japanese)
        #expect(AILanguage(preferredFor: Locale(identifier: "ja")) == .japanese)
    }

    @Test func japaneseIsNamedForTheModel() {
        #expect(AILanguage.japanese.rawValue == "ja")
        #expect(AILanguage.japanese.locale.identifier == "ja_JP")
        #expect(AILanguage.japanese.englishName == "Japanese")
        #expect(AILanguage.allCases == [.english, .vietnamese, .japanese])
    }

    @Test func detectsTheLanguageOfTheText() {
        #expect(AILanguage.dominant(in: "Kế hoạch ra mắt sản phẩm mới cho khách hàng", fallback: .english) == .vietnamese)
        #expect(AILanguage.dominant(in: "Plan the launch of the new product for customers", fallback: .vietnamese) == .english)
        #expect(AILanguage.dominant(in: "", fallback: .vietnamese) == .vietnamese)
        #expect(AILanguage.dominant(in: "新製品の発売計画を顧客に向けて立てる", fallback: .english) == .japanese)
        #expect(AILanguage.dominant(in: "マーケティングのアイデアを考える", fallback: .vietnamese) == .japanese)
        // Kanji only would read as Chinese without the language constraint.
        #expect(AILanguage.dominant(in: "東京旅行計画", fallback: .english) == .japanese)
    }

    @Test func mixedJapaneseAndEnglishCountsAsJapanese() {
        #expect(AILanguage.dominant(in: "新しいiPhoneアプリのマーケティング計画", fallback: .english) == .japanese)
    }

    @Test func rewriteStylesThatTranslatePickTheirLanguage() {
        let context = AIContext(
            mapID: MapID(),
            mapTitle: "Map",
            focus: ContextTopic(nodeID: NodeID(), parentID: nil, title: "Topic", depth: 0),
            language: .english,
            userLocaleIdentifier: "en_US"
        )
        #expect(RewriteRequest(context: context, style: .vietnamese).outputLanguage == .vietnamese)
        #expect(RewriteRequest(context: context, style: .shorter).outputLanguage == .english)
        #expect(RewriteRequest(context: context, style: .japanese).outputLanguage == .japanese)
    }
}
