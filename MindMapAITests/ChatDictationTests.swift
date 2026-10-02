import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapCapture
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import SwiftUI
import Testing

/// Ask by voice (MM-80, FR-AI-21) with `FakeVoiceTranscriber`: the words go
/// into the draft, never asked on their own, and Pro gates the microphone.
@Suite("Chat dictation")
struct ChatDictationTests {
    let repository: SwiftDataMapRepository
    let transcriber = FakeVoiceTranscriber()
    let chatProvider = MockChatProvider()
    let defaults: UserDefaults

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        defaults = try #require(UserDefaults(suiteName: "ChatDictationTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
    }

    private struct OpenFailed: Error {}

    private struct Unlocked: ProEntitlements {
        func allows(_ feature: ProFeature) -> Bool { true }
    }

    private struct Locked: ProEntitlements {
        func allows(_ feature: ProFeature) -> Bool { feature != .voiceInput }
    }

    private func open(
        entitlements: any ProEntitlements = Unlocked(),
        preferredLanguages: [String] = ["en-US"]
    ) async throws -> ChatDictation {
        let engine = try GraphEngine(state: GraphState.newMap(title: "Launch"))
        try await repository.create(engine.state)
        guard case .ready(let session) = await EditorSession.open(mapID: engine.state.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let aiProvider = MockAIProvider(capabilities: .readyForTesting)
        chatProvider.setCapabilities(.readyForTesting)
        let service = AIService(provider: { aiProvider }, chatProvider: { [chatProvider] in chatProvider }, entitlements: Unlocked(), defaults: defaults)
        await service.refresh()
        let assistant = AIAssistant(session: session, service: service, defaults: defaults, locale: Locale(identifier: "en_US"))
        let chat = MapChat(session: session, assistant: assistant, locale: Locale(identifier: "en_US"), copyText: { _ in })
        return ChatDictation(
            chat: chat,
            transcriber: transcriber,
            entitlements: entitlements,
            defaults: defaults,
            preferredLanguages: preferredLanguages
        )
    }

    /// The listen loop runs in a task; give it turns until `condition` holds.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
    }

    private func listen(_ dictation: ChatDictation) async {
        dictation.start()
        await waitUntil { dictation.isListening }
    }

    @Test func theWordsGoIntoTheDraftAndAreNotAsked() async throws {
        transcriber.script(heard: [.final("What comes first"), .volatile("in the")], onFinish: [.final("in the plan?")])
        let dictation = try await open()

        await listen(dictation)
        await waitUntil { dictation.chat.draft == "What comes first in the" }
        #expect(dictation.chat.draft == "What comes first in the", "the guess shows while listening")

        dictation.stop()
        await dictation.listening?.value
        #expect(dictation.phase == .idle)
        #expect(dictation.chat.draft == "What comes first in the plan?")
        #expect(dictation.chat.entries.isEmpty, "nothing is asked until the person asks")
        #expect(chatProvider.questions.isEmpty)
        #expect(!dictation.chat.session.canUndo, "dictating never edits the map")
    }

    @Test func wordsFollowWhatWasTyped() async throws {
        transcriber.script(heard: [.final("the budget?")])
        let dictation = try await open()
        dictation.chat.draft = "What about"

        await listen(dictation)
        await waitUntil { dictation.chat.draft != "What about" }
        #expect(dictation.chat.draft == "What about the budget?")
    }

    @Test func cancelPutsTheDraftBack() async throws {
        transcriber.script(heard: [.final("Summarize")])
        let dictation = try await open()
        dictation.chat.draft = "Typed"

        await listen(dictation)
        await waitUntil { dictation.chat.draft == "Typed Summarize" }
        dictation.cancel()
        #expect(dictation.phase == .idle)
        #expect(dictation.chat.draft == "Typed")

        // Late words from the cancelled session never reach the field.
        transcriber.hear(.final("late"))
        await Task.yield()
        #expect(dictation.chat.draft == "Typed")
    }

    @Test func anEditWhileListeningIsKept() async throws {
        transcriber.script(heard: [.final("Summarize")])
        let dictation = try await open()

        await listen(dictation)
        await waitUntil { dictation.chat.draft == "Summarize" }
        dictation.chat.draft = "Summarize the plan"
        transcriber.hear(.final("briefly"))
        await waitUntil { dictation.chat.draft != "Summarize the plan" }
        #expect(dictation.chat.draft == "Summarize the plan briefly")

        dictation.chat.draft = "Edited"
        dictation.cancel()
        #expect(dictation.chat.draft == "Edited", "Cancel never throws away the person's own edit")
    }

    @Test func withoutProTheMicrophoneOpensThePaywall() async throws {
        let dictation = try await open(entitlements: Locked())

        dictation.start()

        #expect(dictation.paywall?.feature == .voiceInput)
        #expect(dictation.phase == .idle)
        #expect(transcriber.startedLanguages.isEmpty, "nothing listens without Pro")
    }

    @Test func listensInTheSettingsLanguage() async throws {
        let dictation = try await open(preferredLanguages: ["en-US"])
        AppStorage<VoiceLanguage?>(VoiceInput.languageKey, store: defaults).wrappedValue = .vietnamese

        await listen(dictation)

        #expect(dictation.language == .vietnamese)
        #expect(transcriber.startedLanguages == [.vietnamese])
    }

    @Test func aDeniedPermissionSaysSo() async throws {
        transcriber.setPermissionError(.microphoneDenied)
        let dictation = try await open()

        dictation.start()
        await dictation.listening?.value

        #expect(dictation.phase == .failed(.microphoneDenied))
        #expect(dictation.chat.draft.isEmpty)
        #expect(dictation.canToggle, "the microphone can be tried again")
    }

    @Test func aMissingModelWaitsForDownload() async throws {
        transcriber.setAvailability(.needsDownload, for: .english)
        transcriber.script(heard: [.final("Hello")])
        let dictation = try await open()

        dictation.start()
        await dictation.listening?.value
        #expect(dictation.phase == .needsDownload)
        #expect(transcriber.preparedLanguages.isEmpty, "nothing downloads before the person asks")

        dictation.download()
        await waitUntil { dictation.isListening }
        #expect(transcriber.preparedLanguages == [.english])
        await waitUntil { dictation.chat.draft == "Hello" }
        #expect(dictation.chat.draft == "Hello")
    }

    @Test func hiddenWhereTheChatCannotAsk() async throws {
        let dictation = try await open()
        dictation.chat.service.isEnabled = false

        #expect(!dictation.isAvailable)
        #expect(!dictation.canToggle)
        dictation.start()
        #expect(transcriber.startedLanguages.isEmpty)
    }

    @Test func joiningKeepsOneSpace() {
        #expect(ChatDictation.join("", " Hello ") == "Hello")
        #expect(ChatDictation.join("What ", "now") == "What now")
        #expect(ChatDictation.join("Line\n", "next") == "Line\nnext")
        #expect(ChatDictation.join("Kept", "  ") == "Kept")
    }
}
