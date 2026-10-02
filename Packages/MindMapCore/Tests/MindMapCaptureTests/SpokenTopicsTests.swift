import Foundation
@testable import MindMapCapture
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

@Suite("Spoken topics")
struct SpokenTopicsTests {
    @Test func oneTopicPerSentence() {
        #expect(SpokenTopics.titles(from: "Book flights. Find a hotel! Do we need visas?") == [
            "Book flights", "Find a hotel!", "Do we need visas?",
        ])
    }

    @Test func vietnameseSentencesKeepTheirDiacritics() {
        #expect(SpokenTopics.titles(from: "Đặt vé máy bay. Tìm khách sạn gần biển. Chuẩn bị hành lý") == [
            "Đặt vé máy bay", "Tìm khách sạn gần biển", "Chuẩn bị hành lý",
        ])
    }

    @Test func numbersAndVersionsAreNotSentenceEnds() {
        #expect(SpokenTopics.titles(from: "Budget is 3.5 million. Ship v2.0 in May.") == [
            "Budget is 3.5 million", "Ship v2.0 in May",
        ])
    }

    @Test func newlinesSplitAndEmptyPiecesAreDropped() {
        #expect(SpokenTopics.titles(from: "  First idea\n\n. ? …\nSecond idea…  ") == ["First idea", "Second idea"])
        #expect(SpokenTopics.titles(from: "   ").isEmpty)
    }

    @Test func mixedEnglishAndVietnameseStaysAsSaid() {
        #expect(SpokenTopics.titles(from: "Launch plan cho Q4. Marketing trên TikTok.") == [
            "Launch plan cho Q4", "Marketing trên TikTok",
        ])
    }

    @Test func languagePreferenceFollowsTheFirstSupportedLanguage() {
        #expect(VoiceLanguage.preferred(from: ["fr-FR", "vi-VN", "en-US"]) == .vietnamese)
        #expect(VoiceLanguage.preferred(from: ["en-GB", "vi"]) == .english)
        #expect(VoiceLanguage.preferred(from: ["ja-JP"]) == .english)
    }
}

@Suite("Voice transcript")
struct VoiceTranscriptTests {
    @Test func volatileTextIsPendingUntilFinal() {
        var transcript = VoiceTranscript()
        transcript.apply(.volatile("Book fli"))
        #expect(transcript.pending == "Book fli")
        #expect(transcript.topics.isEmpty)

        transcript.apply(.final("Book flights. Find a hotel."))
        #expect(transcript.pending.isEmpty)
        #expect(transcript.titles == ["Book flights", "Find a hotel"])
    }

    @Test func editedAndEmptiedTopicsAreRespected() {
        var transcript = VoiceTranscript()
        transcript.apply(.final("Book flights. Find a hotel."))
        transcript.topics[0].title = "  Book cheap flights "
        transcript.topics[1].title = "  "
        #expect(transcript.titles == ["Book cheap flights"])
    }
}

@Suite("Adding spoken topics")
struct AddSpokenTopicsTests {
    private func engine() throws -> (GraphEngine, NodeID) {
        let engine = try GraphEngine(state: GraphState.newMap(title: "Trip"))
        return (engine, try #require(engine.state.map.rootNodeID))
    }

    @Test func addsEveryTitleUnderTheParentInOrder() throws {
        var (engine, root) = try engine()
        try engine.execute(AddNodeCommand(.child(of: root), title: "Existing"))
        let (command, ids) = SpokenTopics.command(adding: ["Flights", "Hotel"], under: root)

        try engine.execute(command)

        #expect(engine.state.children(of: root).map(\.title) == ["Existing", "Flights", "Hotel"])
        #expect(ids.compactMap { engine.state.node($0)?.title } == ["Flights", "Hotel"])
        #expect(ids.allSatisfy { engine.state.node($0)?.metadata.origin == .user })
    }

    @Test func theWholeDictationIsOneUndoStepAndRedoRestoresIt() throws {
        var (engine, root) = try engine()
        let before = engine.state
        let (command, ids) = SpokenTopics.command(adding: ["Flights", "Hotel", "Visas"], under: root)

        try engine.execute(command)
        let after = engine.state

        #expect(engine.undo() != nil)
        #expect(sameContent(engine.state, before))
        #expect(!engine.canUndo)

        #expect(engine.redo() != nil)
        #expect(sameContent(engine.state, after))
        #expect(ids.allSatisfy { engine.state.node($0) != nil })
    }

    @Test func aMissingParentChangesNothing() throws {
        var (engine, _) = try engine()
        let before = engine.state
        let (command, _) = SpokenTopics.command(adding: ["Flights"], under: NodeID())

        #expect(throws: (any Error).self) { try engine.execute(command) }
        #expect(sameContent(engine.state, before))
    }
}

/// Undo restores the content; the map's `updatedAt` follows the clock.
private func sameContent(_ lhs: GraphState, _ rhs: GraphState) -> Bool {
    var leftMap = lhs.map
    leftMap.updatedAt = rhs.map.updatedAt
    return leftMap == rhs.map && lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
}

@Suite("Fake transcriber")
struct FakeVoiceTranscriberTests {
    @Test func playsTheScriptThenTheFinalWordsOnFinish() async throws {
        let fake = FakeVoiceTranscriber(heard: [.volatile("Fli"), .final("Flights.")], heardOnFinish: [.final("Hotel.")])
        let session = try await fake.start(.vietnamese)
        await session.finish()

        var transcript = VoiceTranscript()
        for try await update in session.updates { transcript.apply(update) }
        #expect(transcript.titles == ["Flights", "Hotel"])
        #expect(fake.startedLanguages == [.vietnamese])
    }
}
