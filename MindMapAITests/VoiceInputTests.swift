import Foundation
@testable import MindMapAI
import MindMapCapture
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import Testing

/// Voice input end to end with `FakeVoiceTranscriber` and a real session on an
/// in-memory store (FR-AI-21).
@Suite("Voice input")
struct VoiceInputTests {
    let repository: SwiftDataMapRepository
    let transcriber = FakeVoiceTranscriber()
    let defaults: UserDefaults

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        defaults = try #require(UserDefaults(suiteName: "VoiceInputTests.\(UUID().uuidString)"))
    }

    private struct OpenFailed: Error {}

    private struct Locked: ProEntitlements {
        func isUnlocked(_ feature: ProFeature) -> Bool { feature != .voiceInput }
    }

    private func open(
        entitlements: any ProEntitlements = AllFeaturesUnlocked(),
        preferredLanguages: [String] = ["en-US"]
    ) async throws -> VoiceInput {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Trip"))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "Before"))
        try await repository.create(engine.state)
        guard case .ready(let session) = await EditorSession.open(mapID: engine.state.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return VoiceInput(
            session: session,
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

    private func dictate(_ voice: VoiceInput) async {
        voice.present()
        await waitUntil { voice.phase == .listening }
        voice.stopListening()
        await voice.listening?.value
    }

    private func rootTitles(_ session: EditorSession) -> [String] {
        session.rootID.map { session.engine.state.children(of: $0).map(\.title) } ?? []
    }

    @Test func spokenSentencesBecomeTopicsOnlyWhenAdded() async throws {
        let voice = try await open()
        transcriber.script(heard: [.volatile("Book fli"), .final("Book flights. Find a hotel.")], onFinish: [.final("Pack bags.")])

        await dictate(voice)

        #expect(voice.phase == .idle)
        #expect(voice.transcript.titles == ["Book flights", "Find a hotel", "Pack bags"])
        #expect(rootTitles(voice.session) == ["Before"])

        voice.addTopics()

        #expect(rootTitles(voice.session) == ["Before", "Book flights", "Find a hotel", "Pack bags"])
        #expect(voice.session.selection.flatMap { voice.session.engine.state.node($0)?.title } == "Book flights")
        #expect(!voice.isPresented)
        #expect(voice.transcript.isEmpty)
    }

    @Test func theWholeDictationIsOneUndoStepAndRedoBringsItBack() async throws {
        let voice = try await open()
        let session = voice.session
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        transcriber.script(heard: [.final("Flights. Hotel. Visas.")])
        await dictate(voice)

        undoManager.beginUndoGrouping()
        voice.addTopics()
        undoManager.endUndoGrouping()
        let added = session.engine.state.nodes

        #expect(undoManager.undoActionName == String(localized: "Add Topics by Voice"))
        #expect(rootTitles(session) == ["Before", "Flights", "Hotel", "Visas"])

        undoManager.undo()
        #expect(rootTitles(session) == ["Before"])
        #expect(!undoManager.canUndo)

        undoManager.redo()
        #expect(rootTitles(session) == ["Before", "Flights", "Hotel", "Visas"])
        #expect(session.engine.state.nodes == added)
    }

    @Test func topicsGoUnderTheSelectedTopicAndCanBeEdited() async throws {
        let voice = try await open()
        let session = voice.session
        let before = try #require(session.engine.state.nodes.values.first { $0.title == "Before" })
        session.selection = before.id
        transcriber.script(heard: [.final("First. Second. Third.")])
        await dictate(voice)

        voice.transcript.topics[0].title = "First, edited"
        voice.removeTopic(voice.transcript.topics[1].id)
        voice.addTopics()

        #expect(session.engine.state.children(of: before.id).map(\.title) == ["First, edited", "Third"])
    }

    @Test func cancelAddsNothing() async throws {
        let voice = try await open()
        let nodes = voice.session.engine.state.nodes
        transcriber.script(heard: [.final("Flights.")])
        await dictate(voice)

        voice.close()

        #expect(voice.session.engine.state.nodes == nodes)
        #expect(!voice.session.canUndo)
        #expect(voice.transcript.isEmpty)
    }

    @Test func lockedWithoutProAndNothingListens() async throws {
        let voice = try await open(entitlements: Locked())

        voice.present()

        #expect(voice.isPresented)
        #expect(voice.phase == .locked)
        #expect(!voice.canAddTopics)
        #expect(transcriber.startedLanguages.isEmpty)
    }

    @Test func deniedMicrophoneShowsWhy() async throws {
        let voice = try await open()
        transcriber.setPermissionError(.microphoneDenied)

        voice.present()
        await voice.listening?.value

        #expect(voice.phase == .failed(.microphoneDenied))
        #expect(transcriber.startedLanguages.isEmpty)
    }

    @Test func aMissingModelDownloadsOnlyWhenAsked() async throws {
        let voice = try await open(preferredLanguages: ["vi-VN"])
        transcriber.setAvailability(.needsDownload, for: .vietnamese)

        voice.present()
        await voice.listening?.value
        #expect(voice.phase == .needsDownload)
        #expect(transcriber.preparedLanguages.isEmpty)

        voice.download()
        await waitUntil { voice.phase == .listening }
        #expect(transcriber.preparedLanguages == [.vietnamese])
        #expect(transcriber.startedLanguages == [.vietnamese])
        voice.close()
    }

    @Test func unsupportedLanguageFails() async throws {
        let voice = try await open()
        transcriber.setAvailability(.unsupported, for: .english)

        voice.present()
        await voice.listening?.value

        #expect(voice.phase == .failed(.unsupportedLanguage))
    }

    @Test func languageFollowsPreferenceThenTheLastChoice() async throws {
        let voice = try await open(preferredLanguages: ["vi-VN", "en-US"])
        #expect(voice.language == .vietnamese)

        voice.language = .english

        let reopened = try await open(preferredLanguages: ["vi-VN"])
        #expect(reopened.language == .english)
    }

    @Test func changingLanguageWhileListeningKeepsTheTopicsAndListensAgain() async throws {
        let voice = try await open()
        transcriber.script(heard: [.final("Flights.")], onFinish: [.final("Hotel.")])
        voice.present()
        await waitUntil { voice.phase == .listening }

        voice.language = .vietnamese
        await waitUntil { transcriber.startedLanguages.count == 2 && voice.phase == .listening }

        #expect(transcriber.startedLanguages == [.english, .vietnamese])
        #expect(Array(voice.transcript.titles.prefix(2)) == ["Flights", "Hotel"])
        voice.close()
    }

    @Test func usageDescriptionsShipInEnglishAndVietnamese() throws {
        #expect((Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String)?.isEmpty == false)
        #expect((Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String)?.isEmpty == false)
        let vietnamese = try #require(Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: "vi"))
        let strings = try #require(NSDictionary(contentsOfFile: vietnamese) as? [String: String])
        #expect(strings["NSMicrophoneUsageDescription"]?.isEmpty == false)
        #expect(strings["NSSpeechRecognitionUsageDescription"]?.isEmpty == false)
    }
}
